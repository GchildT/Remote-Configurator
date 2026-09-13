-- Explicit RGB colors rather than named constants -- see main.lua's note.
local COLOR_WHITE = lcd.RGB(255, 255, 255)
local COLOR_YELLOW = lcd.RGB(255, 210, 0)
local COLOR_GREY = lcd.RGB(150, 150, 150)

-- Confirmed against EdgeTX firmware source (radio/src/keys.h).
local EVT_ROTARY_LEFT = 0x1003
local EVT_ROTARY_RIGHT = 0x1004

local M = {}

-- ratesShared is NOT loaded here with the usual loadScript/dofile-in-file
-- pattern: EdgeTX's loadScript() (like Lua's own loadfile/dofile) compiles
-- and returns a fresh chunk on every call, with no require()-style caching.
-- ratesShared.lua carries genuinely mutable state (load phase) that both
-- this tab and pages/ratesCurves.lua must share, so loading it independently
-- here (a second, unrelated instance) would silently break that sharing.
-- main.lua loads it exactly once and injects that single instance via
-- M.init() instead -- see main.lua's setup and ratesShared.lua's header.
local shared = nil

function M.init(sharedRatesModule)
    shared = sharedRatesModule
end

-- Confirmed against Betaflight Configurator source
-- (src/components/tabs/pid-tuning/RatesSubTab.vue: const RatesType = {...}).
local RATES_TYPE_BETAFLIGHT = 0
local RATES_TYPE_RACEFLIGHT = 1
local RATES_TYPE_KISS = 2
local RATES_TYPE_ACTUAL = 3
local RATES_TYPE_QUICKRATES = 4
local RATE_TYPE_NAMES = {
    [RATES_TYPE_BETAFLIGHT] = "Betaflight",
    [RATES_TYPE_RACEFLIGHT] = "RaceFlight",
    [RATES_TYPE_KISS] = "Kiss",
    [RATES_TYPE_ACTUAL] = "Actual",
    [RATES_TYPE_QUICKRATES] = "QuickRates",
}
local RATE_TYPE_COUNT = 5

