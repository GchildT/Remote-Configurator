-- Backing data/session logic shared by pages/globalFilters.lua and
-- pages/profileFilters.lua.
--
-- Both tabs read and write the SAME underlying flight-controller structure:
-- MSP_FILTER_CONFIG (92/93) is one combined message covering both the gyro
-- ("global"/profile-independent) and D-term/yaw ("profile"-dependent)
-- filter fields together -- Betaflight has no separate MSP command per
-- section. If each tab independently fetched, staged, and saved its OWN
-- copy of that buffer, two tabs dirty at the same time (or one saved while
-- the other's stale copy is later saved) could each round-trip a FULL copy
-- of the shared structure and silently clobber the other's just-written
-- fields with whatever was in its own, no-longer-current, snapshot. Sharing
-- one state key ("filters"), one rawBuffer, and one load/save cycle here
-- avoids that entirely: both tabs stage edits into the exact same
-- underlying table, so a save from either one always includes the other's
-- pending edits too.
local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")

local COLOR_WHITE = lcd.RGB(255, 255, 255)

local M = {}

M.PAGE_KEY = "filters"

-- Confirmed against Betaflight firmware source (src/main/common/filter.h:
-- lowpassFilterType_e) and betaflight-configurator's own filterTypeItems
-- (src/components/tabs/pid-tuning/FilterSubTab.vue).
M.FILTER_TYPE_NAMES = { [0] = "PT1", [1] = "BIQUAD", [2] = "PT2", [3] = "PT3" }
M.FILTER_TYPE_COUNT = 4

-- Every editable raw MSP_FILTER_CONFIG field across BOTH tabs, with jog-dial
-- range/step (or isEnum for the filter-type dropdowns, cycled instead of
-- ranged). See mspMsgs.lua's FILTER_CONFIG_FIELDS comment for verified byte
-- offsets. No on/off toggle controls: every field is a plain always-visible
-- row, tap to focus + dial to adjust. 0 disables the corresponding filter on
-- the FC itself (confirmed against betaflight-configurator source), so
-- dialing a field down to 0 IS turning that filter off.
M.FIELD_SPECS = {
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

-- Filter Multiplier sliders: a jog-dial-adjustable percentage (raw byte /
-- 100, e.g. 150 -> "1.50") that asks the FC to recompute the corresponding
-- filter family's Hz values via MSP_CALCULATE_SIMPLIFIED_GYRO/DTERM, exactly
-- as betaflight-configurator's own slider does (see mspMsgs.lua's
-- FILTER_MULTIPLIER_CALC_FIELDS comment) -- a convenience bulk adjustment,
-- not a separate stored setting; the multiplier value itself is never sent
-- back to the FC, only the Hz values it computes.
M.MULT_MIN, M.MULT_MAX, M.MULT_STEP = 25, 250, 5

local phase = "idle" -- idle | loadingFilterConfig | loadingSimplifiedTuning | ready
local pendingValues = nil -- accumulates across the two load steps before state:load()

local gyroMultDirty = false
local dtermMultDirty = false
local calcPhase = "idle" -- idle | pending
local calcWhich = nil -- "gyro" | "dterm"

function M.create()
    phase = "idle"
    pendingValues = nil
    gyroMultDirty = false
    dtermMultDirty = false
    calcPhase = "idle"
    calcWhich = nil
end

function M.update(state, armed)
    if phase == "idle" and state:get(M.PAGE_KEY) == nil then
        phase = "loadingFilterConfig"
    end
end

function M.beginSave(session, state)
    local values = state:get(M.PAGE_KEY)
    local buf = values.rawBuffer
    for key in pairs(M.FIELD_SPECS) do
        buf = mspBuffer.writeField(buf, mspMsgs.FILTER_CONFIG_FIELDS[key], values[key])
    end
    session:request(mspMsgs.CMD.SET_FILTER_CONFIG, buf)
end

-- Pumps the two-step load (MSP_FILTER_CONFIG, then MSP_SIMPLIFIED_TUNING --
-- the latter only for the two filter-multiplier display values, see
-- mspMsgs.lua's SIMPLIFIED_TUNING_MULTIPLIER_FIELDS comment). Callers (both
-- tabs) must call this every tick from their own M.event before rendering.
-- Returns the current staged values once ready, or nil (having drawn a
-- loading message) while still loading.
function M.ensureLoaded(session, nowMs, state, contentTopY, loadingText)
    if phase == "loadingFilterConfig" then
        local status = session:poll(nowMs)
        if status == "done" then
            local cmd, payload = session:result()
            -- Shared session: only decode a reply to OUR request (see pids.lua).
            if cmd == mspMsgs.CMD.FILTER_CONFIG then
                pendingValues = { rawBuffer = payload }
                for key in pairs(M.FIELD_SPECS) do
                    pendingValues[key] = mspBuffer.readField(payload, mspMsgs.FILTER_CONFIG_FIELDS[key])
                end
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
                state:load(M.PAGE_KEY, pendingValues)
                pendingValues = nil
                phase = "ready"
            else
                phase = "idle"
            end
        elseif status == "idle" then
            session:request(mspMsgs.CMD.SIMPLIFIED_TUNING, "")
        elseif status == "timeout" or status == "error" then
            session:reset()
            -- Nothing was staged into `state` yet, so there's nothing to roll
            -- back -- just restart the whole load.
            pendingValues = nil
            phase = "idle"
        end
    end

    if phase ~= "ready" then
        lcd.drawText(10, contentTopY, loadingText, COLOR_WHITE)
        return nil
    end
    return state:get(M.PAGE_KEY)
end

function M.dtermLpf1IsDynamic(values)
    return values.dtermLpf1DynMinHz ~= 0
end

-- Flips the mode: swaps which of static-cutoff vs dynamic-min/max is the
-- non-zero (active) representation, seeding the other side with a sane
-- default the first time it's used.
function M.setDtermLpf1Mode(values, state, dynamic)
    if dynamic then
        state:setField(M.PAGE_KEY, "dtermLpf1Hz", 0)
        if values.dtermLpf1DynMinHz == 0 then state:setField(M.PAGE_KEY, "dtermLpf1DynMinHz", 100) end
        if values.dtermLpf1DynMaxHz == 0 then state:setField(M.PAGE_KEY, "dtermLpf1DynMaxHz", 250) end
    else
        state:setField(M.PAGE_KEY, "dtermLpf1DynMinHz", 0)
        state:setField(M.PAGE_KEY, "dtermLpf1DynMaxHz", 0)
        if values.dtermLpf1Hz == 0 then state:setField(M.PAGE_KEY, "dtermLpf1Hz", 100) end
    end
end

function M.fieldValueText(key, values)
    local spec = M.FIELD_SPECS[key]
    if spec.isEnum then
        return M.FILTER_TYPE_NAMES[values[key]] or tostring(values[key])
    end
    return tostring(values[key])
end

-- Dispatches a jog-dial rotation to whichever field is focused. `focusedKey`
-- is one of: a raw FIELD_SPECS key, "mode:dtermLpf1", "mult:gyro", or
-- "mult:dterm". Shared by both tabs so the dispatch logic (and the
-- MULT_MIN/MAX/STEP clamp) lives in exactly one place; a tab only ever sets
-- focusedKey to values relevant to its own rendered fields, so the other
-- branches are simply never hit from that tab.
function M.adjustFocusedField(focusedKey, delta, values, state)
    if focusedKey == "mode:dtermLpf1" then
        M.setDtermLpf1Mode(values, state, not M.dtermLpf1IsDynamic(values))
    elseif focusedKey == "mult:gyro" then
        local newValue = math.max(M.MULT_MIN, math.min(M.MULT_MAX, values.gyroFilterMultiplier + delta * M.MULT_STEP))
        state:setField(M.PAGE_KEY, "gyroFilterMultiplier", newValue)
        gyroMultDirty = true
    elseif focusedKey == "mult:dterm" then
        local newValue = math.max(M.MULT_MIN, math.min(M.MULT_MAX, values.dtermFilterMultiplier + delta * M.MULT_STEP))
        state:setField(M.PAGE_KEY, "dtermFilterMultiplier", newValue)
        dtermMultDirty = true
    else
        local spec = M.FIELD_SPECS[focusedKey]
        if spec then
            if spec.isEnum then
                local newValue = (values[focusedKey] + delta) % M.FILTER_TYPE_COUNT
                if newValue < 0 then newValue = newValue + M.FILTER_TYPE_COUNT end
                state:setField(M.PAGE_KEY, focusedKey, newValue)
            else
                local step = spec.step or 1
                local newValue = values[focusedKey] + delta * step
                newValue = math.max(spec.min, math.min(spec.max, newValue))
                state:setField(M.PAGE_KEY, focusedKey, newValue)
            end
        end
    end
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
-- FILTER_MULTIPLIER_CALC_FIELDS comment). Call every tick from whichever tab
-- is active; harmless no-op if neither dirty flag is set.
function M.pumpMultiplierCalc(session, state, values, nowMs)
    if calcPhase == "pending" then
        local status = session:poll(nowMs)
        if status == "done" then
            local cmd, payload = session:result()
            if calcWhich == "gyro" and cmd == mspMsgs.CMD.CALCULATE_SIMPLIFIED_GYRO then
                local r = decodeCalcResponse(payload)
                state:setField(M.PAGE_KEY, "gyroLpf1Hz", r.lpf1Hz)
                state:setField(M.PAGE_KEY, "gyroLpf2Hz", r.lpf2Hz)
            elseif calcWhich == "dterm" and cmd == mspMsgs.CMD.CALCULATE_SIMPLIFIED_DTERM then
                local r = decodeCalcResponse(payload)
                state:setField(M.PAGE_KEY, "dtermLpf1Hz", r.lpf1Hz)
                state:setField(M.PAGE_KEY, "dtermLpf2Hz", r.lpf2Hz)
                state:setField(M.PAGE_KEY, "dtermLpf1DynMinHz", r.dynMinHz)
                state:setField(M.PAGE_KEY, "dtermLpf1DynMaxHz", r.dynMaxHz)
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

return M
