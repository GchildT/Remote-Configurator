local BASE_PATH = "/SCRIPTS/TOOLS/BFDash/"

local function include(relPath)
    if loadScript then
        return assert(loadScript(BASE_PATH .. relPath))()
    else
        -- desktop/test fallback: relative to repo root
        return dofile("src/SCRIPTS/TOOLS/BFDash/" .. relPath)
    end
end

return { include = include }
