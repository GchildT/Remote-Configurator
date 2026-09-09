local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")

-- Explicit RGB colors rather than named constants -- see main.lua's note.
local COLOR_WHITE = lcd.RGB(255, 255, 255)
local COLOR_YELLOW = lcd.RGB(255, 210, 0)
local COLOR_GREY = lcd.RGB(150, 150, 150)

-- Confirmed against EdgeTX firmware source (radio/src/keys.h).
local EVT_ROTARY_LEFT = 0x1003
local EVT_ROTARY_RIGHT = 0x1004

local M = {}

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

-- Layout: content starts at y=66 (below tab bar + profile row) and must finish
-- above the footer at y=232. Rate-type row, then column headers, then 3 axis
-- rows spaced to stay well clear of both boundaries.
local CONTENT_TOP = 66
local TYPE_Y = CONTENT_TOP
local TYPE_H = 18
local TYPE_X, TYPE_W = 150, 100
local HEADER_Y = 92
local AXIS_LABEL_X = 10
local COLUMN_X = { 100, 230, 360 }
local COLUMN_W = 110
local ROW_Y = { 118, 150, 182 }
local ROW_H = 26

local phase = "idle"
local focusedCell = nil -- index into CELLS of the currently jog-dial-editable field, or nil

local function decodeIntoState(state, rawBuffer)
    local values = { rawBuffer = rawBuffer }
    for _, cell in ipairs(CELLS) do
        values[cell.key] = mspBuffer.readField(rawBuffer, mspMsgs.RC_TUNING_FIELDS[cell.key])
    end
    values.ratesType = mspBuffer.readField(rawBuffer, mspMsgs.RC_TUNING_FIELDS.ratesType)
    state:load("rates", values)
end

function M.create()
    phase = "idle"
    focusedCell = nil
end

function M.update(state, armed)
    if phase == "idle" and state:get("rates") == nil then
        phase = "loading"
    end
end

local function beginSave(session, state)
    local values = state:get("rates")
    local buf = values.rawBuffer
    for _, cell in ipairs(CELLS) do
        buf = mspBuffer.writeField(buf, mspMsgs.RC_TUNING_FIELDS[cell.key], values[cell.key])
    end
    buf = mspBuffer.writeField(buf, mspMsgs.RC_TUNING_FIELDS.ratesType, values.ratesType)
    session:request(mspMsgs.CMD.SET_RC_TUNING, buf)
end
M.beginSave = beginSave

function M.event(event, touchState, state, session, nowMs, armed)
    if phase == "loading" then
        local status = session:poll(nowMs)
        if status == "done" then
            local cmd, payload = session:result()
            -- Shared session: only decode a reply to OUR request (see pids.lua).
            if cmd == mspMsgs.CMD.RC_TUNING then
                decodeIntoState(state, payload)
                phase = "ready"
            else
                phase = "idle"
            end
        elseif status == "idle" then
            session:request(mspMsgs.CMD.RC_TUNING, "")
        elseif status == "timeout" or status == "error" then
            session:reset()
            phase = "idle"
        end
    end

    if phase ~= "ready" then
        lcd.drawText(10, CONTENT_TOP, "Loading rates...", COLOR_WHITE)
        return
    end

    local values = state:get("rates")
    lcd.drawText(10, TYPE_Y, "Rate type: " .. (RATE_TYPE_NAMES[values.ratesType] or "?"), COLOR_WHITE)

    if not armed and touchState then
        local tx, ty = touchState.x, touchState.y
        if ty >= TYPE_Y and ty < TYPE_Y + TYPE_H and tx >= TYPE_X and tx < TYPE_X + TYPE_W then
            state:setField("rates", "ratesType", (values.ratesType + 1) % RATE_TYPE_COUNT)
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
        state:setField("rates", cell.key, newValue)
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
