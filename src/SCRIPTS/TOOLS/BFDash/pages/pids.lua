local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")

-- Explicit RGB colors rather than named constants -- see main.lua's note.
local COLOR_WHITE = lcd.RGB(255, 255, 255)
local COLOR_BLUE = lcd.RGB(40, 110, 220)
local COLOR_GREY = lcd.RGB(130, 130, 130)
local COLOR_YELLOW = lcd.RGB(255, 210, 0)

-- Confirmed against EdgeTX firmware source (radio/src/keys.h).
local EVT_ROTARY_LEFT = 0x1003
local EVT_ROTARY_RIGHT = 0x1004

local M = {}

local SLIDERS = {
    { key = "masterMultiplier", label = "Master" },
    { key = "rollPitchRatio", label = "Roll/Pitch Ratio" },
    { key = "iGain", label = "I Gain" },
    { key = "dGain", label = "D Gain" },
    { key = "piGain", label = "PI Gain" },
    { key = "dminRatio", label = "D-Min Ratio" },
    { key = "feedforwardGain", label = "Feedforward" },
    { key = "pitchPiGain", label = "Pitch PI Gain" },
}
local SLIDER_MIN, SLIDER_MAX = 0, 250
-- Layout: page content lives strictly between the chrome above it (tab bar +
-- profile row, which end at y=64) and the footer below it (starts at y=232 on a
-- 272px-tall screen). 8 rows * 20px = 160px, so rows span y=66..226 -- no
-- geometric overlap with either. See main.lua's layout constants.
local ROW_HEIGHT = 20
local ROW_TOP = 66
local SLIDER_H = 18
local SLIDER_X, SLIDER_W = 140, 300

local phase = "idle" -- idle | loading | ready
local focusedIndex = nil -- index into SLIDERS of the currently jog-dial-editable slider, or nil

local function decodeIntoState(state, rawBuffer)
    local values = { rawBuffer = rawBuffer }
    for _, s in ipairs(SLIDERS) do
        values[s.key] = mspBuffer.readField(rawBuffer, mspMsgs.SIMPLIFIED_TUNING_FIELDS[s.key])
    end
    state:load("pids", values)
end

function M.create()
    phase = "idle"
    focusedIndex = nil
end

function M.update(state, armed)
    if phase == "idle" and state:get("pids") == nil then
        phase = "loading"
    end
end

local function beginLoad(session)
    session:request(mspMsgs.CMD.SIMPLIFIED_TUNING, "")
end

local function beginSave(session, state)
    local values = state:get("pids")
    local buf = values.rawBuffer
    for _, s in ipairs(SLIDERS) do
        buf = mspBuffer.writeField(buf, mspMsgs.SIMPLIFIED_TUNING_FIELDS[s.key], values[s.key])
    end
    session:request(mspMsgs.CMD.SET_SIMPLIFIED_TUNING, buf)
end
M.beginSave = beginSave

function M.event(event, touchState, state, session, nowMs, armed)
    if phase == "loading" then
        local status = session:poll(nowMs)
        if status == "done" then
            local cmd, payload = session:result()
            -- The msp session is shared with main.lua's connection check and
            -- save/profile flows. Only decode a reply that is actually the
            -- answer to OUR request -- otherwise we'd decode e.g. a 4-byte
            -- "BTFL" FC_VARIANT string as a 53-byte tuning buffer.
            if cmd == mspMsgs.CMD.SIMPLIFIED_TUNING then
                decodeIntoState(state, payload)
                phase = "ready"
            else
                phase = "idle" -- not ours; retry cleanly on the next update()
            end
        elseif status == "idle" then
            beginLoad(session)
        elseif status == "timeout" or status == "error" then
            session:reset() -- release the terminal state so the retry can request again
            phase = "idle" -- caller will retry on next update()
        end
    end

    if phase ~= "ready" then
        lcd.drawText(10, ROW_TOP, "Loading PID sliders...", COLOR_WHITE)
        return
    end

    -- Jog-dial adjusts whichever slider is currently focused (tapped). Tapping
    -- a slider toggles its focus; tapping a different one moves focus there.
    if not armed and focusedIndex ~= nil and (event == EVT_ROTARY_LEFT or event == EVT_ROTARY_RIGHT) then
        local delta = (event == EVT_ROTARY_RIGHT) and 1 or -1
        local s = SLIDERS[focusedIndex]
        local values = state:get("pids")
        local newValue = values[s.key] + delta
        newValue = math.max(SLIDER_MIN, math.min(SLIDER_MAX, newValue))
        state:setField("pids", s.key, newValue)
    end

    local values = state:get("pids")
    for i, s in ipairs(SLIDERS) do
        local y = ROW_TOP + (i - 1) * ROW_HEIGHT
        local isFocused = (focusedIndex == i)
        lcd.drawText(10, y, s.label, isFocused and COLOR_YELLOW or COLOR_WHITE)
        local value = values[s.key]
        local pct = (value - SLIDER_MIN) / (SLIDER_MAX - SLIDER_MIN)
        lcd.drawRectangle(SLIDER_X, y, SLIDER_W, SLIDER_H, isFocused and COLOR_YELLOW or COLOR_WHITE)
        lcd.drawFilledRectangle(SLIDER_X, y, math.floor(SLIDER_W * pct), SLIDER_H, armed and COLOR_GREY or COLOR_BLUE)
        lcd.drawText(SLIDER_X + SLIDER_W + 10, y, tostring(value), isFocused and COLOR_YELLOW or COLOR_WHITE)

        if not armed and touchState then
            local tx, ty = touchState.x, touchState.y
            if tx >= SLIDER_X and tx <= SLIDER_X + SLIDER_W and ty >= y and ty < y + SLIDER_H then
                focusedIndex = isFocused and nil or i
            end
        end
    end
end

return M
