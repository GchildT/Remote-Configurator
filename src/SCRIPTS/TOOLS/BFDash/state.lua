local M = {}
local State = {}
State.__index = State

function M.new()
    return setmetatable({ clean = {}, staged = {} }, State)
end

local function shallowCopy(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end

function State:load(key, values)
    self.clean[key] = shallowCopy(values)
    self.staged[key] = shallowCopy(values)
end

function State:get(key)
    return self.staged[key]
end

function State:setField(key, fieldName, value)
    self.staged[key][fieldName] = value
end

function State:isDirty(key)
    local clean, staged = self.clean[key], self.staged[key]
    if clean == nil or staged == nil then
        return false
    end
    for k, v in pairs(staged) do
        if clean[k] ~= v then
            return true
        end
    end
    return false
end

function State:isAnyDirty()
    for key, _ in pairs(self.staged) do
        if self:isDirty(key) then
            return true
        end
    end
    return false
end

function State:reload(key)
    self.staged[key] = shallowCopy(self.clean[key])
end

function State:markClean(key)
    self.clean[key] = shallowCopy(self.staged[key])
end

function State:clear(key)
    self.clean[key] = nil
    self.staged[key] = nil
end

return M
