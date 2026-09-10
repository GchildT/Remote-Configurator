local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")
local ui = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/ui.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/ui.lua")

-- Explicit RGB colors rather than named constants -- see main.lua's note.
local COLOR_WHITE = lcd.RGB(255, 255, 255)
local COLOR_YELLOW = lcd.RGB(255, 210, 0)
local COLOR_GREEN = lcd.RGB(30, 170, 60)
local COLOR_GREY = lcd.RGB(110, 110, 110)
local TOGGLE_COLORS = { on = COLOR_GREEN, off = COLOR_GREY, focused = COLOR_YELLOW, text = COLOR_WHITE }

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
local FIELD_SPECS = {
    gyroLpf1Hz = { min = 0, max = 4000, step = 5 },
    gyroLpf1Type = { isEnum = true },
    gyroLpf2Hz = { min = 0, max = 4000, step = 5 },
    gyroLpf2Type = { isEnum = true },
    gyroNotch1Hz = { min = 0, max = 1000, step = 5 },
    gyroNotch1Cutoff = { min = 0, max = 1000, step = 5 },
    gyroNotch2Hz = { min = 0, max = 1000, step = 5 },
    gyroNotch2Cutoff = { min = 0, max = 1000, step = 5 },
    rpmFilterHarmonics = { min = 1, max = 8, step = 1 },
    rpmFilterMinHz = { min = 50, max = 200, step = 5 },
    dynNotchCount = { min = 0, max = 5, step = 1 },
    dynNotchQ = { min = 100, max = 1000, step = 10 },
    dynNotchMinHz = { min = 60, max = 250, step = 5 },
    dynNotchMaxHz = { min = 200, max = 1000, step = 5 },
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

-- Toggle-group model: each group's `primaryKey` is the raw field Betaflight
-- (and betaflight-configurator) treats as the on/off gate for that whole
-- filter -- 0 means off (confirmed against betaflight-configurator source,
-- FilterSubTab.vue: gyroNotch1Enabled/gyroLowpass2Enabled/rpmFilterEnabled/
-- dynamicNotchEnabled/etc. all key off exactly one field being non-zero).
-- `defaults` supplies a sane non-zero value for any of the group's fields
-- that are still 0 when the group is switched back on (a field the user
-- had already set keeps its value -- only genuinely-never-configured fields
-- get a default, since this page has no separate "remembered previous
-- value" cache the way Configurator's own UI does).
local LEFT_GROUPS = { -- "Profile independent Filter Settings" (gyro)
    {
        id = "gyroLpf1", label = "Gyro Lowpass 1", primaryKey = "gyroLpf1Hz",
        defaults = { gyroLpf1Hz = 100 },
        fields = { { key = "gyroLpf1Hz", label = "Cutoff" }, { key = "gyroLpf1Type", label = "Type" } },
    },
    {
        id = "gyroLpf2", label = "Gyro Lowpass 2", primaryKey = "gyroLpf2Hz",
        defaults = { gyroLpf2Hz = 500 },
        fields = { { key = "gyroLpf2Hz", label = "Cutoff" }, { key = "gyroLpf2Type", label = "Type" } },
    },
    {
        id = "gyroNotch1", label = "Gyro Notch 1", primaryKey = "gyroNotch1Hz",
        defaults = { gyroNotch1Hz = 400, gyroNotch1Cutoff = 200 },
        fields = { { key = "gyroNotch1Hz", label = "Center" }, { key = "gyroNotch1Cutoff", label = "Cutoff" } },
    },
    {
        id = "gyroNotch2", label = "Gyro Notch 2", primaryKey = "gyroNotch2Hz",
        defaults = { gyroNotch2Hz = 200, gyroNotch2Cutoff = 100 },
        fields = { { key = "gyroNotch2Hz", label = "Center" }, { key = "gyroNotch2Cutoff", label = "Cutoff" } },
    },
    {
        id = "gyroRpm", label = "Gyro RPM Filter", primaryKey = "rpmFilterHarmonics",
        defaults = { rpmFilterHarmonics = 3, rpmFilterMinHz = 100 },
        fields = { { key = "rpmFilterHarmonics", label = "Harmonics" }, { key = "rpmFilterMinHz", label = "Min Hz" } },
    },
    {
        id = "dynNotch", label = "Dynamic Notch", primaryKey = "dynNotchCount",
        defaults = { dynNotchCount = 3, dynNotchQ = 500, dynNotchMinHz = 100, dynNotchMaxHz = 600 },
        fields = {
            { key = "dynNotchCount", label = "Count" }, { key = "dynNotchQ", label = "Q(x100)" },
            { key = "dynNotchMinHz", label = "Min Hz" }, { key = "dynNotchMaxHz", label = "Max Hz" },
        },
    },
}

local RIGHT_GROUPS = { -- "Profile dependent Filter Settings" (D term / yaw); D Term Lowpass 1 is special-cased below (static/dynamic mode)
    {
        id = "dtermLpf2", label = "D Term Lowpass 2", primaryKey = "dtermLpf2Hz",
        defaults = { dtermLpf2Hz = 150 },
        fields = { { key = "dtermLpf2Hz", label = "Cutoff" }, { key = "dtermLpf2Type", label = "Type" } },
    },
    {
        id = "dtermNotch", label = "D Term Notch", primaryKey = "dtermNotchHz",
        defaults = { dtermNotchHz = 260, dtermNotchCutoff = 160 },
        fields = { { key = "dtermNotchHz", label = "Center" }, { key = "dtermNotchCutoff", label = "Cutoff" } },
    },
    {
        id = "yawLpf", label = "Yaw Lowpass", primaryKey = "yawLowpassHz",
        defaults = { yawLowpassHz = 100 },
        fields = { { key = "yawLowpassHz", label = "Cutoff" } },
    },
}

local ALL_GROUPS = {}
for _, g in ipairs(LEFT_GROUPS) do ALL_GROUPS[#ALL_GROUPS + 1] = g end
for _, g in ipairs(RIGHT_GROUPS) do ALL_GROUPS[#ALL_GROUPS + 1] = g end

local function findGroupById(id)
    for _, g in ipairs(ALL_GROUPS) do
        if g.id == id then return g end
    end
    return nil
end

-- Layout: content starts at y=66 (below tab bar + profile row) and must
-- finish above the footer at y=232 -- a tight budget for up to ~13 rows in
-- the busier column, so rows here are deliberately more compact (ROW_H=16)
-- than the rest of the app's 20-26px rows. If every single filter on this
-- page were simultaneously enabled the bottom rows would crowd the footer;
-- that's an accepted tradeoff for a realistic config (most craft only run
-- a handful of these at once, as in the reference layout this was built
-- against) rather than adding scrolling.
local CONTENT_TOP = 66
local ROW_H = 16
local COL_L_X, COL_L_W = 4, 228
local COL_R_X, COL_R_W = 240, 236

local phase = "idle"
local focusedKey = nil -- raw field key | "toggle:<groupId>" | "mode:dtermLpf1" | nil

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

local function toggleGroup(group, values, state)
    if values[group.primaryKey] ~= 0 then
        state:setField(PAGE_KEY, group.primaryKey, 0)
    else
        for key, def in pairs(group.defaults) do
            if values[key] == 0 then
                state:setField(PAGE_KEY, key, def)
            end
        end
    end
end

-- D Term Lowpass 1 is the one filter with a real static/dynamic mode choice
-- (confirmed against betaflight-configurator's dtermLowpassMode/
-- dtermLowpassEnabled computeds): enabled = static OR dynamic cutoff is
-- non-zero; mode is read from whether the dynamic min is non-zero, not a
-- separate stored field -- Betaflight itself has no explicit mode byte.
local function dtermLpf1Enabled(values)
    return values.dtermLpf1Hz ~= 0 or values.dtermLpf1DynMinHz ~= 0
end

local function dtermLpf1IsDynamic(values)
    return values.dtermLpf1DynMinHz ~= 0
end

local function toggleDtermLpf1(values, state)
    if dtermLpf1Enabled(values) then
        state:setField(PAGE_KEY, "dtermLpf1Hz", 0)
        state:setField(PAGE_KEY, "dtermLpf1DynMinHz", 0)
        state:setField(PAGE_KEY, "dtermLpf1DynMaxHz", 0)
    elseif values.dtermLpf1Hz == 0 and values.dtermLpf1DynMinHz == 0 then
        state:setField(PAGE_KEY, "dtermLpf1Hz", 100) -- re-enable in static mode by default
    end
end

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

local function drawFieldPair(x, w, y, fieldA, fieldB, values, touchState, armed)
    local halfW = w / 2
    drawField(x, halfW, y, fieldA, values, touchState, armed)
    if fieldB then
        drawField(x + halfW, halfW, y, fieldB, values, touchState, armed)
    end
end

local function drawToggleRow(x, w, y, label, on, toggleFocusKey, values, touchState, armed, onToggle)
    local isFocused = (focusedKey == toggleFocusKey)
    local color = isFocused and COLOR_YELLOW or COLOR_WHITE
    lcd.drawText(x, y, label, color)
    local tw, th = ui.toggleSize()
    ui.drawToggle(x + w - tw, y - 1, on, isFocused, TOGGLE_COLORS)
    if not armed and ui.rowTapped(touchState, x, x + w, y, ROW_H) then
        if touchState.x >= x + w - tw then
            onToggle()
        else
            focusedKey = isFocused and nil or toggleFocusKey
        end
    end
end

local function drawGroup(x, w, y, group, values, touchState, armed, state)
    local on = values[group.primaryKey] ~= 0
    drawToggleRow(x, w, y, group.label, on, "toggle:" .. group.id, values, touchState, armed, function()
        toggleGroup(group, values, state)
    end)
    y = y + ROW_H
    if on then
        local fields = group.fields
        local i = 1
        while i <= #fields do
            drawFieldPair(x, w, y, fields[i], fields[i + 1], values, touchState, armed)
            y = y + ROW_H
            i = i + 2
        end
    end
    return y
end

local function drawDtermLpf1(x, w, y, values, touchState, armed, state)
    local on = dtermLpf1Enabled(values)
    drawToggleRow(x, w, y, "D Term Lowpass 1", on, "toggle:dtermLpf1", values, touchState, armed, function()
        toggleDtermLpf1(values, state)
    end)
    y = y + ROW_H

    if on then
        local dynamic = dtermLpf1IsDynamic(values)
        local modeFocusKey = "mode:dtermLpf1"
        local modeFocused = (focusedKey == modeFocusKey)
        lcd.drawText(x, y, "Mode: " .. (dynamic and "DYNAMIC" or "STATIC"), modeFocused and COLOR_YELLOW or COLOR_WHITE)
        if not armed and ui.rowTapped(touchState, x, x + w, y, ROW_H) then
            focusedKey = modeFocused and nil or modeFocusKey
        end
        y = y + ROW_H

        if dynamic then
            drawFieldPair(x, w, y, { key = "dtermLpf1DynMinHz", label = "Min Hz" }, { key = "dtermLpf1DynMaxHz", label = "Max Hz" }, values, touchState, armed)
            y = y + ROW_H
            drawField(x, w, y, { key = "dtermLpf1DynExpo", label = "Dyn Curve Expo" }, values, touchState, armed)
            y = y + ROW_H
        else
            drawField(x, w, y, { key = "dtermLpf1Hz", label = "Cutoff" }, values, touchState, armed)
            y = y + ROW_H
        end

        drawField(x, w, y, { key = "dtermLpf1Type", label = "Type" }, values, touchState, armed)
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
        elseif string.sub(focusedKey, 1, 7) == "toggle:" then
            local id = string.sub(focusedKey, 8)
            if id == "dtermLpf1" then
                toggleDtermLpf1(values, state)
            else
                local group = findGroupById(id)
                if group then toggleGroup(group, values, state) end
            end
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
    for _, group in ipairs(LEFT_GROUPS) do
        y = drawGroup(COL_L_X, COL_L_W, y, group, values, touchState, armed, state)
    end

    y = CONTENT_TOP
    y = drawDtermLpf1(COL_R_X, COL_R_W, y, values, touchState, armed, state)
    for _, group in ipairs(RIGHT_GROUPS) do
        y = drawGroup(COL_R_X, COL_R_W, y, group, values, touchState, armed, state)
    end
end

return M
