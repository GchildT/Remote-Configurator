local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")
local ui = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/ui.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/ui.lua")

-- Explicit RGB colors rather than named constants -- see main.lua's note.
local COLOR_WHITE = lcd.RGB(255, 255, 255)
local COLOR_YELLOW = lcd.RGB(255, 210, 0)

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

-- Editable raw MSP_FILTER_CONFIG fields on this page, with jog-dial
-- range/step (or isEnum for the filter-type dropdowns, cycled instead of
-- ranged). See mspMsgs.lua's FILTER_CONFIG_FIELDS comment for verified byte
-- offsets. D-Term Lowpass 2, Gyro/D-Term Notch, and Yaw Lowpass are
-- intentionally not exposed here (removed for screen space/clutter) -- their
-- raw bytes are still round-tripped untouched by beginSave, so nothing on
-- the FC changes for those fields on save. (D-Term Lowpass 2's Hz CAN still
-- change via the D Term Filter Multiplier slider below, exactly as it would
-- in Configurator -- see pumpMultiplierCalc.)
--
-- No on/off toggle controls: every field is a plain always-visible row, tap
-- to focus + dial to adjust. 0 disables the corresponding filter on the FC
-- itself (confirmed against betaflight-configurator source), so dialing a
-- field down to 0 IS turning that filter off -- no separate switch needed.
local FIELD_SPECS = {
    gyroLpf1Hz = { min = 0, max = 4000, step = 5 },
    gyroLpf1Type = { isEnum = true },
    gyroLpf2Hz = { min = 0, max = 4000, step = 5 },
    gyroLpf2Type = { isEnum = true },
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
}
-- dtermLpf2Hz is round-tripped (see beginSave) but not in FIELD_SPECS: it has
-- no dedicated row of its own, only the multiplier slider can change it.

