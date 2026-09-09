local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")

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
local ROW_HEIGHT = 20
local ROW_TOP = 60
local VALUE_X = 220

local phase = "idle"

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
            decodeIntoState(state, payload)
            phase = "ready"
        elseif status == "idle" then
            session:request(mspMsgs.CMD.RC_TUNING, "")
        elseif status == "timeout" or status == "error" then
            phase = "idle"
        end
    end

    if phase ~= "ready" then
        lcd.drawText(10, 60, "Loading rates...")
        return
    end

    local values = state:get("rates")
    lcd.drawText(10, ROW_TOP - 20, "Rate type: " .. (RATE_TYPE_NAMES[values.ratesType] or "?"))

    if not armed and touchState and touchState.tap then
        local tx, ty = touchState.x, touchState.y
        if ty >= ROW_TOP - 24 and ty <= ROW_TOP - 4 and tx >= 150 and tx <= 250 then
            state:setField("rates", "ratesType", (values.ratesType + 1) % 4)
        end
    end

    for i, r in ipairs(ROWS) do
        local y = ROW_TOP + (i - 1) * ROW_HEIGHT
        lcd.drawText(10, y, r.label)
        lcd.drawText(VALUE_X, y, tostring(values[r.key]))

        if not armed and touchState and touchState.tap then
            local tx, ty = touchState.x, touchState.y
            if ty >= y and ty <= y + ROW_HEIGHT then
                if tx >= VALUE_X + 40 and tx <= VALUE_X + 60 then
                    state:setField("rates", r.key, math.max(0, values[r.key] - 1))
                elseif tx >= VALUE_X + 65 and tx <= VALUE_X + 85 then
                    state:setField("rates", r.key, math.min(255, values[r.key] + 1))
                end
            end
        end
    end
end

return M
