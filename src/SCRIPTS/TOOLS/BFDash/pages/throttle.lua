local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")
local ui = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/ui.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/ui.lua")

-- Explicit RGB colors rather than named constants -- see main.lua's note.
local COLOR_WHITE = lcd.RGB(255, 255, 255)
local COLOR_YELLOW = lcd.RGB(255, 210, 0)
local COLOR_GREEN = lcd.RGB(30, 170, 60)
local COLOR_GREY = lcd.RGB(110, 110, 110)
local TOGGLE_COLORS = { on = COLOR_GREEN, off = COLOR_GREY, focused = COLOR_YELLOW, text = COLOR_WHITE }

-- Confirmed against EdgeTX firmware source (radio/src/keys.h).
local EVT_ROTARY_LEFT = 0x1003
local EVT_ROTARY_RIGHT = 0x1004

local M = {}

-- All five fields live in MSP_PID_ADVANCED/MSP_SET_PID_ADVANCED (94/95),
-- verified byte-for-byte identical between Betaflight 4.5.5 and 2026.6.1 --
-- see mspMsgs.lua's PID_ADVANCED_FIELDS comment. Labels match Betaflight
-- Configurator's "Throttle and Motor Settings" section exactly.
--
-- Vbat Sag Compensation % and Thrust Linearization % are toggle+value rows,
-- like the Filters page: 0 = off (confirmed against Configurator source,
-- betaflight-configurator PIDTuningTab -- vbat_sag_compensation and
-- thrustLinearization are both plain 0-100 percentages with 0 meaning "off",
-- restored to a remembered value when re-enabled).
local NUMERIC_ROWS = {
    { key = "throttleBoost", label = "Throttle Boost", min = 0, max = 100 },
    { key = "motorOutputLimit", label = "Motor Output Limit", min = 25, max = 100 },
    { key = "dynIdleMinRpm", label = "Dynamic Idle Value [x100 RPM]", min = 0, max = 200 },
}
local TOGGLE_ROWS = {
    { key = "vbatSagCompensation", label = "Vbat Sag Compensation %", min = 0, max = 100, defaultOn = 100 },
    { key = "thrustLinearization", label = "Thrust Linearization %", min = 0, max = 100, defaultOn = 25 },
}

-- Layout: content starts at y=66, below the tab bar + profile row (which end
-- at y=64), and must finish above the footer at y=232. Each toggle row can
-- expand to a second line for its value, so rows are placed at a fixed
-- spacing generous enough for that.
local ROW_TOP = 66
local ROW_H = 24
local VALUE_ROW_H = 20
local LABEL_X = 4
local VALUE_X = 300
local TOGGLE_X = 300

local phase = "idle"
local focusedKey = nil -- key into NUMERIC_ROWS/TOGGLE_ROWS of the jog-dial-editable field, or nil

local function decodeIntoState(state, rawBuffer)
    local values = { rawBuffer = rawBuffer }
    for _, r in ipairs(NUMERIC_ROWS) do
        values[r.key] = mspBuffer.readField(rawBuffer, mspMsgs.PID_ADVANCED_FIELDS[r.key])
    end
    for _, r in ipairs(TOGGLE_ROWS) do
        values[r.key] = mspBuffer.readField(rawBuffer, mspMsgs.PID_ADVANCED_FIELDS[r.key])
    end
    state:load("throttle", values)
end

function M.create()
    phase = "idle"
    focusedKey = nil
end

function M.update(state, armed)
    if phase == "idle" and state:get("throttle") == nil then
        phase = "loading"
    end
end

local function beginSave(session, state)
    local values = state:get("throttle")
    local buf = values.rawBuffer
    for _, r in ipairs(NUMERIC_ROWS) do
        buf = mspBuffer.writeField(buf, mspMsgs.PID_ADVANCED_FIELDS[r.key], values[r.key])
    end
    for _, r in ipairs(TOGGLE_ROWS) do
        buf = mspBuffer.writeField(buf, mspMsgs.PID_ADVANCED_FIELDS[r.key], values[r.key])
    end
    session:request(mspMsgs.CMD.SET_PID_ADVANCED, buf)
end
M.beginSave = beginSave

function M.event(event, touchState, state, session, nowMs, armed)
    if phase == "loading" then
        local status = session:poll(nowMs)
        if status == "done" then
            local cmd, payload = session:result()
            -- Shared session: only decode a reply to OUR request (see pids.lua).
            if cmd == mspMsgs.CMD.PID_ADVANCED then
                decodeIntoState(state, payload)
                phase = "ready"
            else
                phase = "idle"
            end
        elseif status == "idle" then
            session:request(mspMsgs.CMD.PID_ADVANCED, "")
        elseif status == "timeout" or status == "error" then
            session:reset()
            phase = "idle"
        end
    end

    if phase ~= "ready" then
        lcd.drawText(10, ROW_TOP, "Loading throttle/motor settings...", COLOR_WHITE)
        return
    end

    local values = state:get("throttle")

    if not armed and focusedKey ~= nil and (event == EVT_ROTARY_LEFT or event == EVT_ROTARY_RIGHT) then
        local delta = (event == EVT_ROTARY_RIGHT) and 1 or -1
        local spec = nil
        for _, r in ipairs(NUMERIC_ROWS) do
            if r.key == focusedKey then spec = r end
        end
        if spec == nil then
            for _, r in ipairs(TOGGLE_ROWS) do
                if r.key == focusedKey then spec = r end
            end
        end
        if spec ~= nil then
            local newValue = values[spec.key] + delta
            newValue = math.max(spec.min, math.min(spec.max, newValue))
            state:setField("throttle", spec.key, newValue)
        end
    end

    local y = ROW_TOP
    for _, r in ipairs(NUMERIC_ROWS) do
        local isFocused = (focusedKey == r.key)
        local color = isFocused and COLOR_YELLOW or COLOR_WHITE
        lcd.drawText(LABEL_X, y, r.label, color)
        lcd.drawText(VALUE_X, y, tostring(values[r.key]), color)

        if not armed and ui.rowTapped(touchState, LABEL_X, LCD_W, y, ROW_H) then
            focusedKey = isFocused and nil or r.key
        end
        y = y + ROW_H
    end

    for _, r in ipairs(TOGGLE_ROWS) do
        local on = values[r.key] ~= 0
        local isFocused = (focusedKey == r.key)
        local color = isFocused and COLOR_YELLOW or COLOR_WHITE
        lcd.drawText(LABEL_X, y, r.label, color)
        ui.drawToggle(TOGGLE_X, y - 2, on, isFocused, TOGGLE_COLORS)

        if not armed and ui.rowTapped(touchState, LABEL_X, LCD_W, y, ROW_H) then
            if focusedKey == r.key then
                focusedKey = nil
            elseif touchState.x >= TOGGLE_X then
                -- Tapping the toggle itself flips on/off immediately, same as
                -- the jog-dial toggle behavior below -- no need to focus first.
                state:setField("throttle", r.key, on and 0 or r.defaultOn)
            else
                focusedKey = r.key
            end
        end
        y = y + ROW_H

        if on then
            lcd.drawText(LABEL_X + 16, y, "Value:", COLOR_GREY)
            lcd.drawText(VALUE_X, y, tostring(values[r.key]), color)
            if not armed and ui.rowTapped(touchState, LABEL_X, LCD_W, y, VALUE_ROW_H) then
                focusedKey = isFocused and nil or r.key
            end
            y = y + VALUE_ROW_H
        end
    end
end

return M
