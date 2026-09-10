local M = {}

-- Command ids verified against Betaflight 4.5.5 src/main/msp/msp_protocol.h.
M.CMD = {
    API_VERSION = 1,
    FC_VARIANT = 2,
    FC_VERSION = 3,
    VTX_CONFIG = 88,
    SET_VTX_CONFIG = 89,
    FILTER_CONFIG = 92,
    SET_FILTER_CONFIG = 93,
    PID_ADVANCED = 94,
    SET_PID_ADVANCED = 95,
    RC_TUNING = 111,
    SET_RC_TUNING = 204,
    SELECT_SETTING = 210,
    EEPROM_WRITE = 250,
    SIMPLIFIED_TUNING = 140,
    SET_SIMPLIFIED_TUNING = 141,
    CALCULATE_SIMPLIFIED_PID = 142,
    CALCULATE_SIMPLIFIED_GYRO = 143,
    CALCULATE_SIMPLIFIED_DTERM = 144,
}

-- Offsets verified against Betaflight 4.5.5 src/main/msp/msp.c
-- (readSimplifiedPids/writeSimplifiedPids), 1-based for Lua string indexing.
M.SIMPLIFIED_TUNING_FIELDS = {
    pidsMode = { offset = 1, size = 1 },
    masterMultiplier = { offset = 2, size = 1 },
    rollPitchRatio = { offset = 3, size = 1 },
    iGain = { offset = 4, size = 1 },
    dGain = { offset = 5, size = 1 },
    piGain = { offset = 6, size = 1 },
    dminRatio = { offset = 7, size = 1 },
    feedforwardGain = { offset = 8, size = 1 },
    pitchPiGain = { offset = 9, size = 1 },
}

-- The full MSP_SIMPLIFIED_TUNING (140) GET payload is actually THREE blocks
-- concatenated -- writeSimplifiedPids (17 bytes, SIMPLIFIED_TUNING_FIELDS
-- above), writeSimplifiedDtermFilters (18 bytes), writeSimplifiedGyroFilters
-- (18 bytes), 53 bytes total -- verified against Betaflight 4.5.5 AND
-- 2026.6.1 src/main/msp/msp.c. This project only reads the two "is the
-- filter multiplier slider set to something" bytes out of the latter two
-- blocks, purely to seed the Filters page's multiplier display on load --
-- see FILTER_MULTIPLIER_CALC_FIELDS below for the separate 18-byte format
-- used to actually recompute filter values from a new multiplier position.
M.SIMPLIFIED_TUNING_MULTIPLIER_FIELDS = {
    dtermFilterMultiplier = { offset = 19, size = 1 },
    gyroFilterMultiplier = { offset = 37, size = 1 },
}

-- Shared 18-byte request/response shape for BOTH MSP_CALCULATE_SIMPLIFIED_
-- GYRO (143) and MSP_CALCULATE_SIMPLIFIED_DTERM (144) -- verified against
-- Betaflight 4.5.5 AND 2026.6.1 src/main/msp/msp.c: readSimplifiedGyroFilters/
-- readSimplifiedDtermFilters (request) and writeSimplifiedGyroFilters/
-- writeSimplifiedDtermFilters (response) are byte-for-byte identical in
-- shape to each other (only the semantic meaning of "which filter family"
-- differs, per which command id was sent): enabled flag, multiplier
-- percentage (raw = display*100), static lpf1/lpf2 Hz, dynamic lpf1 min/max
-- Hz, then 8 reserved bytes. Confirmed against betaflight-configurator
-- source (src/js/composables/useTuningSliders.js:
-- calculateNewGyroFilters/calculateNewDTermFilters): the request is built by
-- setting the enabled flag to 1 and the multiplier to the new slider
-- position, seeding the rest from the currently-loaded filter values, then
-- sending it to the FC, which computes and returns the resulting Hz values
-- in this same shape -- nothing is saved to the FC by this command itself.
M.FILTER_MULTIPLIER_CALC_FIELDS = {
    enabled = { offset = 1, size = 1 },
    multiplier = { offset = 2, size = 1 },
    lpf1Hz = { offset = 3, size = 2 },
    lpf2Hz = { offset = 5, size = 2 },
    dynMinHz = { offset = 7, size = 2 },
    dynMaxHz = { offset = 9, size = 2 },
}
M.FILTER_MULTIPLIER_CALC_PAYLOAD_LEN = 18

