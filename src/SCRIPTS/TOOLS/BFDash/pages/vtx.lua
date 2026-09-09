local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")

local M = {}

local BAND_NAMES = { "A", "B", "E", "F", "R" }
local POWER_MIN, POWER_MAX = 1, 5

local phase = "idle"

function M.create()
    phase = "idle"
end

function M.update(state, armed)
    if phase == "idle" and state:get("vtx") == nil then
        phase = "loading"
    end
end

local function beginSave(session, state)
    local values = state:get("vtx")
    local payload = mspMsgs.encodeVtxConfigSet(values)
    session:request(mspMsgs.CMD.SET_VTX_CONFIG, payload)
end
M.beginSave = beginSave

function M.event(event, touchState, state, session, nowMs, armed)
    if phase == "loading" then
        local status = session:poll(nowMs)
        if status == "done" then
            local cmd, payload = session:result()
            local decoded = mspMsgs.decodeVtxConfig(payload)
            -- lowPowerDisarm and pitModeFreq aren't decoded by decodeVtxConfig
            -- (not user-editable on this page) but are required, unchanged,
            -- by encodeVtxConfigSet's round trip -- read them directly here.
            decoded.lowPowerDisarm = string.byte(payload, 9) or 0
            decoded.pitModeFreq = (string.byte(payload, 10) or 0) + (string.byte(payload, 11) or 0) * 256
            state:load("vtx", decoded)
            phase = "ready"
        elseif status == "idle" then
            session:request(mspMsgs.CMD.VTX_CONFIG, "")
        elseif status == "timeout" or status == "error" then
            phase = "idle"
        end
    end

    if phase ~= "ready" then
        lcd.drawText(10, 60, "Loading VTX config...")
        return
    end

    local values = state:get("vtx")
    lcd.drawText(10, 60, "Band: " .. (BAND_NAMES[values.band] or tostring(values.band)))
    lcd.drawText(10, 90, "Channel: " .. tostring(values.channel))
    lcd.drawText(10, 120, "Power: " .. tostring(values.power))

    if not armed and touchState and touchState.tap then
        local tx, ty = touchState.x, touchState.y
        if ty >= 60 and ty <= 80 then
            if tx >= 150 and tx <= 170 then
                state:setField("vtx", "band", math.max(1, values.band - 1))
            elseif tx >= 175 and tx <= 195 then
                state:setField("vtx", "band", math.min(#BAND_NAMES, values.band + 1))
            end
        elseif ty >= 90 and ty <= 110 then
            if tx >= 150 and tx <= 170 then
                state:setField("vtx", "channel", math.max(1, values.channel - 1))
            elseif tx >= 175 and tx <= 195 then
                state:setField("vtx", "channel", math.min(8, values.channel + 1))
            end
        elseif ty >= 120 and ty <= 140 then
            if tx >= 150 and tx <= 170 then
                state:setField("vtx", "power", math.max(POWER_MIN, values.power - 1))
            elseif tx >= 175 and tx <= 195 then
                state:setField("vtx", "power", math.min(POWER_MAX, values.power + 1))
            end
        end
    end
end

return M
