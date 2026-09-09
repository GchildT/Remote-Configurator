local M = {}

M.CMD = {
    API_VERSION = 1,
    FC_VARIANT = 2,
    FC_VERSION = 3,
    VTX_CONFIG = 88,
    SET_VTX_CONFIG = 89,
    FILTER_CONFIG = 92,
    SET_FILTER_CONFIG = 93,
    RC_TUNING = 111,
    SET_RC_TUNING = 204,
    SELECT_SETTING = 210,
    EEPROM_WRITE = 250,
    SIMPLIFIED_TUNING = 140,
    SET_SIMPLIFIED_TUNING = 141,
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

-- Offsets verified against Betaflight 4.5.5 src/main/msp/msp.c (case MSP_FILTER_CONFIG).
-- Note: byte 1 (C offset 0) is a legacy narrow gyro_lpf1_static_hz duplicate;
-- we deliberately use the full-range U16 copy at offset 21 instead.
M.FILTER_CONFIG_FIELDS = {
    dtermLpf1Hz = { offset = 2, size = 2 },
    gyroLpf1Hz = { offset = 21, size = 2 },
    gyroLpf2Hz = { offset = 23, size = 2 },
    dtermLpf2Hz = { offset = 27, size = 2 },
}

function M.decodeApiVersion(payload)
    return string.byte(payload, 1), string.byte(payload, 2), string.byte(payload, 3)
end

function M.decodeFcVariant(payload)
    return payload:sub(1, 4)
end

function M.isBetaflight(variantString)
    return variantString == "BTFL"
end

function M.decodeFcVersion(payload)
    return string.byte(payload, 1), string.byte(payload, 2), string.byte(payload, 3)
end

local RATEPROFILE_MASK = 0x80

function M.encodeSelectSetting(profileType, index)
    if profileType == "rate" then
        return string.char(RATEPROFILE_MASK | (index & 0x7f))
    else
        return string.char(index & 0x7f)
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
    out[#out + 1] = string.char(legacy % 256, legacy // 256)
    out[#out + 1] = string.char(current.power)
    out[#out + 1] = string.char(current.pitmode)
    out[#out + 1] = string.char(current.lowPowerDisarm)
    out[#out + 1] = string.char(current.pitModeFreq % 256, current.pitModeFreq // 256)
    out[#out + 1] = string.char(current.band, current.channel)
    out[#out + 1] = string.char(0, 0) -- standalone freq: 0 = derive from band/channel
    return table.concat(out)
end

return M
