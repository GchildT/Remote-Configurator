-- Explicit RGB colors rather than named constants -- see main.lua's note.
local COLOR_WHITE = lcd.RGB(255, 255, 255)
local COLOR_YELLOW = lcd.RGB(255, 210, 0)
local COLOR_GREY = lcd.RGB(110, 110, 110)
local COLOR_RED = lcd.RGB(220, 60, 60)
local COLOR_GREEN = lcd.RGB(60, 200, 90)
local COLOR_BLUE = lcd.RGB(70, 140, 240)

-- Confirmed against EdgeTX firmware source (radio/src/keys.h).
local EVT_ROTARY_LEFT = 0x1003
local EVT_ROTARY_RIGHT = 0x1004

local M = {}

-- ratesShared is NOT loaded here with the usual loadScript/dofile-in-file
-- pattern -- see pages/rates.lua's header comment (loadScript()/dofile()
-- have no require()-style caching, and ratesShared.lua carries mutable
-- state both rate tabs must share). main.lua injects the one instance via
-- M.init().
local shared = nil

function M.init(sharedRatesModule)
    shared = sharedRatesModule
end

-- Confirmed against Betaflight Configurator source
-- (src/components/tabs/pid-tuning/RatesSubTab.vue: const RatesType = {...}
-- -- same enum rates.lua uses).
local RATES_TYPE_RACEFLIGHT = 1
local RATES_TYPE_KISS = 2
local RATES_TYPE_ACTUAL = 3
local RATES_TYPE_QUICKRATES = 4

-- Confirmed against Betaflight firmware source
-- (src/main/fc/controlrate_profile.h: throttleLimitType_e).
local THROTTLE_LIMIT_TYPE_NAMES = { [0] = "OFF", [1] = "SCALE", [2] = "CLIP" }
local THROTTLE_LIMIT_TYPE_COUNT = 3

--------------------------------------------------------------------------------
-- Rate curve math -- ported line-for-line from betaflight-configurator's own
-- src/js/RateCurve.js (getBetaflightRates/getRaceflightRates/getKISSRates/
-- getActualRates/getQuickRates), which is itself how Configurator draws its
-- "Rates Preview" graph. `t` is the normalized stick position in [-1, 1]
-- (RateCurve.js's `rcCommandf` with deadband=0, which this project doesn't
-- fetch -- a minor simplification that only affects the exact shape right
-- at center stick, not the overall curve). All rate/rcRate/rcExpo inputs are
-- the SAME per-type-scaled floats rates.lua's formatCenterSensitivity/
-- formatMaxRate/formatExpo already compute for display -- see
-- scaledRateValue() below, which factors that scaling out of those
-- functions instead of duplicating it.
--------------------------------------------------------------------------------

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- Betaflight's default type; Configurator always evaluates it with
-- superExpoActive=true regardless of the FC's actual feature flag (it
-- hardcodes `currentRates.superexpo = true` right before drawing the
-- preview), so this project does the same for the graph.
local function getBetaflightRate(t, tAbs, rate, rcRate, rcExpo, limit)
    if rcRate > 2 then
        rcRate = rcRate + (rcRate - 2) * 14.54
    end
    local rcCommandf = t
    if rcExpo > 0 then
        rcCommandf = t * (tAbs * tAbs * tAbs) * rcExpo + t * (1 - rcExpo)
    end
    local rcFactor = 1 / clamp(1 - tAbs * rate, 0.01, 1)
    local angularVel = 200 * rcRate * rcCommandf * rcFactor
    return clamp(angularVel, -limit, limit)
end

local function getRaceflightRate(t, rate, rcRate, rcExpo)
    local angularVel = (1 + 0.01 * rcExpo * (t * t - 1.0)) * t
    angularVel = angularVel * (rcRate + math.abs(angularVel) * rcRate * rate * 0.01)
    return angularVel
end

local function getKissRate(t, tAbs, rate, rcRate, rcExpo)
    local kissRpy = 1 - tAbs * rate
    local kissTempCurve = t * t
    local rcCommandf = (t * kissTempCurve * rcExpo + t * (1 - rcExpo)) * (rcRate / 10)
    return 2000.0 * (1.0 / kissRpy) * rcCommandf
end

local function getActualRate(t, tAbs, rate, rcRate, rcExpo)
    local expof = tAbs * (t * t * t * t * t * rcExpo + t * (1 - rcExpo))
    local angularVel = math.max(0, rate - rcRate)
    angularVel = t * rcRate + angularVel * expof
    return angularVel
end

local function getQuickRate(t, tAbs, rate, rcRate, rcExpo)
    rcRate = rcRate * 200
    rate = math.max(rate, rcRate)
    local superExpoConfig = (rate / rcRate - 1) / (rate / rcRate)
    local curve = (tAbs * tAbs * tAbs) * rcExpo + tAbs * (1 - rcExpo)
    local angularVel = 1.0 / (1.0 - curve * superExpoConfig)
    angularVel = t * rcRate * angularVel
    return angularVel
