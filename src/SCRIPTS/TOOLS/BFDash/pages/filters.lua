local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")

-- Explicit RGB colors rather than named constants -- see main.lua's note.
local COLOR_WHITE = lcd.RGB(255, 255, 255)

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

local function decodeIntoState(state, rawBuffer)
    local values = { rawBuffer = rawBuffer }
    for _, r in ipairs(ROWS) do
        values[r.key] = mspBuffer.readField(rawBuffer, mspMsgs.FILTER_CONFIG_FIELDS[r.key])
    end
    state:load("filters", values)
end

function M.create()
    phase = "idle"
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

    local values = state:get("filters")
    for i, r in ipairs(ROWS) do
        local y = ROW_TOP + (i - 1) * ROW_HEIGHT
        lcd.drawText(10, y, r.label, COLOR_WHITE)
        lcd.drawText(VALUE_X, y, tostring(values[r.key]), COLOR_WHITE)

        if not armed and touchState and touchState.tap then
            local tx, ty = touchState.x, touchState.y
            if ty >= y and ty < y + ROW_HEIGHT then
                if tx >= VALUE_X + 60 and tx <= VALUE_X + 85 then
                    state:setField("filters", r.key, math.max(0, values[r.key] - 5))
                elseif tx >= VALUE_X + 90 and tx <= VALUE_X + 115 then
                    state:setField("filters", r.key, math.min(1000, values[r.key] + 5))
                end
            end
        end
    end
end

return M
