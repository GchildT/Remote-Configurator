-- EdgeTX embeds Lua 5.2.2 (confirmed from the EdgeTX firmware source), which
-- has no native bitwise operators (`|`/`&`/`<<`/`~`, added in 5.3) and no
-- floor-division operator (`//`, also added in 5.3). Every bit-manipulation
-- and integer-division below is written as portable arithmetic instead:
-- `math.floor(x)` for floor division, `+` for OR-ing disjoint bit fields,
-- `% (2^n)` for masking the low n bits, and `math.floor(x / 2^n) % 2` for
-- testing a single bit.
local M = {}

local MSP_VERSION = 2
local CHUNK_MAX = 8 -- radio -> FC per-chunk payload cap (CRSF_FRAME_RX_MSP_FRAME_SIZE)

local STATUS_SEQ_MASK = 0x0f
local STATUS_START_MASK = 0x10
local STATUS_VERSION_SHIFT = 5
local STATUS_ERROR_MASK = 0x80

local function hasBit(value, singleBitValue)
    return math.floor(value / singleBitValue) % 2 == 1
end

function M.buildRequestChunks(cmd, payload)
    payload = payload or ""
    local size = #payload
    local header = string.char(
        0, -- status placeholder, patched per-chunk below
        0, -- flags
        cmd % 256, math.floor(cmd / 256),
        size % 256, math.floor(size / 256)
    )

    local chunks = {}
    local seq = 0

    -- first chunk: header (minus status byte) + as much payload as fits
    local firstPayloadRoom = CHUNK_MAX - #header
    local firstPayload = payload:sub(1, firstPayloadRoom)
    -- STATUS_START_MASK (bit 4), the shifted version (bits 5-6), and the
    -- masked seq (bits 0-3) never overlap, so OR-ing them is addition.
    local status = STATUS_START_MASK + (MSP_VERSION * (2 ^ STATUS_VERSION_SHIFT)) + (seq % (STATUS_SEQ_MASK + 1))
    table.insert(chunks, string.char(status) .. header:sub(2) .. firstPayload)

    local remaining = payload:sub(firstPayloadRoom + 1)
    while #remaining > 0 do
        seq = seq + 1
        local room = CHUNK_MAX - 1 -- 1 byte for status
        local piece = remaining:sub(1, room)
        remaining = remaining:sub(room + 1)
        local contStatus = (MSP_VERSION * (2 ^ STATUS_VERSION_SHIFT)) + (seq % (STATUS_SEQ_MASK + 1))
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
    local seq = status % (STATUS_SEQ_MASK + 1)
    local isStart = hasBit(status, STATUS_START_MASK)

    if isStart then
        self.isError = hasBit(status, STATUS_ERROR_MASK)
        self.cmd = string.byte(chunk, 3) + string.byte(chunk, 4) * 256
        self.expectedSize = string.byte(chunk, 5) + string.byte(chunk, 6) * 256
        self.buf = chunk:sub(7)
        self.started = true
        self.lastSeq = seq
    else
        if not self.started then
            error("continuation chunk received before a start chunk")
        end
        local expectedSeq = (self.lastSeq + 1) % (STATUS_SEQ_MASK + 1)
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
