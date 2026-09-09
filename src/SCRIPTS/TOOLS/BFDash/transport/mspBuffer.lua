local bytes = dofile("src/SCRIPTS/TOOLS/BFDash/bytes.lua")

local M = {}

function M.readField(buf, field)
    if field.size == 1 then
        return bytes.readU8(buf, field.offset)
    elseif field.size == 2 then
        return bytes.readU16LE(buf, field.offset)
    else
        error("unsupported field size: " .. tostring(field.size))
    end
end

function M.writeField(buf, field, value)
    if field.size == 1 then
        return bytes.writeU8(buf, field.offset, value)
    elseif field.size == 2 then
        return bytes.writeU16LE(buf, field.offset, value)
    else
        error("unsupported field size: " .. tostring(field.size))
    end
end

return M
