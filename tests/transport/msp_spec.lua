local testkit = require("tests.testkit")

-- Fake CRSF push log, reset before each test group. This module never calls
-- crossfireTelemetryPop() itself (see the module's Interfaces note), so no
-- pop mock is needed -- responses are delivered via session:feed().
local pushLog

_G.crossfireTelemetryPush = function(command, data)
    table.insert(pushLog, { command = command, data = data })
    return true
end

local function freshMsp()
    pushLog = {}
    package.loaded["src.SCRIPTS.TOOLS.BFDash.transport.msp"] = nil
    return dofile("src/SCRIPTS/TOOLS/BFDash/transport/msp.lua")
end

testkit.describe("msp session", function()
    testkit.it("sends the request chunk on the first poll", function()
        local msp = freshMsp()
        local session = msp.new(1000)
        session:request(1, "") -- MSP_API_VERSION
        local status = session:poll(0)
        testkit.assertEquals(status, "pending", "still pending, no response yet")
        testkit.assertEquals(#pushLog, 1, "one chunk pushed")
        testkit.assertEquals(pushLog[1].command, 0x7A, "MSP_REQ frame type")
    end)

    testkit.it("assembles a single-chunk response fed via session:feed and reports done", function()
        local msp = freshMsp()
        local session = msp.new(1000)
        session:request(1, "")
        session:poll(0)
        -- FC replies: status(start,v2,seq0)=0x50, flags=0, cmd=1,0, size=3,0, payload "ABC"
        local reply = string.char(0x50, 0, 1, 0, 3, 0) .. "ABC"
        session:feed(reply)
        local status = session:poll(10)
        testkit.assertEquals(status, "done", "response assembled")
        local cmd, payload, isError = session:result()
        testkit.assertEquals(cmd, 1, "cmd echoed back")
        testkit.assertEquals(payload, "ABC", "payload")
        testkit.assertEquals(isError, false, "no error")
    end)

    testkit.it("feed is a no-op when no request is pending", function()
        local msp = freshMsp()
        local session = msp.new(1000)
        local ok = pcall(function() session:feed(string.char(0x50, 0, 1, 0, 0, 0)) end)
        testkit.assertTrue(ok, "feed before any request does not error")
        testkit.assertEquals(session:poll(0), "idle", "still idle")
    end)

    testkit.it("times out if no response arrives in time", function()
        local msp = freshMsp()
        local session = msp.new(100)
        session:request(1, "")
        session:poll(0)
        local status = session:poll(150)
        testkit.assertEquals(status, "timeout", "exceeded timeout with no response")
    end)

    testkit.it("feeding a malformed/out-of-sequence chunk degrades to error state, not an uncaught error", function()
        local msp = freshMsp()
        local session = msp.new(1000)
        session:request(1, "")
        session:poll(0)
        -- start chunk declares a 10-byte payload, seq 0
        local startChunk = string.char(0x50, 0, 1, 0, 10, 0) .. "ABCD"
        local ok1 = pcall(function() session:feed(startChunk) end)
        testkit.assertTrue(ok1, "start chunk feeds without error")
        -- skip seq 1, send seq 2 instead -- simulates dropped/reordered chunk
        local badChunk = string.char(0x02) .. "EFGHIJ"
        local ok2 = pcall(function() session:feed(badChunk) end)
        testkit.assertTrue(ok2, "out-of-sequence chunk does not propagate an error out of feed()")
        testkit.assertEquals(session:poll(10), "error", "session degrades to error state")
    end)

    testkit.it("request() while a previous request is still pending raises an error", function()
        local msp = freshMsp()
        local session = msp.new(1000)
        session:request(1, "")
        session:poll(0)
        testkit.assertEquals(session:poll(0), "pending", "first request still pending")
        local ok = pcall(function() session:request(2, "") end)
        testkit.assertTrue(not ok, "request() while pending raises an error")
    end)

    testkit.it("sends a second request only after the first completes", function()
        local msp = freshMsp()
        local session = msp.new(1000)
        session:request(1, "")
        session:poll(0)
        local reply = string.char(0x50, 0, 1, 0, 0, 0)
        session:feed(reply)
        session:poll(10)
        session:request(2, "")
        session:poll(20)
        testkit.assertEquals(#pushLog, 2, "second request's chunk was pushed")
        testkit.assertEquals(pushLog[2].command, 0x7A, "second request also MSP_REQ")
    end)
end)
