local testkit = require("tests.testkit")
local mspMsgs = dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")

testkit.describe("mspMsgs.CMD", function()
    testkit.it("has the command ids verified against Betaflight 4.5.5 msp_protocol.h", function()
        testkit.assertEquals(mspMsgs.CMD.API_VERSION, 1, "API_VERSION")
        testkit.assertEquals(mspMsgs.CMD.FC_VARIANT, 2, "FC_VARIANT")
        testkit.assertEquals(mspMsgs.CMD.FC_VERSION, 3, "FC_VERSION")
        testkit.assertEquals(mspMsgs.CMD.VTX_CONFIG, 88, "VTX_CONFIG")
        testkit.assertEquals(mspMsgs.CMD.SET_VTX_CONFIG, 89, "SET_VTX_CONFIG")
        testkit.assertEquals(mspMsgs.CMD.FILTER_CONFIG, 92, "FILTER_CONFIG")
        testkit.assertEquals(mspMsgs.CMD.SET_FILTER_CONFIG, 93, "SET_FILTER_CONFIG")
        testkit.assertEquals(mspMsgs.CMD.RC_TUNING, 111, "RC_TUNING")
        testkit.assertEquals(mspMsgs.CMD.SET_RC_TUNING, 204, "SET_RC_TUNING")
        testkit.assertEquals(mspMsgs.CMD.SELECT_SETTING, 210, "SELECT_SETTING (not 10 -- verified from source)")
        testkit.assertEquals(mspMsgs.CMD.EEPROM_WRITE, 250, "EEPROM_WRITE")
        testkit.assertEquals(mspMsgs.CMD.SIMPLIFIED_TUNING, 140, "SIMPLIFIED_TUNING")
        testkit.assertEquals(mspMsgs.CMD.SET_SIMPLIFIED_TUNING, 141, "SET_SIMPLIFIED_TUNING")
        testkit.assertEquals(mspMsgs.CMD.CALCULATE_SIMPLIFIED_PID, 142, "CALCULATE_SIMPLIFIED_PID")
        testkit.assertEquals(mspMsgs.CMD.CALCULATE_SIMPLIFIED_GYRO, 143, "CALCULATE_SIMPLIFIED_GYRO")
        testkit.assertEquals(mspMsgs.CMD.CALCULATE_SIMPLIFIED_DTERM, 144, "CALCULATE_SIMPLIFIED_DTERM")
    end)
end)

testkit.describe("mspMsgs FC identity decoders", function()
    testkit.it("decodes MSP_API_VERSION payload", function()
        local payload = string.char(2, 1, 46) -- protocol=2, major=1, minor=46
        local proto, major, minor = mspMsgs.decodeApiVersion(payload)
        testkit.assertEquals(proto, 2, "protocol version")
        testkit.assertEquals(major, 1, "api major")
        testkit.assertEquals(minor, 46, "api minor")
    end)

    testkit.it("decodes MSP_FC_VARIANT payload as a 4-char string", function()
        testkit.assertEquals(mspMsgs.decodeFcVariant("BTFL"), "BTFL", "variant string")
    end)

    testkit.it("identifies Betaflight from the variant string", function()
        testkit.assertTrue(mspMsgs.isBetaflight("BTFL"), "BTFL recognized")
        testkit.assertTrue(not mspMsgs.isBetaflight("INAV"), "INAV rejected")
    end)

    testkit.it("decodes MSP_FC_VERSION payload", function()
        local major, minor, patch = mspMsgs.decodeFcVersion(string.char(4, 5, 5))
        testkit.assertEquals(major, 4, "major")
        testkit.assertEquals(minor, 5, "minor")
        testkit.assertEquals(patch, 5, "patch")
    end)
end)

