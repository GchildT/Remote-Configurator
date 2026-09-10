local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")

-- Explicit RGB colors rather than named constants -- see main.lua's note.
local COLOR_WHITE = lcd.RGB(255, 255, 255)
local COLOR_YELLOW = lcd.RGB(255, 210, 0)

-- Confirmed against EdgeTX firmware source (radio/src/keys.h).
local EVT_ROTARY_LEFT = 0x1003
local EVT_ROTARY_RIGHT = 0x1004

local M = {}

-- All five fields live in MSP_PID_ADVANCED/MSP_SET_PID_ADVANCED (94/95),
-- verified byte-for-byte identical between Betaflight 4.5.5 and 2026.6.1 --
-- see mspMsgs.lua's PID_ADVANCED_FIELDS comment. Labels match Betaflight
-- Configurator's "Throttle and Motor Settings" section exactly.
--
-- No on/off toggle controls: every field is a plain always-visible row, tap
-- to focus + dial to adjust, same as PIDs/Rates/VTX. Vbat Sag Compensation %
-- and Thrust Linearization % are both plain 0-100 percentages where 0 means
-- "off" on the FC itself (confirmed against betaflight-configurator source)
-- -- dialing either down to 0 disables it, no separate switch needed.
local ROWS = {
    { key = "throttleBoost", label = "Throttle Boost", min = 0, max = 100, step = 1 },
    { key = "motorOutputLimit", label = "Motor Output Limit", min = 25, max = 100, step = 1 },
    { key = "dynIdleMinRpm", label = "Dynamic Idle Value [x100 RPM]", min = 0, max = 200, step = 1 },
    { key = "vbatSagCompensation", label = "Vbat Sag Compensation %", min = 0, max = 100, step = 1 },
    { key = "thrustLinearization", label = "Thrust Linearization %", min = 0, max = 100, step = 1 },
}

-- Layout: content starts at y=66, below the tab bar + profile row (which end
-- at y=64), and must finish above the footer at y=232. 5 rows * 26px = 130px
-- span y=66..196, comfortably clear of both boundaries.
local ROW_TOP = 66
local ROW_H = 26
local LABEL_X = 4
local VALUE_X = 320

local phase = "idle"
local focusedIndex = nil -- index into ROWS of the currently jog-dial-editable field, or nil

local function decodeIntoState(state, rawBuffer)
    local values = { rawBuffer = rawBuffer }
    for _, r in ipairs(ROWS) do
        values[r.key] = mspBuffer.readField(rawBuffer, mspMsgs.PID_ADVANCED_FIELDS[r.key])
    end
    state:load("throttle", values)
end

function M.create()
    phase = "idle"
    focusedIndex = nil
end

function M.update(state, armed)
    if phase == "idle" and state:get("throttle") == nil then
        phase = "loading"
    end
end

local function beginSave(session, state)
    local values = state:get("throttle")
    local buf = values.rawBuffer
    for _, r in ipairs(ROWS) do
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

    if not armed and focusedIndex ~= nil and (event == EVT_ROTARY_LEFT or event == EVT_ROTARY_RIGHT) then
        local delta = (event == EVT_ROTARY_RIGHT) and 1 or -1
        local r = ROWS[focusedIndex]
        local newValue = values[r.key] + delta * r.step
        newValue = math.max(r.min, math.min(r.max, newValue))
        state:setField("throttle", r.key, newValue)
    end

    for i, r in ipairs(ROWS) do
        local y = ROW_TOP + (i - 1) * ROW_H
        local isFocused = (focusedIndex == i)
        local color = isFocused and COLOR_YELLOW or COLOR_WHITE
        lcd.drawText(LABEL_X, y, r.label, color)
        lcd.drawText(VALUE_X, y, tostring(values[r.key]), color)

        if not armed and touchState then
            local tx, ty = touchState.x, touchState.y
            if ty >= y and ty < y + ROW_H and tx >= LABEL_X and tx < LCD_W then
                focusedIndex = isFocused and nil or i
            end
        end
    end
end

return M
