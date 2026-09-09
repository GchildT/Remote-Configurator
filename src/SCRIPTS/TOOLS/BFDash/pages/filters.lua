local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")

-- Explicit RGB colors rather than named constants -- see main.lua's note.
local COLOR_WHITE = lcd.RGB(255, 255, 255)
local COLOR_YELLOW = lcd.RGB(255, 210, 0)

-- Confirmed against EdgeTX firmware source (radio/src/keys.h).
local EVT_ROTARY_LEFT = 0x1003
local EVT_ROTARY_RIGHT = 0x1004

local M = {}

local ROWS = {
    { key = "gyroLpf1Hz", label = "Gyro LPF1 (Hz)" },
    { key = "gyroLpf2Hz", label = "Gyro LPF2 (Hz)" },
    { key = "dtermLpf1Hz", label = "D-term LPF1 (Hz)" },
    { key = "dtermLpf2Hz", label = "D-term LPF2 (Hz)" },
}
-- Layout: content starts at y=66, below the tab bar + profile row (which end at
-- y=64). 4 rows * 26px = 104px span y=66..170, well clear of the footer at 232.
local ROW_HEIGHT = 26
local ROW_TOP = 66
local VALUE_X = 220

local phase = "idle"
local focusedIndex = nil -- index into ROWS of the currently jog-dial-editable field, or nil

local function decodeIntoState(state, rawBuffer)
    local values = { rawBuffer = rawBuffer }
    for _, r in ipairs(ROWS) do
        values[r.key] = mspBuffer.readField(rawBuffer, mspMsgs.FILTER_CONFIG_FIELDS[r.key])
    end
    state:load("filters", values)
end

function M.create()
    phase = "idle"
    focusedIndex = nil
end

function M.update(state, armed)
    if phase == "idle" and state:get("filters") == nil then
        phase = "loading"
    end
end

local function beginSave(session, state)
    local values = state:get("filters")
    local buf = values.rawBuffer
    for _, r in ipairs(ROWS) do
        buf = mspBuffer.writeField(buf, mspMsgs.FILTER_CONFIG_FIELDS[r.key], values[r.key])
    end
    session:request(mspMsgs.CMD.SET_FILTER_CONFIG, buf)
end
M.beginSave = beginSave

function M.event(event, touchState, state, session, nowMs, armed)
    if phase == "loading" then
        local status = session:poll(nowMs)
        if status == "done" then
            local cmd, payload = session:result()
            -- Shared session: only decode a reply to OUR request (see pids.lua).
            if cmd == mspMsgs.CMD.FILTER_CONFIG then
                decodeIntoState(state, payload)
                phase = "ready"
            else
                phase = "idle"
            end
        elseif status == "idle" then
            session:request(mspMsgs.CMD.FILTER_CONFIG, "")
        elseif status == "timeout" or status == "error" then
            session:reset()
            phase = "idle"
        end
    end

    if phase ~= "ready" then
        lcd.drawText(10, ROW_TOP, "Loading filters...", COLOR_WHITE)
        return
    end

    -- Jog-dial adjusts whichever field is currently focused (tapped).
    local values = state:get("filters")
    if not armed and focusedIndex ~= nil and (event == EVT_ROTARY_LEFT or event == EVT_ROTARY_RIGHT) then
        local delta = (event == EVT_ROTARY_RIGHT) and 5 or -5
        local r = ROWS[focusedIndex]
        local newValue = values[r.key] + delta
        newValue = math.max(0, math.min(1000, newValue))
        state:setField("filters", r.key, newValue)
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
