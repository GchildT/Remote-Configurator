local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")
local ui = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/ui.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/ui.lua")

-- Explicit RGB colors rather than named constants -- see main.lua's note.
local COLOR_WHITE = lcd.RGB(255, 255, 255)
local COLOR_YELLOW = lcd.RGB(255, 210, 0)
local COLOR_GREY = lcd.RGB(150, 150, 150)

-- Confirmed against EdgeTX firmware source (radio/src/keys.h).
local EVT_ROTARY_LEFT = 0x1003
local EVT_ROTARY_RIGHT = 0x1004

local PAGE_KEY = "filters"

local M = {}

-- Confirmed against Betaflight firmware source (src/main/common/filter.h:
-- lowpassFilterType_e) and betaflight-configurator's own filterTypeItems
-- (src/components/tabs/pid-tuning/FilterSubTab.vue).
local FILTER_TYPE_NAMES = { [0] = "PT1", [1] = "BIQUAD", [2] = "PT2", [3] = "PT3" }
local FILTER_TYPE_COUNT = 4

-- Every editable raw MSP field on this page, with its jog-dial range/step (or
-- isEnum for the filter-type dropdowns, cycled instead of ranged). All of
-- these read/write through mspMsgs.FILTER_CONFIG_FIELDS -- see that table's
-- comment for the verified byte offsets (Betaflight 4.5.5 and 2026.6.1,
-- byte-for-byte identical).
--
-- No on/off toggle controls: every field is a plain always-visible row, tap
-- to focus + dial to adjust. 0 disables the corresponding filter on the FC
-- itself (confirmed against betaflight-configurator source -- e.g.
-- gyroNotch1Enabled/rpmFilterEnabled/dynamicNotchEnabled/etc. all key off
-- exactly one field being non-zero) -- dialing a field down to 0 IS turning
-- that filter off, no separate switch needed.
local FIELD_SPECS = {
    gyroLpf1Hz = { min = 0, max = 4000, step = 5 },
    gyroLpf1Type = { isEnum = true },
    gyroLpf2Hz = { min = 0, max = 4000, step = 5 },
    gyroLpf2Type = { isEnum = true },
    gyroNotch1Hz = { min = 0, max = 1000, step = 5 },
    gyroNotch1Cutoff = { min = 0, max = 1000, step = 5 },
    gyroNotch2Hz = { min = 0, max = 1000, step = 5 },
    gyroNotch2Cutoff = { min = 0, max = 1000, step = 5 },
    rpmFilterHarmonics = { min = 0, max = 8, step = 1 },
    rpmFilterMinHz = { min = 0, max = 200, step = 5 },
    dynNotchCount = { min = 0, max = 5, step = 1 },
    dynNotchQ = { min = 0, max = 1000, step = 10 },
    dynNotchMinHz = { min = 0, max = 250, step = 5 },
    dynNotchMaxHz = { min = 0, max = 1000, step = 5 },
    dtermLpf1Hz = { min = 0, max = 1000, step = 5 },
    dtermLpf1Type = { isEnum = true },
    dtermLpf1DynMinHz = { min = 0, max = 1000, step = 5 },
    dtermLpf1DynMaxHz = { min = 0, max = 1000, step = 5 },
    dtermLpf1DynExpo = { min = 0, max = 10, step = 1 },
    dtermLpf2Hz = { min = 0, max = 1000, step = 5 },
    dtermLpf2Type = { isEnum = true },
    dtermNotchHz = { min = 0, max = 1000, step = 5 },
    dtermNotchCutoff = { min = 0, max = 1000, step = 5 },
    yawLowpassHz = { min = 0, max = 1000, step = 5 },
}