-- Raw MSP bytes are decoded to a "Configurator float" by /100 (confirmed
-- against betaflight-configurator source, src/js/msp/MSPHelper.js: every
-- RC_TUNING field is `data.readU8() / 100`), then scaled per rate type for
-- display (confirmed against RatesSubTab.vue: getScaleFactor/
-- getRateScaleFactor). This is a DISPLAY-only transform -- the raw byte
-- staged in state and adjusted by the jog dial is unchanged, so a dial step
-- of 1 raw unit lands on a sensible display step for every type (e.g. 10
-- deg/s per click for Actual's Center Sensitivity/Max Rate, matching how
-- Configurator's own UI steps these fields).
local function formatCenterSensitivity(raw, ratesType)
    local scaled = raw / 100
    if ratesType == RATES_TYPE_RACEFLIGHT or ratesType == RATES_TYPE_ACTUAL then
        return tostring(math.floor(scaled * 1000 + 0.5))
    end
    return string.format("%.2f", scaled)
end

local function formatMaxRate(raw, ratesType)
    local scaled = raw / 100
    if ratesType == RATES_TYPE_RACEFLIGHT then
        return tostring(math.floor(scaled * 100 + 0.5))
    elseif ratesType == RATES_TYPE_ACTUAL or ratesType == RATES_TYPE_QUICKRATES then
        return tostring(math.floor(scaled * 1000 + 0.5))
    end
    return string.format("%.2f", scaled)
end

local function formatExpo(raw, ratesType)
    local scaled = raw / 100
    if ratesType == RATES_TYPE_RACEFLIGHT then
        return tostring(math.floor(scaled * 100 + 0.5))
    end
    return string.format("%.2f", scaled)
end

-- 3x3 grid: rows are axes, columns are field groups -- matches Configurator's
-- own Rates tab layout (Center Sensitivity / Max Rate / Expo as columns).
local AXES = { "Roll", "Pitch", "Yaw" }
local COLUMNS = {
    { header = "Sensitivity", keys = { "rcRateRoll", "rcRatePitch", "rcRateYaw" }, format = formatCenterSensitivity },
    { header = "Max Rate", keys = { "superRateRoll", "superRatePitch", "superRateYaw" }, format = formatMaxRate },
    { header = "Expo", keys = { "rcExpoRoll", "rcExpoPitch", "rcExpoYaw" }, format = formatExpo },
}
-- Flat list of all 9 editable cells, built once: each is {key, format, col, row}.
local CELLS = {}
for c, col in ipairs(COLUMNS) do
    for r = 1, 3 do
        CELLS[#CELLS + 1] = { key = col.keys[r], format = col.format, col = c, row = r }
    end
end

-- Layout: content starts at y=86 (below tab bar + profile row, with a blank
-- gap so it doesn't visually crowd the profile row) and must finish above
-- the footer at y=232. Rate-type row, then column headers, then 3 axis rows
-- spaced to stay well clear of both boundaries.
local CONTENT_TOP = 86
local TYPE_Y = CONTENT_TOP
local TYPE_H = 18
local TYPE_X, TYPE_W = 150, 100
local HEADER_Y = 112
local AXIS_LABEL_X = 10
local COLUMN_X = { 100, 230, 360 }
local COLUMN_W = 110
local ROW_Y = { 138, 170, 202 }
local ROW_H = 26

local focusedCell = nil -- index into CELLS of the currently jog-dial-editable field, or nil

function M.create()
    shared.create()
    focusedCell = nil
end

function M.update(state, armed)
    shared.update(state, armed)
end

function M.beginSave(session, state)
    shared.beginSave(session, state)
end

function M.event(event, touchState, state, session, nowMs, armed)
    local values = shared.ensureLoaded(session, nowMs, state, CONTENT_TOP, "Loading rates...")
    if values == nil then
        return
    end

    lcd.drawText(10, TYPE_Y, "Rate type: " .. (RATE_TYPE_NAMES[values.ratesType] or "?"), COLOR_WHITE)

    if not armed and touchState then
        local tx, ty = touchState.x, touchState.y
        if ty >= TYPE_Y and ty < TYPE_Y + TYPE_H and tx >= TYPE_X and tx < TYPE_X + TYPE_W then
            state:setField(shared.PAGE_KEY, "ratesType", (values.ratesType + 1) % RATE_TYPE_COUNT)
        end
    end

    -- Jog-dial adjusts whichever cell is currently focused (tapped). The dial
    -- always steps the underlying raw MSP byte by 1 -- the format() functions
    -- above translate that into a sensible-looking display step per rate type.
    if not armed and focusedCell ~= nil and (event == EVT_ROTARY_LEFT or event == EVT_ROTARY_RIGHT) then
        local delta = (event == EVT_ROTARY_RIGHT) and 1 or -1
        local cell = CELLS[focusedCell]
        local newValue = values[cell.key] + delta
        newValue = math.max(0, math.min(255, newValue))
        state:setField(shared.PAGE_KEY, cell.key, newValue)
    end

    for c, col in ipairs(COLUMNS) do
        lcd.drawText(COLUMN_X[c], HEADER_Y, col.header, COLOR_GREY)
    end
    for r, axisName in ipairs(AXES) do
        lcd.drawText(AXIS_LABEL_X, ROW_Y[r], axisName, COLOR_WHITE)
    end

    for i, cell in ipairs(CELLS) do
        local x = COLUMN_X[cell.col]
        local y = ROW_Y[cell.row]
        local isFocused = (focusedCell == i)
        local text = cell.format(values[cell.key], values.ratesType)
        lcd.drawText(x, y, text, isFocused and COLOR_YELLOW or COLOR_WHITE)

        if not armed and touchState then
            local tx, ty = touchState.x, touchState.y
            if tx >= x and tx < x + COLUMN_W and ty >= y - 4 and ty < y + ROW_H - 4 then
                focusedCell = isFocused and nil or i
            end
        end
    end
end

return M