-- Offsets verified against Betaflight 4.5.5 src/main/msp/msp.c (case MSP_RC_TUNING).
M.RC_TUNING_FIELDS = {
    rcRateRoll = { offset = 1, size = 1 },
    rcExpoRoll = { offset = 2, size = 1 },
    superRateRoll = { offset = 3, size = 1 },
    superRatePitch = { offset = 4, size = 1 },
    superRateYaw = { offset = 5, size = 1 },
    thrMid8 = { offset = 7, size = 1 },
    thrExpo8 = { offset = 8, size = 1 },
    rcExpoYaw = { offset = 11, size = 1 },
    rcRateYaw = { offset = 12, size = 1 },
    rcRatePitch = { offset = 13, size = 1 },
    rcExpoPitch = { offset = 14, size = 1 },
    throttleLimitType = { offset = 15, size = 1 },
    throttleLimitPercent = { offset = 16, size = 1 },
    rateLimitRoll = { offset = 17, size = 2 },
    rateLimitPitch = { offset = 19, size = 2 },
    rateLimitYaw = { offset = 21, size = 2 },
    ratesType = { offset = 23, size = 1 },
}

-- Offsets verified against Betaflight 4.5.5 AND 2026.6.1 src/main/msp/msp.c
-- (case MSP_FILTER_CONFIG -- byte-for-byte identical between the two).
-- Note: byte 1 (C offset 0) is a legacy narrow gyro_lpf1_static_hz duplicate;
-- we deliberately use the full-range U16 copy at offset 21 instead.
M.FILTER_CONFIG_FIELDS = {
    dtermLpf1Hz = { offset = 2, size = 2 },
    yawLowpassHz = { offset = 4, size = 2 },
    gyroNotch1Hz = { offset = 6, size = 2 },
    gyroNotch1Cutoff = { offset = 8, size = 2 },
    dtermNotchHz = { offset = 10, size = 2 },
    dtermNotchCutoff = { offset = 12, size = 2 },
    gyroNotch2Hz = { offset = 14, size = 2 },
    gyroNotch2Cutoff = { offset = 16, size = 2 },
    dtermLpf1Type = { offset = 18, size = 1 },
    gyroLpf1Hz = { offset = 21, size = 2 },
    gyroLpf2Hz = { offset = 23, size = 2 },
    gyroLpf1Type = { offset = 25, size = 1 },
    gyroLpf2Type = { offset = 26, size = 1 },
    dtermLpf2Hz = { offset = 27, size = 2 },
    dtermLpf2Type = { offset = 29, size = 1 },
    dtermLpf1DynMinHz = { offset = 34, size = 2 },
    dtermLpf1DynMaxHz = { offset = 36, size = 2 },
    dynNotchQ = { offset = 40, size = 2 },
    dynNotchMinHz = { offset = 42, size = 2 },
    rpmFilterHarmonics = { offset = 44, size = 1 },
    rpmFilterMinHz = { offset = 45, size = 1 },
    dynNotchMaxHz = { offset = 46, size = 2 },
    dtermLpf1DynExpo = { offset = 48, size = 1 },
    dynNotchCount = { offset = 49, size = 1 },
}

-- Offsets verified against Betaflight 4.5.5 AND 2026.6.1 src/main/msp/msp.c
-- (case MSP_PID_ADVANCED -- byte-for-byte identical between the two, aside
-- from a same-offset field rename: abs_control_gain in 4.5.5 became a
-- reserved/always-0 byte in 2026.6.1, not used by this project either way).
-- 61-byte payload; round-tripped in full like SIMPLIFIED_TUNING_FIELDS.
M.PID_ADVANCED_FIELDS = {
    throttleBoost = { offset = 31, size = 1 },
    motorOutputLimit = { offset = 48, size = 1 },
    dynIdleMinRpm = { offset = 50, size = 1 },
    vbatSagCompensation = { offset = 56, size = 1 },
    thrustLinearization = { offset = 57, size = 1 },
}

