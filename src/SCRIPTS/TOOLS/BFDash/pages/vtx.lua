local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")

-- Explicit RGB colors rather than named constants -- see main.lua's note.
local COLOR_WHITE = lcd.RGB(255, 255, 255)

local M = {}

local BAND_NAMES = { "A", "B", "E", "F", "R" }
local POWER_MIN, POWER_MAX = 1, 5

-- Layout: content starts at y=66, below the tab bar + profile row (which end at
-- y=64). Three 20px rows at 70/100/130 stay clear of the footer at 232.
local CONTENT_TOP = 66
local ROW_H = 20
local BAND_Y, CHANNEL_Y, POWER_Y = 70, 100, 130
local DEC_X, DEC_W = 150, 20
local INC_X, INC_W = 175, 20

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
            -- Shared session: only decode a reply to OUR request (see pids.lua).
            if cmd == mspMsgs.CMD.VTX_CONFIG then
                local decoded = mspMsgs.decodeVtxConfig(payload)
                -- lowPowerDisarm and pitModeFreq aren't decoded by decodeVtxConfig
                -- (not user-editable on this page) but are required, unchanged,
                -- by encodeVtxConfigSet's round trip -- read them directly here.
                decoded.lowPowerDisarm = string.byte(payload, 9) or 0
                decoded.pitModeFreq = (string.byte(payload, 10) or 0) + (string.byte(payload, 11) or 0) * 256
                state:load("vtx", decoded)
                phase = "ready"
            else
                phase = "idle"
            end
        elseif status == "idle" then
            session:request(mspMsgs.CMD.VTX_CONFIG, "")
        elseif status == "timeout" or status == "error" then
            session:reset()
            phase = "idle"
        end
    end

    if phase ~= "ready" then
        lcd.drawText(10, CONTENT_TOP, "Loading VTX config...", COLOR_WHITE)
        return
    end

    local values = state:get("vtx")
    lcd.drawText(10, BAND_Y, "Band: " .. (BAND_NAMES[values.band] or tostring(values.band)), COLOR_WHITE)
    lcd.drawText(10, CHANNEL_Y, "Channel: " .. tostring(values.channel), COLOR_WHITE)
    lcd.drawText(10, POWER_Y, "Power: " .. tostring(values.power), COLOR_WHITE)

    if not armed and touchState and touchState.tap then
        local tx, ty = touchState.x, touchState.y
        local dec = tx >= DEC_X and tx < DEC_X + DEC_W
        local inc = tx >= INC_X and tx < INC_X + INC_W
        if ty >= BAND_Y and ty < BAND_Y + ROW_H then
            if dec then
                state:setField("vtx", "band", math.max(1, values.band - 1))
            elseif inc then
                state:setField("vtx", "band", math.min(#BAND_NAMES, values.band + 1))
            end
        elseif ty >= CHANNEL_Y and ty < CHANNEL_Y + ROW_H then
            if dec then
                state:setField("vtx", "channel", math.max(1, values.channel - 1))
            elseif inc then
                state:setField("vtx", "channel", math.min(8, values.channel + 1))
            end
        elseif ty >= POWER_Y and ty < POWER_Y + ROW_H then
            if dec then
                state:setField("vtx", "power", math.max(POWER_MIN, values.power - 1))
            elseif inc then
                state:setField("vtx", "power", math.min(POWER_MAX, values.power + 1))
            end
        end
    end
end

return M
