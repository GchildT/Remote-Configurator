local mspMsgs = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/mspMsgs.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/mspMsgs.lua")
local mspBuffer = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/transport/mspBuffer.lua")

-- Explicit RGB colors rather than named constants -- see main.lua's note.
local COLOR_WHITE = lcd.RGB(255, 255, 255)
local COLOR_BLUE = lcd.RGB(40, 110, 220)
local COLOR_GREY = lcd.RGB(130, 130, 130)
local COLOR_YELLOW = lcd.RGB(255, 210, 0)

-- Confirmed against EdgeTX firmware source (radio/src/keys.h).
local EVT_ROTARY_LEFT = 0x1003
local EVT_ROTARY_RIGHT = 0x1004

local M = {}

-- Labels AND order match Betaflight Configurator's own "PID Tuning Sliders"
-- screen exactly (each Configurator slider has a main label plus a subtitle
-- naming the underlying gain(s), e.g. "Damping: D Gains" -> "Damping"):
--   Damping (D Gains), Tracking (P & I Gains), Stick Response (FF Gains),
--   -- separator --
--   Dynamic Damping (D Max), Drift - Wobble (I Gains),
--   Pitch Damping (Pitch:Roll D), Pitch Tracking (Pitch:Roll P, I & FF),
--   Master Multiplier
local SLIDERS = {
    { key = "dGain", label = "Damping" },
    { key = "piGain", label = "Tracking" },
    { key = "feedforwardGain", label = "Stick Rsp" },
    { key = "dminRatio", label = "Dyn Damp" },
    { key = "iGain", label = "Drift-Wob" },
    { key = "rollPitchRatio", label = "Pitch Damp" },
    { key = "pitchPiGain", label = "Pitch Trk" },
    { key = "masterMultiplier", label = "Master" },
}
local SLIDER_MIN, SLIDER_MAX = 0, 250

-- Split layout: left half is the sliders (adjustable), right half is a live
-- preview of the actual per-axis P/I/D/D-Min/FF values Betaflight's firmware
-- would compute from the current slider percentages (via
-- MSP_CALCULATE_SIMPLIFIED_PID -- confirmed against Betaflight 4.5.5
-- src/main/msp/msp.c: this computes and returns the result WITHOUT saving
-- anything, exactly the live-preview semantics needed here).
--
-- Layout: content lives strictly between the chrome above (tab bar + profile
-- row, end at y=64) and the footer below (starts at y=232 on a 272px-tall
-- screen). ROW_TOP leaves a blank gap below the profile row (which ends at
-- y=64) for visual breathing room. 8 slider rows * 18px = 144px, so rows
-- span y=86..230.
local ROW_HEIGHT = 18
local ROW_TOP = 86
local SLIDER_H = 16
local LABEL_X = 2
local SLIDER_X, SLIDER_W = 74, 90
local VALUE_X = 168

local PREVIEW_X = 208
local PREVIEW_AXIS_X = PREVIEW_X
local PREVIEW_COL_X = { PREVIEW_X + 22, PREVIEW_X + 70, PREVIEW_X + 118, PREVIEW_X + 166, PREVIEW_X + 214 }
local PREVIEW_COL_HEADERS = { "P", "I", "D", "Dm", "FF" }
local PREVIEW_HEADER_Y = ROW_TOP
local PREVIEW_ROW_Y = { ROW_TOP + 22, ROW_TOP + 44, ROW_TOP + 66 }
local PREVIEW_AXIS_LABELS = { "R", "P", "Y" }
local PREVIEW_AXIS_KEYS = { "roll", "pitch", "yaw" }

local phase = "idle" -- idle | loading | ready
local focusedIndex = nil -- index into SLIDERS of the currently jog-dial-editable slider, or nil

local previewValues = nil -- decoded MSP_CALCULATE_SIMPLIFIED_PID result, or nil before the first fetch
local previewPhase = "idle" -- idle | pending
local previewDirty = true -- true when the sliders have changed since the last preview fetch

local function decodeIntoState(state, rawBuffer)
    local values = { rawBuffer = rawBuffer }
    for _, s in ipairs(SLIDERS) do
        values[s.key] = mspBuffer.readField(rawBuffer, mspMsgs.SIMPLIFIED_TUNING_FIELDS[s.key])
    end
    state:load("pids", values)
end

function M.create()
    phase = "idle"
    focusedIndex = nil
    previewValues = nil
    previewPhase = "idle"
    previewDirty = true
end

function M.update(state, armed)
    if phase == "idle" and state:get("pids") == nil then
        phase = "loading"
    end
end

local function beginLoad(session)
    session:request(mspMsgs.CMD.SIMPLIFIED_TUNING, "")
end

local function beginSave(session, state)
    local values = state:get("pids")
    local buf = values.rawBuffer
    for _, s in ipairs(SLIDERS) do
        buf = mspBuffer.writeField(buf, mspMsgs.SIMPLIFIED_TUNING_FIELDS[s.key], values[s.key])
    end
    session:request(mspMsgs.CMD.SET_SIMPLIFIED_TUNING, buf)
end
M.beginSave = beginSave