testkit.describe("mspMsgs.SIMPLIFIED_TUNING_FIELDS", function()
    testkit.it("reads the 9 slider fields at their verified offsets", function()
        -- mode, master, rollPitch, i, d, pi, dmin, ff, pitchPi = 1..9, then 8 reserved bytes
        local buf = string.char(1, 100, 100, 100, 100, 100, 100, 100, 100) .. string.rep("\0", 8)
        local f = mspMsgs.SIMPLIFIED_TUNING_FIELDS
        testkit.assertEquals(mspBuffer.readField(buf, f.pidsMode), 1, "pidsMode")
        testkit.assertEquals(mspBuffer.readField(buf, f.masterMultiplier), 100, "masterMultiplier")
        testkit.assertEquals(mspBuffer.readField(buf, f.pitchPiGain), 100, "pitchPiGain (offset 9, last of the 9)")
    end)

    testkit.it("patches only the PID slider bytes, leaving the rest of a 53-byte buffer untouched", function()
        local buf = string.rep("\170", 53) -- 0xAA filler standing in for dterm/gyro filter sub-blocks
        local f = mspMsgs.SIMPLIFIED_TUNING_FIELDS
        local patched = mspBuffer.writeField(buf, f.masterMultiplier, 150)
        testkit.assertEquals(#patched, 53, "length preserved")
        testkit.assertEquals(mspBuffer.readField(patched, f.masterMultiplier), 150, "patched field")
        testkit.assertEquals(string.byte(patched, 10), 0xAA, "byte 10 (start of dterm filter sub-block) untouched")
        testkit.assertEquals(string.byte(patched, 53), 0xAA, "last byte untouched")
    end)
end)

testkit.describe("mspMsgs.RC_TUNING_FIELDS", function()
    testkit.it("reads rates_type at the last byte of a 23-byte response", function()
        local buf = string.rep("\0", 22) .. string.char(2) -- rates_type = 2 (RaceFlight)
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.RC_TUNING_FIELDS.ratesType), 2, "ratesType")
    end)

    testkit.it("reads rate_limit fields as u16", function()
        local buf = string.rep("\0", 16) .. string.char(0xE8, 0x03) .. string.rep("\0", 4) -- rateLimitRoll=1000 at offset 17-18
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.RC_TUNING_FIELDS.rateLimitRoll), 1000, "rateLimitRoll")
    end)
end)

testkit.describe("mspMsgs.FILTER_CONFIG_FIELDS", function()
    testkit.it("reads gyro/dterm lowpass fields at their verified offsets", function()
        local buf = string.rep("\0", 45)
        buf = mspBuffer.writeField(buf, mspMsgs.FILTER_CONFIG_FIELDS.dtermLpf1Hz, 100)
        buf = mspBuffer.writeField(buf, mspMsgs.FILTER_CONFIG_FIELDS.gyroLpf1Hz, 250)
        buf = mspBuffer.writeField(buf, mspMsgs.FILTER_CONFIG_FIELDS.gyroLpf2Hz, 500)
        buf = mspBuffer.writeField(buf, mspMsgs.FILTER_CONFIG_FIELDS.dtermLpf2Hz, 150)
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.FILTER_CONFIG_FIELDS.dtermLpf1Hz), 100, "dtermLpf1Hz")
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.FILTER_CONFIG_FIELDS.gyroLpf1Hz), 250, "gyroLpf1Hz")
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.FILTER_CONFIG_FIELDS.gyroLpf2Hz), 500, "gyroLpf2Hz")
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.FILTER_CONFIG_FIELDS.dtermLpf2Hz), 150, "dtermLpf2Hz")
    end)

    -- Notch/RPM/dynamic-notch/yaw/filter-type fields added for the extended
    -- Filters tab (toggles + full editable set) -- offsets verified against
    -- Betaflight 4.5.5 AND 2026.6.1 src/main/msp/msp.c (case
    -- MSP_FILTER_CONFIG), byte-for-byte identical between the two.
    testkit.it("reads notch/RPM/dynamic-notch/yaw/filter-type fields at their verified offsets, without disturbing neighbors", function()
        local buf = string.rep("\0", 49)
        local fields = {
            yawLowpassHz = 100,
            gyroNotch1Hz = 400, gyroNotch1Cutoff = 200,
            dtermNotchHz = 260, dtermNotchCutoff = 160,
            gyroNotch2Hz = 200, gyroNotch2Cutoff = 100,
            dtermLpf1Type = 1, gyroLpf1Type = 2, gyroLpf2Type = 3,
            dtermLpf2Type = 0,
            dtermLpf1DynMinHz = 75, dtermLpf1DynMaxHz = 150,
            dynNotchQ = 600, dynNotchMinHz = 90,
            rpmFilterHarmonics = 3, rpmFilterMinHz = 75,
            dynNotchMaxHz = 475,
            dtermLpf1DynExpo = 5,
            dynNotchCount = 3,
        }
        for key, value in pairs(fields) do
            buf = mspBuffer.writeField(buf, mspMsgs.FILTER_CONFIG_FIELDS[key], value)
        end
        for key, value in pairs(fields) do
            testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.FILTER_CONFIG_FIELDS[key]), value, key)
        end
        testkit.assertEquals(#buf, 49, "buffer length unchanged by writes")
    end)
end)

