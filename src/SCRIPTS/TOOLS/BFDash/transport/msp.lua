local mspChunk = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspChunk.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspChunk.lua")

-- 0x7A (CRSF_FRAMETYPE_MSP_REQ) is used for BOTH reads and writes. Betaflight's
-- MSP-over-telemetry handler replies only to 0x7A; 0x7C (MSP_WRITE) is a
-- fire-and-forget frame type that produces no response, and this session (and
-- the save flow built on it) depends on getting a reply to confirm the write.
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
