local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")

-- Explicit RGB colors rather than named constants -- see main.lua's note.
local COLOR_WHITE = lcd.RGB(255, 255, 255)
local COLOR_YELLOW = lcd.RGB(255, 210, 0)

-- Confirmed against EdgeTX firmware source (radio/src/keys.h).
local EVT_ROTARY_LEFT = 0x1003
local EVT_ROTARY_RIGHT = 0x1004

local M = {}

local RATE_TYPE_NAMES = { [0] = "Betaflight", [1] = "RaceFlight", [2] = "Kiss", [3] = "Actual" }

local ROWS = {
    { key = "rcRateRoll", label = "Roll Rate" },
    { key = "rcRatePitch", label = "Pitch Rate" },
    { key = "rcRateYaw", label = "Yaw Rate" },
    { key = "rcExpoRoll", label = "Roll Expo" },
    { key = "rcExpoPitch", label = "Pitch Expo" },
    { key = "rcExpoYaw", label = "Yaw Expo" },
    { key = "superRateRoll", label = "Roll Super Rate" },
    { key = "superRatePitch", label = "Pitch Super Rate" },
    { key = "superRateYaw", label = "Yaw Super Rate" },
}
-- Layout: page content starts at y=66 (below the tab bar + profile row, which
-- end at y=64) and must finish above the footer at y=232. The rate-type toggle
-- gets its own 18px row at the top of the content area (previously it sat at
-- ROW_TOP-24, which put it inside the profile row AND the tab-bar strip), then
-- 9 value rows * 16px = 144px span y=86..230.
local CONTENT_TOP = 66
local TYPE_Y = CONTENT_TOP
local TYPE_H = 18
local TYPE_X, TYPE_W = 150, 100
local ROW_HEIGHT = 16
local ROW_TOP = 86
local VALUE_X = 220

local phase = "idle"
local focusedIndex = nil -- index into ROWS of the currently jog-dial-editable field, or nil

local function decodeIntoState(state, rawBuffer)
    local values = { rawBuffer = rawBuffer }
    for _, r in ipairs(ROWS) do
        values[r.key] = mspBuffer.readField(rawBuffer, mspMsgs.RC_TUNING_FIELDS[r.key])
    end
    values.ratesType = mspBuffer.readField(rawBuffer, mspMsgs.RC_TUNING_FIELDS.ratesType)
    state:load("rates", values)
end

function M.create()
    phase = "idle"
    focusedIndex = nil
end

function M.update(state, armed)
    if phase == "idle" and state:get("rates") == nil then
        phase = "loading"
    end
end

local function beginSave(session, state)
    local values = state:get("rates")
    local buf = values.rawBuffer
    for _, r in ipairs(ROWS) do
        buf = mspBuffer.writeField(buf, mspMsgs.RC_TUNING_FIELDS[r.key], values[r.key])
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
            state:setField("rates", "ratesType", (values.ratesType + 1) % 4)
        end
    end

    -- Jog-dial adjusts whichever field is currently focused (tapped).
    if not armed and focusedIndex ~= nil and (event == EVT_ROTARY_LEFT or event == EVT_ROTARY_RIGHT) then
        local delta = (event == EVT_ROTARY_RIGHT) and 1 or -1
        local r = ROWS[focusedIndex]
        local newValue = values[r.key] + delta
        newValue = math.max(0, math.min(255, newValue))
        state:setField("rates", r.key, newValue)
    end

    for i, r in ipairs(ROWS) do
        local y = ROW_TOP + (i - 1) * ROW_HEIGHT
        local isFocused = (focusedIndex == i)
        lcd.drawText(10, y, r.label, isFocused and COLOR_YELLOW or COLOR_WHITE)
        lcd.drawText(VALUE_X, y, tostring(values[r.key]), isFocused and COLOR_YELLOW or COLOR_WHITE)

        if not armed and touchState then
            local tx, ty = touchState.x, touchState.y
            if ty >= y and ty < y + ROW_HEIGHT and tx >= VALUE_X and tx < VALUE_X + 100 then
                focusedIndex = isFocused and nil or i
            end
        end
    end
end

return M
