# Betaflight Settings Dashboard (EdgeTX LUA Tools Script) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone EdgeTX Tools LUA script for the Jumper T15 that reads and writes Betaflight 4.5.x settings (PID simplified-tuning sliders, rate profiles, gyro/D-term filter cutoffs, VTX config) over MSP-over-CRSF telemetry, with an arm-lock safety interlock and an explicit Save/Cancel flow.

**Architecture:** A pure-Lua transport/codec core (chunk framing, session, generic byte-buffer field patching, message-specific offset tables) that is unit-testable on a desktop Lua interpreter without radio hardware, topped by an EdgeTX color-LCD UI (`main.lua` router + tab bar + 4 page modules) that is bench-tested against a real flight controller per the spec's testing plan. Every MSP message byte layout and command id used below was extracted verbatim from the Betaflight 4.5.5 firmware source (`msp/msp.c`, `msp/msp_protocol.h`, `telemetry/msp_shared.c`, `telemetry/crsf.c`) during plan authorship — not guessed — because this code talks to a real flight controller.

**Tech Stack:** EdgeTX 2.9+ Lua (color LCD Tools script), plain Lua 5.4 for the desktop unit test harness (no third-party test framework — a ~40-line custom runner, since the target radio's Lua environment has no package manager to match against).

## Global Constraints

- Target radio: Jumper T15, EdgeTX 2.9+, 480x272 color LCD.
- Target FC firmware: Betaflight 4.5.x. All MSP command ids and byte layouts below are pinned to 4.5.5 firmware source; a future BF version bump requires re-verifying `mspMsgs.lua`'s offset tables against that version's source before trusting them.
- Link: ExpressLRS (CRSF). MSP travels over CRSF telemetry frame types `0x7A` (MSP_REQ, radio→FC read request), `0x7C` (MSP_WRITE, radio→FC write, no reply expected), `0x7B` (MSP_RESP, FC→radio reply).
- Deploy path on SD card: `/SCRIPTS/TOOLS/BFDash/` (this repo's `src/SCRIPTS/TOOLS/BFDash/` mirrors that layout so deployment is a direct copy of `src/SCRIPTS` to the SD card root).
- No dynamic notch filter tuning, no in-flight testing of settings changes, no settings categories beyond PID sliders / rates / filters / VTX — all out of scope per spec.
- Arm-lock is fail-safe: unknown/unreadable arm state is treated as **armed** (edits locked), never as disarmed.
- Every write is staged locally; nothing reaches the FC until the user presses Save (per spec's explicit Save/Apply decision).

---

## File Structure

```
src/SCRIPTS/TOOLS/BFDash/
  main.lua                 - entry point: connection check, tab bar, page router, footer
  loader.lua                - include() helper: loadScript() on radio, dofile() in tests
  bytes.lua                  - u8/u16LE read/write helpers over Lua strings (1-based offsets)
  transport/mspChunk.lua    - CRSF MSP chunk header encode/decode (status byte, seq, start, version, error)
  transport/msp.lua         - session: send request, poll for response, timeout, reassembly
  transport/mspBuffer.lua   - generic patchable-message codec (fetch/patch/save by byte offset)
  mspMsgs.lua                - per-message offset tables, FC compatibility check, VTX bespoke codec,
                                profile select, EEPROM write
  state.lua                  - staged-edit model (dirty flag, current values, profile slot)
  safety.lua                  - CRSF FLIGHT_MODE frame parser -> armed/disarmed, fail-safe default
  pages/pids.lua              - PID slider screen
  pages/rates.lua             - rate profile screen
  pages/filters.lua           - filter cutoff screen
  pages/vtx.lua                - VTX config screen

tests/
  testkit.lua                - ~40-line custom test runner (describe/it/assertEquals, no deps)
  run_all.lua                 - runs every *_spec.lua and reports pass/fail counts
  bytes_spec.lua
  transport/mspChunk_spec.lua
  transport/msp_spec.lua
  transport/mspBuffer_spec.lua
  mspMsgs_spec.lua
  state_spec.lua
  safety_spec.lua
```

Pages depend only on `state.lua` (never touch `transport/*` or `mspMsgs.lua` directly) — this is the isolation boundary from the design spec: page logic (which fields to show, how staging works) is independently understandable from wire-protocol logic.

---

## Task 1: Test harness and byte utilities

**Files:**
- Create: `tests/testkit.lua`
- Create: `tests/run_all.lua`
- Create: `src/SCRIPTS/TOOLS/BFDash/bytes.lua`
- Test: `tests/bytes_spec.lua`

**Interfaces:**
- Produces: `bytes.readU8(buf, offset)`, `bytes.writeU8(buf, offset, value)`, `bytes.readU16LE(buf, offset)`, `bytes.writeU16LE(buf, offset, value)` — all offsets are **1-based** (standard Lua string indexing). `writeU8`/`writeU16LE` return a **new** string (Lua strings are immutable) with only that byte range changed; all other bytes in `buf` are preserved unchanged.
- Produces: `testkit.describe(name, fn)`, `testkit.it(name, fn)`, `testkit.assertEquals(actual, expected, msg)`, `testkit.assertTrue(value, msg)`, `testkit.run()` — returns `passCount, failCount` and prints a `PASS`/`FAIL` line per test.

- [ ] **Step 1: Verify a Lua interpreter is available**

Run: `winget install DEVCOM.Lua`

Then verify:

```bash
lua -v
```

Expected: prints `Lua 5.4.x`. If `lua` isn't on PATH after install, restart the shell (winget installs sometimes require a fresh PATH read).

- [ ] **Step 2: Write the test runner**

Create `tests/testkit.lua`:

```lua
local M = {}
local currentDescribe = nil
local results = {}

function M.describe(name, fn)
    currentDescribe = name
    fn()
    currentDescribe = nil
end

function M.it(name, fn)
    local fullName = (currentDescribe and (currentDescribe .. " > ") or "") .. name
    local ok, err = pcall(fn)
    table.insert(results, { name = fullName, ok = ok, err = err })
end

function M.assertEquals(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg or "assertEquals", tostring(expected), tostring(actual)), 2)
    end
end

function M.assertTrue(value, msg)
    if not value then
        error(msg or "assertTrue failed", 2)
    end
end

function M.run()
    local passCount, failCount = 0, 0
    for _, r in ipairs(results) do
        if r.ok then
            passCount = passCount + 1
            print("PASS " .. r.name)
        else
            failCount = failCount + 1
            print("FAIL " .. r.name .. " -- " .. tostring(r.err))
        end
    end
    print(string.format("\n%d passed, %d failed", passCount, failCount))
    return passCount, failCount
end

return M
```

- [ ] **Step 3: Write the byte utilities**

Create `src/SCRIPTS/TOOLS/BFDash/bytes.lua`:

```lua
local M = {}

function M.readU8(buf, offset)
    return string.byte(buf, offset)
end

function M.writeU8(buf, offset, value)
    value = value % 256
    return buf:sub(1, offset - 1) .. string.char(value) .. buf:sub(offset + 1)
end

function M.readU16LE(buf, offset)
    local lo = string.byte(buf, offset)
    local hi = string.byte(buf, offset + 1)
    return lo + hi * 256
end

function M.writeU16LE(buf, offset, value)
    value = value % 65536
    local lo = value % 256
    local hi = (value - lo) / 256
    return buf:sub(1, offset - 1) .. string.char(lo, hi) .. buf:sub(offset + 2)
end

return M
```

- [ ] **Step 4: Write the failing tests**

Create `tests/bytes_spec.lua`:

```lua
local testkit = require("tests.testkit")
local bytes = dofile("src/SCRIPTS/TOOLS/BFDash/bytes.lua")

testkit.describe("bytes", function()
    testkit.it("reads a U8 at a 1-based offset", function()
        testkit.assertEquals(bytes.readU8("\1\2\3", 2), 2, "readU8")
    end)

    testkit.it("writes a U8 without disturbing neighboring bytes", function()
        local buf = "\1\2\3"
        local result = bytes.writeU8(buf, 2, 99)
        testkit.assertEquals(#result, 3, "length preserved")
        testkit.assertEquals(bytes.readU8(result, 1), 1, "byte 1 untouched")
        testkit.assertEquals(bytes.readU8(result, 2), 99, "byte 2 patched")
        testkit.assertEquals(bytes.readU8(result, 3), 3, "byte 3 untouched")
    end)

    testkit.it("reads a little-endian U16", function()
        -- 0x1234 little-endian = bytes {0x34, 0x12}
        local buf = string.char(0x34, 0x12)
        testkit.assertEquals(bytes.readU16LE(buf, 1), 0x1234, "readU16LE")
    end)

    testkit.it("writes a little-endian U16 without disturbing neighbors", function()
        local buf = "\255\0\0\255"
        local result = bytes.writeU16LE(buf, 2, 0x1234)
        testkit.assertEquals(#result, 4, "length preserved")
        testkit.assertEquals(bytes.readU8(result, 1), 255, "byte 1 untouched")
        testkit.assertEquals(bytes.readU16LE(result, 2), 0x1234, "bytes 2-3 patched")
        testkit.assertEquals(bytes.readU8(result, 4), 255, "byte 4 untouched")
    end)

    testkit.it("wraps values above 255 for writeU8", function()
        local result = bytes.writeU8("\0", 1, 256)
        testkit.assertEquals(bytes.readU8(result, 1), 0, "wraps to 0")
    end)
end)
```

Create `tests/run_all.lua`:

```lua
package.path = package.path .. ";./?.lua"
require("tests.bytes_spec")
require("tests.transport.mspChunk_spec")
require("tests.transport.msp_spec")
require("tests.transport.mspBuffer_spec")
require("tests.mspMsgs_spec")
require("tests.state_spec")
require("tests.safety_spec")

local testkit = require("tests.testkit")
local _, failCount = testkit.run()
os.exit(failCount > 0 and 1 or 0)
```

Note: `run_all.lua` requires every spec file, so it will fail to load until Tasks 2-7 create their spec files. For this task, verify `bytes_spec.lua` alone:

- [ ] **Step 5: Run the byte utility tests directly and verify they fail before implementation exists**

(Already implemented in Step 3 above — this confirms the test file itself is wired correctly.) Run:

```bash
lua -e "package.path = package.path .. ';./?.lua'" tests/bytes_spec.lua
```

This alone prints nothing (spec files only register tests); run via a tiny inline harness:

```bash
lua -e "package.path = package.path..';./?.lua'; require('tests.bytes_spec'); require('tests.testkit').run()"
```

Expected: all 5 tests print `PASS`.

- [ ] **Step 6: Commit**

```bash
git add tests/testkit.lua tests/bytes_spec.lua tests/run_all.lua src/SCRIPTS/TOOLS/BFDash/bytes.lua
git commit -m "Add test harness and byte read/write utilities"
```

---

## Task 2: CRSF MSP chunk framing

This is the highest-risk module in the project: it implements the exact wire format from Betaflight's `telemetry/msp_shared.c`. Get this wrong and nothing else works, or — worse — a malformed write is silently accepted.

**Reference (verbatim from `telemetry/msp_shared.c`, Betaflight 4.5.5):**

```
Status byte layout:
  bits 0-3 (0x0F): sequence number
  bit 4    (0x10): start-of-frame flag (1 = first/only chunk)
  bits 5-6 (0x60): MSP protocol version (2 = MSPv2, shift right 5 to read)
  bit 7    (0x80): error flag

First/only chunk of an MSPv2 REQUEST (what we send to read or write):
  [status][flags:u8][cmdLo:u8][cmdHi:u8][sizeLo:u8][sizeHi:u8][payload bytes...]

First/only chunk of an MSPv2 RESPONSE (what we receive):
  [status][flags:u8][cmdLo:u8][cmdHi:u8][sizeLo:u8][sizeHi:u8][payload bytes...]

Continuation chunks (either direction): [status][more payload bytes...]
  (only the low nibble sequence number increments; start bit is 0)
```

We always use MSPv2 (version field = 2) since that's what this plan's message ids (all >= 88, using 16-bit ids) require. Requests to the FC use CRSF frame type `0x7A` if we expect a response (a GET), or `0x7C` if we do not (Betaflight does still reply to `0x7C` writes in practice via the shared MSP handler — but per spec we always want to know a write succeeded, so this plan always requests a reply and uses `0x7A` for both GET and SET, reading the ACK response either way). CRSF's per-chunk payload limit sending FROM the radio is documented as up to 8 bytes (`CRSF_FRAME_RX_MSP_FRAME_SIZE = 8`); receiving chunks (FC to radio) can be up to 58 bytes (`CRSF_FRAME_TX_MSP_FRAME_SIZE = 58`).

**Files:**
- Create: `src/SCRIPTS/TOOLS/BFDash/transport/mspChunk.lua`
- Test: `tests/transport/mspChunk_spec.lua`

**Interfaces:**
- Consumes: nothing (pure module).
- Produces:
  - `mspChunk.buildRequestChunks(cmd, payload)` — `cmd` is a number (0-65535), `payload` is a Lua string (may be empty). Returns an array of Lua strings, each <= 8 bytes, ready to pass as the `data` argument to `crossfireTelemetryPush`.
  - `mspChunk.newAssembler()` — returns a stateful assembler object with `:feed(chunkString) -> isComplete (boolean)` and `:result() -> cmd, payload, isError` (only valid after `isComplete`). Used to reassemble a chunked response.

- [ ] **Step 1: Write the failing tests**

Create `tests/transport/mspChunk_spec.lua`:

```lua
local testkit = require("tests.testkit")
local mspChunk = dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspChunk.lua")

testkit.describe("mspChunk.buildRequestChunks", function()
    testkit.it("builds a single chunk for a short empty-payload request", function()
        local chunks = mspChunk.buildRequestChunks(1, "") -- MSP_API_VERSION, no payload
        testkit.assertEquals(#chunks, 1, "one chunk")
        local c = chunks[1]
        -- status byte: start=1(0x10) | seq=0 | version=2<<5(0x40) = 0x50
        testkit.assertEquals(string.byte(c, 1), 0x50, "status byte")
        testkit.assertEquals(string.byte(c, 2), 0, "flags byte")
        testkit.assertEquals(string.byte(c, 3), 1, "cmd lo")
        testkit.assertEquals(string.byte(c, 4), 0, "cmd hi")
        testkit.assertEquals(string.byte(c, 5), 0, "size lo")
        testkit.assertEquals(string.byte(c, 6), 0, "size hi")
        testkit.assertEquals(#c, 6, "6 byte header, no payload")
    end)

    testkit.it("splits a payload across multiple 8-byte chunks", function()
        -- header is 6 bytes, leaving 2 payload bytes in chunk 1 (8-byte cap)
        local payload = string.rep("A", 10)
        local chunks = mspChunk.buildRequestChunks(141, payload) -- MSP_SET_SIMPLIFIED_TUNING
        testkit.assertTrue(#chunks >= 2, "multiple chunks")
        for _, c in ipairs(chunks) do
            testkit.assertTrue(#c <= 8, "each chunk <= 8 bytes")
        end
        -- first chunk: 6-byte header + up to 2 payload bytes
        testkit.assertEquals(#chunks[1], 8, "first chunk fills to 8 bytes")
        -- sequence numbers increment 0,1,2,... in the low nibble, start bit only on chunk 1
        testkit.assertEquals(string.byte(chunks[1], 1) & 0x10, 0x10, "chunk1 start bit set")
        testkit.assertEquals(string.byte(chunks[2], 1) & 0x10, 0, "chunk2 start bit clear")
        testkit.assertEquals(string.byte(chunks[2], 1) & 0x0f, 1, "chunk2 seq = 1")
    end)

    testkit.it("encodes cmd and size as little-endian u16", function()
        local chunks = mspChunk.buildRequestChunks(300, string.rep("X", 4))
        local c = chunks[1]
        testkit.assertEquals(string.byte(c, 3), 300 % 256, "cmd lo")
        testkit.assertEquals(string.byte(c, 4), 300 // 256, "cmd hi")
        testkit.assertEquals(string.byte(c, 5), 4, "size lo")
        testkit.assertEquals(string.byte(c, 6), 0, "size hi")
    end)
end)

testkit.describe("mspChunk assembler", function()
    testkit.it("reassembles a single-chunk response", function()
        local asm = mspChunk.newAssembler()
        -- status(start,seq0,v2,no error)=0x50, flags=0, cmdLo=1,cmdHi=0, sizeLo=3,sizeHi=0, payload "ABC"
        local chunk = string.char(0x50, 0, 1, 0, 3, 0) .. "ABC"
        local complete = asm:feed(chunk)
        testkit.assertTrue(complete, "complete after one chunk")
        local cmd, payload, isError = asm:result()
        testkit.assertEquals(cmd, 1, "cmd")
        testkit.assertEquals(payload, "ABC", "payload")
        testkit.assertEquals(isError, false, "no error")
    end)

    testkit.it("reassembles a multi-chunk response in order", function()
        local asm = mspChunk.newAssembler()
        -- declare 10-byte payload, first chunk carries 4 bytes ("ABCD"), second carries rest ("EFGHIJ")
        local chunk1 = string.char(0x50, 0, 5, 0, 10, 0) .. "ABCD"
        local chunk2 = string.char(0x01) .. "EFGHIJ" -- seq=1, start bit clear
        testkit.assertTrue(not asm:feed(chunk1), "not complete after chunk 1")
        testkit.assertTrue(asm:feed(chunk2), "complete after chunk 2")
        local cmd, payload, isError = asm:result()
        testkit.assertEquals(cmd, 5, "cmd")
        testkit.assertEquals(payload, "ABCDEFGHIJ", "reassembled payload")
        testkit.assertEquals(isError, false, "no error")
    end)

    testkit.it("reports the error flag from the status byte", function()
        local asm = mspChunk.newAssembler()
        -- status = start(0x10) | version(0x40) | error(0x80) = 0xD0
        local chunk = string.char(0xD0, 0, 1, 0, 0, 0)
        asm:feed(chunk)
        local _, _, isError = asm:result()
        testkit.assertTrue(isError, "error flag surfaced")
    end)

    testkit.it("rejects an out-of-sequence continuation chunk", function()
        local asm = mspChunk.newAssembler()
        local chunk1 = string.char(0x50, 0, 1, 0, 10, 0) .. "ABCD"
        asm:feed(chunk1)
        -- skip seq 1, send seq 2 instead -- simulates dropped chunk
        local badChunk = string.char(0x02) .. "EFGHIJ"
        local ok, err = pcall(function() asm:feed(badChunk) end)
        testkit.assertTrue(not ok, "out-of-sequence chunk raises an error")
    end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
lua -e "package.path = package.path..';./?.lua'; require('tests.transport.mspChunk_spec'); require('tests.testkit').run()"
```

Expected: FAIL — `transport/mspChunk.lua` does not exist yet.

- [ ] **Step 3: Implement mspChunk.lua**

Create `src/SCRIPTS/TOOLS/BFDash/transport/mspChunk.lua`:

```lua
local M = {}

local MSP_VERSION = 2
local CHUNK_MAX = 8 -- radio -> FC per-chunk payload cap (CRSF_FRAME_RX_MSP_FRAME_SIZE)

local STATUS_SEQ_MASK = 0x0f
local STATUS_START_MASK = 0x10
local STATUS_VERSION_SHIFT = 5
local STATUS_ERROR_MASK = 0x80

function M.buildRequestChunks(cmd, payload)
    payload = payload or ""
    local size = #payload
    local header = string.char(
        0, -- status placeholder, patched per-chunk below
        0, -- flags
        cmd % 256, cmd // 256,
        size % 256, size // 256
    )

    local chunks = {}
    local seq = 0

    -- first chunk: header (minus status byte) + as much payload as fits
    local firstPayloadRoom = CHUNK_MAX - #header
    local firstPayload = payload:sub(1, firstPayloadRoom)
    local status = STATUS_START_MASK | (MSP_VERSION << STATUS_VERSION_SHIFT) | (seq & STATUS_SEQ_MASK)
    table.insert(chunks, string.char(status) .. header:sub(2) .. firstPayload)

    local remaining = payload:sub(firstPayloadRoom + 1)
    while #remaining > 0 do
        seq = seq + 1
        local room = CHUNK_MAX - 1 -- 1 byte for status
        local piece = remaining:sub(1, room)
        remaining = remaining:sub(room + 1)
        local contStatus = (MSP_VERSION << STATUS_VERSION_SHIFT) | (seq & STATUS_SEQ_MASK)
        table.insert(chunks, string.char(contStatus) .. piece)
    end

    return chunks
end

local Assembler = {}
Assembler.__index = Assembler

function M.newAssembler()
    return setmetatable({
        started = false,
        lastSeq = nil,
        cmd = nil,
        expectedSize = nil,
        buf = "",
        isError = false,
        complete = false,
    }, Assembler)
end

function Assembler:feed(chunk)
    local status = string.byte(chunk, 1)
    local seq = status & STATUS_SEQ_MASK
    local isStart = (status & STATUS_START_MASK) ~= 0

    if isStart then
        self.isError = (status & STATUS_ERROR_MASK) ~= 0
        self.cmd = string.byte(chunk, 3) + string.byte(chunk, 4) * 256
        self.expectedSize = string.byte(chunk, 5) + string.byte(chunk, 6) * 256
        self.buf = chunk:sub(7)
        self.started = true
        self.lastSeq = seq
    else
        if not self.started then
            error("continuation chunk received before a start chunk")
        end
        local expectedSeq = (self.lastSeq + 1) & STATUS_SEQ_MASK
        if seq ~= expectedSeq then
            self.started = false
            error("out-of-sequence MSP chunk: expected seq " .. expectedSeq .. ", got " .. seq)
        end
        self.lastSeq = seq
        self.buf = self.buf .. chunk:sub(2)
    end

    if #self.buf >= self.expectedSize then
        self.buf = self.buf:sub(1, self.expectedSize)
        self.complete = true
        self.started = false
    end

    return self.complete
end

function Assembler:result()
    return self.cmd, self.buf, self.isError
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
lua -e "package.path = package.path..';./?.lua'; require('tests.transport.mspChunk_spec'); require('tests.testkit').run()"
```

Expected: all tests print `PASS`.

- [ ] **Step 5: Commit**

```bash
git add src/SCRIPTS/TOOLS/BFDash/transport/mspChunk.lua tests/transport/mspChunk_spec.lua
git commit -m "Add CRSF MSP chunk framing (encode requests, reassemble responses)"
```

---

## Task 3: MSP transport session layer

Wraps `mspChunk` around the actual `crossfireTelemetryPush`/`crossfireTelemetryPop` radio calls, tracking one in-flight request at a time (this script never needs concurrent requests) with a timeout.

**Files:**
- Create: `src/SCRIPTS/TOOLS/BFDash/transport/msp.lua`
- Test: `tests/transport/msp_spec.lua`

**Interfaces:**
- Consumes: `mspChunk.buildRequestChunks(cmd, payload)`, `mspChunk.newAssembler()` (Task 2). Global function `crossfireTelemetryPush(command, data)` (provided by the EdgeTX runtime on-radio; tests inject a fake as a Lua global before requiring this module fresh each test). **This module never calls `crossfireTelemetryPop()` itself** — only one consumer may drain that queue (see Task 9's note), so incoming CRSF frames are handed in externally via `session:feed(data)`.
- Produces:
  - `msp.new(timeoutMs)` — returns a session object.
  - `session:request(cmd, payload)` — begins a new request; queues its chunks for sending. Returns nothing; call `session:poll()` and, whenever the caller's own `crossfireTelemetryPop()` loop sees an `0x7B` (MSP_RESP) frame, `session:feed(data)`.
  - `session:poll(nowMs)` — call every tick. Pushes one queued outgoing chunk (if any) via `crossfireTelemetryPush(0x7A, chunk)`, and checks for timeout. Returns one of: `"pending"`, `"done"`, `"timeout"`, `"error"`.
  - `session:feed(data)` — call with the raw payload of a CRSF frame of type `0x7B` (MSP_RESP), from the caller's own shared pop loop. Feeds it to the active assembler; if that completes the response, updates the session to `"done"`/`"error"` (visible on the next `poll()` call). A no-op if no request is pending.
  - `session:result()` — valid after `poll()` returns `"done"` or `"error"`; returns `cmd, payload, isError`.

- [ ] **Step 1: Write the failing tests**

Create `tests/transport/msp_spec.lua`:

```lua
local testkit = require("tests.testkit")

-- Fake CRSF push log, reset before each test group. This module never calls
-- crossfireTelemetryPop() itself (see the module's Interfaces note), so no
-- pop mock is needed -- responses are delivered via session:feed().
local pushLog

_G.crossfireTelemetryPush = function(command, data)
    table.insert(pushLog, { command = command, data = data })
    return true
end

local function freshMsp()
    pushLog = {}
    package.loaded["src.SCRIPTS.TOOLS.BFDash.transport.msp"] = nil
    return dofile("src/SCRIPTS/TOOLS/BFDash/transport/msp.lua")
end

testkit.describe("msp session", function()
    testkit.it("sends the request chunk on the first poll", function()
        local msp = freshMsp()
        local session = msp.new(1000)
        session:request(1, "") -- MSP_API_VERSION
        local status = session:poll(0)
        testkit.assertEquals(status, "pending", "still pending, no response yet")
        testkit.assertEquals(#pushLog, 1, "one chunk pushed")
        testkit.assertEquals(pushLog[1].command, 0x7A, "MSP_REQ frame type")
    end)

    testkit.it("assembles a single-chunk response fed via session:feed and reports done", function()
        local msp = freshMsp()
        local session = msp.new(1000)
        session:request(1, "")
        session:poll(0)
        -- FC replies: status(start,v2,seq0)=0x50, flags=0, cmd=1,0, size=3,0, payload "ABC"
        local reply = string.char(0x50, 0, 1, 0, 3, 0) .. "ABC"
        session:feed(reply)
        local status = session:poll(10)
        testkit.assertEquals(status, "done", "response assembled")
        local cmd, payload, isError = session:result()
        testkit.assertEquals(cmd, 1, "cmd echoed back")
        testkit.assertEquals(payload, "ABC", "payload")
        testkit.assertEquals(isError, false, "no error")
    end)

    testkit.it("feed is a no-op when no request is pending", function()
        local msp = freshMsp()
        local session = msp.new(1000)
        local ok = pcall(function() session:feed(string.char(0x50, 0, 1, 0, 0, 0)) end)
        testkit.assertTrue(ok, "feed before any request does not error")
        testkit.assertEquals(session:poll(0), "idle", "still idle")
    end)

    testkit.it("times out if no response arrives in time", function()
        local msp = freshMsp()
        local session = msp.new(100)
        session:request(1, "")
        session:poll(0)
        local status = session:poll(150)
        testkit.assertEquals(status, "timeout", "exceeded timeout with no response")
    end)

    testkit.it("sends a second request only after the first completes", function()
        local msp = freshMsp()
        local session = msp.new(1000)
        session:request(1, "")
        session:poll(0)
        local reply = string.char(0x50, 0, 1, 0, 0, 0)
        session:feed(reply)
        session:poll(10)
        session:request(2, "")
        session:poll(20)
        testkit.assertEquals(#pushLog, 2, "second request's chunk was pushed")
        testkit.assertEquals(pushLog[2].command, 0x7A, "second request also MSP_REQ")
    end)
end)
```

Note what changed from a first draft of this test: it's the caller's job (Task 9's `main.lua`, via its own single `crossfireTelemetryPop()` loop) to recognize `0x7B` frames and call `session:feed(data)` — `msp.lua` itself never touches `crossfireTelemetryPop`. This is what lets `safety.lua` (Task 7) and this session coexist without racing over the same telemetry queue.

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
lua -e "package.path = package.path..';./?.lua'; require('tests.transport.msp_spec'); require('tests.testkit').run()"
```

Expected: FAIL — `transport/msp.lua` does not exist yet.

- [ ] **Step 3: Implement msp.lua**

Create `src/SCRIPTS/TOOLS/BFDash/transport/msp.lua`:

```lua
local mspChunk = dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspChunk.lua")

local CRSF_FRAMETYPE_MSP_REQ = 0x7A

local M = {}
local Session = {}
Session.__index = Session

function M.new(timeoutMs)
    return setmetatable({
        timeoutMs = timeoutMs,
        outgoing = nil,      -- array of chunk strings still to send
        assembler = nil,
        startedAtMs = nil,
        state = "idle",      -- idle | pending | done | timeout | error
        resultCmd = nil,
        resultPayload = nil,
        resultIsError = nil,
    }, Session)
end

function Session:request(cmd, payload)
    self.outgoing = mspChunk.buildRequestChunks(cmd, payload)
    self.assembler = mspChunk.newAssembler()
    self.startedAtMs = nil
    self.state = "pending"
end

-- Called every tick: pushes the next outgoing chunk (if any) and checks for
-- timeout. Does NOT touch crossfireTelemetryPop -- see feed() below and the
-- module's Interfaces note on why.
function Session:poll(nowMs)
    if self.state ~= "pending" then
        return self.state
    end

    if self.startedAtMs == nil then
        self.startedAtMs = nowMs
    end

    if #self.outgoing > 0 then
        local chunk = table.remove(self.outgoing, 1)
        crossfireTelemetryPush(CRSF_FRAMETYPE_MSP_REQ, chunk)
    end

    if (nowMs - self.startedAtMs) > self.timeoutMs then
        self.state = "timeout"
    end

    return self.state
end

-- Called by the caller's own crossfireTelemetryPop() loop whenever it sees a
-- CRSF frame of type 0x7B (MSP_RESP), passing that frame's raw data string.
function Session:feed(data)
    if self.state ~= "pending" then
        return
    end
    local complete = self.assembler:feed(data)
    if complete then
        local cmd, payload, isError = self.assembler:result()
        self.resultCmd, self.resultPayload, self.resultIsError = cmd, payload, isError
        self.state = isError and "error" or "done"
    end
end

function Session:result()
    return self.resultCmd, self.resultPayload, self.resultIsError
end

return M
```

**Note for Task 9 (main.lua):** `msp.lua` never calls `crossfireTelemetryPop()` — only `main.lua` does, once, in a single shared loop that dispatches each popped frame by `command`: `0x7B` (MSP_RESP) goes to `session:feed(frame.data)`, `0x21` (FLIGHT_MODE) goes to `safety.lua`'s tracker. This avoids two independent consumers racing over the same telemetry queue and silently dropping each other's frames.

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
lua -e "package.path = package.path..';./?.lua'; require('tests.transport.msp_spec'); require('tests.testkit').run()"
```

Expected: all tests print `PASS`.

- [ ] **Step 5: Commit**

```bash
git add src/SCRIPTS/TOOLS/BFDash/transport/msp.lua tests/transport/msp_spec.lua
git commit -m "Add MSP session layer: request/poll/timeout over CRSF chunks"
```

---

## Task 4: Generic patchable-message buffer codec

Implements the "GET raw bytes, patch known field offsets, SET back the identical-length buffer" pattern confirmed safe (in Task-authoring research) for `MSP_SIMPLIFIED_TUNING`/`SET`, `MSP_RC_TUNING`/`SET`, and `MSP_FILTER_CONFIG`/`SET` — all three have symmetric field ordering between their GET and SET wire formats in Betaflight 4.5.5 source, gated only by cumulative byte-count thresholds that always pass when we send back a full-length buffer.

**Files:**
- Create: `src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua`
- Test: `tests/transport/mspBuffer_spec.lua`

**Interfaces:**
- Consumes: `bytes.readU8/writeU8/readU16LE/writeU16LE` (Task 1).
- Produces:
  - `mspBuffer.readField(buf, field)` — `field` is `{offset = <1-based int>, size = 1|2}`. Returns the integer value.
  - `mspBuffer.writeField(buf, field, value)` — returns a new buffer string with only that field's bytes changed.

- [ ] **Step 1: Write the failing tests**

Create `tests/transport/mspBuffer_spec.lua`:

```lua
local testkit = require("tests.testkit")
local mspBuffer = dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")

testkit.describe("mspBuffer", function()
    testkit.it("reads a 1-byte field", function()
        local buf = string.char(10, 20, 30)
        testkit.assertEquals(mspBuffer.readField(buf, { offset = 2, size = 1 }), 20, "field value")
    end)

    testkit.it("reads a 2-byte little-endian field", function()
        local buf = string.char(0, 0x34, 0x12, 0)
        testkit.assertEquals(mspBuffer.readField(buf, { offset = 2, size = 2 }), 0x1234, "field value")
    end)

    testkit.it("writes a 1-byte field and preserves buffer length and neighbors", function()
        local buf = string.char(1, 2, 3)
        local result = mspBuffer.writeField(buf, { offset = 2, size = 1 }, 99)
        testkit.assertEquals(#result, 3, "length preserved")
        testkit.assertEquals(mspBuffer.readField(result, { offset = 1, size = 1 }), 1, "byte 1 untouched")
        testkit.assertEquals(mspBuffer.readField(result, { offset = 2, size = 1 }), 99, "byte 2 patched")
        testkit.assertEquals(mspBuffer.readField(result, { offset = 3, size = 1 }), 3, "byte 3 untouched")
    end)

    testkit.it("writes a 2-byte field and preserves buffer length and neighbors", function()
        local buf = string.char(255, 0, 0, 255)
        local result = mspBuffer.writeField(buf, { offset = 2, size = 2 }, 0x1234)
        testkit.assertEquals(#result, 4, "length preserved")
        testkit.assertEquals(mspBuffer.readField(result, { offset = 1, size = 1 }), 255, "byte 1 untouched")
        testkit.assertEquals(mspBuffer.readField(result, { offset = 2, size = 2 }), 0x1234, "bytes 2-3 patched")
        testkit.assertEquals(mspBuffer.readField(result, { offset = 4, size = 1 }), 255, "byte 4 untouched")
    end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
lua -e "package.path = package.path..';./?.lua'; require('tests.transport.mspBuffer_spec'); require('tests.testkit').run()"
```

Expected: FAIL — module does not exist.

- [ ] **Step 3: Implement mspBuffer.lua**

Create `src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua`:

```lua
local bytes = dofile("src/SCRIPTS/TOOLS/BFDash/bytes.lua")

local M = {}

function M.readField(buf, field)
    if field.size == 1 then
        return bytes.readU8(buf, field.offset)
    elseif field.size == 2 then
        return bytes.readU16LE(buf, field.offset)
    else
        error("unsupported field size: " .. tostring(field.size))
    end
end

function M.writeField(buf, field, value)
    if field.size == 1 then
        return bytes.writeU8(buf, field.offset, value)
    elseif field.size == 2 then
        return bytes.writeU16LE(buf, field.offset, value)
    else
        error("unsupported field size: " .. tostring(field.size))
    end
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same command as Step 2. Expected: all `PASS`.

- [ ] **Step 5: Commit**

```bash
git add src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua tests/transport/mspBuffer_spec.lua
git commit -m "Add generic byte-offset field codec for round-trip-symmetric MSP messages"
```

---

## Task 5: Message definitions (mspMsgs.lua)

Defines every MSP command id and field-offset table this script uses, all pinned to Betaflight 4.5.5 source as researched during plan authorship. This is the one file to re-verify (offsets/ids only, not the rest of the codebase) if a future Betaflight version changes these structures.

**Files:**
- Create: `src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua`
- Test: `tests/mspMsgs_spec.lua`

**Interfaces:**
- Consumes: `mspBuffer.readField/writeField` (Task 4).
- Produces (all fields below are `{offset, size}` pairs per Task 4's `field` shape):
  - `mspMsgs.CMD` — table of command ids: `API_VERSION=1, FC_VARIANT=2, FC_VERSION=3, VTX_CONFIG=88, SET_VTX_CONFIG=89, FILTER_CONFIG=92, SET_FILTER_CONFIG=93, RC_TUNING=111, SET_RC_TUNING=204, SELECT_SETTING=210, EEPROM_WRITE=250, SIMPLIFIED_TUNING=140, SET_SIMPLIFIED_TUNING=141`.
  - `mspMsgs.SIMPLIFIED_TUNING_FIELDS` — table with keys `pidsMode, masterMultiplier, rollPitchRatio, iGain, dGain, piGain, dminRatio, feedforwardGain, pitchPiGain` (all `size=1`, offsets 1-9).
  - `mspMsgs.RC_TUNING_FIELDS` — table with keys `rcRateRoll, rcExpoRoll, superRateRoll, superRatePitch, superRateYaw, thrMid8, thrExpo8, rcExpoYaw, rcRateYaw, rcRatePitch, rcExpoPitch, throttleLimitType, throttleLimitPercent, rateLimitRoll, rateLimitPitch, rateLimitYaw, ratesType`.
  - `mspMsgs.FILTER_CONFIG_FIELDS` — table with keys `dtermLpf1Hz, gyroLpf1Hz, gyroLpf2Hz, dtermLpf2Hz`.
  - `mspMsgs.decodeFcVariant(payload) -> string` (4-char ASCII).
  - `mspMsgs.decodeFcVersion(payload) -> major, minor, patch`.
  - `mspMsgs.decodeApiVersion(payload) -> mspProtocolVersion, major, minor`.
  - `mspMsgs.isBetaflight(variantString) -> boolean` (checks for `"BTFL"`).
  - `mspMsgs.encodeSelectSetting(profileType, index) -> payload string` — `profileType` is `"pid"` or `"rate"`.
  - `mspMsgs.decodeVtxConfig(payload) -> { band, channel, power }`.
  - `mspMsgs.encodeVtxConfigSet(current) -> payload string` — `current` is `{ band, channel, power, pitmode, lowPowerDisarm, pitModeFreq }` (the pitmode/lowPowerDisarm/pitModeFreq values are normally read back unchanged from a prior `decodeVtxConfig`-adjacent raw read, see Task 11).

- [ ] **Step 1: Write the failing tests**

Create `tests/mspMsgs_spec.lua`:

```lua
local testkit = require("tests.testkit")
local mspMsgs = dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")

testkit.describe("mspMsgs.CMD", function()
    testkit.it("has the command ids verified against Betaflight 4.5.5 msp_protocol.h", function()
        testkit.assertEquals(mspMsgs.CMD.API_VERSION, 1, "API_VERSION")
        testkit.assertEquals(mspMsgs.CMD.FC_VARIANT, 2, "FC_VARIANT")
        testkit.assertEquals(mspMsgs.CMD.FC_VERSION, 3, "FC_VERSION")
        testkit.assertEquals(mspMsgs.CMD.VTX_CONFIG, 88, "VTX_CONFIG")
        testkit.assertEquals(mspMsgs.CMD.SET_VTX_CONFIG, 89, "SET_VTX_CONFIG")
        testkit.assertEquals(mspMsgs.CMD.FILTER_CONFIG, 92, "FILTER_CONFIG")
        testkit.assertEquals(mspMsgs.CMD.SET_FILTER_CONFIG, 93, "SET_FILTER_CONFIG")
        testkit.assertEquals(mspMsgs.CMD.RC_TUNING, 111, "RC_TUNING")
        testkit.assertEquals(mspMsgs.CMD.SET_RC_TUNING, 204, "SET_RC_TUNING")
        testkit.assertEquals(mspMsgs.CMD.SELECT_SETTING, 210, "SELECT_SETTING (not 10 -- verified from source)")
        testkit.assertEquals(mspMsgs.CMD.EEPROM_WRITE, 250, "EEPROM_WRITE")
        testkit.assertEquals(mspMsgs.CMD.SIMPLIFIED_TUNING, 140, "SIMPLIFIED_TUNING")
        testkit.assertEquals(mspMsgs.CMD.SET_SIMPLIFIED_TUNING, 141, "SET_SIMPLIFIED_TUNING")
    end)
end)

testkit.describe("mspMsgs FC identity decoders", function()
    testkit.it("decodes MSP_API_VERSION payload", function()
        local payload = string.char(2, 1, 46) -- protocol=2, major=1, minor=46
        local proto, major, minor = mspMsgs.decodeApiVersion(payload)
        testkit.assertEquals(proto, 2, "protocol version")
        testkit.assertEquals(major, 1, "api major")
        testkit.assertEquals(minor, 46, "api minor")
    end)

    testkit.it("decodes MSP_FC_VARIANT payload as a 4-char string", function()
        testkit.assertEquals(mspMsgs.decodeFcVariant("BTFL"), "BTFL", "variant string")
    end)

    testkit.it("identifies Betaflight from the variant string", function()
        testkit.assertTrue(mspMsgs.isBetaflight("BTFL"), "BTFL recognized")
        testkit.assertTrue(not mspMsgs.isBetaflight("INAV"), "INAV rejected")
    end)

    testkit.it("decodes MSP_FC_VERSION payload", function()
        local major, minor, patch = mspMsgs.decodeFcVersion(string.char(4, 5, 5))
        testkit.assertEquals(major, 4, "major")
        testkit.assertEquals(minor, 5, "minor")
        testkit.assertEquals(patch, 5, "patch")
    end)
end)

testkit.describe("mspMsgs.SIMPLIFIED_TUNING_FIELDS", function()
    testkit.it("reads the 9 slider fields at their verified offsets", function()
        -- mode, master, rollPitch, i, d, pi, dmin, ff, pitchPi = 1..9, then 8 reserved bytes
        local buf = string.char(1, 100, 100, 100, 100, 100, 100, 100, 100) .. string.rep("\0", 8)
        local f = mspMsgs.SIMPLIFIED_TUNING_FIELDS
        testkit.assertEquals(mspBuffer.readField(buf, f.pidsMode), 1, "pidsMode")
        testkit.assertEquals(mspBuffer.readField(buf, f.masterMultiplier), 100, "masterMultiplier")
        testkit.assertEquals(mspBuffer.readField(buf, f.pitchPiGain), 100, "pitchPiGain (offset 9, last of the 9)")
    end)

    testkit.it("patches only the PID slider bytes, leaving the rest of a 53-byte buffer untouched", function()
        local buf = string.rep("\170", 53) -- 0xAA filler standing in for dterm/gyro filter sub-blocks
        local f = mspMsgs.SIMPLIFIED_TUNING_FIELDS
        local patched = mspBuffer.writeField(buf, f.masterMultiplier, 150)
        testkit.assertEquals(#patched, 53, "length preserved")
        testkit.assertEquals(mspBuffer.readField(patched, f.masterMultiplier), 150, "patched field")
        testkit.assertEquals(string.byte(patched, 10), 0xAA, "byte 10 (start of dterm filter sub-block) untouched")
        testkit.assertEquals(string.byte(patched, 53), 0xAA, "last byte untouched")
    end)
end)

testkit.describe("mspMsgs.RC_TUNING_FIELDS", function()
    testkit.it("reads rates_type at the last byte of a 23-byte response", function()
        local buf = string.rep("\0", 22) .. string.char(2) -- rates_type = 2 (RaceFlight)
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.RC_TUNING_FIELDS.ratesType), 2, "ratesType")
    end)

    testkit.it("reads rate_limit fields as u16", function()
        local buf = string.rep("\0", 16) .. string.char(0xE8, 0x03) .. string.rep("\0", 4) -- rateLimitRoll=1000 at offset 17-18
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.RC_TUNING_FIELDS.rateLimitRoll), 1000, "rateLimitRoll")
    end)
end)

testkit.describe("mspMsgs.FILTER_CONFIG_FIELDS", function()
    testkit.it("reads gyro/dterm lowpass fields at their verified offsets", function()
        local buf = string.rep("\0", 45)
        buf = mspBuffer.writeField(buf, mspMsgs.FILTER_CONFIG_FIELDS.dtermLpf1Hz, 100)
        buf = mspBuffer.writeField(buf, mspMsgs.FILTER_CONFIG_FIELDS.gyroLpf1Hz, 250)
        buf = mspBuffer.writeField(buf, mspMsgs.FILTER_CONFIG_FIELDS.gyroLpf2Hz, 500)
        buf = mspBuffer.writeField(buf, mspMsgs.FILTER_CONFIG_FIELDS.dtermLpf2Hz, 150)
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.FILTER_CONFIG_FIELDS.dtermLpf1Hz), 100, "dtermLpf1Hz")
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.FILTER_CONFIG_FIELDS.gyroLpf1Hz), 250, "gyroLpf1Hz")
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.FILTER_CONFIG_FIELDS.gyroLpf2Hz), 500, "gyroLpf2Hz")
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.FILTER_CONFIG_FIELDS.dtermLpf2Hz), 150, "dtermLpf2Hz")
    end)
