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

    testkit.it("pushes the chunk as a 1-indexed table of byte values, not a string", function()
        -- Confirmed against EdgeTX firmware source: crossfireTelemetryPush's
        -- second argument must be a Lua table (luaL_checktype LUA_TTABLE),
        -- not a packed string.
        local msp = freshMsp()
        local session = msp.new(1000)
        session:request(1, "")
        session:poll(0)
        local data = pushLog[1].data
        testkit.assertEquals(type(data), "table", "data is a table, not a string")
        -- API_VERSION request chunk: status(0x50), flags(0), cmdLo(1), cmdHi(0),
        -- sizeLo(0), sizeHi(0) -- 6 header bytes, no payload for an empty request.
        testkit.assertEquals(#data, 6, "6-byte header, empty payload")
        testkit.assertEquals(data[1], 0x50, "byte 1: status")
        testkit.assertEquals(data[3], 1, "byte 3: cmd lo")
    end)

    testkit.it("round-trips a byte string through tableToString correctly", function()
        local msp = freshMsp()
        local t = { 0x41, 0x42, 0x43, 0x00, 0xFF }
        testkit.assertEquals(msp.tableToString(t), "ABC" .. string.char(0) .. string.char(0xFF), "table converted to string")
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

    testkit.it("isPending reflects whether a request is in flight", function()
        local msp = freshMsp()
        local session = msp.new(1000)
        testkit.assertEquals(session:isPending(), false, "idle session is not pending")
        session:request(1, "")
        testkit.assertEquals(session:isPending(), true, "pending after request()")
        session:poll(0)
        local reply = string.char(0x50, 0, 1, 0, 0, 0)
        session:feed(reply)
        testkit.assertEquals(session:isPending(), false, "not pending once response is fed")
    end)

    testkit.it("returns to idle after result() consumes a completed response", function()
        local msp = freshMsp()
        local session = msp.new(1000)
        session:request(1, "")
        session:poll(0)
        session:feed(string.char(0x50, 0, 1, 0, 3, 0) .. "ABC")
        testkit.assertEquals(session:poll(10), "done", "completed")
        local cmd, payload = session:result()
        testkit.assertEquals(cmd, 1, "result still returns the cmd")
        testkit.assertEquals(payload, "ABC", "result still returns the payload")
        testkit.assertEquals(session:poll(20), "idle", "session is idle again, not a stale 'done'")
    end)

    testkit.it("a second caller polling a consumed session sees idle and can issue its own request", function()
        local msp = freshMsp()
        local session = msp.new(1000)
        -- caller A: MSP_FC_VARIANT
        session:request(2, "")
        session:poll(0)
        session:feed(string.char(0x50, 0, 2, 0, 4, 0) .. "BTFL")
        session:poll(10)
        session:result()
        -- caller B (a page) polls the shared session on its next tick
        testkit.assertEquals(session:poll(20), "idle", "page sees an idle session")
        session:request(140, "") -- MSP_SIMPLIFIED_TUNING
        testkit.assertEquals(session:poll(30), "pending", "page's own request went out")
        testkit.assertEquals(#pushLog, 2, "a second MSP_REQ chunk was pushed")
    end)

    testkit.it("reset() clears a terminal timeout state so the session is reusable", function()
        local msp = freshMsp()
        local session = msp.new(100)
        session:request(1, "")
        session:poll(0)
        testkit.assertEquals(session:poll(150), "timeout", "timed out")
        testkit.assertEquals(session:poll(160), "timeout", "still stuck without a reset")
        session:reset()
        testkit.assertEquals(session:poll(170), "idle", "idle after reset")
    end)

    testkit.it("reset() clears a terminal error state so the session is reusable", function()
        local msp = freshMsp()
        local session = msp.new(1000)
        session:request(1, "")
        session:poll(0)
        session:feed(string.char(0x50, 0, 1, 0, 10, 0) .. "ABCD")
        pcall(function() session:feed(string.char(0x02) .. "EFGHIJ") end)
        testkit.assertEquals(session:poll(10), "error", "error state")
        session:reset()
        testkit.assertEquals(session:poll(20), "idle", "idle after reset")
    end)

    testkit.it("result() after a consumed response no longer returns stale data", function()
        local msp = freshMsp()
        local session = msp.new(1000)
        session:request(1, "")
        session:poll(0)
        session:feed(string.char(0x50, 0, 1, 0, 3, 0) .. "ABC")
        session:poll(10)
        session:result()
        local cmd, payload = session:result()
        testkit.assertEquals(cmd, nil, "stale cmd dropped")
        testkit.assertEquals(payload, nil, "stale payload dropped")
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