testkit.describe("mspMsgs.SIMPLIFIED_TUNING_MULTIPLIER_FIELDS", function()
    testkit.it("reads the gyro/dterm filter multiplier bytes at their verified offsets in the 53-byte MSP_SIMPLIFIED_TUNING payload", function()
        -- Offsets verified against Betaflight 4.5.5 AND 2026.6.1
        -- src/main/msp/msp.c: writeSimplifiedPids (17 bytes) +
        -- writeSimplifiedDtermFilters (18 bytes, multiplier at its byte 2 ->
        -- overall offset 19) + writeSimplifiedGyroFilters (18 bytes,
        -- multiplier at its byte 2 -> overall offset 37).
        local buf = string.rep("\0", 53)
        buf = mspBuffer.writeField(buf, mspMsgs.SIMPLIFIED_TUNING_MULTIPLIER_FIELDS.dtermFilterMultiplier, 120)
        buf = mspBuffer.writeField(buf, mspMsgs.SIMPLIFIED_TUNING_MULTIPLIER_FIELDS.gyroFilterMultiplier, 150)
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.SIMPLIFIED_TUNING_MULTIPLIER_FIELDS.dtermFilterMultiplier), 120, "dtermFilterMultiplier")
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.SIMPLIFIED_TUNING_MULTIPLIER_FIELDS.gyroFilterMultiplier), 150, "gyroFilterMultiplier")
        testkit.assertEquals(#buf, 53, "buffer length unchanged by writes")
    end)
end)

testkit.describe("mspMsgs.FILTER_MULTIPLIER_CALC_FIELDS", function()
    testkit.it("reads/writes the shared 18-byte CALCULATE_SIMPLIFIED_GYRO/DTERM request-response fields", function()
        -- Offsets verified against Betaflight 4.5.5 AND 2026.6.1
        -- src/main/msp/msp.c: readSimplifiedGyroFilters/readSimplifiedDtermFilters
        -- (request) and writeSimplifiedGyroFilters/writeSimplifiedDtermFilters
        -- (response) share this exact 18-byte shape.
        local F = mspMsgs.FILTER_MULTIPLIER_CALC_FIELDS
        local buf = string.rep("\0", mspMsgs.FILTER_MULTIPLIER_CALC_PAYLOAD_LEN)
        buf = mspBuffer.writeField(buf, F.enabled, 1)
        buf = mspBuffer.writeField(buf, F.multiplier, 150)
        buf = mspBuffer.writeField(buf, F.lpf1Hz, 250)
        buf = mspBuffer.writeField(buf, F.lpf2Hz, 500)
        buf = mspBuffer.writeField(buf, F.dynMinHz, 100)
        buf = mspBuffer.writeField(buf, F.dynMaxHz, 400)
        testkit.assertEquals(mspBuffer.readField(buf, F.enabled), 1, "enabled")
        testkit.assertEquals(mspBuffer.readField(buf, F.multiplier), 150, "multiplier")
        testkit.assertEquals(mspBuffer.readField(buf, F.lpf1Hz), 250, "lpf1Hz")
        testkit.assertEquals(mspBuffer.readField(buf, F.lpf2Hz), 500, "lpf2Hz")
        testkit.assertEquals(mspBuffer.readField(buf, F.dynMinHz), 100, "dynMinHz")
        testkit.assertEquals(mspBuffer.readField(buf, F.dynMaxHz), 400, "dynMaxHz")
        testkit.assertEquals(#buf, 18, "buffer length is 18 bytes")
    end)
end)

testkit.describe("mspMsgs.PID_ADVANCED_FIELDS", function()
    testkit.it("reads throttle/motor fields at their verified offsets, without disturbing neighbors", function()
        -- Offsets verified against Betaflight 4.5.5 AND 2026.6.1
        -- src/main/msp/msp.c (case MSP_PID_ADVANCED), byte-for-byte identical
        -- between the two -- 61-byte payload.
        local buf = string.rep("\0", 61)
        buf = mspBuffer.writeField(buf, mspMsgs.PID_ADVANCED_FIELDS.throttleBoost, 5)
        buf = mspBuffer.writeField(buf, mspMsgs.PID_ADVANCED_FIELDS.motorOutputLimit, 100)
        buf = mspBuffer.writeField(buf, mspMsgs.PID_ADVANCED_FIELDS.dynIdleMinRpm, 40)
        buf = mspBuffer.writeField(buf, mspMsgs.PID_ADVANCED_FIELDS.vbatSagCompensation, 100)
        buf = mspBuffer.writeField(buf, mspMsgs.PID_ADVANCED_FIELDS.thrustLinearization, 25)
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.PID_ADVANCED_FIELDS.throttleBoost), 5, "throttleBoost")
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.PID_ADVANCED_FIELDS.motorOutputLimit), 100, "motorOutputLimit")
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.PID_ADVANCED_FIELDS.dynIdleMinRpm), 40, "dynIdleMinRpm")
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.PID_ADVANCED_FIELDS.vbatSagCompensation), 100, "vbatSagCompensation")
        testkit.assertEquals(mspBuffer.readField(buf, mspMsgs.PID_ADVANCED_FIELDS.thrustLinearization), 25, "thrustLinearization")
        testkit.assertEquals(#buf, 61, "buffer length unchanged by writes")
    end)