function M.decodeApiVersion(payload)
    return string.byte(payload, 1), string.byte(payload, 2), string.byte(payload, 3)
end

function M.decodeFcVariant(payload)
    return string.sub(payload, 1, 4)
end

function M.isBetaflight(variantString)
    return variantString == "BTFL"
end

function M.decodeFcVersion(payload)
    return string.byte(payload, 1), string.byte(payload, 2), string.byte(payload, 3)
end

local RATEPROFILE_MASK = 0x80

-- EdgeTX embeds Lua 5.2, which has no native bitwise operators (added in
-- 5.3) -- these are written as portable arithmetic instead. RATEPROFILE_MASK
-- (bit 7) and the low-7-bits index are disjoint, so OR-ing them is addition.
function M.encodeSelectSetting(profileType, index)
    if profileType == "rate" then
        return string.char(RATEPROFILE_MASK + (index % 128))
    else
        return string.char(index % 128)
    end
end

-- GET response layout verified against Betaflight 4.5.5 (case MSP_VTX_CONFIG).
function M.decodeVtxConfig(payload)
    return {
        vtxType = string.byte(payload, 1),
        band = string.byte(payload, 2),
        channel = string.byte(payload, 3),
        power = string.byte(payload, 4),
        pitmode = string.byte(payload, 5),
    }
end

-- SET payload layout verified against Betaflight 4.5.5 (case MSP_SET_VTX_CONFIG).
-- Sends: [legacy band/chan-encoded u16][power][pitmode][lowPowerDisarm][pitModeFreq u16]
--        [standalone band][standalone channel][standalone freq u16 = 0, band/channel takes priority]
-- Both the legacy-encoded field and the standalone band/channel fields are sent
-- with the same values so they can't disagree; band/channel are always 1-8 here
-- so (band-1)*8+(channel-1) <= 63 = VTXCOMMON_MSP_BANDCHAN_CHKVAL, keeping the
-- legacy field interpreted as band/channel (not as a raw frequency).
function M.encodeVtxConfigSet(current)
    local legacy = (current.band - 1) * 8 + (current.channel - 1)
    local out = {}
    out[#out + 1] = string.char(legacy % 256, math.floor(legacy / 256))
    out[#out + 1] = string.char(current.power)
    out[#out + 1] = string.char(current.pitmode)
    out[#out + 1] = string.char(current.lowPowerDisarm)
    out[#out + 1] = string.char(current.pitModeFreq % 256, math.floor(current.pitModeFreq / 256))
    out[#out + 1] = string.char(current.band, current.channel)
    out[#out + 1] = string.char(0, 0) -- standalone freq: 0 = derive from band/channel
    return table.concat(out)
end

-- MSP_CALCULATE_SIMPLIFIED_PID (142) response layout verified against
-- Betaflight 4.5.5 src/main/msp/msp.c: writePidfs() writes, for each of
-- XYZ_AXIS_COUNT (3) axes in Roll/Pitch/Yaw order: P(u8), I(u8), D(u8),
-- d_min(u8), F(u16 LE) -- 6 bytes/axis, 18 bytes total. This is the
-- firmware's OWN computation of the resulting per-axis PID values from the
-- current simplified-tuning slider percentages, without saving anything --
-- used for a live preview while the sliders are being adjusted.
function M.decodeSimplifiedPidPreview(payload)
    local axes = {}
    local order = { "roll", "pitch", "yaw" }
    for i, name in ipairs(order) do
        local base = (i - 1) * 6
        axes[name] = {
            p = string.byte(payload, base + 1),
            i = string.byte(payload, base + 2),
            d = string.byte(payload, base + 3),
            dMin = string.byte(payload, base + 4),
            ff = string.byte(payload, base + 5) + string.byte(payload, base + 6) * 256,
        }
    end
    return axes
end

return M
