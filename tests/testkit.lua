local M = {}
local currentDescribe = nil
local results = {}

function M.describe(name, fn)
    currentDescribe = name
    fn()
    currentDescribe = nil
end

function M.it(name, fn)
    local fullName = (currentDescribe and (currentDescribe .. " > ") or "") .. name
    local ok, err = pcall(fn)
    table.insert(results, { name = fullName, ok = ok, err = err })
end

function M.assertEquals(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg or "assertEquals", tostring(expected), tostring(actual)), 2)
    end
end

function M.assertTrue(value, msg)
    if not value then
        error(msg or "assertTrue failed", 2)
    end
end

function M.run()
    local passCount, failCount = 0, 0
    for _, r in ipairs(results) do
        if r.ok then
            passCount = passCount + 1
            print("PASS " .. r.name)
        else
            failCount = failCount + 1
            print("FAIL " .. r.name .. " -- " .. tostring(r.err))
        end
    end
    print(string.format("\n%d passed, %d failed", passCount, failCount))
    return passCount, failCount
end

return M
