-- DIAGNOSTIC WRAPPER: everything that can fail at load time (module includes,
-- constructing the app table) runs inside a pcall. If ANY of it throws, init()
-- and run() below fall back to drawing the actual error message on screen
-- instead of the radio silently doing nothing. Remove this wrapper once the
-- script is confirmed loading cleanly on real hardware.
local msp, mspMsgs, stateMod, safety
local pidsPage, ratesPage, filtersPage, vtxPage
local CRSF_FRAMETYPE_MSP_RESP, CRSF_FRAMETYPE_FLIGHT_MODE
local FLIGHT_MODE_STALE_MS, REQUEST_TIMEOUT_MS
local SUPPORTED_MAJOR, SUPPORTED_MINOR
local pages, pageNames, pageKeys, pageByKey, SET_CMD_BY_KEY
local app

local setupOk, setupErr = pcall(function()
    local loader = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/loader.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/loader.lua")
    local include = loader.include

    msp = include("transport/msp.lua")
    mspMsgs = include("mspMsgs.lua")
    stateMod = include("state.lua")
    safety = include("safety.lua")

    pidsPage = include("pages/pids.lua")
    ratesPage = include("pages/rates.lua")
    filtersPage = include("pages/filters.lua")
    vtxPage = include("pages/vtx.lua")

    CRSF_FRAMETYPE_MSP_RESP = 0x7B
    CRSF_FRAMETYPE_FLIGHT_MODE = 0x21
    FLIGHT_MODE_STALE_MS = 3000
    REQUEST_TIMEOUT_MS = 800

    -- Every byte offset in this project is pinned to Betaflight 4.5.x firmware
    -- source. Writing those offsets to a different minor version could land in
    -- the wrong fields, so the connection check gates on the FC version too.
    SUPPORTED_MAJOR, SUPPORTED_MINOR = 4, 5

    pages = { pidsPage, ratesPage, filtersPage, vtxPage }
    pageNames = { "PIDs", "Rates", "Filters", "VTX" }
    pageKeys = { "pids", "rates", "filters", "vtx" }
    pageByKey = { pids = pidsPage, rates = ratesPage, filters = filtersPage, vtx = vtxPage }

    -- The SET command each page's beginSave() issues. Used to validate that a
    -- response actually belongs to the request we just made before treating it
    -- as a successful write (see the msp session's shared-session hazard).
    SET_CMD_BY_KEY = {
        pids = mspMsgs.CMD.SET_SIMPLIFIED_TUNING,
        rates = mspMsgs.CMD.SET_RC_TUNING,
        filters = mspMsgs.CMD.SET_FILTER_CONFIG,
        vtx = mspMsgs.CMD.SET_VTX_CONFIG,
    }

    app = {
        activeTab = 1,
        -- connecting | connected | unsupported | unsupported_version | disconnected
        connection = "connecting",
        session = msp.new(REQUEST_TIMEOUT_MS),
        arm = safety.new(),
        state = stateMod.new(),
        lastFlightModeMs = 0,
        profileSlot = 1,
    }
end)

--------------------------------------------------------------------------------
-- Layout
--
-- 480x272 screen. Regions are laid out so that no two distinct interactive
-- elements share any pixel, and a tap is additionally consumed by the first
-- handler that claims it (chrome before page content) as a second line of
-- defence:
--
--   y   0.. 20  armed banner (non-interactive)
--   y  20.. 44  tab bar
--   y  44.. 64  profile-slot row
--   y  66..232  page content (pages own this band; see each page's constants)
--   y 232..272  footer (Save / Cancel / status)
--------------------------------------------------------------------------------
local TAB_Y, TAB_H = 20, 24
local PROFILE_Y = 44
local PROFILE_ROW_H = 20
local PROFILE_BOX_W = 30
local PROFILE_BOX_GAP = 6
local PROFILE_BOX_X0 = 60
local FOOTER_H = 40
local FOOTER_Y = LCD_H - FOOTER_H
local BTN_SAVE_X, BTN_SAVE_W = 0, 100
local BTN_CANCEL_X, BTN_CANCEL_W = 110, 100

-- Single shared CRSF pop loop: dispatches MSP_RESP frames to the active
-- session via session:feed(), and FLIGHT_MODE frames to the arm tracker.
-- msp.lua deliberately never calls crossfireTelemetryPop() itself (see
-- Task 3's note) so this is the only consumer of the telemetry queue.
local function pumpTelemetry(nowMs)
    while true do
        local frame = crossfireTelemetryPop()
        if frame == nil then
            break
        end
        if frame.command == CRSF_FRAMETYPE_MSP_RESP then
            app.session:feed(frame.data)
        elseif frame.command == CRSF_FRAMETYPE_FLIGHT_MODE then
            app.arm:feedFlightModeFrame(frame.data)
            app.lastFlightModeMs = nowMs
        end
    end
    if nowMs - app.lastFlightModeMs > FLIGHT_MODE_STALE_MS then
        app.arm:markStale()
    end
end

--------------------------------------------------------------------------------
-- Connection check: MSP_FC_VARIANT (is it Betaflight?) then MSP_FC_VERSION
-- (is it a version whose MSP field offsets match the ones we hard-code?).
--------------------------------------------------------------------------------
local connectFlow = "variant" -- variant | version | done
local fcVersionText = nil

local function checkConnection()
    connectFlow = "variant"
    app.session:request(mspMsgs.CMD.FC_VARIANT, "")
end

local function onConnectionResponse(cmd, payload)
    if connectFlow == "variant" then
        if cmd ~= mspMsgs.CMD.FC_VARIANT then
            -- Not our reply; re-ask rather than decoding someone else's payload.
            app.session:request(mspMsgs.CMD.FC_VARIANT, "")
        elseif mspMsgs.isBetaflight(mspMsgs.decodeFcVariant(payload)) then
            connectFlow = "version"
            app.session:request(mspMsgs.CMD.FC_VERSION, "")
        else
            app.connection = "unsupported"
        end
    elseif connectFlow == "version" then
        if cmd ~= mspMsgs.CMD.FC_VERSION then
            app.session:request(mspMsgs.CMD.FC_VERSION, "")
        else
            local major, minor, patch = mspMsgs.decodeFcVersion(payload)
            fcVersionText = tostring(major or "?") .. "." .. tostring(minor or "?") .. "." .. tostring(patch or "?")
            if major == SUPPORTED_MAJOR and minor == SUPPORTED_MINOR then
                connectFlow = "done"
                app.connection = "connected"
            else
                app.connection = "unsupported_version"
            end
        end
    end
end

local function pumpConnection(nowMs)
    local status = app.session:poll(nowMs)
    if status == "done" then
        local cmd, payload = app.session:result()
        onConnectionResponse(cmd, payload)
    elseif status == "timeout" or status == "error" then
        app.session:reset()
        app.connection = "disconnected"
    end
end

function init()
    if not setupOk then
        return
    end
    checkConnection()
end

--------------------------------------------------------------------------------
-- Tap consumption: exactly one handler may act on a given tick's tap. Priority
-- is chrome first (tab bar -> profile row -> footer), then the active page's
-- own content, which receives a nil touchState once the tap has been claimed.
--------------------------------------------------------------------------------
local tapConsumed = false

local function tapInRect(touchState, x, y, w, h)
    if tapConsumed or not touchState or not touchState.tap then
        return false
    end
    return touchState.x >= x and touchState.x < x + w
        and touchState.y >= y and touchState.y < y + h
end

--------------------------------------------------------------------------------
-- Save flow
--
-- Sequential queue over the DIRTY page keys (the msp session handles one
-- request at a time): send each dirty key's SET message and wait for its
-- reply, then issue a single EEPROM_WRITE, and only mark keys clean once that
-- EEPROM_WRITE is itself confirmed. Anything less would either lose edits made
-- on a non-active tab or report "saved" for settings that only reached FC RAM.
--------------------------------------------------------------------------------
-- Declared here (ahead of the profile section below) because handleFooterTouch
-- needs to see it: a Lua closure only captures locals already in scope.
local profileFlow = "idle" -- idle | selectPid | selectRate
local pendingSlot = nil

local saveFlow = "idle" -- idle | sending | waitSet | eeprom
local saveQueue = nil
local saveIndex = 0
local saveWritten = nil -- keys whose SET was acknowledged, pending EEPROM confirm
local saveError = nil

local function beginSaveFlow()
    saveQueue = {}
    for _, key in ipairs(pageKeys) do
        -- A key can only be dirty if it was loaded, but guard anyway: never
        -- call beginSave() on a page whose state was never fetched.
        if app.state:isDirty(key) and app.state:get(key) ~= nil then
            saveQueue[#saveQueue + 1] = key
        end
    end
    if #saveQueue == 0 then
        saveQueue = nil
        return
    end
    saveIndex = 0
    saveWritten = {}
    saveError = nil
    saveFlow = "sending"
end

local function failSave(message)
    saveError = message
    saveFlow = "idle"
    saveQueue = nil
    saveWritten = nil
    saveIndex = 0
end

local function pumpSaveFlow(nowMs)
    if saveFlow == "idle" then
        return false
    end

    if app.arm:isArmed() then
        -- The pilot armed mid-save: cancel whatever MSP request is in flight
        -- and abort the queue the same way a timeout/error would, without
        -- marking any key clean.
        app.session:reset()
        failSave("Save aborted: armed.")
        return true
    end

    if saveFlow == "sending" then
        saveIndex = saveIndex + 1
        local key = saveQueue[saveIndex]
        if key == nil then
            -- Every dirty key's SET has been acknowledged; commit to EEPROM.
            app.session:request(mspMsgs.CMD.EEPROM_WRITE, "")
            saveFlow = "eeprom"
        else
            pageByKey[key].beginSave(app.session, app.state)
            saveFlow = "waitSet"
        end
        return true

    elseif saveFlow == "waitSet" then
        local status = app.session:poll(nowMs)
        local key = saveQueue[saveIndex]
        if status == "done" then
            local cmd = app.session:result()
            if cmd == SET_CMD_BY_KEY[key] then
                saveWritten[#saveWritten + 1] = key
                saveFlow = "sending"
            else
                -- Unexpected reply: we cannot claim this write landed.
                failSave("Save failed: unexpected reply writing " .. key .. ".")
            end
        elseif status == "timeout" or status == "error" then
            -- Stop the queue: do not skip ahead, and mark nothing clean.
            app.session:reset()
            failSave("Save failed: no reply writing " .. key .. ".")
        end
        return true

    elseif saveFlow == "eeprom" then
        local status = app.session:poll(nowMs)
        if status == "done" then
            local cmd = app.session:result()
            if cmd == mspMsgs.CMD.EEPROM_WRITE then
                -- Confirmed persisted: only now is it honest to clear the
                -- "unsaved changes" indicator, and only for keys we actually
                -- got a SET acknowledgement for.
                for _, key in ipairs(saveWritten) do
                    app.state:markClean(key)
                end
                saveError = nil
                saveFlow = "idle"
                saveQueue = nil
                saveWritten = nil
                saveIndex = 0
            else
                failSave("Save failed: unexpected reply to EEPROM write.")
            end
        elseif status == "timeout" or status == "error" then
            app.session:reset()
            failSave("Save failed: settings not written to EEPROM.")
        end
        return true
    end

    return false
end

local function drawFooter(armed)
    if armed then
        return
    end
    lcd.drawFilledRectangle(BTN_SAVE_X, FOOTER_Y, BTN_SAVE_W, FOOTER_H, GREEN)
    lcd.drawText(BTN_SAVE_X + 10, FOOTER_Y + 12, "Save")
    lcd.drawFilledRectangle(BTN_CANCEL_X, FOOTER_Y, BTN_CANCEL_W, FOOTER_H, GREY)
    lcd.drawText(BTN_CANCEL_X + 10, FOOTER_Y + 12, "Cancel")

    if saveError then
        lcd.drawText(220, FOOTER_Y + 12, saveError, RED)
    elseif saveFlow ~= "idle" then
        lcd.drawText(220, FOOTER_Y + 12, "Saving...")
    elseif app.state:isAnyDirty() then
        lcd.drawText(220, FOOTER_Y + 12, "* unsaved changes")
    end
end

local function handleFooterTouch(touchState, armed)
    if armed then
        return
    end
    -- Claim the whole footer strip: nothing else is allowed to act on a tap
    -- that lands here, even if this particular tap hits no button.
    if not tapInRect(touchState, 0, FOOTER_Y, LCD_W, FOOTER_H) then
        return
    end
    tapConsumed = true
    local tx = touchState.x
    if tx >= BTN_SAVE_X and tx < BTN_SAVE_X + BTN_SAVE_W then
        -- Don't start a save on top of an in-flight page load: the msp session
        -- handles one request at a time and request() throws while pending.
        if saveFlow == "idle" and profileFlow == "idle"
            and not app.session:isPending() and app.state:isAnyDirty() then
            beginSaveFlow()
        end
    elseif tx >= BTN_CANCEL_X and tx < BTN_CANCEL_X + BTN_CANCEL_W then
        if saveFlow == "idle" then
            for _, key in ipairs(pageKeys) do
                app.state:reload(key)
            end
            saveError = nil
        end
    end
end

-- Profile-slot selector: a row of three tappable "1"/"2"/"3" labels below the
-- tab bar. Switching slots issues two separate MSP_SELECT_SETTING requests
-- (one for the PID profile, one for the rate profile) sequenced through the
-- single-request-at-a-time msp session, then invalidates all four cached
-- state keys so each page's update() re-fetches fresh data for the new slot.
-- (profileFlow / pendingSlot are declared above, next to the save-flow state.)

local function clearCachedState()
    for _, key in ipairs(pageKeys) do
        app.state:clear(key)
    end
    -- state:clear() alone does not make pages reload: each page module only
    -- re-enters its "loading" phase from a module-local `phase` variable that
    -- becomes "idle" via that page's own create(). Reset all four explicitly
    -- so the next update() actually re-fetches fresh data for the new slot.
    pidsPage.create()
    ratesPage.create()
    filtersPage.create()
    vtxPage.create()
end

local function drawProfileRow(armed)
    if armed then
        return
    end
    lcd.drawText(4, PROFILE_Y, "Profile:")
    for i = 1, 3 do
        local x = PROFILE_BOX_X0 + (i - 1) * (PROFILE_BOX_W + PROFILE_BOX_GAP)
        local isActive = (i == app.profileSlot)
        lcd.drawFilledRectangle(x, PROFILE_Y, PROFILE_BOX_W, PROFILE_ROW_H, isActive and BLUE or GREY)
        lcd.drawText(x + 10, PROFILE_Y, tostring(i))
    end
end

local function handleProfileTouch(touchState, armed)
    if armed then
        return
    end
    -- Claim the whole profile strip before applying the guards below, so a tap
    -- rejected by a guard is not then re-interpreted by the page underneath.
    if not tapInRect(touchState, 0, PROFILE_Y, LCD_W, PROFILE_ROW_H) then
        return
    end
    tapConsumed = true
    if saveFlow ~= "idle" or profileFlow ~= "idle" then
        return
    end
    if app.state:isAnyDirty() then
        return -- avoid silently discarding unsaved edits when switching slots
    end
    if app.session:isPending() then
        return -- avoid reentrant session:request() while a page's own load is in flight
    end
    local tx = touchState.x
    for i = 1, 3 do
        local x = PROFILE_BOX_X0 + (i - 1) * (PROFILE_BOX_W + PROFILE_BOX_GAP)
        if tx >= x and tx < x + PROFILE_BOX_W and i ~= app.profileSlot then
            pendingSlot = i
            app.session:request(mspMsgs.CMD.SELECT_SETTING, mspMsgs.encodeSelectSetting("pid", i - 1))
            profileFlow = "selectPid"
            return
        end
    end
end

local function pumpProfileFlow(nowMs)
    if profileFlow == "selectPid" then
        local status = app.session:poll(nowMs)
        if status == "done" then
            local cmd = app.session:result()
            if cmd == mspMsgs.CMD.SELECT_SETTING then
                app.session:request(mspMsgs.CMD.SELECT_SETTING, mspMsgs.encodeSelectSetting("rate", pendingSlot - 1))
                profileFlow = "selectRate"
            else
                profileFlow = "idle"
                pendingSlot = nil
            end
        elseif status == "timeout" or status == "error" then
            app.session:reset()
            profileFlow = "idle"
            pendingSlot = nil
        end
        return true
    elseif profileFlow == "selectRate" then
        local status = app.session:poll(nowMs)
        if status == "done" then
            local cmd = app.session:result()
            if cmd == mspMsgs.CMD.SELECT_SETTING then
                app.profileSlot = pendingSlot
                clearCachedState()
            end
            profileFlow = "idle"
            pendingSlot = nil
        elseif status == "timeout" or status == "error" then
            app.session:reset()
            profileFlow = "idle"
            pendingSlot = nil
        end
        return true
    end
    return false
end

local function drawTabBar(armed)
    for i, name in ipairs(pageNames) do
        local w = math.floor(LCD_W / #pageNames)
        local x = (i - 1) * w
        if i == app.activeTab then
            lcd.drawFilledRectangle(x, TAB_Y, w, TAB_H, BLUE)
        end
        lcd.drawText(x + 8, TAB_Y + 4, name)
    end
end

local function handleTabTouch(touchState, armed)
    if armed then
        return
    end
    local w = math.floor(LCD_W / #pageNames)
    for i = 1, #pageNames do
        local x = (i - 1) * w
        if tapInRect(touchState, x, TAB_Y, w, TAB_H) then
            tapConsumed = true
            app.activeTab = i
            return
        end
    end
end

local function connectionMessage()
    if app.connection == "connecting" then
        return "Connecting to flight controller..."
    elseif app.connection == "unsupported" then
        return "Connected, but flight controller is not Betaflight."
    elseif app.connection == "unsupported_version" then
        return "Unsupported firmware " .. tostring(fcVersionText)
            .. " -- this tool requires Betaflight "
            .. SUPPORTED_MAJOR .. "." .. SUPPORTED_MINOR .. ".x"
    end
    return "No response from flight controller. Check link."
end

function run(event, touchState)
    if not setupOk then
        lcd.clear()
        lcd.drawText(5, 5, "BFDash failed to load:", MIDSIZE)
        lcd.drawText(5, 30, tostring(setupErr))
        return
    end

    local nowMs = getTime() * 10
    pumpTelemetry(nowMs)

    if app.connection == "connecting" then
        pumpConnection(nowMs)
    end

    lcd.clear()

    if app.connection ~= "connected" then
        lcd.drawText(10, 10, "Betaflight Dashboard", MIDSIZE)
        lcd.drawText(10, 40, connectionMessage())
        return
    end

    local armed = app.arm:isArmed()
    if armed then
        lcd.drawFilledRectangle(0, 0, LCD_W, 20, RED)
        lcd.drawText(10, 4, "ARMED -- read only", WHITE)
    end

    -- Touch dispatch, highest priority first. Each handler claims the tap if it
    -- lands in its region, so a single tap can never trigger two actions.
    tapConsumed = false
    handleTabTouch(touchState, armed)
    handleProfileTouch(touchState, armed)
    handleFooterTouch(touchState, armed)

    drawTabBar(armed)
    drawProfileRow(armed)

    if pumpSaveFlow(nowMs) then
        -- save in progress; skip page update/event this tick
    elseif pumpProfileFlow(nowMs) then
        -- profile-slot switch in progress; skip page update/event this tick
    else
        -- The page only ever sees a tap the chrome did not already claim.
        -- NB: not `tapConsumed and nil or touchState` -- that idiom yields
        -- touchState in BOTH branches, since the true branch evaluates to nil.
        local pageTouch = touchState
        if tapConsumed then
            pageTouch = nil
        end
        local activePage = pages[app.activeTab]
        activePage.update(app.state, armed)
        activePage.event(event, pageTouch, app.state, app.session, nowMs, armed)
    end

    drawFooter(armed)
end

-- EdgeTX's script loader requires the top-level chunk to return a table with
-- a `run` field (required) and optionally `init`/`background` -- defining
-- these as bare globals is NOT sufficient; the loader marks the script
-- SCRIPT_SYNTAX_ERROR ("The script did not return a table") and never calls
-- run() at all, which is why nothing appeared on screen. Confirmed against
-- EdgeTX firmware source (radio/src/lua/interface.cpp).
return { init = init, run = run }