end

local function rateAt(t, ratesType, rate, rcRate, rcExpo, limit)
    local tAbs = math.abs(t)
    if ratesType == RATES_TYPE_RACEFLIGHT then
        return getRaceflightRate(t, rate, rcRate, rcExpo)
    elseif ratesType == RATES_TYPE_KISS then
        return getKissRate(t, tAbs, rate, rcRate, rcExpo)
    elseif ratesType == RATES_TYPE_ACTUAL then
        return getActualRate(t, tAbs, rate, rcRate, rcExpo)
    elseif ratesType == RATES_TYPE_QUICKRATES then
        return getQuickRate(t, tAbs, rate, rcRate, rcExpo)
    else
        return getBetaflightRate(t, tAbs, rate, rcRate, rcExpo, limit)
    end
end

-- Raw MSP byte (0-255ish) -> the per-type-scaled float RateCurve.js's own
-- getCurrentRates() feeds into the formulas above. `kind` is "rate" (super
-- rate / Max Rate), "rcRate" (RC Rate / Center Sensitivity), or "expo" --
-- confirmed against that function's switch statement that these three
-- scale DIFFERENTLY per type (e.g. QuickRates scales "rate" by 1000 but
-- leaves "rcRate" and "expo" unscaled; RaceFlight scales all three, but
-- "rcRate" by 1000 while "rate"/"expo" are only *100).
local function scaledRateValue(raw, ratesType, kind)
    local v = raw / 100
    if ratesType == RATES_TYPE_RACEFLIGHT then
        if kind == "rcRate" then return v * 1000 end
        return v * 100
    elseif ratesType == RATES_TYPE_ACTUAL then
        if kind == "expo" then return v end
        return v * 1000
    elseif ratesType == RATES_TYPE_QUICKRATES then
        if kind == "rate" then return v * 1000 end
        return v
    else
        return v -- Betaflight/Kiss: unscaled
    end
end

--------------------------------------------------------------------------------
-- Layout: two columns below the tab bar/profile row. Left: the rate-curve
-- graph. Right: Throttle Limit + Throttle MID/Hover/EXPO, matching
-- Configurator's own grouping (just stacked instead of side-by-side within
-- the column, since this screen is far narrower).
--------------------------------------------------------------------------------
local CONTENT_TOP = 86
local GRAPH_X, GRAPH_Y, GRAPH_W, GRAPH_H = 6, CONTENT_TOP, 228, 140
local COL_R_X, COL_R_W = 246, 228
local ROW_H = 22

local focusedKey = nil -- "throttleLimitType" | raw field key | nil

local FIELD_SPECS = {
    throttleLimitPercent = { label = "Limit %", min = 0, max = 100, step = 1 },
    thrMid8 = { label = "Throttle MID", min = 0, max = 100, step = 1 },
    hoverPoint = { label = "Hover Point", min = 0, max = 100, step = 1 },
    thrExpo8 = { label = "Throttle EXPO", min = 0, max = 100, step = 1 },
}

function M.create()
    shared.create()
    focusedKey = nil
end

function M.update(state, armed)
    shared.update(state, armed)
end

function M.beginSave(session, state)
    shared.beginSave(session, state)
end

local function drawGraph(values)
    lcd.drawRectangle(GRAPH_X, GRAPH_Y, GRAPH_W, GRAPH_H, COLOR_GREY)
    local cx, cy = GRAPH_X + GRAPH_W / 2, GRAPH_Y + GRAPH_H / 2
    lcd.drawLine(GRAPH_X + 1, cy, GRAPH_X + GRAPH_W - 1, cy, SOLID, COLOR_GREY)
    lcd.drawLine(cx, GRAPH_Y + 1, cx, GRAPH_Y + GRAPH_H - 1, SOLID, COLOR_GREY)

    local ratesType = values.ratesType
    local limit = math.max(values.rateLimitRoll, values.rateLimitPitch, values.rateLimitYaw)
    if limit <= 0 then limit = 1998 end

    local axes = {
        { key = "Roll", color = COLOR_RED, rate = scaledRateValue(values.superRateRoll, ratesType, "rate"), rcRate = scaledRateValue(values.rcRateRoll, ratesType, "rcRate"), rcExpo = scaledRateValue(values.rcExpoRoll, ratesType, "expo") },
        { key = "Pitch", color = COLOR_GREEN, rate = scaledRateValue(values.superRatePitch, ratesType, "rate"), rcRate = scaledRateValue(values.rcRatePitch, ratesType, "rcRate"), rcExpo = scaledRateValue(values.rcExpoPitch, ratesType, "expo") },
        { key = "Yaw", color = COLOR_BLUE, rate = scaledRateValue(values.superRateYaw, ratesType, "rate"), rcRate = scaledRateValue(values.rcRateYaw, ratesType, "rcRate"), rcExpo = scaledRateValue(values.rcExpoYaw, ratesType, "expo") },
    }

    -- Shared vertical scale across all 3 curves, sized to the largest one's
    -- full-deflection value -- same approach as RateCurve.js's
    -- getMaxAngularVel/setMaxAngularVel (round up to the next 200).
    local maxVal = 1
    for _, a in ipairs(axes) do
        local v = math.abs(rateAt(1, ratesType, a.rate, a.rcRate, a.rcExpo, limit))
        if v > maxVal then maxVal = v end
    end
    maxVal = math.ceil(maxVal / 200) * 200

    local halfW, halfH = GRAPH_W / 2 - 2, GRAPH_H / 2 - 2
    local STEPS = 24
    for _, a in ipairs(axes) do
        local prevX, prevY = nil, nil
        for i = 0, STEPS do
            local t = -1 + (2 * i / STEPS)
            local v = rateAt(t, ratesType, a.rate, a.rcRate, a.rcExpo, limit)
            local px = cx + t * halfW
            local py = cy - clamp(v / maxVal, -1, 1) * halfH
            if prevX ~= nil then
                lcd.drawLine(prevX, prevY, px, py, SOLID, a.color)
            end
            prevX, prevY = px, py
        end
    end

    lcd.drawText(GRAPH_X + 4, GRAPH_Y + 2, tostring(math.floor(maxVal)) .. " deg/s", COLOR_GREY)