-- Fetches the live PID preview. Shares the session with the page's own load
-- flow (mutually exclusive via `phase`) and with main.lua's save/profile
-- flows (those only run activePage.event() when neither is active, and both
-- check session:isPending() before starting their own requests -- see
-- transport/msp.lua's Session:request() reentrancy guard).
local function pumpPreview(session, state, nowMs)
    if previewPhase == "pending" then
        local status = session:poll(nowMs)
        if status == "done" then
            local cmd, payload = session:result()
            if cmd == mspMsgs.CMD.CALCULATE_SIMPLIFIED_PID then
                previewValues = mspMsgs.decodeSimplifiedPidPreview(payload)
            else
                -- Response belonged to a different in-flight request on this
                -- shared session (see module comment above). Our request was
                -- never actually answered -- retry it, or the preview would
                -- be stuck showing stale/empty values forever.
                previewDirty = true
            end
            previewPhase = "idle"
        elseif status == "timeout" or status == "error" then
            session:reset()
            previewPhase = "idle"
            -- Must retry: without this, a single dropped/late response
            -- permanently blanks the preview, since nothing else would ever
            -- mark it dirty again.
            previewDirty = true
        end
    elseif previewDirty and not session:isPending() then
        local values = state:get("pids")
        -- Only the first 17 bytes (mode + 8 gains + 8 reserved) matter to
        -- MSP_CALCULATE_SIMPLIFIED_PID's request format -- confirmed against
        -- Betaflight 4.5.5 src/main/msp/msp.c: readSimplifiedPids().
        local buf = string.sub(values.rawBuffer, 1, 17)
        for _, s in ipairs(SLIDERS) do
            buf = mspBuffer.writeField(buf, mspMsgs.SIMPLIFIED_TUNING_FIELDS[s.key], values[s.key])
        end
        session:request(mspMsgs.CMD.CALCULATE_SIMPLIFIED_PID, buf)
        previewPhase = "pending"
        previewDirty = false
    end
end

function M.event(event, touchState, state, session, nowMs, armed)
    if phase == "loading" then
        local status = session:poll(nowMs)
        if status == "done" then
            local cmd, payload = session:result()
            -- The msp session is shared with main.lua's connection check and
            -- save/profile flows. Only decode a reply that is actually the
            -- answer to OUR request -- otherwise we'd decode e.g. a 4-byte
            -- "BTFL" FC_VARIANT string as a 53-byte tuning buffer.
            if cmd == mspMsgs.CMD.SIMPLIFIED_TUNING then
                decodeIntoState(state, payload)
                phase = "ready"
                previewDirty = true
            else
                phase = "idle" -- not ours; retry cleanly on the next update()
            end
        elseif status == "idle" then
            beginLoad(session)
        elseif status == "timeout" or status == "error" then
            session:reset() -- release the terminal state so the retry can request again
            phase = "idle" -- caller will retry on next update()
        end
    end

    if phase ~= "ready" then
        lcd.drawText(10, ROW_TOP, "Loading PID sliders...", COLOR_WHITE)
        return
    end

    -- Jog-dial adjusts whichever slider is currently focused (tapped). Tapping
    -- a slider toggles its focus; tapping a different one moves focus there.
    if not armed and focusedIndex ~= nil and (event == EVT_ROTARY_LEFT or event == EVT_ROTARY_RIGHT) then
        local delta = (event == EVT_ROTARY_RIGHT) and 1 or -1
        local s = SLIDERS[focusedIndex]
        local values = state:get("pids")
        local newValue = values[s.key] + delta
        newValue = math.max(SLIDER_MIN, math.min(SLIDER_MAX, newValue))
        state:setField("pids", s.key, newValue)
        previewDirty = true
    end

    if not armed then
        pumpPreview(session, state, nowMs)
    end

    local values = state:get("pids")
    for i, s in ipairs(SLIDERS) do
        local y = ROW_TOP + (i - 1) * ROW_HEIGHT
        local isFocused = (focusedIndex == i)
        lcd.drawText(LABEL_X, y, s.label, isFocused and COLOR_YELLOW or COLOR_WHITE)
        local value = values[s.key]
        local pct = (value - SLIDER_MIN) / (SLIDER_MAX - SLIDER_MIN)
        lcd.drawRectangle(SLIDER_X, y, SLIDER_W, SLIDER_H, isFocused and COLOR_YELLOW or COLOR_WHITE)
        lcd.drawFilledRectangle(SLIDER_X, y, math.floor(SLIDER_W * pct), SLIDER_H, armed and COLOR_GREY or COLOR_BLUE)
        lcd.drawText(VALUE_X, y, tostring(value), isFocused and COLOR_YELLOW or COLOR_WHITE)

        if not armed and touchState then
            local tx, ty = touchState.x, touchState.y
            -- Whole row is tappable -- label, slider, and value text alike --
            -- not just the slider rectangle itself. Right edge stops short of
            -- the live-preview columns so taps there don't steal focus.
            if tx >= LABEL_X and tx < PREVIEW_X - 4 and ty >= y and ty < y + ROW_HEIGHT then
                focusedIndex = isFocused and nil or i
            end
        end
    end

    for c, header in ipairs(PREVIEW_COL_HEADERS) do
        lcd.drawText(PREVIEW_COL_X[c], PREVIEW_HEADER_Y, header, COLOR_GREY)
    end
    for r, axisLabel in ipairs(PREVIEW_AXIS_LABELS) do
        local y = PREVIEW_ROW_Y[r]
        lcd.drawText(PREVIEW_AXIS_X, y, axisLabel, COLOR_WHITE)
        if previewValues then
            local axis = previewValues[PREVIEW_AXIS_KEYS[r]]
            lcd.drawText(PREVIEW_COL_X[1], y, tostring(axis.p), COLOR_WHITE)
            lcd.drawText(PREVIEW_COL_X[2], y, tostring(axis.i), COLOR_WHITE)
            lcd.drawText(PREVIEW_COL_X[3], y, tostring(axis.d), COLOR_WHITE)
            lcd.drawText(PREVIEW_COL_X[4], y, tostring(axis.dMin), COLOR_WHITE)
            lcd.drawText(PREVIEW_COL_X[5], y, tostring(axis.ff), COLOR_WHITE)
        else
            lcd.drawText(PREVIEW_COL_X[1], y, "...", COLOR_GREY)
        end
    end
end

return M