-- Field order below matches Betaflight Configurator's own Filter Settings
-- screen top-to-bottom: Gyro Lowpass Filters, (Gyro Notch Filters -- removed
-- here), Gyro RPM Filter, Dynamic Notch Filter on the gyro side; D Term
-- Lowpass Filters (D Term Lowpass 1 only -- LP2 removed as its own row,
-- (D Term Notch Filter / Yaw Lowpass Filter -- also removed here) on the
-- D-term side. Single full-width column (not Configurator's two) -- see the
-- commit that introduced this: a 480px-wide two-column split only gave each
-- field ~114px, too narrow for these labels and prone to visually
-- overlapping text.
local ROWS = {
    { { key = "gyroLpf1Hz", label = "Gyro LP1 Cutoff" }, { key = "gyroLpf1Type", label = "Type" } },
    { { key = "gyroLpf2Hz", label = "Gyro LP2 Cutoff" }, { key = "gyroLpf2Type", label = "Type" } },
    { { key = "rpmFilterHarmonics", label = "RPM Harmonics" }, { key = "rpmFilterMinHz", label = "Min Hz" } },
    { { key = "dynNotchCount", label = "Dyn Notch Count" }, { key = "dynNotchQ", label = "Q(x100)" } },
    { { key = "dynNotchMinHz", label = "Dyn Notch Min Hz" }, { key = "dynNotchMaxHz", label = "Max Hz" } },
}

-- Layout: content starts at y=70 (below tab bar + profile row, with a
-- deliberate few-px gap so it doesn't crowd the profile row) and must finish
-- above the footer at y=232. Worst case (D Term Lowpass 1 in dynamic mode)
-- is 9 rows total, each with a full ~230px-wide half-column per field.
local CONTENT_TOP = 70
local ROW_H = 18
local COL_X, COL_W = 6, 468

-- Filter Multiplier sliders: a jog-dial-adjustable percentage (raw byte /
-- 100, e.g. 150 -> "1.50") that asks the FC to recompute the corresponding
-- filter family's Hz values via MSP_CALCULATE_SIMPLIFIED_GYRO/DTERM, exactly
-- as betaflight-configurator's own slider does (see mspMsgs.lua's
-- FILTER_MULTIPLIER_CALC_FIELDS comment) -- this is a convenience bulk
-- adjustment, not a separate stored setting; the multiplier value itself is
-- never sent back to the FC, only the Hz values it computes.
local MULT_MIN, MULT_MAX, MULT_STEP = 25, 250, 5

local phase = "idle" -- idle | loadingFilterConfig | loadingSimplifiedTuning | ready
local focusedKey = nil -- raw field key | "mode:dtermLpf1" | "mult:gyro" | "mult:dterm" | nil
local pendingValues = nil -- accumulates across the two load steps before state:load()

local gyroMultDirty = false
local dtermMultDirty = false
local calcPhase = "idle" -- idle | pending
local calcWhich = nil -- "gyro" | "dterm"

function M.create()
    phase = "idle"
    focusedKey = nil
    pendingValues = nil
    gyroMultDirty = false
    dtermMultDirty = false
    calcPhase = "idle"
    calcWhich = nil
end

function M.update(state, armed)
    if phase == "idle" and state:get(PAGE_KEY) == nil then
        phase = "loadingFilterConfig"
    end
end

local function beginSave(session, state)
    local values = state:get(PAGE_KEY)
    local buf = values.rawBuffer
    for key in pairs(FIELD_SPECS) do
        buf = mspBuffer.writeField(buf, mspMsgs.FILTER_CONFIG_FIELDS[key], values[key])
    end
    buf = mspBuffer.writeField(buf, mspMsgs.FILTER_CONFIG_FIELDS.dtermLpf2Hz, values.dtermLpf2Hz)
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

local function drawMultiplierRow(x, w, y, values, touchState, armed)
    local halfW = w / 2
    local gyroFocused = (focusedKey == "mult:gyro")
    local dtermFocused = (focusedKey == "mult:dterm")
    lcd.drawText(x, y, string.format("Gyro Mult: %.2f", values.gyroFilterMultiplier / 100), gyroFocused and COLOR_YELLOW or COLOR_WHITE)
    lcd.drawText(x + halfW, y, string.format("D Term Mult: %.2f", values.dtermFilterMultiplier / 100), dtermFocused and COLOR_YELLOW or COLOR_WHITE)
    if not armed and ui.rowTapped(touchState, x, x + halfW, y, ROW_H) then
        focusedKey = gyroFocused and nil or "mult:gyro"
    end
    if not armed and ui.rowTapped(touchState, x + halfW, x + w, y, ROW_H) then
        focusedKey = dtermFocused and nil or "mult:dterm"
    end
end

local function drawDtermLpf1(x, w, y, values, touchState, armed)
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

-- Builds an 18-byte MSP_CALCULATE_SIMPLIFIED_GYRO/DTERM request -- see
-- mspMsgs.lua's FILTER_MULTIPLIER_CALC_FIELDS comment. `enabled=1` matches
-- betaflight-configurator's own request construction exactly.
local function buildCalcRequest(multiplier, lpf1Hz, lpf2Hz, dynMinHz, dynMaxHz)
    local F = mspMsgs.FILTER_MULTIPLIER_CALC_FIELDS
    local buf = string.rep("\0", mspMsgs.FILTER_MULTIPLIER_CALC_PAYLOAD_LEN)
    buf = mspBuffer.writeField(buf, F.enabled, 1)
    buf = mspBuffer.writeField(buf, F.multiplier, multiplier)
    buf = mspBuffer.writeField(buf, F.lpf1Hz, lpf1Hz)
    buf = mspBuffer.writeField(buf, F.lpf2Hz, lpf2Hz)
    buf = mspBuffer.writeField(buf, F.dynMinHz, dynMinHz)
    buf = mspBuffer.writeField(buf, F.dynMaxHz, dynMaxHz)
    return buf
end

local function decodeCalcResponse(payload)
    local F = mspMsgs.FILTER_MULTIPLIER_CALC_FIELDS
    return {
        lpf1Hz = mspBuffer.readField(payload, F.lpf1Hz),
        lpf2Hz = mspBuffer.readField(payload, F.lpf2Hz),
        dynMinHz = mspBuffer.readField(payload, F.dynMinHz),
        dynMaxHz = mspBuffer.readField(payload, F.dynMaxHz),
    }
end

-- Sends whichever multiplier just changed to the FC via MSP_CALCULATE_
-- SIMPLIFIED_GYRO/DTERM and applies the computed Hz values back into staged
-- state -- exactly betaflight-configurator's calculateNewGyroFilters/
-- calculateNewDTermFilters behavior (see mspMsgs.lua's
-- FILTER_MULTIPLIER_CALC_FIELDS comment): the FC computes new filter cutoffs
-- from the multiplier position, and this is what actually changes what gets
-- saved -- the multiplier byte itself is never sent to the FC.
local function pumpMultiplierCalc(session, state, values, nowMs)
    if calcPhase == "pending" then
        local status = session:poll(nowMs)
        if status == "done" then
            local cmd, payload = session:result()
            if calcWhich == "gyro" and cmd == mspMsgs.CMD.CALCULATE_SIMPLIFIED_GYRO then
                local r = decodeCalcResponse(payload)
                state:setField(PAGE_KEY, "gyroLpf1Hz", r.lpf1Hz)
                state:setField(PAGE_KEY, "gyroLpf2Hz", r.lpf2Hz)
            elseif calcWhich == "dterm" and cmd == mspMsgs.CMD.CALCULATE_SIMPLIFIED_DTERM then
                local r = decodeCalcResponse(payload)
                state:setField(PAGE_KEY, "dtermLpf1Hz", r.lpf1Hz)
                state:setField(PAGE_KEY, "dtermLpf2Hz", r.lpf2Hz)
                state:setField(PAGE_KEY, "dtermLpf1DynMinHz", r.dynMinHz)
                state:setField(PAGE_KEY, "dtermLpf1DynMaxHz", r.dynMaxHz)
            else
                -- Response belonged to a different in-flight request on this
                -- shared session -- our request was never actually answered.
                -- Retry, or the slider would silently stop taking effect.
                if calcWhich == "gyro" then gyroMultDirty = true else dtermMultDirty = true end
            end
            calcPhase = "idle"
            calcWhich = nil
        elseif status == "timeout" or status == "error" then
            session:reset()
            if calcWhich == "gyro" then gyroMultDirty = true else dtermMultDirty = true end
            calcPhase = "idle"
            calcWhich = nil
        end
    elseif not session:isPending() then
        if gyroMultDirty then
            local buf = buildCalcRequest(values.gyroFilterMultiplier, values.gyroLpf1Hz, values.gyroLpf2Hz, 0, 0)
            session:request(mspMsgs.CMD.CALCULATE_SIMPLIFIED_GYRO, buf)
            calcPhase, calcWhich, gyroMultDirty = "pending", "gyro", false
        elseif dtermMultDirty then
            local buf = buildCalcRequest(values.dtermFilterMultiplier, values.dtermLpf1Hz, values.dtermLpf2Hz, values.dtermLpf1DynMinHz, values.dtermLpf1DynMaxHz)
            session:request(mspMsgs.CMD.CALCULATE_SIMPLIFIED_DTERM, buf)
            calcPhase, calcWhich, dtermMultDirty = "pending", "dterm", false
        end
    end
end

function M.event(event, touchState, state, session, nowMs, armed)
    if phase == "loadingFilterConfig" then
        local status = session:poll(nowMs)
        if status == "done" then
            local cmd, payload = session:result()
            -- Shared session: only decode a reply to OUR request (see pids.lua).
            if cmd == mspMsgs.CMD.FILTER_CONFIG then
                pendingValues = { rawBuffer = payload }
                for key in pairs(FIELD_SPECS) do
                    pendingValues[key] = mspBuffer.readField(payload, mspMsgs.FILTER_CONFIG_FIELDS[key])
                end
                pendingValues.dtermLpf2Hz = mspBuffer.readField(payload, mspMsgs.FILTER_CONFIG_FIELDS.dtermLpf2Hz)
                phase = "loadingSimplifiedTuning"
            else
                phase = "idle" -- not ours; retry cleanly on the next update()
            end
        elseif status == "idle" then
            session:request(mspMsgs.CMD.FILTER_CONFIG, "")
        elseif status == "timeout" or status == "error" then
            session:reset()
            phase = "idle"
        end
    elseif phase == "loadingSimplifiedTuning" then
        local status = session:poll(nowMs)
        if status == "done" then
            local cmd, payload = session:result()
            if cmd == mspMsgs.CMD.SIMPLIFIED_TUNING then
                local F = mspMsgs.SIMPLIFIED_TUNING_MULTIPLIER_FIELDS
                pendingValues.gyroFilterMultiplier = mspBuffer.readField(payload, F.gyroFilterMultiplier)
                pendingValues.dtermFilterMultiplier = mspBuffer.readField(payload, F.dtermFilterMultiplier)
                state:load(PAGE_KEY, pendingValues)
                pendingValues = nil
                phase = "ready"
            else
                phase = "idle"
            end
        elseif status == "idle" then
            session:request(mspMsgs.CMD.SIMPLIFIED_TUNING, "")
        elseif status == "timeout" or status == "error" then
            session:reset()
            -- Restart the whole load: pendingValues is discarded, but nothing
            -- was staged into `state` yet, so there's nothing to roll back.
            pendingValues = nil
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
        elseif focusedKey == "mult:gyro" then
            local newValue = math.max(MULT_MIN, math.min(MULT_MAX, values.gyroFilterMultiplier + delta * MULT_STEP))
            state:setField(PAGE_KEY, "gyroFilterMultiplier", newValue)
            gyroMultDirty = true
        elseif focusedKey == "mult:dterm" then
            local newValue = math.max(MULT_MIN, math.min(MULT_MAX, values.dtermFilterMultiplier + delta * MULT_STEP))
            state:setField(PAGE_KEY, "dtermFilterMultiplier", newValue)
            dtermMultDirty = true
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

    if not armed then
        pumpMultiplierCalc(session, state, values, nowMs)
        values = state:get(PAGE_KEY) -- pumpMultiplierCalc may have just applied a computed result
    end

    local y = CONTENT_TOP
    drawMultiplierRow(COL_X, COL_W, y, values, touchState, armed)
    y = y + ROW_H

    for _, row in ipairs(ROWS) do
        drawRow(COL_X, COL_W, y, row, values, touchState, armed)
        y = y + ROW_H
    end

    drawDtermLpf1(COL_X, COL_W, y, values, touchState, armed)
end

return M