end

local function drawField(x, w, y, key, values)
    local spec = FIELD_SPECS[key]
    local isFocused = (focusedKey == key)
    local color = isFocused and COLOR_YELLOW or COLOR_WHITE
    local valueText
    if key == "thrMid8" or key == "thrExpo8" or key == "hoverPoint" then
        valueText = string.format("%.2f", values[key] / 100)
    else
        valueText = tostring(values[key])
    end
    lcd.drawText(x, y, spec.label .. ": " .. valueText, color)
    return isFocused
end

function M.event(event, touchState, state, session, nowMs, armed)
    local values = shared.ensureLoaded(session, nowMs, state, CONTENT_TOP, "Loading rate curves...")
    if values == nil then
        return
    end

    local hasHover = shared.hasHoverPoint(values)

    if not armed and focusedKey ~= nil and (event == EVT_ROTARY_LEFT or event == EVT_ROTARY_RIGHT) then
        local delta = (event == EVT_ROTARY_RIGHT) and 1 or -1
        if focusedKey == "throttleLimitType" then
            local newValue = (values.throttleLimitType + delta) % THROTTLE_LIMIT_TYPE_COUNT
            if newValue < 0 then newValue = newValue + THROTTLE_LIMIT_TYPE_COUNT end
            state:setField(shared.PAGE_KEY, "throttleLimitType", newValue)
        else
            local spec = FIELD_SPECS[focusedKey]
            if spec and (focusedKey ~= "hoverPoint" or hasHover) then
                local newValue = clamp(values[focusedKey] + delta * spec.step, spec.min, spec.max)
                state:setField(shared.PAGE_KEY, focusedKey, newValue)
            end
        end
        values = state:get(shared.PAGE_KEY) -- re-fetch: the branches above may have staged new values
    end

    drawGraph(values)

    local y = CONTENT_TOP
    -- Throttle Limit Type + %
    do
        local isFocused = (focusedKey == "throttleLimitType")
        lcd.drawText(COL_R_X, y, "Throttle Limit: " .. (THROTTLE_LIMIT_TYPE_NAMES[values.throttleLimitType] or "?"), isFocused and COLOR_YELLOW or COLOR_WHITE)
        if not armed and touchState and touchState.x >= COL_R_X and touchState.x < COL_R_X + COL_R_W and touchState.y >= y and touchState.y < y + ROW_H then
            focusedKey = isFocused and nil or "throttleLimitType"
        end
        y = y + ROW_H
    end

    for _, key in ipairs({ "throttleLimitPercent", "thrMid8", "hoverPoint", "thrExpo8" }) do
        if key == "hoverPoint" and not hasHover then
            lcd.drawText(COL_R_X, y, "Hover Point: N/A (needs newer FW)", COLOR_GREY)
        else
            local isFocused = drawField(COL_R_X, COL_R_W, y, key, values)
            if not armed and touchState and touchState.x >= COL_R_X and touchState.x < COL_R_X + COL_R_W and touchState.y >= y and touchState.y < y + ROW_H then
                focusedKey = isFocused and nil or key
            end
        end
        y = y + ROW_H
    end
end

-- Test-only seam: exposes the otherwise-local curve math so it can be
-- verified directly against hand-derived expected values (see
-- tests/mspMsgs_spec.lua-adjacent manual smoke tests) without needing to
-- drive the whole page through a fake session/touch sequence just to check
-- a formula port. Not used by any real page logic above.
M._test = {
    rateAt = rateAt,
    scaledRateValue = scaledRateValue,
}

return M
