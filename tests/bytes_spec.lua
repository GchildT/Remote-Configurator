local testkit = require("tests.testkit")
local bytes = dofile("src/SCRIPTS/TOOLS/BFDash/bytes.lua")

testkit.describe("bytes", function()
    testkit.it("reads a U8 at a 1-based offset", function()
        testkit.assertEquals(bytes.readU8("\1\2\3", 2), 2, "readU8")
    end)

    testkit.it("writes a U8 without disturbing neighboring bytes", function()
        local buf = "\1\2\3"
        local result = bytes.writeU8(buf, 2, 99)
        testkit.assertEquals(#result, 3, "length preserved")
        testkit.assertEquals(bytes.readU8(result, 1), 1, "byte 1 untouched")
        testkit.assertEquals(bytes.readU8(result, 2), 99, "byte 2 patched")
        testkit.assertEquals(bytes.readU8(result, 3), 3, "byte 3 untouched")
    end)

    testkit.it("reads a little-endian U16", function()
        -- 0x1234 little-endian = bytes {0x34, 0x12}
        local buf = string.char(0x34, 0x12)
        testkit.assertEquals(bytes.readU16LE(buf, 1), 0x1234, "readU16LE")
    end)

    testkit.it("writes a little-endian U16 without disturbing neighbors", function()
        local buf = "\255\0\0\255"
        local result = bytes.writeU16LE(buf, 2, 0x1234)
        testkit.assertEquals(#result, 4, "length preserved")
        testkit.assertEquals(bytes.readU8(result, 1), 255, "byte 1 untouched")
        testkit.assertEquals(bytes.readU16LE(result, 2), 0x1234, "bytes 2-3 patched")
        testkit.assertEquals(bytes.readU8(result, 4), 255, "byte 4 untouched")
    end)

    testkit.it("wraps values above 255 for writeU8", function()
        local result = bytes.writeU8("\0", 1, 256)
        testkit.assertEquals(bytes.readU8(result, 1), 0, "wraps to 0")
    end)
end)
