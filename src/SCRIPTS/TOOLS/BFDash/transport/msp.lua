local mspChunk = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspChunk.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspChunk.lua")

-- 0x7A (CRSF_FRAMETYPE_MSP_REQ) is used for BOTH reads and writes. Betaflight's
-- MSP-over-telemetry handler replies only to 0x7A; 0x7C (MSP_WRITE) is a
-- fire-and-forget frame type that produces no response, and this session (and
-- the save flow built on it) depends on getting a reply to confirm the write.
local CRSF_FRAMETYPE_MSP_REQ = 0x7A

-- Confirmed against Betaflight firmware source (src/main/rx/crsf.c: the
-- CRSF_FRAMETYPE_MSP_REQ/MSP_WRITE case strips exactly
-- CRSF_FRAME_ORIGIN_DEST_SIZE=2 leading bytes -- [[destination][origin]] --
-- before treating the remainder as the MSP-over-telemetry chunk that
-- mspChunk.lua builds; src/main/telemetry/msp_shared.c's own header comment
-- documents the same layout: "<sync/address><length><type><destination>
-- <origin><status><MSP_body><CRC>". Without these two bytes, Betaflight
-- misreads the MSP status byte as a destination address, fails the address
-- check, and silently drops the frame -- no error, no response, exactly the
-- "no response from flight controller" symptom this fixed.
local CRSF_ADDRESS_FLIGHT_CONTROLLER = 0xC8 -- destination: this session always talks to the FC
local CRSF_ADDRESS_RADIO_TRANSMITTER = 0xEA -- origin: this session always speaks as the radio

-- Confirmed against EdgeTX firmware source (radio/src/lua/api_general.cpp,
-- luaCrossfireTelemetryPush/Pop): crossfireTelemetryPush's second argument
-- must be a Lua TABLE of byte values (1-indexed), not a packed string --
-- EdgeTX builds the actual CRSF frame (address/length/CRC) around it. The
-- rest of this codebase (mspChunk.lua's chunk framing, the MSP status byte,
-- etc.) works entirely in byte strings, which is the right internal
-- representation -- these are the sole adapters at the boundary.
local function chunkToOutgoingTable(s)
    local t = { CRSF_ADDRESS_FLIGHT_CONTROLLER, CRSF_ADDRESS_RADIO_TRANSMITTER }
    for i = 1, #s do
        t[#t + 1] = string.byte(s, i)
    end
    return t
end

local function tableToString(t)
    local s = ""
    for i = 1, #t do
        s = s .. string.char(t[i])
    end
    return s
end

-- Betaflight's MSP_RESP frame carries the same 2-byte [destination][origin]
-- prefix as our outgoing requests (src/main/telemetry/crsf.c:
-- crsfSendMspResponse writes [mspRequestOriginID][CRSF_ADDRESS_FLIGHT_
-- CONTROLLER] before the MSP chunk). Strip it before handing the rest to
-- mspChunk's assembler, which expects to see the MSP status byte first.
local function responseTableToChunkString(packet)
    return string.sub(tableToString(packet), 3)
end

local M = {}
M.tableToString = tableToString
M.responseTableToChunkString = responseTableToChunkString

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
    if self.state == "pending" then
        error("msp session: request() called while a previous request is still pending")
    end
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
        crossfireTelemetryPush(CRSF_FRAMETYPE_MSP_REQ, chunkToOutgoingTable(chunk))
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
    local ok, complete = pcall(function() return self.assembler:feed(data) end)
    if not ok then
        self.state = "error"
        return
    end
    if complete then
        local cmd, payload, isError = self.assembler:result()
        self.resultCmd, self.resultPayload, self.resultIsError = cmd, payload, isError
        self.state = isError and "error" or "done"
    end
end

-- Return the session to "idle" and drop any stored result. Callers use this to
-- discard a terminal state they are NOT consuming via result() -- notably the
-- "timeout"/"error" branches, which would otherwise leave the session stuck in
-- that terminal state forever (nothing else ever clears it).
function Session:reset()
    self.outgoing = nil
    self.assembler = nil
    self.startedAtMs = nil
    self.state = "idle"
    self.resultCmd, self.resultPayload, self.resultIsError = nil, nil, nil
end

-- Consuming accessor: returns the completed result AND returns the session to
-- "idle" so the next caller's poll() sees a free session and issues its own
-- request(). Without this reset, a completed session stays "done" forever and
-- every later caller takes its decode branch on the previous caller's payload.
function Session:result()
    local cmd, payload, isError = self.resultCmd, self.resultPayload, self.resultIsError
    self:reset()
    return cmd, payload, isError
end

function Session:isPending()
    return self.state == "pending"
end

return M