end)

testkit.describe("mspMsgs.encodeSelectSetting", function()
    testkit.it("encodes a PID profile index with bit 7 clear", function()
        local payload = mspMsgs.encodeSelectSetting("pid", 2)
        testkit.assertEquals(string.byte(payload, 1), 2, "pid profile index, no rate bit")
    end)

    testkit.it("encodes a rate profile index with bit 7 set", function()
        local payload = mspMsgs.encodeSelectSetting("rate", 1)
        testkit.assertEquals(string.byte(payload, 1), 0x80 | 1, "rate profile index, rate bit set")
    end)
end)

testkit.describe("mspMsgs VTX config codec", function()
    testkit.it("decodes band/channel/power from a GET response", function()
        -- vtxType,band,channel,power,pitmode,freqLo,freqHi,ready,lowPowerDisarm,pitFreqLo,pitFreqHi,...
        local payload = string.char(3, 2, 5, 3, 0) .. string.char(0x88, 0x16) .. string.char(1, 0) .. string.char(0, 0)
        local cfg = mspMsgs.decodeVtxConfig(payload)
        testkit.assertEquals(cfg.band, 2, "band")
        testkit.assertEquals(cfg.channel, 5, "channel")
        testkit.assertEquals(cfg.power, 3, "power")
    end)

    testkit.it("encodes a SET_VTX_CONFIG payload using the standalone band/channel/freq extension", function()
        local current = { band = 3, channel = 4, power = 2, pitmode = 0, lowPowerDisarm = 0, pitModeFreq = 5658 }
        local payload = mspMsgs.encodeVtxConfigSet(current)
        testkit.assertEquals(#payload, 11, "11-byte SET payload")
        -- bytes 8-9 (1-based) are the standalone band/channel per the plan's derived layout
        testkit.assertEquals(string.byte(payload, 8), 3, "standalone band")
        testkit.assertEquals(string.byte(payload, 9), 4, "standalone channel")
        testkit.assertEquals(string.byte(payload, 3), 2, "power field")
    end)
end)

testkit.describe("mspMsgs.decodeSimplifiedPidPreview", function()
    testkit.it("decodes 3 axes of P/I/D/dMin/FF from an 18-byte response, roll/pitch/yaw order", function()
        -- roll: P=45,I=80,D=30,dMin=20,F=120 (u16 LE: 120,0)
        -- pitch: P=47,I=84,D=34,dMin=23,F=125
        -- yaw: P=45,I=80,D=0,dMin=0,F=120
        local payload = string.char(45, 80, 30, 20, 120, 0)
            .. string.char(47, 84, 34, 23, 125, 0)
            .. string.char(45, 80, 0, 0, 120, 0)
        local axes = mspMsgs.decodeSimplifiedPidPreview(payload)
        testkit.assertEquals(axes.roll.p, 45, "roll P")
        testkit.assertEquals(axes.roll.i, 80, "roll I")
        testkit.assertEquals(axes.roll.d, 30, "roll D")
        testkit.assertEquals(axes.roll.dMin, 20, "roll dMin")
        testkit.assertEquals(axes.roll.ff, 120, "roll FF")
        testkit.assertEquals(axes.pitch.d, 34, "pitch D")
        testkit.assertEquals(axes.pitch.ff, 125, "pitch FF")
        testkit.assertEquals(axes.yaw.dMin, 0, "yaw dMin")
    end)

    testkit.it("decodes a 2-byte feedforward value correctly (u16 little-endian)", function()
        local payload = string.char(0, 0, 0, 0, 0x2C, 0x01) -- FF = 0x012C = 300
            .. string.rep("\0", 6) .. string.rep("\0", 6)
        local axes = mspMsgs.decodeSimplifiedPidPreview(payload)
        testkit.assertEquals(axes.roll.ff, 300, "FF decoded as little-endian u16")
    end)
end)
