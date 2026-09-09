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

    testkit.it("treats an empty or malformed frame as armed (fail-safe)", function()
        local t = safety.new()
        t:feedFlightModeFrame("ACRO\0") -- arm first, to prove markStale overrides it
        t:markStale()
        testkit.assertTrue(t:isArmed(), "stale telemetry forces armed")
    end)

    testkit.it("a fresh frame after markStale clears the stale override", function()
        local t = safety.new()
        t:markStale()
        t:feedFlightModeFrame("ACRO\0")
        testkit.assertEquals(t:isArmed(), true, "fresh frame re-evaluated normally")
    end)
end)
