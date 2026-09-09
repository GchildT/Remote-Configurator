local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")

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
local ROW_HEIGHT = 26
local ROW_TOP = 50
local SLIDER_X, SLIDER_W = 140, 300

local phase = "idle" -- idle | loading | ready | saving
local pendingRawBuffer = nil
local selectedRow = nil

local function decodeIntoState(state, rawBuffer)
    local values = { rawBuffer = rawBuffer }
    for _, s in ipairs(SLIDERS) do
        values[s.key] = mspBuffer.readField(rawBuffer, mspMsgs.SIMPLIFIED_TUNING_FIELDS[s.key])
    end
    state:load("pids", values)
end

function M.create()
    phase = "idle"
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
    pendingRawBuffer = buf
    session:request(mspMsgs.CMD.SET_SIMPLIFIED_TUNING, buf)
end
M.beginSave = beginSave

function M.event(event, touchState, state, session, nowMs, armed)
    if phase == "loading" then
        local status = session:poll(nowMs)
        if status == "done" then
            local cmd, payload = session:result()
            decodeIntoState(state, payload)
            phase = "ready"
        elseif status == "idle" then
            beginLoad(session)
        elseif status == "timeout" or status == "error" then
            phase = "idle" -- caller will retry on next update()
        end
    end

    if phase ~= "ready" then
        lcd.drawText(10, 60, "Loading PID sliders...")
        return
    end

    local values = state:get("pids")
    for i, s in ipairs(SLIDERS) do
        local y = ROW_TOP + (i - 1) * ROW_HEIGHT
        lcd.drawText(10, y, s.label)
        local value = values[s.key]
        local pct = (value - SLIDER_MIN) / (SLIDER_MAX - SLIDER_MIN)
        lcd.drawRectangle(SLIDER_X, y, SLIDER_W, 18)
        lcd.drawFilledRectangle(SLIDER_X, y, math.floor(SLIDER_W * pct), 18, armed and GREY or BLUE)
        lcd.drawText(SLIDER_X + SLIDER_W + 10, y, tostring(value))

        if not armed and touchState and touchState.tap then
            local tx, ty = touchState.x, touchState.y
            if tx >= SLIDER_X and tx <= SLIDER_X + SLIDER_W and ty >= y and ty <= y + 18 then
                local newPct = (tx - SLIDER_X) / SLIDER_W
                local newValue = math.floor(SLIDER_MIN + newPct * (SLIDER_MAX - SLIDER_MIN))
                state:setField("pids", s.key, newValue)
            end
        end
    end
end

return M
