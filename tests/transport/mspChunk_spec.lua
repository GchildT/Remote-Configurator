local testkit = require("tests.testkit")
local mspChunk = dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspChunk.lua")

testkit.describe("mspChunk.buildRequestChunks", function()
    testkit.it("builds a single chunk for a short empty-payload request", function()
        local chunks = mspChunk.buildRequestChunks(1, "") -- MSP_API_VERSION, no payload
        testkit.assertEquals(#chunks, 1, "one chunk")
        local c = chunks[1]
        -- status byte: start=1(0x10) | seq=0 | version=2<<5(0x40) = 0x50
        testkit.assertEquals(string.byte(c, 1), 0x50, "status byte")
        testkit.assertEquals(string.byte(c, 2), 0, "flags byte")
        testkit.assertEquals(string.byte(c, 3), 1, "cmd lo")
        testkit.assertEquals(string.byte(c, 4), 0, "cmd hi")
        testkit.assertEquals(string.byte(c, 5), 0, "size lo")
        testkit.assertEquals(string.byte(c, 6), 0, "size hi")
        testkit.assertEquals(#c, 6, "6 byte header, no payload")
    end)

    testkit.it("splits a payload across multiple 8-byte chunks", function()
        -- header is 6 bytes, leaving 2 payload bytes in chunk 1 (8-byte cap)
        local payload = string.rep("A", 10)
        local chunks = mspChunk.buildRequestChunks(141, payload) -- MSP_SET_SIMPLIFIED_TUNING
        testkit.assertTrue(#chunks >= 2, "multiple chunks")
        for _, c in ipairs(chunks) do
            testkit.assertTrue(#c <= 8, "each chunk <= 8 bytes")
        end
        -- first chunk: 6-byte header + up to 2 payload bytes
        testkit.assertEquals(#chunks[1], 8, "first chunk fills to 8 bytes")
        -- sequence numbers increment 0,1,2,... in the low nibble, start bit only on chunk 1
        testkit.assertEquals(string.byte(chunks[1], 1) & 0x10, 0x10, "chunk1 start bit set")
        testkit.assertEquals(string.byte(chunks[2], 1) & 0x10, 0, "chunk2 start bit clear")
        testkit.assertEquals(string.byte(chunks[2], 1) & 0x0f, 1, "chunk2 seq = 1")
    end)

    testkit.it("encodes cmd and size as little-endian u16", function()
        local chunks = mspChunk.buildRequestChunks(300, string.rep("X", 4))
        local c = chunks[1]
        testkit.assertEquals(string.byte(c, 3), 300 % 256, "cmd lo")
        testkit.assertEquals(string.byte(c, 4), 300 // 256, "cmd hi")
        testkit.assertEquals(string.byte(c, 5), 4, "size lo")
        testkit.assertEquals(string.byte(c, 6), 0, "size hi")
    end)
end)

testkit.describe("mspChunk assembler", function()
    testkit.it("reassembles a single-chunk response", function()
        local asm = mspChunk.newAssembler()
        -- status(start,seq0,v2,no error)=0x50, flags=0, cmdLo=1,cmdHi=0, sizeLo=3,sizeHi=0, payload "ABC"
        local chunk = string.char(0x50, 0, 1, 0, 3, 0) .. "ABC"
        local complete = asm:feed(chunk)
        testkit.assertTrue(complete, "complete after one chunk")
        local cmd, payload, isError = asm:result()
        testkit.assertEquals(cmd, 1, "cmd")
        testkit.assertEquals(payload, "ABC", "payload")
        testkit.assertEquals(isError, false, "no error")
    end)

    testkit.it("reassembles a multi-chunk response in order", function()
        local asm = mspChunk.newAssembler()
        -- declare 10-byte payload, first chunk carries 4 bytes ("ABCD"), second carries rest ("EFGHIJ")
        local chunk1 = string.char(0x50, 0, 5, 0, 10, 0) .. "ABCD"
        local chunk2 = string.char(0x01) .. "EFGHIJ" -- seq=1, start bit clear
        testkit.assertTrue(not asm:feed(chunk1), "not complete after chunk 1")
        testkit.assertTrue(asm:feed(chunk2), "complete after chunk 2")
        local cmd, payload, isError = asm:result()
        testkit.assertEquals(cmd, 5, "cmd")
        testkit.assertEquals(payload, "ABCDEFGHIJ", "reassembled payload")
        testkit.assertEquals(isError, false, "no error")
    end)

    testkit.it("reports the error flag from the status byte", function()
        local asm = mspChunk.newAssembler()
        -- status = start(0x10) | version(0x40) | error(0x80) = 0xD0
        local chunk = string.char(0xD0, 0, 1, 0, 0, 0)
        asm:feed(chunk)
        local _, _, isError = asm:result()
        testkit.assertTrue(isError, "error flag surfaced")
    end)

    testkit.it("rejects an out-of-sequence continuation chunk", function()
        local asm = mspChunk.newAssembler()
        local chunk1 = string.char(0x50, 0, 1, 0, 10, 0) .. "ABCD"
        asm:feed(chunk1)
        -- skip seq 1, send seq 2 instead -- simulates dropped chunk
        local badChunk = string.char(0x02) .. "EFGHIJ"
        local ok, err = pcall(function() asm:feed(badChunk) end)
        testkit.assertTrue(not ok, "out-of-sequence chunk raises an error")
    end)
end)