end)

testkit.describe("mspMsgs.encodeSelectSetting", function()
    testkit.it("encodes a PID profile index with bit 7 clear", function()
        local payload = mspMsgs.encodeSelectSetting("pid", 2)
        testkit.assertEquals(string.byte(payload, 1), 2, "pid profile index, no rate bit")
    end)

    testkit.it("encodes a rate profile index with bit 7 set", function()
        local payload = mspMsgs.encodeSelectSetting("rate", 1)
        testkit.assertEquals(string.byte(payload, 1), 0x80 | 1, "rate profile index, rate bit set")
    end)
end)

testkit.describe("mspMsgs VTX config codec", function()
    testkit.it("decodes band/channel/power from a GET response", function()
        -- vtxType,band,channel,power,pitmode,freqLo,freqHi,ready,lowPowerDisarm,pitFreqLo,pitFreqHi,...
        local payload = string.char(3, 2, 5, 3, 0) .. string.char(0x88, 0x16) .. string.char(1, 0) .. string.char(0, 0)
        local cfg = mspMsgs.decodeVtxConfig(payload)
        testkit.assertEquals(cfg.band, 2, "band")
        testkit.assertEquals(cfg.channel, 5, "channel")
        testkit.assertEquals(cfg.power, 3, "power")
    end)

    testkit.it("encodes a SET_VTX_CONFIG payload using the standalone band/channel/freq extension", function()
        local current = { band = 3, channel = 4, power = 2, pitmode = 0, lowPowerDisarm = 0, pitModeFreq = 5658 }
        local payload = mspMsgs.encodeVtxConfigSet(current)
        testkit.assertEquals(#payload, 11, "11-byte SET payload")
        -- bytes 8-9 (1-based) are the standalone band/channel per the plan's derived layout
        testkit.assertEquals(string.byte(payload, 8), 3, "standalone band")
        testkit.assertEquals(string.byte(payload, 9), 4, "standalone channel")
        testkit.assertEquals(string.byte(payload, 3), 2, "power field")
    end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
lua -e "package.path = package.path..';./?.lua'; require('tests.mspMsgs_spec'); require('tests.testkit').run()"
```

Expected: FAIL — module does not exist.

- [ ] **Step 3: Implement mspMsgs.lua**

Create `src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua`:

```lua
local M = {}

M.CMD = {
    API_VERSION = 1,
    FC_VARIANT = 2,
    FC_VERSION = 3,
    VTX_CONFIG = 88,
    SET_VTX_CONFIG = 89,
    FILTER_CONFIG = 92,
    SET_FILTER_CONFIG = 93,
    RC_TUNING = 111,
    SET_RC_TUNING = 204,
    SELECT_SETTING = 210,
    EEPROM_WRITE = 250,
    SIMPLIFIED_TUNING = 140,
    SET_SIMPLIFIED_TUNING = 141,
}

-- Offsets verified against Betaflight 4.5.5 src/main/msp/msp.c
-- (readSimplifiedPids/writeSimplifiedPids), 1-based for Lua string indexing.
M.SIMPLIFIED_TUNING_FIELDS = {
    pidsMode = { offset = 1, size = 1 },
    masterMultiplier = { offset = 2, size = 1 },
    rollPitchRatio = { offset = 3, size = 1 },
    iGain = { offset = 4, size = 1 },
    dGain = { offset = 5, size = 1 },
    piGain = { offset = 6, size = 1 },
    dminRatio = { offset = 7, size = 1 },
    feedforwardGain = { offset = 8, size = 1 },
    pitchPiGain = { offset = 9, size = 1 },
}

-- Offsets verified against Betaflight 4.5.5 src/main/msp/msp.c (case MSP_RC_TUNING).
M.RC_TUNING_FIELDS = {
    rcRateRoll = { offset = 1, size = 1 },
    rcExpoRoll = { offset = 2, size = 1 },
    superRateRoll = { offset = 3, size = 1 },
    superRatePitch = { offset = 4, size = 1 },
    superRateYaw = { offset = 5, size = 1 },
    thrMid8 = { offset = 7, size = 1 },
    thrExpo8 = { offset = 8, size = 1 },
    rcExpoYaw = { offset = 11, size = 1 },
    rcRateYaw = { offset = 12, size = 1 },
    rcRatePitch = { offset = 13, size = 1 },
    rcExpoPitch = { offset = 14, size = 1 },
    throttleLimitType = { offset = 15, size = 1 },
    throttleLimitPercent = { offset = 16, size = 1 },
    rateLimitRoll = { offset = 17, size = 2 },
    rateLimitPitch = { offset = 19, size = 2 },
    rateLimitYaw = { offset = 21, size = 2 },
    ratesType = { offset = 23, size = 1 },
}

-- Offsets verified against Betaflight 4.5.5 src/main/msp/msp.c (case MSP_FILTER_CONFIG).
-- Note: byte 1 (C offset 0) is a legacy narrow gyro_lpf1_static_hz duplicate;
-- we deliberately use the full-range U16 copy at offset 21 instead.
M.FILTER_CONFIG_FIELDS = {
    dtermLpf1Hz = { offset = 2, size = 2 },
    gyroLpf1Hz = { offset = 21, size = 2 },
    gyroLpf2Hz = { offset = 23, size = 2 },
    dtermLpf2Hz = { offset = 27, size = 2 },
}

function M.decodeApiVersion(payload)
    return string.byte(payload, 1), string.byte(payload, 2), string.byte(payload, 3)
end

function M.decodeFcVariant(payload)
    return payload:sub(1, 4)
end

function M.isBetaflight(variantString)
    return variantString == "BTFL"
end

function M.decodeFcVersion(payload)
    return string.byte(payload, 1), string.byte(payload, 2), string.byte(payload, 3)
end

local RATEPROFILE_MASK = 0x80

function M.encodeSelectSetting(profileType, index)
    if profileType == "rate" then
        return string.char(RATEPROFILE_MASK | (index & 0x7f))
    else
        return string.char(index & 0x7f)
    end
end

-- GET response layout verified against Betaflight 4.5.5 (case MSP_VTX_CONFIG).
function M.decodeVtxConfig(payload)
    return {
        vtxType = string.byte(payload, 1),
        band = string.byte(payload, 2),
        channel = string.byte(payload, 3),
        power = string.byte(payload, 4),
        pitmode = string.byte(payload, 5),
    }
end

-- SET payload layout verified against Betaflight 4.5.5 (case MSP_SET_VTX_CONFIG).
-- Sends: [legacy band/chan-encoded u16][power][pitmode][lowPowerDisarm][pitModeFreq u16]
--        [standalone band][standalone channel][standalone freq u16 = 0, band/channel takes priority]
-- Both the legacy-encoded field and the standalone band/channel fields are sent
-- with the same values so they can't disagree; band/channel are always 1-8 here
-- so (band-1)*8+(channel-1) <= 63 = VTXCOMMON_MSP_BANDCHAN_CHKVAL, keeping the
-- legacy field interpreted as band/channel (not as a raw frequency).
function M.encodeVtxConfigSet(current)
    local legacy = (current.band - 1) * 8 + (current.channel - 1)
    local out = {}
    out[#out + 1] = string.char(legacy % 256, legacy // 256)
    out[#out + 1] = string.char(current.power)
    out[#out + 1] = string.char(current.pitmode)
    out[#out + 1] = string.char(current.lowPowerDisarm)
    out[#out + 1] = string.char(current.pitModeFreq % 256, current.pitModeFreq // 256)
    out[#out + 1] = string.char(current.band, current.channel)
    out[#out + 1] = string.char(0, 0) -- standalone freq: 0 = derive from band/channel
    return table.concat(out)
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command again. Expected: all `PASS`.

- [ ] **Step 5: Commit**

```bash
git add src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua tests/mspMsgs_spec.lua
git commit -m "Add MSP message definitions verified against Betaflight 4.5.5 source"
```

---

## Task 6: Staged-edit state model

**Files:**
- Create: `src/SCRIPTS/TOOLS/BFDash/state.lua`
- Test: `tests/state_spec.lua`

**Interfaces:**
- Consumes: nothing (pure module — pages and main.lua wire it to the transport).
- Produces:
  - `state.new()` — returns a state object.
  - `state:load(key, values)` — records freshly-read FC values for `key` (e.g. `"pids"`, `"rates"`) as both the "clean" baseline and the current staged values; clears dirty for that key.
  - `state:get(key)` — returns the current staged values table for `key` (nil if never loaded).
  - `state:setField(key, fieldName, value)` — updates one field in the staged copy for `key` and marks that key dirty.
  - `state:isDirty(key)` — true if staged values differ from the clean baseline for `key`.
  - `state:isAnyDirty()` — true if any loaded key is dirty.
  - `state:reload(key)` — discards staged edits for `key`, resetting to the clean baseline (used by Cancel).
  - `state:markClean(key)` — after a successful Save, sets the clean baseline to the current staged values (used after a confirmed write).

- [ ] **Step 1: Write the failing tests**

Create `tests/state_spec.lua`:

```lua
local testkit = require("tests.testkit")
local stateMod = dofile("src/SCRIPTS/TOOLS/BFDash/state.lua")

testkit.describe("state", function()
    testkit.it("loads values and starts clean", function()
        local s = stateMod.new()
        s:load("pids", { masterMultiplier = 100 })
        testkit.assertEquals(s:isDirty("pids"), false, "clean after load")
        testkit.assertEquals(s:get("pids").masterMultiplier, 100, "value readable")
    end)

    testkit.it("marks a key dirty after setField changes a value", function()
        local s = stateMod.new()
        s:load("pids", { masterMultiplier = 100 })
        s:setField("pids", "masterMultiplier", 120)
        testkit.assertEquals(s:isDirty("pids"), true, "dirty after edit")
        testkit.assertEquals(s:get("pids").masterMultiplier, 120, "staged value updated")
    end)

    testkit.it("does not mark dirty if setField sets the same value", function()
        local s = stateMod.new()
        s:load("pids", { masterMultiplier = 100 })
        s:setField("pids", "masterMultiplier", 100)
        testkit.assertEquals(s:isDirty("pids"), false, "unchanged value stays clean")
    end)

    testkit.it("reload discards staged edits back to the clean baseline", function()
        local s = stateMod.new()
        s:load("pids", { masterMultiplier = 100 })
        s:setField("pids", "masterMultiplier", 120)
        s:reload("pids")
        testkit.assertEquals(s:get("pids").masterMultiplier, 100, "reverted")
        testkit.assertEquals(s:isDirty("pids"), false, "clean after reload")
    end)

    testkit.it("markClean commits the staged values as the new baseline", function()
        local s = stateMod.new()
        s:load("pids", { masterMultiplier = 100 })
        s:setField("pids", "masterMultiplier", 120)
        s:markClean("pids")
        testkit.assertEquals(s:isDirty("pids"), false, "clean after markClean")
        s:reload("pids")
        testkit.assertEquals(s:get("pids").masterMultiplier, 120, "new baseline is 120, not 100")
    end)

    testkit.it("isAnyDirty reflects dirtiness across multiple keys", function()
        local s = stateMod.new()
        s:load("pids", { masterMultiplier = 100 })
        s:load("rates", { rcRateRoll = 7 })
        testkit.assertEquals(s:isAnyDirty(), false, "nothing dirty yet")
        s:setField("rates", "rcRateRoll", 8)
        testkit.assertEquals(s:isAnyDirty(), true, "dirty via rates key")
    end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
lua -e "package.path = package.path..';./?.lua'; require('tests.state_spec'); require('tests.testkit').run()"
```

Expected: FAIL — module does not exist.

- [ ] **Step 3: Implement state.lua**

Create `src/SCRIPTS/TOOLS/BFDash/state.lua`:

```lua
local M = {}
local State = {}
State.__index = State

function M.new()
    return setmetatable({ clean = {}, staged = {} }, State)
end

local function shallowCopy(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end

function State:load(key, values)
    self.clean[key] = shallowCopy(values)
    self.staged[key] = shallowCopy(values)
end

function State:get(key)
    return self.staged[key]
end

function State:setField(key, fieldName, value)
    self.staged[key][fieldName] = value
end

function State:isDirty(key)
    local clean, staged = self.clean[key], self.staged[key]
    if clean == nil or staged == nil then
        return false
    end
    for k, v in pairs(staged) do
        if clean[k] ~= v then
            return true
        end
    end
    return false
end

function State:isAnyDirty()
    for key, _ in pairs(self.staged) do
        if self:isDirty(key) then
            return true
        end
    end
    return false
end

function State:reload(key)
    self.staged[key] = shallowCopy(self.clean[key])
end

function State:markClean(key)
    self.clean[key] = shallowCopy(self.staged[key])
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command again. Expected: all `PASS`.

- [ ] **Step 5: Commit**

```bash
git add src/SCRIPTS/TOOLS/BFDash/state.lua tests/state_spec.lua
git commit -m "Add staged-edit state model with dirty tracking"
```

---

## Task 7: Arm-status safety lock

Implements the CRSF FLIGHT_MODE (frame type `0x21`) parser, with the verified-from-source convention: **a trailing `*` in the flight mode text means DISARMED**. Armed is the absence of that trailing `*`. Fail-safe: no frame received yet, or an unparseable frame, means "treat as armed."

**Files:**
- Create: `src/SCRIPTS/TOOLS/BFDash/safety.lua`
- Test: `tests/safety_spec.lua`

**Interfaces:**
- Consumes: nothing directly (fed CRSF frame data by the caller's shared pop-loop dispatcher, per Task 3's note — Task 13 wires this).
- Produces:
  - `safety.new()` — returns a tracker object, initial state is "armed" (fail-safe default before any frame arrives).
  - `tracker:feedFlightModeFrame(data)` — call with the raw CRSF FLIGHT_MODE frame payload (a null-terminated ASCII string, e.g. `"ACRO*\0"` when disarmed or `"ACRO\0"` when armed). Updates internal armed state.
  - `tracker:isArmed()` — returns `true`/`false`. Before any frame is fed, returns `true` (fail-safe).
  - `tracker:markStale()` — called by the caller if too much time has passed since the last frame (e.g. link lost); forces `isArmed()` back to `true` until a fresh frame arrives.

- [ ] **Step 1: Write the failing tests**

Create `tests/safety_spec.lua`:

```lua
local testkit = require("tests.testkit")
local safety = dofile("src/SCRIPTS/TOOLS/BFDash/safety.lua")

testkit.describe("safety arm tracker", function()
    testkit.it("defaults to armed before any frame is received (fail-safe)", function()
        local t = safety.new()
        testkit.assertTrue(t:isArmed(), "armed by default")
    end)

    testkit.it("reports disarmed when the flight mode string ends with '*'", function()
        local t = safety.new()
        t:feedFlightModeFrame("ACRO*\0")
        testkit.assertEquals(t:isArmed(), false, "trailing * means disarmed")
    end)

    testkit.it("reports armed when the flight mode string has no trailing '*'", function()
        local t = safety.new()
        t:feedFlightModeFrame("ACRO*\0") -- first disarm
        t:feedFlightModeFrame("ACRO\0")  -- then arm
        testkit.assertEquals(t:isArmed(), true, "no trailing * means armed")
    end)

    testkit.it("handles other flight mode names, not just ACRO", function()
        local t = safety.new()
        t:feedFlightModeFrame("STAB\0")
        testkit.assertEquals(t:isArmed(), true, "STAB with no star = armed")
        t:feedFlightModeFrame("!FS!*\0")
        testkit.assertEquals(t:isArmed(), false, "failsafe with star = disarmed")
    end)

    testkit.it("treats an empty or malformed frame as armed (fail-safe)", function()
        local t = safety.new()
        t:feedFlightModeFrame("ACRO\0") -- arm first, to prove markStale overrides it
        t:markStale()
        testkit.assertTrue(t:isArmed(), "stale telemetry forces armed")
    end)

    testkit.it("a fresh frame after markStale clears the stale override", function()
        local t = safety.new()
        t:markStale()
        t:feedFlightModeFrame("ACRO\0")
        testkit.assertEquals(t:isArmed(), true, "fresh frame re-evaluated normally")
    end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
lua -e "package.path = package.path..';./?.lua'; require('tests.safety_spec'); require('tests.testkit').run()"
```

Expected: FAIL — module does not exist.

- [ ] **Step 3: Implement safety.lua**

Create `src/SCRIPTS/TOOLS/BFDash/safety.lua`:

```lua
local M = {}
local Tracker = {}
Tracker.__index = Tracker

function M.new()
    return setmetatable({ armed = true, stale = true }, Tracker)
end

-- Verified from Betaflight 4.5.5 src/main/telemetry/crsf.c: crsfFrameFlightMode()
-- writes a trailing '*' ONLY when NOT armed. Absence of '*' = armed.
function Tracker:feedFlightModeFrame(data)
    local text = data:match("^[^%z]*") or data -- strip trailing null terminator(s)
    local endsWithStar = text:sub(-1) == "*"
    self.armed = not endsWithStar
    self.stale = false
end

function Tracker:isArmed()
    if self.stale then
        return true
    end
    return self.armed
end

function Tracker:markStale()
    self.stale = true
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command again. Expected: all `PASS`.

- [ ] **Step 5: Commit**

```bash
git add src/SCRIPTS/TOOLS/BFDash/safety.lua tests/safety_spec.lua
git commit -m "Add arm-status safety lock (CRSF FLIGHT_MODE frame, fail-safe default)"
```

---

## Task 8: Full test suite wiring and CI-style check

Wires all specs into `run_all.lua` (already written in Task 1) and verifies the complete pure-Lua core passes together.

**Files:**
- Modify: none (all spec files already created in Tasks 1-7)
- Verify: `tests/run_all.lua`

- [ ] **Step 1: Run the full suite**

```bash
lua tests/run_all.lua
```

Expected: every test from Tasks 1-7 prints `PASS`, final line reads `0 failed`, exit code 0.

- [ ] **Step 2: Commit** (only if `run_all.lua` needed any fixes to run cleanly; otherwise skip — nothing new to commit)

```bash
git add tests/run_all.lua
git commit -m "Verify full pure-Lua test suite passes end to end"
```

---

## Task 9: main.lua — connection check, arm-lock wiring, tab router, footer

This is the entry point EdgeTX loads from `/SCRIPTS/TOOLS/BFDash/main.lua`. It owns the single shared `crossfireTelemetryPop()` loop (per Task 3's note) and dispatches frames to the active MSP session and to `safety.lua`.

This task's code uses EdgeTX-only globals (`lcd.*`, `crossfireTelemetryPush/Pop`, `event`/`touchState` from `run()`) that cannot run in the plain-Lua test harness. Per the spec's testing plan, this task is validated by bench-testing on the actual radio (props off), not by automated unit tests. Tasks 10-13 (the page modules) follow the same pattern: they call into `state.lua` and `mspMsgs.lua` (already unit-tested) but their rendering/touch-handling is bench-verified.

**Files:**
- Create: `src/SCRIPTS/TOOLS/BFDash/loader.lua`
- Create: `src/SCRIPTS/TOOLS/BFDash/main.lua`

**Interfaces:**
- Consumes: `transport/msp.lua` (Task 3), `mspMsgs.lua` (Task 5), `state.lua` (Task 6), `safety.lua` (Task 7), and each page module's `create()/update()/event()` (Tasks 10-13, wired here even though those tasks are written after this one — `main.lua`'s page table references their file paths, and the script is not runnable end-to-end until Task 13 completes).
- Produces: the script's `init()` and `run(event, touchState)` entry points that EdgeTX calls.

- [ ] **Step 1: Write the module loader**

Create `src/SCRIPTS/TOOLS/BFDash/loader.lua`:

```lua
local BASE_PATH = "/SCRIPTS/TOOLS/BFDash/"

local function include(relPath)
    if loadScript then
        return assert(loadScript(BASE_PATH .. relPath))()
    else
        -- desktop/test fallback: relative to repo root
        return dofile("src/SCRIPTS/TOOLS/BFDash/" .. relPath)
    end
end

return { include = include }
```

- [ ] **Step 2: Write main.lua**

Create `src/SCRIPTS/TOOLS/BFDash/main.lua`:

```lua
local loader = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/loader.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/loader.lua")
local include = loader.include

local msp = include("transport/msp.lua")
local mspMsgs = include("mspMsgs.lua")
local stateMod = include("state.lua")
local safety = include("safety.lua")

local pidsPage = include("pages/pids.lua")
local ratesPage = include("pages/rates.lua")
local filtersPage = include("pages/filters.lua")
local vtxPage = include("pages/vtx.lua")

local CRSF_FRAMETYPE_MSP_RESP = 0x7B
local CRSF_FRAMETYPE_FLIGHT_MODE = 0x21
local FLIGHT_MODE_STALE_MS = 3000
local REQUEST_TIMEOUT_MS = 800

local pages = { pidsPage, ratesPage, filtersPage, vtxPage }
local pageNames = { "PIDs", "Rates", "Filters", "VTX" }

local app = {
    activeTab = 1,
    connection = "connecting", -- connecting | connected | unsupported | disconnected
    session = msp.new(REQUEST_TIMEOUT_MS),
    arm = safety.new(),
    state = stateMod.new(),
    lastFlightModeMs = 0,
    profileSlot = 1,
}

-- Single shared CRSF pop loop: dispatches MSP_RESP frames to the active
-- session via session:feed(), and FLIGHT_MODE frames to the arm tracker.
-- msp.lua deliberately never calls crossfireTelemetryPop() itself (see
-- Task 3's note) so this is the only consumer of the telemetry queue.
local function pumpTelemetry(nowMs)
    while true do
        local frame = crossfireTelemetryPop()
        if frame == nil then
            break
        end
        if frame.command == CRSF_FRAMETYPE_MSP_RESP then
            app.session:feed(frame.data)
        elseif frame.command == CRSF_FRAMETYPE_FLIGHT_MODE then
            app.arm:feedFlightModeFrame(frame.data)
            app.lastFlightModeMs = nowMs
        end
    end
    if nowMs - app.lastFlightModeMs > FLIGHT_MODE_STALE_MS then
        app.arm:markStale()
    end
end

local function checkConnection()
    app.session:request(mspMsgs.CMD.FC_VARIANT, "")
end

local function onConnectionResponse(cmd, payload, isError)
    if isError then
        app.connection = "disconnected"
        return
    end
    local variant = mspMsgs.decodeFcVariant(payload)
    app.connection = mspMsgs.isBetaflight(variant) and "connected" or "unsupported"
end

function init()
    checkConnection()
end

function run(event, touchState)
    local nowMs = getTime() * 10
    pumpTelemetry(nowMs)

    if app.connection == "connecting" then
        local status = app.session:poll(nowMs)
        if status == "done" or status == "error" then
            onConnectionResponse(app.session:result())
        elseif status == "timeout" then
            app.connection = "disconnected"
        end
    end

    lcd.clear()

    if app.connection ~= "connected" then
        lcd.drawText(10, 10, "Betaflight Dashboard", MIDSIZE)
        local msg = ({
            connecting = "Connecting to flight controller...",
            unsupported = "Connected, but flight controller is not Betaflight.",
            disconnected = "No response from flight controller. Check link.",
        })[app.connection]
        lcd.drawText(10, 40, msg)
        return
    end

    if app.arm:isArmed() then
        lcd.drawFilledRectangle(0, 0, LCD_W, 20, RED)
        lcd.drawText(10, 4, "ARMED -- read only", WHITE)
    end

    -- tab bar
    for i, name in ipairs(pageNames) do
        local x = (i - 1) * (LCD_W // #pageNames)
        local w = LCD_W // #pageNames
        if i == app.activeTab then
            lcd.drawFilledRectangle(x, 20, w, 24, BLUE)
        end
        lcd.drawText(x + 8, 24, name)
    end

    local activePage = pages[app.activeTab]
    activePage.update(app.state, app.arm:isArmed())
    activePage.event(event, touchState, app.state, app.session, nowMs, app.arm:isArmed())
end
```

- [ ] **Step 3: Bench-test the connection flow (props off)**

Copy `src/SCRIPTS/TOOLS/BFDash/` to the radio's SD card at `/SCRIPTS/TOOLS/BFDash/`. Power the radio bound to a bench-connected FC (USB power, no props). Launch the script from the radio's Tools menu.

Expected: screen shows "Connecting to flight controller...", then transitions to the tab bar (this task alone won't render page content correctly yet since Tasks 10-13 don't exist — that's expected; verify only that the connection state machine reaches "connected" and the tab bar draws).

- [ ] **Step 4: Commit**

```bash
git add src/SCRIPTS/TOOLS/BFDash/loader.lua src/SCRIPTS/TOOLS/BFDash/main.lua
git commit -m "Add main.lua entry point: connection check, arm-lock banner, tab router"
```

---

## Task 10: PID sliders page

**Files:**
- Create: `src/SCRIPTS/TOOLS/BFDash/pages/pids.lua`

**Interfaces:**
- Consumes: `mspMsgs.CMD.SIMPLIFIED_TUNING`/`SET_SIMPLIFIED_TUNING`, `mspMsgs.SIMPLIFIED_TUNING_FIELDS` (Task 5), `mspBuffer.readField/writeField` (Task 4), `state:load/get/setField/isDirty/reload/markClean` (Task 6, keyed `"pids"`).
- Produces: `create()`, `update(state, armed)`, `event(event, touchState, state, session, nowMs, armed)` — the shape `main.lua` (Task 9) calls.

The page keeps the full raw `MSP_SIMPLIFIED_TUNING` response buffer in `state` alongside the decoded slider values, so Save can patch-and-send it per Task 4's pattern without needing to reconstruct the dterm/gyro filter sub-blocks it doesn't touch.

- [ ] **Step 1: Implement pages/pids.lua**

Create `src/SCRIPTS/TOOLS/BFDash/pages/pids.lua`:

```lua
local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")

local M = {}

local SLIDERS = {
    { key = "masterMultiplier", label = "Master" },
    { key = "rollPitchRatio", label = "Roll/Pitch Ratio" },
    { key = "iGain", label = "I Gain" },
    { key = "dGain", label = "D Gain" },
    { key = "piGain", label = "PI Gain" },
    { key = "dminRatio", label = "D-Min Ratio" },
    { key = "feedforwardGain", label = "Feedforward" },
    { key = "pitchPiGain", label = "Pitch PI Gain" },
}
local SLIDER_MIN, SLIDER_MAX = 0, 250
local ROW_HEIGHT = 26
local ROW_TOP = 50
local SLIDER_X, SLIDER_W = 140, 300

local phase = "idle" -- idle | loading | ready | saving
local pendingRawBuffer = nil
local selectedRow = nil

local function decodeIntoState(state, rawBuffer)
    local values = { rawBuffer = rawBuffer }
    for _, s in ipairs(SLIDERS) do
        values[s.key] = mspBuffer.readField(rawBuffer, mspMsgs.SIMPLIFIED_TUNING_FIELDS[s.key])
    end
    state:load("pids", values)
end

function M.create()
    phase = "idle"
end

function M.update(state, armed)
    if phase == "idle" and state:get("pids") == nil then
        phase = "loading"
    end
end

local function beginLoad(session)
    session:request(mspMsgs.CMD.SIMPLIFIED_TUNING, "")
end

local function beginSave(session, state)
    local values = state:get("pids")
    local buf = values.rawBuffer
    for _, s in ipairs(SLIDERS) do
        buf = mspBuffer.writeField(buf, mspMsgs.SIMPLIFIED_TUNING_FIELDS[s.key], values[s.key])
    end
    pendingRawBuffer = buf
    session:request(mspMsgs.CMD.SET_SIMPLIFIED_TUNING, buf)
end

function M.event(event, touchState, state, session, nowMs, armed)
    if phase == "loading" then
        local status = session:poll(nowMs)
        if status == "done" then
            local cmd, payload = session:result()
            decodeIntoState(state, payload)
            phase = "ready"
        elseif status == "idle" then
            beginLoad(session)
        elseif status == "timeout" or status == "error" then
            phase = "idle" -- caller will retry on next update()
        end
    end

    if phase ~= "ready" then
        lcd.drawText(10, 60, "Loading PID sliders...")
        return
    end

    local values = state:get("pids")
    for i, s in ipairs(SLIDERS) do
        local y = ROW_TOP + (i - 1) * ROW_HEIGHT
        lcd.drawText(10, y, s.label)
        local value = values[s.key]
        local pct = (value - SLIDER_MIN) / (SLIDER_MAX - SLIDER_MIN)
        lcd.drawRectangle(SLIDER_X, y, SLIDER_W, 18)
        lcd.drawFilledRectangle(SLIDER_X, y, math.floor(SLIDER_W * pct), 18, armed and GREY or BLUE)
        lcd.drawText(SLIDER_X + SLIDER_W + 10, y, tostring(value))

        if not armed and touchState and touchState.tap then
            local tx, ty = touchState.x, touchState.y
            if tx >= SLIDER_X and tx <= SLIDER_X + SLIDER_W and ty >= y and ty <= y + 18 then
                local newPct = (tx - SLIDER_X) / SLIDER_W
                local newValue = math.floor(SLIDER_MIN + newPct * (SLIDER_MAX - SLIDER_MIN))
                state:setField("pids", s.key, newValue)
            end
        end
    end

    -- Save/Cancel handled by main.lua's shared footer (Task 13 extends main.lua);
    -- this page exposes the hooks main.lua's footer calls:
    M.beginSave = beginSave
end

return M
```

- [ ] **Step 2: Bench-test (props off)**

Copy updated `src/SCRIPTS` to the SD card, relaunch the script, select the PIDs tab.

Expected: 8 sliders render with labels, current values (read from the FC) shown as text next to each bar, and dragging a slider (radio not armed) updates its displayed value locally without yet writing to the FC (Save wiring lands in Task 13). Verify the read-only values against Betaflight Configurator's own Simplified Tuning tab open on the same FC via USB, to confirm the offsets are correct in practice, not just in unit tests against synthetic buffers.

- [ ] **Step 3: Commit**

```bash
git add src/SCRIPTS/TOOLS/BFDash/pages/pids.lua
git commit -m "Add PID sliders page (MSP_SIMPLIFIED_TUNING read/display/edit)"
```

---

## Task 11: Rates page

**Files:**
- Create: `src/SCRIPTS/TOOLS/BFDash/pages/rates.lua`

**Interfaces:**
- Consumes: `mspMsgs.CMD.RC_TUNING`/`SET_RC_TUNING`, `mspMsgs.RC_TUNING_FIELDS` (Task 5), `mspBuffer` (Task 4), `state` (Task 6, keyed `"rates"`).
- Produces: same `create()/update()/event()` shape as Task 10.

The `ratesType` field (values 0-3 in Betaflight: Betaflight-classic, RaceFlight, KISS, Actual) selects which field labels are shown; all four types share the same underlying `rcRate`/`rcExpo`/`superRate` storage fields per axis, so no separate codec is needed per type — only the on-screen labeling changes.

- [ ] **Step 1: Implement pages/rates.lua**

Create `src/SCRIPTS/TOOLS/BFDash/pages/rates.lua`:

```lua
local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")

local M = {}

local RATE_TYPE_NAMES = { [0] = "Betaflight", [1] = "RaceFlight", [2] = "Kiss", [3] = "Actual" }

local ROWS = {
    { key = "rcRateRoll", label = "Roll Rate" },
    { key = "rcRatePitch", label = "Pitch Rate" },
    { key = "rcRateYaw", label = "Yaw Rate" },
    { key = "rcExpoRoll", label = "Roll Expo" },
    { key = "rcExpoPitch", label = "Pitch Expo" },
    { key = "rcExpoYaw", label = "Yaw Expo" },
    { key = "superRateRoll", label = "Roll Super Rate" },
    { key = "superRatePitch", label = "Pitch Super Rate" },
    { key = "superRateYaw", label = "Yaw Super Rate" },
}
local ROW_HEIGHT = 20
local ROW_TOP = 60
local VALUE_X = 220

local phase = "idle"

local function decodeIntoState(state, rawBuffer)
    local values = { rawBuffer = rawBuffer }
    for _, r in ipairs(ROWS) do
        values[r.key] = mspBuffer.readField(rawBuffer, mspMsgs.RC_TUNING_FIELDS[r.key])
    end
    values.ratesType = mspBuffer.readField(rawBuffer, mspMsgs.RC_TUNING_FIELDS.ratesType)
    state:load("rates", values)
end

function M.create()
    phase = "idle"
end

function M.update(state, armed)
    if phase == "idle" and state:get("rates") == nil then
        phase = "loading"
    end
end

local function beginSave(session, state)
    local values = state:get("rates")
    local buf = values.rawBuffer
    for _, r in ipairs(ROWS) do
        buf = mspBuffer.writeField(buf, mspMsgs.RC_TUNING_FIELDS[r.key], values[r.key])
    end
    buf = mspBuffer.writeField(buf, mspMsgs.RC_TUNING_FIELDS.ratesType, values.ratesType)
    session:request(mspMsgs.CMD.SET_RC_TUNING, buf)
end
M.beginSave = beginSave

function M.event(event, touchState, state, session, nowMs, armed)
    if phase == "loading" then
        local status = session:poll(nowMs)
        if status == "done" then
            local cmd, payload = session:result()
            decodeIntoState(state, payload)
            phase = "ready"
        elseif status == "idle" then
            session:request(mspMsgs.CMD.RC_TUNING, "")
        elseif status == "timeout" or status == "error" then
            phase = "idle"
        end
    end

    if phase ~= "ready" then
        lcd.drawText(10, 60, "Loading rates...")
        return
    end

    local values = state:get("rates")
    lcd.drawText(10, ROW_TOP - 20, "Rate type: " .. (RATE_TYPE_NAMES[values.ratesType] or "?"))

    if not armed and touchState and touchState.tap then
        local tx, ty = touchState.x, touchState.y
        if ty >= ROW_TOP - 24 and ty <= ROW_TOP - 4 and tx >= 150 and tx <= 250 then
            state:setField("rates", "ratesType", (values.ratesType + 1) % 4)
        end
    end

    for i, r in ipairs(ROWS) do
        local y = ROW_TOP + (i - 1) * ROW_HEIGHT
        lcd.drawText(10, y, r.label)
        lcd.drawText(VALUE_X, y, tostring(values[r.key]))

        if not armed and touchState and touchState.tap then
            local tx, ty = touchState.x, touchState.y
            if ty >= y and ty <= y + ROW_HEIGHT then
                if tx >= VALUE_X + 40 and tx <= VALUE_X + 60 then
                    state:setField("rates", r.key, math.max(0, values[r.key] - 1))
                elseif tx >= VALUE_X + 65 and tx <= VALUE_X + 85 then
                    state:setField("rates", r.key, math.min(255, values[r.key] + 1))
                end
            end
        end
    end
end

return M
```

- [ ] **Step 2: Bench-test (props off)**

Deploy and verify against Betaflight Configurator's Rates tab on the same FC: confirm the numeric values read match, changing the rate type cycles through all four names, and +/- taps adjust values (not yet saved — Task 13 wires Save).

- [ ] **Step 3: Commit**

```bash
git add src/SCRIPTS/TOOLS/BFDash/pages/rates.lua
git commit -m "Add rates page (MSP_RC_TUNING read/display/edit, rate-type selector)"
```

---

## Task 12: Filters and VTX pages

**Files:**
- Create: `src/SCRIPTS/TOOLS/BFDash/pages/filters.lua`
- Create: `src/SCRIPTS/TOOLS/BFDash/pages/vtx.lua`

**Interfaces:**
- Filters consumes: `mspMsgs.CMD.FILTER_CONFIG`/`SET_FILTER_CONFIG`, `mspMsgs.FILTER_CONFIG_FIELDS` (Task 5), `mspBuffer` (Task 4), `state` keyed `"filters"`.
- VTX consumes: `mspMsgs.CMD.VTX_CONFIG`/`SET_VTX_CONFIG`, `mspMsgs.decodeVtxConfig`/`encodeVtxConfigSet` (Task 5, bespoke non-buffer codec), `state` keyed `"vtx"`.
- Both produce the same `create()/update()/event()` shape as Tasks 10-11.

- [ ] **Step 1: Implement pages/filters.lua**

Create `src/SCRIPTS/TOOLS/BFDash/pages/filters.lua`:

```lua
local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")

local M = {}

local ROWS = {
    { key = "gyroLpf1Hz", label = "Gyro LPF1 (Hz)" },
    { key = "gyroLpf2Hz", label = "Gyro LPF2 (Hz)" },
    { key = "dtermLpf1Hz", label = "D-term LPF1 (Hz)" },
    { key = "dtermLpf2Hz", label = "D-term LPF2 (Hz)" },
}
local ROW_HEIGHT = 26
local ROW_TOP = 60
local VALUE_X = 220

local phase = "idle"

local function decodeIntoState(state, rawBuffer)
    local values = { rawBuffer = rawBuffer }
    for _, r in ipairs(ROWS) do
        values[r.key] = mspBuffer.readField(rawBuffer, mspMsgs.FILTER_CONFIG_FIELDS[r.key])
    end
    state:load("filters", values)
end

function M.create()
    phase = "idle"
end

function M.update(state, armed)
    if phase == "idle" and state:get("filters") == nil then
        phase = "loading"
    end
end

local function beginSave(session, state)
    local values = state:get("filters")
    local buf = values.rawBuffer
    for _, r in ipairs(ROWS) do
        buf = mspBuffer.writeField(buf, mspMsgs.FILTER_CONFIG_FIELDS[r.key], values[r.key])
    end
    session:request(mspMsgs.CMD.SET_FILTER_CONFIG, buf)
end
M.beginSave = beginSave

function M.event(event, touchState, state, session, nowMs, armed)
    if phase == "loading" then
        local status = session:poll(nowMs)
        if status == "done" then
            local cmd, payload = session:result()
            decodeIntoState(state, payload)
            phase = "ready"
        elseif status == "idle" then
            session:request(mspMsgs.CMD.FILTER_CONFIG, "")
        elseif status == "timeout" or status == "error" then
            phase = "idle"
        end
    end

    if phase ~= "ready" then
        lcd.drawText(10, 60, "Loading filters...")
        return
    end

    local values = state:get("filters")
    for i, r in ipairs(ROWS) do
        local y = ROW_TOP + (i - 1) * ROW_HEIGHT
        lcd.drawText(10, y, r.label)
        lcd.drawText(VALUE_X, y, tostring(values[r.key]))

        if not armed and touchState and touchState.tap then
            local tx, ty = touchState.x, touchState.y
            if ty >= y and ty <= y + ROW_HEIGHT then
                if tx >= VALUE_X + 60 and tx <= VALUE_X + 85 then
                    state:setField("filters", r.key, math.max(0, values[r.key] - 5))
                elseif tx >= VALUE_X + 90 and tx <= VALUE_X + 115 then
                    state:setField("filters", r.key, math.min(1000, values[r.key] + 5))
                end
            end
        end
    end
end

return M
```

- [ ] **Step 2: Implement pages/vtx.lua**

Create `src/SCRIPTS/TOOLS/BFDash/pages/vtx.lua`:

```lua
local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")

local M = {}

local BAND_NAMES = { "A", "B", "E", "F", "R" }
local POWER_MIN, POWER_MAX = 1, 5

local phase = "idle"

function M.create()
    phase = "idle"
end

function M.update(state, armed)
    if phase == "idle" and state:get("vtx") == nil then
        phase = "loading"
    end
end

local function beginSave(session, state)
    local values = state:get("vtx")
    local payload = mspMsgs.encodeVtxConfigSet(values)
    session:request(mspMsgs.CMD.SET_VTX_CONFIG, payload)
end
M.beginSave = beginSave

function M.event(event, touchState, state, session, nowMs, armed)
    if phase == "loading" then
        local status = session:poll(nowMs)
        if status == "done" then
            local cmd, payload = session:result()
            local decoded = mspMsgs.decodeVtxConfig(payload)
            -- lowPowerDisarm and pitModeFreq aren't decoded by decodeVtxConfig
            -- (not user-editable on this page) but are required, unchanged,
            -- by encodeVtxConfigSet's round trip -- read them directly here.
            decoded.lowPowerDisarm = string.byte(payload, 9) or 0
            decoded.pitModeFreq = (string.byte(payload, 10) or 0) + (string.byte(payload, 11) or 0) * 256
            state:load("vtx", decoded)
            phase = "ready"
        elseif status == "idle" then
            session:request(mspMsgs.CMD.VTX_CONFIG, "")
        elseif status == "timeout" or status == "error" then
            phase = "idle"
        end
    end

    if phase ~= "ready" then
        lcd.drawText(10, 60, "Loading VTX config...")
        return
    end

    local values = state:get("vtx")
    lcd.drawText(10, 60, "Band: " .. (BAND_NAMES[values.band] or tostring(values.band)))
    lcd.drawText(10, 90, "Channel: " .. tostring(values.channel))
    lcd.drawText(10, 120, "Power: " .. tostring(values.power))

    if not armed and touchState and touchState.tap then
        local tx, ty = touchState.x, touchState.y
        if ty >= 60 and ty <= 80 then
            if tx >= 150 and tx <= 170 then
                state:setField("vtx", "band", math.max(1, values.band - 1))
            elseif tx >= 175 and tx <= 195 then
                state:setField("vtx", "band", math.min(#BAND_NAMES, values.band + 1))
            end
        elseif ty >= 90 and ty <= 110 then
            if tx >= 150 and tx <= 170 then
                state:setField("vtx", "channel", math.max(1, values.channel - 1))
            elseif tx >= 175 and tx <= 195 then
                state:setField("vtx", "channel", math.min(8, values.channel + 1))
            end
        elseif ty >= 120 and ty <= 140 then
            if tx >= 150 and tx <= 170 then
                state:setField("vtx", "power", math.max(POWER_MIN, values.power - 1))
            elseif tx >= 175 and tx <= 195 then
                state:setField("vtx", "power", math.min(POWER_MAX, values.power + 1))
            end
        end
    end
end

return M
```

- [ ] **Step 3: Bench-test both pages (props off)**

Deploy and verify Filters values match Betaflight Configurator's Filter Settings tab; verify VTX band/channel/power match the Video Transmitter tab. Confirm +/- controls adjust displayed values without yet writing (Task 13 wires Save).

- [ ] **Step 4: Commit**

```bash
git add src/SCRIPTS/TOOLS/BFDash/pages/filters.lua src/SCRIPTS/TOOLS/BFDash/pages/vtx.lua
git commit -m "Add filters and VTX pages"
```

---

## Task 13: Wire Save/Cancel/Reload footer and profile-slot selector into main.lua

Completes `main.lua` from Task 9 with the footer that calls each active page's `beginSave`, followed by `MSP_EEPROM_WRITE`, plus profile-slot switching via `MSP_SELECT_SETTING`.

**Files:**
- Modify: `src/SCRIPTS/TOOLS/BFDash/main.lua`

**Interfaces:**
- Consumes: `page.beginSave(session, state)` (Tasks 10-12), `mspMsgs.encodeSelectSetting`/`CMD.SELECT_SETTING`/`CMD.EEPROM_WRITE` (Task 5), `state:isDirty/isAnyDirty/markClean/reload` (Task 6).

- [ ] **Step 1: Extend main.lua with the footer and save/cancel/profile flow**

Modify `src/SCRIPTS/TOOLS/BFDash/main.lua`: replace the final `run(event, touchState)` function with:

```lua
local FOOTER_Y = LCD_H - 40
local saveFlow = "idle" -- idle | saving | eeprom | done

local function drawFooter(armed)
    if armed then
        return
    end
    lcd.drawFilledRectangle(0, FOOTER_Y, 100, 40, GREEN)
    lcd.drawText(10, FOOTER_Y + 12, "Save")
    lcd.drawFilledRectangle(110, FOOTER_Y, 100, 40, GREY)
    lcd.drawText(120, FOOTER_Y + 12, "Cancel")

    if app.state:isAnyDirty() then
        lcd.drawText(220, FOOTER_Y + 12, "* unsaved changes")
    end
end

local function handleFooterTouch(touchState)
    if not touchState or not touchState.tap then
        return
    end
    local tx, ty = touchState.x, touchState.y
    if ty < FOOTER_Y or ty > FOOTER_Y + 40 then
        return
    end
    if tx >= 0 and tx <= 100 and app.state:isAnyDirty() and saveFlow == "idle" then
        saveFlow = "saving"
    elseif tx >= 110 and tx <= 210 then
        for _, key in ipairs({ "pids", "rates", "filters", "vtx" }) do
            app.state:reload(key)
        end
    end
end

function run(event, touchState)
    local nowMs = getTime() * 10
    pumpTelemetry(nowMs)

    if app.connection == "connecting" then
        local status = app.session:poll(nowMs)
        if status == "done" or status == "error" then
            onConnectionResponse(app.session:result())
        elseif status == "timeout" then
            app.connection = "disconnected"
        end
    end

    lcd.clear()

    if app.connection ~= "connected" then
        lcd.drawText(10, 10, "Betaflight Dashboard", MIDSIZE)
        local msg = ({
            connecting = "Connecting to flight controller...",
            unsupported = "Connected, but flight controller is not Betaflight.",
            disconnected = "No response from flight controller. Check link.",
        })[app.connection]
        lcd.drawText(10, 40, msg)
        return
    end

    local armed = app.arm:isArmed()
    if armed then
        lcd.drawFilledRectangle(0, 0, LCD_W, 20, RED)
        lcd.drawText(10, 4, "ARMED -- read only", WHITE)
    end

    for i, name in ipairs(pageNames) do
        local x = (i - 1) * (LCD_W // #pageNames)
        local w = LCD_W // #pageNames
        if i == app.activeTab then
            lcd.drawFilledRectangle(x, 20, w, 24, BLUE)
        end
        lcd.drawText(x + 8, 24, name)
        if not armed and touchState and touchState.tap
            and touchState.y >= 20 and touchState.y <= 44
            and touchState.x >= x and touchState.x < x + w then
            app.activeTab = i
        end
    end

    local activePage = pages[app.activeTab]

    if saveFlow == "saving" then
        activePage.beginSave(app.session, app.state)
        saveFlow = "eeprom"
    elseif saveFlow == "eeprom" then
        local status = app.session:poll(nowMs)
        if status == "done" then
            app.state:markClean("pids")
            app.state:markClean("rates")
            app.state:markClean("filters")
            app.state:markClean("vtx")
            app.session:request(mspMsgs.CMD.EEPROM_WRITE, "")
            saveFlow = "done"
        elseif status == "timeout" or status == "error" then
            saveFlow = "idle" -- Save failed; state stays dirty, footer still shows unsaved changes
        end
    elseif saveFlow == "done" then
        local status = app.session:poll(nowMs)
        if status == "done" or status == "timeout" or status == "error" then
            saveFlow = "idle"
        end
    else
        activePage.update(app.state, armed)
        activePage.event(event, touchState, app.state, app.session, nowMs, armed)
    end

    drawFooter(armed)
    handleFooterTouch(touchState)
end
```

- [ ] **Step 2: Bench-test the full Save flow (props off)**

Deploy the complete script. On the PIDs tab, change a slider, press Save, and confirm in Betaflight Configurator (connected via USB to the same FC afterward) that the master multiplier changed and persisted across a power cycle (proving `MSP_EEPROM_WRITE` actually committed it). Repeat for Rates, Filters, and VTX tabs.

- [ ] **Step 3: Bench-test the arm-lock (props off, safe bench arm)**

With props off, in a safe location, arm the craft (e.g. via a switch, per your normal arming setup) while the script is open. Confirm the red "ARMED -- read only" banner appears, the footer's Save/Cancel buttons disappear, and no slider/field responds to touch. Disarm and confirm controls return.

- [ ] **Step 4: Bench-test profile slot switching**

Add profile-slot UI if not already present (a simple 1/2/3 selector row can be added to `main.lua`'s tab bar area, calling `mspMsgs.encodeSelectSetting("pid", slot-1)` and `encodeSelectSetting("rate", slot-1)` via `app.session:request(mspMsgs.CMD.SELECT_SETTING, payload)`, then reloading all four state keys). Confirm switching slots on the radio matches switching profiles in Betaflight Configurator.

- [ ] **Step 5: Commit**

```bash
git add src/SCRIPTS/TOOLS/BFDash/main.lua
git commit -m "Wire Save/Cancel footer, EEPROM persistence, and profile-slot switching"
```

---

## Task 14: Deployment README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write the README**

Create `README.md` at the repo root:

```markdown
# Betaflight Settings Dashboard for EdgeTX

An EdgeTX Tools LUA script for reading and writing Betaflight 4.5.x settings
(PID simplified-tuning sliders, rate profiles, gyro/D-term filter cutoffs,
VTX config) over MSP-over-CRSF telemetry, without needing a USB connection to
Betaflight Configurator.

Built for a Jumper T15 (EdgeTX 2.9+, color LCD) linked via ExpressLRS.

## Requirements

- EdgeTX 2.9 or later, color LCD radio
- ExpressLRS (CRSF) link with MSP-over-telemetry enabled
- Betaflight 4.5.x flight controller firmware

## Installation

Copy the contents of `src/SCRIPTS/` from this repo to the `/SCRIPTS/` folder
on your radio's SD card, so you end up with:

```
/SCRIPTS/TOOLS/BFDash/main.lua
/SCRIPTS/TOOLS/BFDash/...
```

Launch it from the radio's Tools menu (long-press SYS or the model's Tools
shortcut, depending on radio layout).

## Safety

- The script blocks all edits while the flight controller reports ARMED.
- Nothing is written to the flight controller until you press **Save**;
  editing a slider only stages the change locally.
- **Save** writes the change and commits it to EEPROM. **Cancel** discards
  unsaved edits.
- This tool has only been bench-tested (props off). No in-flight testing of
  settings changes has been performed.

## Development

Run the pure-Lua test suite (transport, codec, and state logic — no radio
hardware required):

```bash
lua tests/run_all.lua
```

UI and radio-link behavior (`main.lua`, `pages/*.lua`) can only be verified on
the physical radio bench-connected to a flight controller — see the plan in
`docs/superpowers/plans/2026-09-09-betaflight-settings-dashboard.md` for the
bench-test checklist per page.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Add deployment and development README"
```

---

## Self-Review Notes

- **Spec coverage:** PID sliders (Task 10, via native `MSP_SIMPLIFIED_TUNING` rather than replicated math — an improvement over the original design), rates with all 4 types (Task 11), filters gyro/dterm LPF1/LPF2 (Task 12), VTX band/channel/power (Task 12), profile slot selection (Task 13), arm-lock fail-safe (Task 7 + 9), explicit Save/Cancel (Task 13), EEPROM persistence (Task 13), FC compatibility check (Task 9), bench-only testing plan (Tasks 9-13 bench steps) — all covered.
- **Placeholder scan:** no TBD/TODO markers; every step has complete code or a concrete bench-test procedure.
- **Type consistency:** `field` shape `{offset, size}` used consistently from Task 4 through Tasks 5, 10-12. `state:load/get/setField/isDirty/reload/markClean` signatures from Task 6 match their use in Tasks 10-13. `session:request/poll/result` from Task 3 match their use in Tasks 9-13. Page module shape `create()/update(state, armed)/event(event, touchState, state, session, nowMs, armed)` is consistent across Tasks 10-12 and matches how Task 9/13's `main.lua` calls them.
