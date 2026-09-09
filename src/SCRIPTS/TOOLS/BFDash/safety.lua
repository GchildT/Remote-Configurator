local M = {}
local Tracker = {}
Tracker.__index = Tracker

function M.new()
    return setmetatable({ armed = true, stale = true, lastRawText = nil, frameCount = 0 }, Tracker)
end

-- Verified from Betaflight src/main/telemetry/crsf.c: crsfFrameFlightMode().
-- 4.5.5: writes a trailing '*' ONLY when NOT armed. Absence of '*' = armed.
-- 2026.6.1: writes a trailing '*' (ready to arm), '!' (arming disabled), or
-- '?' (GPS rescue unavailable) ONLY when NOT armed AND NOT in failsafe.
-- Absence of any suffix = armed. During failsafe, the mode text is the fixed
-- string "!FS!" and NO suffix logic runs at all -- that text is therefore
-- ambiguous about arm state and is special-cased below to fail safe (locked).
function Tracker:feedFlightModeFrame(data)
    if type(data) ~= "string" or data == "" then
        -- Malformed/missing frame: do not update armed state, and do not
        -- clear stale. If this is the first frame ever, isArmed() still
        -- fail-safes to armed via stale. If a later frame is malformed,
        -- the previous (or stale) state continues to govern isArmed().
        return
    end
    local ok, text = pcall(function()
        return string.match(data, "^[^%z]*") or data -- strip trailing null terminator(s)
    end)
    if not ok or type(text) ~= "string" then
        return
    end
    if text == "!FS!" then
        -- Failsafe mode name, no suffix logic applied by the FC -- arm state
        -- is undeterminable from this text alone. Fail safe: treat as armed.
        self.armed = true
    else
        local lastChar = string.sub(text, -1)
        local hasDisarmSuffix = lastChar == "*" or lastChar == "!" or lastChar == "?"
        self.armed = not hasDisarmSuffix
    end
    self.stale = false
    self.lastRawText = text
    self.frameCount = self.frameCount + 1
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

function Tracker:isStale()
    return self.stale
end

-- Diagnostic accessor: lets the UI show whether/what flight-mode frames are
-- actually being received, for bench-testing the arm-lock. Not used by any
-- safety-relevant logic itself.
function Tracker:debugInfo()
    return self.stale, self.armed, self.lastRawText, self.frameCount
end

return M
