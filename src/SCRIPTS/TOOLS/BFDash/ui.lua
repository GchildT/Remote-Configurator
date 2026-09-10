-- Small shared drawing/hit-testing helpers used by pages with on/off toggle
-- rows (Filters, Throttle/Motor) and by every page's "whole row is tappable"
-- interaction model.
local M = {}

-- Draws a compact on/off toggle: a filled rounded-looking box (plain
-- rectangle -- EdgeTX's lcd API used here has no rounded-rect primitive)
-- with "ON"/"OFF" text, colored to match state and focus. x/y is the
-- top-left corner; the box is a fixed small size so callers can lay out
-- consistently.
local TOGGLE_W, TOGGLE_H = 34, 16

function M.toggleSize()
    return TOGGLE_W, TOGGLE_H
end

function M.drawToggle(x, y, on, focused, colors)
    local fill = on and colors.on or colors.off
    if focused then
        fill = colors.focused
    end
    lcd.drawFilledRectangle(x, y, TOGGLE_W, TOGGLE_H, fill)
    lcd.drawText(x + 4, y + 2, on and "ON" or "OFF", colors.text)
end

-- Whole-row tap target: spans [xMin, xMax) horizontally and [y, y+h)
-- vertically. Used so tapping anywhere on a row's label, value, or toggle
-- focuses/activates it -- not just the narrow control itself.
function M.rowTapped(touchState, xMin, xMax, y, h)
    if not touchState then
        return false
    end
    local tx, ty = touchState.x, touchState.y
    return tx >= xMin and tx < xMax and ty >= y and ty < y + h
end

return M
