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
