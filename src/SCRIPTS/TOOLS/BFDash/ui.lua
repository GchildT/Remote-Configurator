-- Small shared hit-testing/drawing helpers for pages' "whole row is
-- tappable" interaction model and PID-slider-style graphical sliders.
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

-- Draws a proportional-fill slider bar, matching pages/pids.lua's PID
-- slider look exactly (outlined rectangle + filled-to-value-percent
-- rectangle inside it). `value` is clamped into [min, max] before computing
-- the fill percentage, so a caller never needs to pre-clamp for display.
function M.drawSliderBar(x, y, w, h, value, min, max, outlineColor, fillColor)
    local clamped = math.max(min, math.min(max, value))
    local pct = (clamped - min) / (max - min)
    lcd.drawRectangle(x, y, w, h, outlineColor)
    lcd.drawFilledRectangle(x, y, math.floor(w * pct), h, fillColor)
end

return M
