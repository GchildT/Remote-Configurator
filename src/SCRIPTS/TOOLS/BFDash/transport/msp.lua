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

function Session:result()
    return self.resultCmd, self.resultPayload, self.resultIsError
end

function Session:isPending()
    return self.state == "pending"
end

return M