-- Flat row list, 2 fields per row where they fit -- "Profile independent
-- Filter Settings" (gyro; all profile-independent in Betaflight itself).
local LEFT_ROWS = {
    { { key = "gyroLpf1Hz", label = "Gyro LP1 Cutoff" }, { key = "gyroLpf1Type", label = "Type" } },
    { { key = "gyroLpf2Hz", label = "Gyro LP2 Cutoff" }, { key = "gyroLpf2Type", label = "Type" } },
    { { key = "gyroNotch1Hz", label = "Notch1 Center" }, { key = "gyroNotch1Cutoff", label = "Cutoff" } },
    { { key = "gyroNotch2Hz", label = "Notch2 Center" }, { key = "gyroNotch2Cutoff", label = "Cutoff" } },
    { { key = "rpmFilterHarmonics", label = "RPM Harmonics" }, { key = "rpmFilterMinHz", label = "Min Hz" } },
    { { key = "dynNotchCount", label = "Dyn Notch Count" }, { key = "dynNotchQ", label = "Q(x100)" } },
    { { key = "dynNotchMinHz", label = "Dyn Notch Min Hz" }, { key = "dynNotchMaxHz", label = "Max Hz" } },
}

-- "Profile dependent Filter Settings" (D term / yaw). D Term Lowpass 1 is
-- special-cased below: it's the one filter with a real static/dynamic mode
-- choice (confirmed against betaflight-configurator's dtermLowpassMode
-- computed), inferred from whether the dynamic-min field is non-zero --
-- there is no separate stored "mode" field in the firmware.
local RIGHT_ROWS = {
    { { key = "dtermLpf2Hz", label = "D Term LP2 Cutoff" }, { key = "dtermLpf2Type", label = "Type" } },
    { { key = "dtermNotchHz", label = "D Notch Center" }, { key = "dtermNotchCutoff", label = "Cutoff" } },
    { { key = "yawLowpassHz", label = "Yaw LP Cutoff" } },
}

-- Layout: content starts at y=66 (below tab bar + profile row) and must
-- finish above the footer at y=232. Worst case (D Term Lowpass 1 in dynamic
-- mode) is 7 rows on the left, 6 on the right -- comfortably fits at a
-- touch-friendly row height, unlike the toggle-based version this replaced.
local CONTENT_TOP = 66
local ROW_H = 22
local COL_L_X, COL_L_W = 4, 228
local COL_R_X, COL_R_W = 240, 236

local phase = "idle"
local focusedKey = nil -- raw field key | "mode:dtermLpf1" | nil

local function decodeIntoState(state, rawBuffer)
    local values = { rawBuffer = rawBuffer }
    for key in pairs(FIELD_SPECS) do
        values[key] = mspBuffer.readField(rawBuffer, mspMsgs.FILTER_CONFIG_FIELDS[key])
    end
    state:load(PAGE_KEY, values)
end

function M.create()
    phase = "idle"
    focusedKey = nil
end

function M.update(state, armed)
    if phase == "idle" and state:get(PAGE_KEY) == nil then
        phase = "loading"
    end
end

local function beginSave(session, state)
    local values = state:get(PAGE_KEY)
    local buf = values.rawBuffer
    for key in pairs(FIELD_SPECS) do
        buf = mspBuffer.writeField(buf, mspMsgs.FILTER_CONFIG_FIELDS[key], values[key])
    end
    session:request(mspMsgs.CMD.SET_FILTER_CONFIG, buf)
end
M.beginSave = beginSave

local function dtermLpf1IsDynamic(values)
    return values.dtermLpf1DynMinHz ~= 0
end

-- Flips the mode: swaps which of static-cutoff vs dynamic-min/max is the
-- non-zero (active) representation, seeding the other side with a sane
-- default the first time it's used.
local function setDtermLpf1Mode(values, state, dynamic)
    if dynamic then
        state:setField(PAGE_KEY, "dtermLpf1Hz", 0)
        if values.dtermLpf1DynMinHz == 0 then state:setField(PAGE_KEY, "dtermLpf1DynMinHz", 100) end
        if values.dtermLpf1DynMaxHz == 0 then state:setField(PAGE_KEY, "dtermLpf1DynMaxHz", 250) end
    else
        state:setField(PAGE_KEY, "dtermLpf1DynMinHz", 0)
        state:setField(PAGE_KEY, "dtermLpf1DynMaxHz", 0)
        if values.dtermLpf1Hz == 0 then state:setField(PAGE_KEY, "dtermLpf1Hz", 100) end
    end
end

local function fieldValueText(key, values)
    local spec = FIELD_SPECS[key]
    if spec.isEnum then
        return FILTER_TYPE_NAMES[values[key]] or tostring(values[key])
    end
    return tostring(values[key])
