local testkit = require("tests.testkit")
local safety = dofile("src/SCRIPTS/TOOLS/BFDash/safety.lua")

testkit.describe("safety arm tracker", function()
    testkit.it("defaults to armed before any frame is received (fail-safe)", function()
        local t = safety.new()
        testkit.assertTrue(t:isArmed(), "armed by default")
    end)

    testkit.it("reports disarmed when the flight mode string ends with '*'", function()
        local t = safety.new()
        t:feedFlightModeFrame("ACRO*\0")
        testkit.assertEquals(t:isArmed(), false, "trailing * means disarmed")
    end)

    testkit.it("debugInfo reports stale/armed/lastRawText/frameCount for on-screen diagnostics", function()
        local t = safety.new()
        local stale0 = t:debugInfo()
        testkit.assertEquals(stale0, true, "stale before any frame")
        t:feedFlightModeFrame("ACRO*\0")
        local stale, armed, lastRawText, frameCount = t:debugInfo()
        testkit.assertEquals(stale, false, "not stale after a frame")
        testkit.assertEquals(armed, false, "armed reflects the parsed frame")
        testkit.assertEquals(lastRawText, "ACRO*", "lastRawText is the null-stripped text")
        testkit.assertEquals(frameCount, 1, "frameCount increments")
        t:feedFlightModeFrame("ACRO\0")
        local _, _, _, frameCount2 = t:debugInfo()
        testkit.assertEquals(frameCount2, 2, "frameCount increments again")
    end)

    testkit.it("reports armed when the flight mode string has no trailing '*'", function()
        local t = safety.new()
        t:feedFlightModeFrame("ACRO*\0") -- first disarm
        t:feedFlightModeFrame("ACRO\0")  -- then arm
        testkit.assertEquals(t:isArmed(), true, "no trailing * means armed")
    end)

    testkit.it("handles other flight mode names, not just ACRO", function()
        local t = safety.new()
        t:feedFlightModeFrame("STAB\0")
        testkit.assertEquals(t:isArmed(), true, "STAB with no star = armed")
        t:feedFlightModeFrame("!FS!*\0")
        testkit.assertEquals(t:isArmed(), false, "failsafe with star = disarmed")
    end)

    -- Betaflight 2026.6.1 src/main/telemetry/crsf.c: crsfFrameFlightMode() writes
    -- '!' (arming disabled) or '?' (GPS rescue unavailable) instead of '*' in
    -- some disarmed states -- confirmed on real hardware (mode text "AIR!").
    testkit.it("reports disarmed when the flight mode string ends with '!' (arming disabled)", function()
        local t = safety.new()
        t:feedFlightModeFrame("AIR!\0")
        testkit.assertEquals(t:isArmed(), false, "trailing ! means disarmed (arming disabled)")
    end)

    testkit.it("reports disarmed when the flight mode string ends with '?' (GPS rescue unavailable)", function()
        local t = safety.new()
        t:feedFlightModeFrame("AIR?\0")
        testkit.assertEquals(t:isArmed(), false, "trailing ? means disarmed (GPS rescue unavailable)")
    end)

    -- During failsafe, Betaflight sends the fixed text "!FS!" with NO suffix
    -- logic applied regardless of arm state, so it cannot be used to infer
    -- arm state via suffix. Must fail safe (treated as armed/locked) rather
    -- than be misread as disarmed just because it happens to end in '!'.
    testkit.it("treats the exact failsafe mode text '!FS!' as armed (ambiguous, fail-safe default)", function()
        local t = safety.new()
        t:feedFlightModeFrame("ACRO\0") -- armed baseline
        t:feedFlightModeFrame("!FS!\0")
        testkit.assertEquals(t:isArmed(), true, "'!FS!' alone is ambiguous -> defaults to armed")
    end)

    testkit.it("markStale forces armed regardless of prior frame (fail-safe)", function()
        local t = safety.new()
        t:feedFlightModeFrame("ACRO\0") -- arm first, to prove markStale overrides it
        t:markStale()
        testkit.assertTrue(t:isArmed(), "stale telemetry forces armed")
    end)

    testkit.it("feedFlightModeFrame(nil) does not throw and stays armed (fail-safe)", function()
        local t = safety.new()
        local ok = pcall(function()
            t:feedFlightModeFrame(nil)
        end)
        testkit.assertTrue(ok, "feedFlightModeFrame(nil) must not throw")
        testkit.assertTrue(t:isArmed(), "no valid data received yet -> armed via stale fail-safe")
    end)

    testkit.it("feedFlightModeFrame('') does not throw", function()
        local t = safety.new()
        local ok = pcall(function()
            t:feedFlightModeFrame("")
        end)
        testkit.assertTrue(ok, "feedFlightModeFrame('') must not throw")
        testkit.assertTrue(t:isArmed(), "no valid data received yet -> armed via stale fail-safe")
    end)

    testkit.it("feedFlightModeFrame with a malformed nil frame does not corrupt a prior armed reading", function()
        local t = safety.new()
        t:feedFlightModeFrame("ACRO\0") -- valid armed frame, clears stale
        testkit.assertTrue(t:isArmed(), "armed after valid frame")
        local ok = pcall(function()
            t:feedFlightModeFrame(nil)
        end)
        testkit.assertTrue(ok, "feedFlightModeFrame(nil) must not throw")
        testkit.assertTrue(t:isArmed(), "malformed frame ignored, previous armed state retained")
    end)

    testkit.it("feedFlightModeFrame treats a string with no null terminator or star as a valid armed frame", function()
        local t = safety.new()
        local ok = pcall(function()
            t:feedFlightModeFrame("garbage-no-null")
        end)
        testkit.assertTrue(ok, "feedFlightModeFrame('garbage-no-null') must not throw")
        testkit.assertEquals(t:isArmed(), true, "no null and no trailing * -> armed")
    end)

    testkit.it("a fresh frame after markStale clears the stale override", function()
        local t = safety.new()
        t:markStale()
        t:feedFlightModeFrame("ACRO\0")
        testkit.assertEquals(t:isArmed(), true, "fresh frame re-evaluated normally")
    end)
end)
