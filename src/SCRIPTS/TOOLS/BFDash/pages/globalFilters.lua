local ui = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/ui.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/ui.lua")

-- Explicit RGB colors rather than named constants -- see main.lua's note.
local COLOR_WHITE = lcd.RGB(255, 255, 255)
local COLOR_YELLOW = lcd.RGB(255, 210, 0)
local COLOR_BLUE = lcd.RGB(40, 110, 220)
local COLOR_GREY = lcd.RGB(130, 130, 130)

-- Confirmed against EdgeTX firmware source (radio/src/keys.h).
local EVT_ROTARY_LEFT = 0x1003
local EVT_ROTARY_RIGHT = 0x1004

local M = {}

-- filtersShared is NOT loaded here with the usual loadScript/dofile-in-file
-- pattern: EdgeTX's loadScript() (like Lua's own loadfile/dofile) compiles
-- and returns a fresh chunk on every call, with no require()-style caching.
-- filtersShared.lua carries genuinely mutable, must-be-shared state (load
-- phase, in-flight multiplier-calc tracking) between this tab and
-- pages/profileFilters.lua, so loading it independently here (a second,
-- unrelated instance) would silently break that sharing. main.lua loads it
-- exactly once and injects that single instance via M.init() instead -- see
-- main.lua's setup and filtersShared.lua's header comment.
local shared = nil

function M.init(sharedFiltersModule)
    shared = sharedFiltersModule
end

-- "Global Filters" -- the profile-INDEPENDENT half of Betaflight's Filter
-- Settings screen (gyroConfig() is a single global struct shared across all
-- 3 PID profiles, unlike the D-term/yaw fields on the Profile Filters tab).
-- Field order matches Configurator's own screen top-to-bottom: Gyro Filter
-- Multiplier slider, Gyro Lowpass Filters, Gyro Notch Filters, Gyro RPM
-- Filter, Dynamic Notch Filter. All data/save logic is shared with
-- pages/profileFilters.lua via filtersShared.lua -- see that file's header
-- comment for why (both tabs edit the same underlying MSP_FILTER_CONFIG
-- buffer).
local ROWS = {
    { { key = "gyroLpf1Hz", label = "Gyro Lowpass 1 [Hz]" }, { key = "gyroLpf1Type", label = "Type" } },
    { { key = "gyroLpf2Hz", label = "Gyro Lowpass 2 [Hz]" }, { key = "gyroLpf2Type", label = "Type" } },
    { { key = "gyroNotch1Hz", label = "Gyro Notch 1 Center [Hz]" }, { key = "gyroNotch1Cutoff", label = "Cutoff [Hz]" } },
    { { key = "gyroNotch2Hz", label = "Gyro Notch 2 Center [Hz]" }, { key = "gyroNotch2Cutoff", label = "Cutoff [Hz]" } },
    { { key = "rpmFilterHarmonics", label = "RPM Filter Harmonics" }, { key = "rpmFilterMinHz", label = "Min Hz" } },
    { { key = "dynNotchCount", label = "Dyn Notch Count" }, { key = "dynNotchQ", label = "Q Factor" } },
    { { key = "dynNotchMinHz", label = "Dyn Notch Min Hz" }, { key = "dynNotchMaxHz", label = "Max Hz" } },
}

-- Layout: content starts a few px below the tab bar + profile row (which end
-- at y=64), so it doesn't crowd it, and must finish above the footer at
-- y=232. Slider row (20px) + spacer (10px) + 7 field rows * 18px = 156px,
-- span y=70..226.
local CONTENT_TOP = 70
local SLIDER_ROW_H = 20
local SPACER_H = 10
local ROW_H = 18
local COL_X, COL_W = 6, 468
local SLIDER_X, SLIDER_W, SLIDER_H = 220, 180, 18
local VALUE_X = 410

local focusedKey = nil -- raw field key | "mult:gyro" | nil

function M.create()
    shared.create()
    focusedKey = nil
end

function M.update(state, armed)
    shared.update(state, armed)
end

function M.beginSave(session, state)
    shared.beginSave(session, state)
end

local function fieldValueText(key, values)
    return shared.fieldValueText(key, values)
end

local function drawField(x, w, y, field, values, touchState, armed)
    local isFocused = (focusedKey == field.key)
    local color = isFocused and COLOR_YELLOW or COLOR_WHITE
    lcd.drawText(x, y, field.label .. ": " .. fieldValueText(field.key, values), color)
    if not armed and ui.rowTapped(touchState, x, x + w, y, ROW_H) then
        focusedKey = isFocused and nil or field.key
    end
end

local function drawRow(x, w, y, row, values, touchState, armed)
    local halfW = w / 2
    drawField(x, row[2] and halfW or w, y, row[1], values, touchState, armed)
    if row[2] then
        drawField(x + halfW, halfW, y, row[2], values, touchState, armed)
    end
end

-- Slider supports both jog-dial stepping (while focused, handled in
-- M.event below via shared.adjustFocusedField) AND direct touch-drag: a
-- touch landing inside the bar itself sets the value straight from the
-- touch's x position, same as dragging a real slider, and also focuses it
-- so the dial can keep adjusting from there. A touch elsewhere on the row
-- (the label or value text) just toggles focus, matching every other row.
local function drawMultiplierSlider(x, w, y, values, touchState, armed, state)
    local isFocused = (focusedKey == "mult:gyro")
    local color = isFocused and COLOR_YELLOW or COLOR_WHITE
    lcd.drawText(x, y, "Gyro Filter Multiplier", color)
    ui.drawSliderBar(SLIDER_X, y, SLIDER_W, SLIDER_H, values.gyroFilterMultiplier, shared.MULT_MIN, shared.MULT_MAX,
        color, isFocused and COLOR_YELLOW or COLOR_BLUE)
    lcd.drawText(VALUE_X, y, string.format("%.2f", values.gyroFilterMultiplier / 100), color)

    if armed then
        return
    end
    local dragValue = ui.sliderTouchValue(touchState, SLIDER_X, SLIDER_W, y, SLIDER_H, shared.MULT_MIN, shared.MULT_MAX)
    if dragValue then
        focusedKey = "mult:gyro"
        shared.setMultiplier("gyro", state, dragValue)
    elseif ui.rowTapped(touchState, x, x + w, y, SLIDER_ROW_H) then
        focusedKey = isFocused and nil or "mult:gyro"
    end
end

function M.event(event, touchState, state, session, nowMs, armed)
    local values = shared.ensureLoaded(session, nowMs, state, CONTENT_TOP, "Loading global filters...")
    if values == nil then
        return
    end

    if not armed and focusedKey ~= nil and (event == EVT_ROTARY_LEFT or event == EVT_ROTARY_RIGHT) then
        local delta = (event == EVT_ROTARY_RIGHT) and 1 or -1
        shared.adjustFocusedField(focusedKey, delta, values, state)
        values = state:get(shared.PAGE_KEY) -- re-fetch: the adjustment above may have staged new values
    end

    if not armed then
        shared.pumpMultiplierCalc(session, state, values, nowMs)
        values = state:get(shared.PAGE_KEY) -- pumpMultiplierCalc may have just applied a computed result
    end

    local y = CONTENT_TOP
    drawMultiplierSlider(COL_X, COL_W, y, values, touchState, armed, state)
    y = y + SLIDER_ROW_H + SPACER_H

    for _, row in ipairs(ROWS) do
        drawRow(COL_X, COL_W, y, row, values, touchState, armed)
        y = y + ROW_H
    end
end

return M
