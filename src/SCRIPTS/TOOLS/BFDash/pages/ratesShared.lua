-- Backing data/session logic shared by pages/rates.lua and
-- pages/ratesCurves.lua.
--
-- Both tabs read and write the SAME underlying MSP_RC_TUNING (111/204)
-- buffer -- Betaflight has no separate MSP command per section, so (exactly
-- like pages/filtersShared.lua for the two Filters tabs) sharing one state
-- key, one rawBuffer, and one load/save cycle here avoids one tab's save
-- silently clobbering the other's pending edits, and avoids a redundant
-- reload when switching between them.
local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")

local COLOR_WHITE = lcd.RGB(255, 255, 255)

local M = {}

M.PAGE_KEY = "rates"

-- Every raw MSP_RC_TUNING field that is ALWAYS present at this project's API
-- 1.44 floor -- see mspMsgs.lua's RC_TUNING_FIELDS comment for verified byte
-- offsets. `hoverPoint` is handled separately below: it's only present on
-- API 1.47+, so it can't be in this unconditionally-iterated set without
-- risking a read/write past the end of an older FC's shorter payload.
M.FIELD_KEYS = {
    "rcRateRoll", "rcExpoRoll", "superRateRoll", "superRatePitch", "superRateYaw",
    "thrMid8", "thrExpo8", "rcExpoYaw", "rcRateYaw", "rcRatePitch", "rcExpoPitch",
    "throttleLimitType", "throttleLimitPercent",
    "rateLimitRoll", "rateLimitPitch", "rateLimitYaw",
    "ratesType",
}

local phase = "idle" -- idle | loading | ready

function M.create()
    phase = "idle"
end

function M.update(state, armed)
    if phase == "idle" and state:get(M.PAGE_KEY) == nil then
        phase = "loading"
    end
end

-- True when the loaded rawBuffer is long enough to actually contain the
-- API-1.47+ hoverPoint byte. Callers must check this before reading/writing
-- values.hoverPoint -- on an older FC it simply doesn't exist in the buffer.
function M.hasHoverPoint(values)
    local f = mspMsgs.RC_TUNING_FIELDS.hoverPoint
    return #values.rawBuffer >= (f.offset + f.size - 1)
end

local function decodeIntoState(state, rawBuffer)
    local values = { rawBuffer = rawBuffer }
    for _, key in ipairs(M.FIELD_KEYS) do
        values[key] = mspBuffer.readField(rawBuffer, mspMsgs.RC_TUNING_FIELDS[key])
    end
    if M.hasHoverPoint(values) then
        values.hoverPoint = mspBuffer.readField(rawBuffer, mspMsgs.RC_TUNING_FIELDS.hoverPoint)
    end
    state:load(M.PAGE_KEY, values)
end

function M.beginSave(session, state)
    local values = state:get(M.PAGE_KEY)
    local buf = values.rawBuffer
    for _, key in ipairs(M.FIELD_KEYS) do
        buf = mspBuffer.writeField(buf, mspMsgs.RC_TUNING_FIELDS[key], values[key])
    end
    if M.hasHoverPoint(values) then
        buf = mspBuffer.writeField(buf, mspMsgs.RC_TUNING_FIELDS.hoverPoint, values.hoverPoint)
    end
    session:request(mspMsgs.CMD.SET_RC_TUNING, buf)
end

-- Pumps the single-request load (MSP_RC_TUNING). Callers (both tabs) must
-- call this every tick from their own M.event before rendering. Returns the
-- current staged values once ready, or nil (having drawn a loading message)
-- while still loading.
function M.ensureLoaded(session, nowMs, state, contentTopY, loadingText)
    if phase == "loading" then
        local status = session:poll(nowMs)
        if status == "done" then
            local cmd, payload = session:result()
            -- Shared session: only decode a reply to OUR request (see pids.lua).
            if cmd == mspMsgs.CMD.RC_TUNING then
                decodeIntoState(state, payload)
                phase = "ready"
            else
                phase = "idle" -- not ours; retry cleanly on the next update()
            end
        elseif status == "idle" then
            session:request(mspMsgs.CMD.RC_TUNING, "")
        elseif status == "timeout" or status == "error" then
            session:reset()
            phase = "idle"
        end
    end

    if phase ~= "ready" then
        lcd.drawText(10, contentTopY, loadingText, COLOR_WHITE)
        return nil
    end
    return state:get(M.PAGE_KEY)
end

return M
