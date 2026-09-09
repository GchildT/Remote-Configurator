local M = {}
local Tracker = {}
Tracker.__index = Tracker

function M.new()
    return setmetatable({ armed = true, stale = true }, Tracker)
end

-- Verified from Betaflight 4.5.5 src/main/telemetry/crsf.c: crsfFrameFlightMode()
-- writes a trailing '*' ONLY when NOT armed. Absence of '*' = armed.
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
    local endsWithStar = string.sub(text, -1) == "*"
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
