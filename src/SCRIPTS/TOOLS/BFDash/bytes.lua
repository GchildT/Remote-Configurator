local M = {}

function M.readU8(buf, offset)
    return string.byte(buf, offset)
end

function M.writeU8(buf, offset, value)
    value = value % 256
    return buf:sub(1, offset - 1) .. string.char(value) .. buf:sub(offset + 1)
end

function M.readU16LE(buf, offset)
    local lo = string.byte(buf, offset)
    local hi = string.byte(buf, offset + 1)
    return lo + hi * 256
end

function M.writeU16LE(buf, offset, value)
    value = value % 65536
    local lo = value % 256
    local hi = (value - lo) / 256
    return buf:sub(1, offset - 1) .. string.char(lo, hi) .. buf:sub(offset + 2)
end

return M