end

local function drawField(x, w, y, field, values, touchState, armed)
    local isFocused = (focusedKey == field.key)
    local color = isFocused and COLOR_YELLOW or COLOR_WHITE
    lcd.drawText(x, y, field.label .. ": " .. fieldValueText(field.key, values), color)
    if not armed and ui.rowTapped(touchState, x, x + w, y, ROW_H) then
        focusedKey = isFocused and nil or field.key
    end
end

local function drawRow(x, w, y, row, values, touchState, armed)
    local halfW = w / 2
    drawField(x, row[2] and halfW or w, y, row[1], values, touchState, armed)
    if row[2] then
        drawField(x + halfW, halfW, y, row[2], values, touchState, armed)
    end
end

local function drawDtermLpf1(x, w, y, values, touchState, armed, state)
    local dynamic = dtermLpf1IsDynamic(values)
    local modeFocusKey = "mode:dtermLpf1"
    local modeFocused = (focusedKey == modeFocusKey)
    local halfW = w / 2
    lcd.drawText(x, y, "D Term LP1 Mode: " .. (dynamic and "DYN" or "STATIC"), modeFocused and COLOR_YELLOW or COLOR_WHITE)
    if not armed and ui.rowTapped(touchState, x, x + halfW, y, ROW_H) then
        focusedKey = modeFocused and nil or modeFocusKey
    end
    drawField(x + halfW, halfW, y, { key = "dtermLpf1Type", label = "Type" }, values, touchState, armed)
    y = y + ROW_H

    if dynamic then
        drawRow(x, w, y, { { key = "dtermLpf1DynMinHz", label = "Min Hz" }, { key = "dtermLpf1DynMaxHz", label = "Max Hz" } }, values, touchState, armed)
        y = y + ROW_H
        drawField(x, w, y, { key = "dtermLpf1DynExpo", label = "Dyn Curve Expo" }, values, touchState, armed)
        y = y + ROW_H
    else
        drawField(x, w, y, { key = "dtermLpf1Hz", label = "Cutoff" }, values, touchState, armed)
        y = y + ROW_H
    end
    return y
end

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
        lcd.drawText(10, CONTENT_TOP, "Loading filters...", COLOR_WHITE)
        return
    end

    local values = state:get(PAGE_KEY)

    if not armed and focusedKey ~= nil and (event == EVT_ROTARY_LEFT or event == EVT_ROTARY_RIGHT) then
        local delta = (event == EVT_ROTARY_RIGHT) and 1 or -1
        if focusedKey == "mode:dtermLpf1" then
            setDtermLpf1Mode(values, state, not dtermLpf1IsDynamic(values))
        else
            local spec = FIELD_SPECS[focusedKey]
            if spec then
                if spec.isEnum then
                    local newValue = (values[focusedKey] + delta) % FILTER_TYPE_COUNT
                    if newValue < 0 then newValue = newValue + FILTER_TYPE_COUNT end
                    state:setField(PAGE_KEY, focusedKey, newValue)
                else
                    local step = spec.step or 1
                    local newValue = values[focusedKey] + delta * step
                    newValue = math.max(spec.min, math.min(spec.max, newValue))
                    state:setField(PAGE_KEY, focusedKey, newValue)
                end
            end
        end
        values = state:get(PAGE_KEY) -- re-fetch: the branches above may have staged new values
    end

    lcd.drawText(COL_L_X, CONTENT_TOP - 14, "Profile independent", COLOR_GREY)
    lcd.drawText(COL_R_X, CONTENT_TOP - 14, "Profile dependent", COLOR_GREY)

    local y = CONTENT_TOP
    for _, row in ipairs(LEFT_ROWS) do
        drawRow(COL_L_X, COL_L_W, y, row, values, touchState, armed)
        y = y + ROW_H
    end

    y = CONTENT_TOP
    y = drawDtermLpf1(COL_R_X, COL_R_W, y, values, touchState, armed, state)
    for _, row in ipairs(RIGHT_ROWS) do
        drawRow(COL_R_X, COL_R_W, y, row, values, touchState, armed)
        y = y + ROW_H
    end
end

return M
