-- Small shared hit-testing helper for pages' "whole row is tappable"
-- interaction model.
local M = {}

-- Whole-row tap target: spans [xMin, xMax) horizontally and [y, y+h)
-- vertically. Used so tapping anywhere on a row's label or value
-- focuses/activates it -- not just the narrow value text itself.
function M.rowTapped(touchState, xMin, xMax, y, h)
    if not touchState then
        return false
    end
    local tx, ty = touchState.x, touchState.y
    return tx >= xMin and tx < xMax and ty >= y and ty < y + h
end

return M
