local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")

-- Explicit RGB colors rather than named constants -- see main.lua's note.
local COLOR_WHITE = lcd.RGB(255, 255, 255)
local COLOR_YELLOW = lcd.RGB(255, 210, 0)

-- Confirmed against EdgeTX firmware source (radio/src/keys.h).
local EVT_ROTARY_LEFT = 0x1003
local EVT_ROTARY_RIGHT = 0x1004

local M = {}

local BAND_NAMES = { "A", "B", "E", "F", "R" }
local POWER_MIN, POWER_MAX = 1, 5
local FIELD_RANGE = {
    band = { min = 1, max = #BAND_NAMES },
    channel = { min = 1, max = 8 },
    power = { min = POWER_MIN, max = POWER_MAX },
}

-- Layout: content starts at y=86, leaving a blank gap below the tab bar +
-- profile row (which end at y=64) for visual breathing room. Three 20px rows
-- at 90/120/150 stay clear of the footer at 232.
local CONTENT_TOP = 86
local ROW_H = 20
local BAND_Y, CHANNEL_Y, POWER_Y = 90, 120, 150

local phase = "idle"
local focusedField = nil -- "band" | "channel" | "power" | nil, jog-dial-editable

function M.create()
    phase = "idle"
    focusedField = nil
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

    -- Jog-dial adjusts whichever field is currently focused (tapped).
    if not armed and focusedField ~= nil and (event == EVT_ROTARY_LEFT or event == EVT_ROTARY_RIGHT) then
        local delta = (event == EVT_ROTARY_RIGHT) and 1 or -1
        local range = FIELD_RANGE[focusedField]
        local newValue = values[focusedField] + delta
        newValue = math.max(range.min, math.min(range.max, newValue))
        state:setField("vtx", focusedField, newValue)
    end

    local bandFocused = (focusedField == "band")
    local channelFocused = (focusedField == "channel")
    local powerFocused = (focusedField == "power")
    lcd.drawText(10, BAND_Y, "Band: " .. (BAND_NAMES[values.band] or tostring(values.band)), bandFocused and COLOR_YELLOW or COLOR_WHITE)
    lcd.drawText(10, CHANNEL_Y, "Channel: " .. tostring(values.channel), channelFocused and COLOR_YELLOW or COLOR_WHITE)
    lcd.drawText(10, POWER_Y, "Power: " .. tostring(values.power), powerFocused and COLOR_YELLOW or COLOR_WHITE)

    if not armed and touchState then
        local tx, ty = touchState.x, touchState.y
        if tx >= 10 and tx < 250 then
            if ty >= BAND_Y and ty < BAND_Y + ROW_H then
                focusedField = bandFocused and nil or "band"
            elseif ty >= CHANNEL_Y and ty < CHANNEL_Y + ROW_H then
                focusedField = channelFocused and nil or "channel"
            elseif ty >= POWER_Y and ty < POWER_Y + ROW_H then
                focusedField = powerFocused and nil or "power"
            end
        end
    end
end

return M
