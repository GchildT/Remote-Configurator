-- Explicit RGB colors rather than named constants (RED/WHITE/BLUE/GREY/GREEN):
-- this project could not confirm from source exactly how EdgeTX's named color
-- constants are exposed to scripts (which global table, if any), and an
-- earlier version of this script rendered a solid but completely blank
-- screen with no error -- consistent with drawText calls silently resolving
-- to an invisible default color. lcd.RGB(r,g,b) is confirmed to exist
-- (radio/src/lua/api_colorlcd.cpp: LROT_FUNCENTRY(RGB, luaRGB)) and removes
-- the ambiguity entirely.
local COLOR_BLACK = lcd.RGB(0, 0, 0)
local COLOR_WHITE = lcd.RGB(255, 255, 255)
local COLOR_RED = lcd.RGB(220, 30, 30)
local COLOR_GREEN = lcd.RGB(30, 170, 60)
local COLOR_BLUE = lcd.RGB(40, 110, 220)
local COLOR_GREY = lcd.RGB(130, 130, 130)
local COLOR_ORANGE = lcd.RGB(230, 140, 20)

-- DIAGNOSTIC WRAPPER: everything that can fail at load time (module includes,
-- constructing the app table) runs inside a pcall. If ANY of it throws, init()
-- and run() below fall back to drawing the actual error message on screen
-- instead of the radio silently doing nothing. Remove this wrapper once the
-- script is confirmed loading cleanly on real hardware.
local msp, mspMsgs, stateMod, safety
local pidsPage, ratesPage, globalFiltersPage, profileFiltersPage, vtxPage, throttlePage
local CRSF_FRAMETYPE_MSP_RESP
local REQUEST_TIMEOUT_MS
local MIN_API_MAJOR, MIN_API_MINOR
local pages, pageNames, pageKeys, pageByKey, SET_CMD_BY_KEY, PROFILE_TYPE_PAGE_KEYS, RATES_TAB_INDEX
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
    globalFiltersPage = include("pages/globalFilters.lua")
    profileFiltersPage = include("pages/profileFilters.lua")
    vtxPage = include("pages/vtx.lua")
    throttlePage = include("pages/throttle.lua")

    -- filtersShared.lua carries mutable state (load phase, in-flight
    -- multiplier-calc tracking) that MUST be the exact same instance for
    -- both filter tabs -- loadScript()/dofile() have no require()-style
    -- caching, so each tab loading it independently in its own file would
    -- silently create two separate, un-synchronized copies. Load it here
    -- exactly once (same pattern as mspMsgs/stateMod/safety/msp above) and
    -- inject that one instance into both tabs.
    local filtersShared = include("pages/filtersShared.lua")
    globalFiltersPage.init(filtersShared)
    profileFiltersPage.init(filtersShared)

    CRSF_FRAMETYPE_MSP_RESP = 0x7B
    -- Generous enough to cover a full multi-chunk SET request (the largest,
    -- MSP_SET_SIMPLIFIED_TUNING, needs ~7 chunks): crossfireTelemetryPush()
    -- only actually queues a chunk when EdgeTX's own outgoing telemetry
    -- buffer is free (see transport/msp.lua's Session:poll() note), so a
    -- multi-chunk write can take noticeably longer to actually get on the
    -- air than a single-chunk read, depending on the link's telemetry ratio.
    REQUEST_TIMEOUT_MS = 2000

    -- Minimum MSP API version this project's byte offsets are verified
    -- against (see the connection-check comment below for the full
    -- explanation of why this is an API-version gate, not a firmware-version
    -- gate). MSP_SIMPLIFIED_TUNING ("Added in MSP API 1.44") is the newest
    -- message used here, making 1.44 the true floor; confirmed unchanged
    -- through API 1.48 (Betaflight 2026.6.1).
    MIN_API_MAJOR, MIN_API_MINOR = 1, 44

    -- Global Filters and Profile Filters are two TABS but share ONE state
    -- key ("filters") and one underlying MSP_FILTER_CONFIG buffer -- see
    -- pages/filtersShared.lua's header comment for why: that buffer covers
    -- both tabs' fields together, and giving each tab its own independent
    -- copy would let one tab's save silently clobber the other's pending
    -- edits. pageKeys/pageByKey are intentionally NOT parallel to pages/
    -- pageNames here (5 state keys backing 6 tabs) -- nothing else in this
    -- file assumes they're the same length.
    pages = { pidsPage, ratesPage, globalFiltersPage, profileFiltersPage, vtxPage, throttlePage }
    pageNames = { "PIDs", "Rates", "Filters(G)", "Filters(P)", "VTX", "Motor" }
    pageKeys = { "pids", "rates", "filters", "vtx", "throttle" }
    pageByKey = { pids = pidsPage, rates = ratesPage, filters = globalFiltersPage, vtx = vtxPage, throttle = throttlePage }
    RATES_TAB_INDEX = 2 -- position of ratesPage in `pages` above; the rate-profile selector only shows on this tab (see drawProfileRow/handleProfileTouch)

    -- Betaflight tracks PID profile and rate profile as two SEPARATE active
    -- indices (MSP_SELECT_SETTING's RATEPROFILE_MASK bit picks which one a
    -- given SELECT_SETTING call addresses) -- they are not the same "profile
    -- slot" and switching one does not switch the other. This table says
    -- which cached page data depends on which: PIDs/Filters/Motor all read
    -- fields out of the currently-active pidProfile_t, Rates reads out of
    -- the currently-active controlRateConfig_t, and VTX depends on neither
    -- (a single global config, not profile-scoped at all).
    PROFILE_TYPE_PAGE_KEYS = {
        pid = { "pids", "filters", "throttle" },
        rate = { "rates" },
    }

    -- The SET command each page's beginSave() issues. Used to validate that a
    -- response actually belongs to the request we just made before treating it
    -- as a successful write (see the msp session's shared-session hazard).
    SET_CMD_BY_KEY = {
        pids = mspMsgs.CMD.SET_SIMPLIFIED_TUNING,
        rates = mspMsgs.CMD.SET_RC_TUNING,
        filters = mspMsgs.CMD.SET_FILTER_CONFIG,
        vtx = mspMsgs.CMD.SET_VTX_CONFIG,
        throttle = mspMsgs.CMD.SET_PID_ADVANCED,
    }

    app = {
        activeTab = 1,
        -- connecting | connected | unsupported | unsupported_version | disconnected
        connection = "connecting",
        session = msp.new(REQUEST_TIMEOUT_MS),
        arm = safety.new(),
        state = stateMod.new(),
        -- Separate PID and rate profile slots -- see PROFILE_TYPE_PAGE_KEYS
        -- above for why these are tracked independently, not as one "profile".
        pidProfileSlot = 1,
        rateProfileSlot = 1,
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
local PROFILE_ROW_H = 26
local PROFILE_BOX_W = 34
local PROFILE_BOX_GAP = 8
local PROFILE_TEXT_Y_OFFSET = 6 -- vertically centers text in the taller PROFILE_ROW_H box
-- PID and rate profile selectors sit side by side on the one profile row
-- (rather than stacked on two rows) so every page keeps its existing content
-- band starting at y=86 (or y=70 on pages that don't need the extra gap) --
-- see PROFILE_TYPE_PAGE_KEYS above for why they're two independent
-- selectors instead of one.
local PID_LABEL_X = 4
local PID_BOX_X0 = 46
local RATE_LABEL_X = 226
local RATE_BOX_X0 = 270
local FOOTER_H = 40
local FOOTER_Y = LCD_H - FOOTER_H
local BTN_SAVE_X, BTN_SAVE_W = 0, 100
local BTN_CANCEL_X, BTN_CANCEL_W = 110, 100

-- Single shared CRSF pop loop: dispatches MSP_RESP frames to the active
-- session via session:feed(). msp.lua deliberately never calls
-- crossfireTelemetryPop() itself (see Task 3's note) so this is the only
-- consumer of the telemetry queue.
--
-- crossfireTelemetryPop() returns TWO values -- command (number), packet
-- (table of byte values) -- not a single table with .command/.data fields,
-- and returns nothing at all (not nil) when the queue is empty. Confirmed
-- against EdgeTX firmware source (radio/src/lua/api_general.cpp). MSP_RESP
-- packets additionally carry a 2-byte CRSF [destination][origin] prefix
-- (confirmed against Betaflight source, telemetry/crsf.c) that
-- msp.responseTableToChunkString strips before handing the rest to
-- session:feed().
--
-- Arm status does NOT come through this queue: confirmed against EdgeTX
-- firmware source (radio/src/telemetry/crossfire.cpp) that CRSF FLIGHT_MODE
-- (0x21) frames are consumed entirely by EdgeTX's own sensor decoder (into
-- a built-in "FM" text sensor, radio/src/telemetry/sensor_names.h) and never
-- forwarded to the Lua crossfireTelemetryPop() queue at all -- unlike MSP,
-- which has its own separate, always-forwarded queue. So arm status is read
-- via EdgeTX's own decoded sensor with getValue("FM") instead (see
-- pumpArmStatus below), confirmed to return a Lua string for UNIT_TEXT
-- sensors (radio/src/lua/api_general.cpp: luaGetValueAndPush).
local function pumpTelemetry(nowMs)
    while true do
        local command, packet = crossfireTelemetryPop()
        if command == nil then
            break
        end
        if command == CRSF_FRAMETYPE_MSP_RESP then
            app.session:feed(msp.responseTableToChunkString(packet))
        end
    end
end

-- getValue("FM") returns the flight-mode text as a string when telemetry is
-- streaming, or the number 0 when it isn't (radio/src/lua/api_general.cpp).
-- feedFlightModeFrame already ignores non-string input safely, but we also
-- explicitly mark stale on that path so the fail-safe re-engages promptly if
-- telemetry drops out, rather than latching onto the last-seen value forever.
local function pumpArmStatus()
    local fm = getValue("FM")
    if type(fm) == "string" then
        app.arm:feedFlightModeFrame(fm)
    else
        app.arm:markStale()
    end
end

--------------------------------------------------------------------------------
-- Connection check: MSP_FC_VARIANT (is it Betaflight?) then MSP_API_VERSION.
--
-- Gates on the MSP *protocol* version, not the human-facing firmware version
-- string. This matters because Betaflight switched from "4.x.y" versioning
-- to calendar versioning ("2026.6.1") at some point after 4.5.x -- a user
-- hit exactly this connecting an FC on the new scheme, which broke the old
-- major==4/minor==5 firmware-version gate outright (MSP_FC_VERSION's 3
-- single-byte fields can't even represent a 4-digit year; Betaflight source,
-- src/main/msp/msp.c, now sends year-2000/month/patch instead of
-- major/minor/patch there). The MSP API version is a different, more stable
-- number Betaflight itself uses to track when individual MSP fields were
-- introduced -- every message this project depends on has been byte-for-byte
-- unchanged since MSP API 1.44 (confirmed directly against Betaflight
-- firmware source for both 4.5.5 and 2026.6.1: MSP_SIMPLIFIED_TUNING,
-- introduced "Added in MSP API 1.44", is the newest message used here, and
-- every other message's fields this project reads/writes are also present
-- and byte-identical between those two versions). Gating on the API version
-- instead is both backward compatible (4.5.3+) and forward compatible with
-- whatever Betaflight ships next, as long as it doesn't remove or reorder
-- these specific fields.
--------------------------------------------------------------------------------
local connectFlow = "variant" -- variant | apiVersion | done
local apiVersionText = nil

-- Governs retrying the initial handshake after a timeout/error, and
-- re-attempting it after a detected disconnect (see RECONNECT_INTERVAL_MS
-- and the stale-telemetry watchdog in runBody below).
local RECONNECT_INTERVAL_MS = 1000
local nextConnectAttemptMs = 0

-- How long the FM sensor (arm status) must go stale while "connected" before
-- this is treated as the flight controller having gone away (unplugged,
-- swapped for a different one, powered off) rather than a single dropped
-- telemetry frame. getValue("FM") already reflects EdgeTX's own sensor
-- staleness timeout, which debounces brief dropouts on its own, so this only
-- needs to guard against acting on one bad tick -- kept short so swapping
-- FCs feels responsive.
local DISCONNECT_STALE_MS = 1500
local staleSinceMs = nil

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
            connectFlow = "apiVersion"
            app.session:request(mspMsgs.CMD.API_VERSION, "")
        else
            app.connection = "unsupported"
        end
    elseif connectFlow == "apiVersion" then
        if cmd ~= mspMsgs.CMD.API_VERSION then
            app.session:request(mspMsgs.CMD.API_VERSION, "")
        else
            local mspProtocolVersion, apiMajor, apiMinor = mspMsgs.decodeApiVersion(payload)
            apiVersionText = tostring(apiMajor or "?") .. "." .. tostring(apiMinor or "?")
            if apiMajor == MIN_API_MAJOR and apiMinor >= MIN_API_MINOR then
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
        nextConnectAttemptMs = nowMs + RECONNECT_INTERVAL_MS
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

-- EdgeTX's touch event table (radio/src/lua/lua_event.cpp:
-- luaPushTouchEventTable) has fields x, y, tapCount -- there is no `tap`
-- field. touchState is only ever passed to run() at all when the current
-- event is a touch event, so its mere presence already means a touch
-- occurred this tick; that's the correct check here, not a nonexistent
-- boolean field (which was always nil/false and silently blocked all input).
local function tapInRect(touchState, x, y, w, h)
    if tapConsumed or not touchState then
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
local profileFlow = "idle" -- idle | selecting
local pendingProfileType = nil -- "pid" | "rate"
local pendingSlot = nil

-- A PID/rate profile switch takes effect on the FC immediately (SELECT_
-- SETTING is a RAM-only change), but does NOT survive a power cycle until
-- an EEPROM_WRITE happens -- so it's tracked here as its own kind of
-- "unsaved change", separate from isDirty() on any page's staged field
-- edits, and Save must commit it too. See runBody's footer text and
-- handleFooterTouch's Save-tap gate below.
local profileSwitchPending = false

local saveFlow = "idle" -- idle | sending | waitSet | eeprom
local saveQueue = nil
local saveIndex = 0
local saveWritten = nil -- keys whose SET was acknowledged, pending EEPROM confirm
local saveError = nil

-- How long the post-save "Saved!" footer confirmation stays up, so a
-- successful save (whether it touched PIDs, Rates, Filters, VTX, or the
-- Motor tab) is positively acknowledged rather than the footer just quietly
-- going blank -- the only prior feedback was "Saving..." disappearing.
local SAVE_CONFIRMATION_MS = 2500
local saveConfirmedUntilMs = nil

local function beginSaveFlow()
    saveQueue = {}
    for _, key in ipairs(pageKeys) do
        -- A key can only be dirty if it was loaded, but guard anyway: never
        -- call beginSave() on a page whose state was never fetched.
        if app.state:isDirty(key) and app.state:get(key) ~= nil then
            saveQueue[#saveQueue + 1] = key
        end
    end
    -- An empty queue still needs to proceed straight to the EEPROM_WRITE
    -- step (pumpSaveFlow's "sending" branch already does that whenever
    -- saveQueue[saveIndex] is nil) when a profile switch is the only thing
    -- that needs persisting -- otherwise Save would silently do nothing for
    -- a switch-with-no-other-edits.
    if #saveQueue == 0 and not profileSwitchPending then
        saveQueue = nil
        return
    end
    saveIndex = 0
    saveWritten = {}
    saveError = nil
    saveConfirmedUntilMs = nil
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
                -- Whatever PID/rate profile is active right now (it may
                -- have been switched since the last EEPROM_WRITE) is now
                -- persisted too -- this EEPROM_WRITE covers the FC's entire
                -- current RAM state, not just the fields this tool staged.
                profileSwitchPending = false
                saveError = nil
                saveConfirmedUntilMs = nowMs + SAVE_CONFIRMATION_MS
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

local function drawFooter(armed, nowMs)
    if armed then
        return
    end
    lcd.drawFilledRectangle(BTN_SAVE_X, FOOTER_Y, BTN_SAVE_W, FOOTER_H, COLOR_GREEN)
    lcd.drawText(BTN_SAVE_X + 10, FOOTER_Y + 12, "Save", COLOR_WHITE)
    lcd.drawFilledRectangle(BTN_CANCEL_X, FOOTER_Y, BTN_CANCEL_W, FOOTER_H, COLOR_GREY)
    lcd.drawText(BTN_CANCEL_X + 10, FOOTER_Y + 12, "Cancel", COLOR_WHITE)

    if saveError then
        lcd.drawText(220, FOOTER_Y + 12, saveError, COLOR_RED)
    elseif saveFlow ~= "idle" then
        lcd.drawText(220, FOOTER_Y + 12, "Saving...", COLOR_WHITE)
    elseif app.state:isAnyDirty() and profileSwitchPending then
        lcd.drawText(220, FOOTER_Y + 12, "* unsaved changes + profile switch", COLOR_ORANGE)
    elseif app.state:isAnyDirty() then
        lcd.drawText(220, FOOTER_Y + 12, "* unsaved changes", COLOR_WHITE)
    elseif profileSwitchPending then
        lcd.drawText(220, FOOTER_Y + 12, "Profile switched -- Save to keep", COLOR_ORANGE)
    elseif saveConfirmedUntilMs ~= nil and nowMs < saveConfirmedUntilMs then
        lcd.drawText(220, FOOTER_Y + 12, "Saved!", COLOR_GREEN)
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
            and not app.session:isPending() and (app.state:isAnyDirty() or profileSwitchPending) then
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

-- Profile selectors: two independent rows of three tappable "1"/"2"/"3"
-- boxes side by side on the one profile strip -- PID profile on the left,
-- rate profile on the right (see PROFILE_TYPE_PAGE_KEYS above for why these
-- are separate). Switching either issues ONE MSP_SELECT_SETTING request
-- (not two), then invalidates only the cached page keys that actually
-- depend on that profile type, so switching rate profile doesn't force a
-- pointless PIDs/Filters/Motor reload and vice versa.
-- (profileFlow / pendingProfileType / pendingSlot are declared above, next
-- to the save-flow state.)

local function reloadPageKey(key)
    if key == "pids" then
        pidsPage.create()
    elseif key == "rates" then
        ratesPage.create()
    elseif key == "filters" then
        -- Both filter tabs share filtersShared.lua's load state -- calling
        -- both create()s is harmless/idempotent, see that file's header.
        globalFiltersPage.create()
        profileFiltersPage.create()
    elseif key == "vtx" then
        vtxPage.create()
    elseif key == "throttle" then
        throttlePage.create()
    end
end

-- state:clear() alone does not make a page reload: each page module only
-- re-enters its "loading" phase from a module-local `phase` variable that
-- becomes "idle" via that page's own create() -- reloadPageKey is what
-- actually does that, for whichever keys are passed in.
local function clearCachedStateFor(keys)
    for _, key in ipairs(keys) do
        app.state:clear(key)
        reloadPageKey(key)
    end
end

local function clearAllCachedState()
    clearCachedStateFor(pageKeys)
end

-- Confirmed against Betaflight firmware source (src/main/target/common_pre.h,
-- both 4.5.5 and 2026.6.1): PID_PROFILE_COUNT and CONTROL_RATE_PROFILE_COUNT
-- are both 4, not 3.
local PROFILE_SLOT_COUNT = 4

local function drawProfileSelector(labelX, boxX0, label, activeSlot, armed)
    lcd.drawText(labelX, PROFILE_Y + PROFILE_TEXT_Y_OFFSET, label, COLOR_WHITE)
    for i = 1, PROFILE_SLOT_COUNT do
        local x = boxX0 + (i - 1) * (PROFILE_BOX_W + PROFILE_BOX_GAP)
        local isActive = (i == activeSlot)
        local fill = COLOR_GREY
        if isActive then
            fill = profileSwitchPending and COLOR_ORANGE or COLOR_BLUE
        end
        lcd.drawFilledRectangle(x, PROFILE_Y, PROFILE_BOX_W, PROFILE_ROW_H, fill)
        lcd.drawText(x + PROFILE_BOX_W / 2 - 4, PROFILE_Y + PROFILE_TEXT_Y_OFFSET, tostring(i), COLOR_WHITE)
    end
end

-- Rate profile only affects the Rates tab (PIDs/Filters/Motor all depend on
-- PID profile instead -- see PROFILE_TYPE_PAGE_KEYS), so its selector is
-- only shown/tappable while that tab is active, decluttering every other
-- tab. PID's selector stays visible everywhere since it's relevant on 4 of
-- the 6 tabs.
local function drawProfileRow(armed)
    if armed then
        return
    end
    drawProfileSelector(PID_LABEL_X, PID_BOX_X0, "PID:", app.pidProfileSlot, armed)
    if app.activeTab == RATES_TAB_INDEX then
        drawProfileSelector(RATE_LABEL_X, RATE_BOX_X0, "Rate:", app.rateProfileSlot, armed)
    end
end

-- Returns which slot (1..PROFILE_SLOT_COUNT) a tap x-position hit within a
-- selector starting at boxX0, or nil if it missed every box.
local function hitSlot(tx, boxX0)
    for i = 1, PROFILE_SLOT_COUNT do
        local x = boxX0 + (i - 1) * (PROFILE_BOX_W + PROFILE_BOX_GAP)
        if tx >= x and tx < x + PROFILE_BOX_W then
            return i
        end
    end
    return nil
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
    if tx < RATE_LABEL_X then
        local slot = hitSlot(tx, PID_BOX_X0)
        if slot and slot ~= app.pidProfileSlot then
            pendingProfileType, pendingSlot = "pid", slot
            app.session:request(mspMsgs.CMD.SELECT_SETTING, mspMsgs.encodeSelectSetting("pid", slot - 1))
            profileFlow = "selecting"
        end
    elseif app.activeTab == RATES_TAB_INDEX then
        -- Rate's selector isn't even drawn on other tabs -- ignore a tap
        -- landing in that screen region elsewhere rather than acting on a
        -- control the user can't see.
        local slot = hitSlot(tx, RATE_BOX_X0)
        if slot and slot ~= app.rateProfileSlot then
            pendingProfileType, pendingSlot = "rate", slot
            app.session:request(mspMsgs.CMD.SELECT_SETTING, mspMsgs.encodeSelectSetting("rate", slot - 1))
            profileFlow = "selecting"
        end
    end
end

local function pumpProfileFlow(nowMs)
    if profileFlow ~= "selecting" then
        return false
    end
    local status = app.session:poll(nowMs)
    if status == "done" then
        local cmd = app.session:result()
        if cmd == mspMsgs.CMD.SELECT_SETTING then
            if pendingProfileType == "pid" then
                app.pidProfileSlot = pendingSlot
            else
                app.rateProfileSlot = pendingSlot
            end
            clearCachedStateFor(PROFILE_TYPE_PAGE_KEYS[pendingProfileType])
            -- Takes effect on the FC immediately (RAM), but needs Save to
            -- survive a power cycle -- see profileSwitchPending's own comment.
            profileSwitchPending = true
        end
        profileFlow = "idle"
        pendingProfileType, pendingSlot = nil, nil
    elseif status == "timeout" or status == "error" then
        app.session:reset()
        profileFlow = "idle"
        pendingProfileType, pendingSlot = nil, nil
    end
    return true
end

-- Returns the whole app to exactly the state it's in right after init() --
-- as if the script had just been launched -- so unplugging one flight
-- controller and plugging in a different one needs no script restart. Called
-- both when the connection watchdog below detects a lost link, and whenever
-- a not-yet-connected handshake needs to retry.
--
-- Cached PID/rate/filter/VTX values, dirty edits, the save/profile-switch
-- flows, and the arm tracker all belong to whichever FC was last talked to --
-- carrying any of it over to a newly-plugged FC would risk showing stale
-- values as if they were the new FC's, or silently discarding/misapplying an
-- in-flight save/profile-switch that can never complete now the link is gone.
local function resetToInitialState()
    app.session:reset()
    app.arm = safety.new()
    app.pidProfileSlot = 1
    app.rateProfileSlot = 1
    app.activeTab = 1
    clearAllCachedState()

    saveFlow = "idle"
    saveQueue = nil
    saveIndex = 0
    saveWritten = nil
    saveError = nil
    saveConfirmedUntilMs = nil

    profileFlow = "idle"
    pendingProfileType = nil
    pendingSlot = nil
    profileSwitchPending = false

    staleSinceMs = nil
    app.connection = "connecting"
    checkConnection()
end

local function drawTabBar(armed)
    for i, name in ipairs(pageNames) do
        local w = math.floor(LCD_W / #pageNames)
        local x = (i - 1) * w
        if i == app.activeTab then
            lcd.drawFilledRectangle(x, TAB_Y, w, TAB_H, COLOR_BLUE)
        end
        lcd.drawText(x + 8, TAB_Y + 4, name, COLOR_WHITE)
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
        return "Unsupported MSP API " .. tostring(apiVersionText)
            .. " -- this tool requires API "
            .. MIN_API_MAJOR .. "." .. MIN_API_MINOR .. "+"
    end
    return "No response from flight controller. Check link."
end

-- DIAGNOSTIC WRAPPER (see the setup-time one above): the real per-frame logic
-- lives in runBody(); the global run() below pcalls it so a mid-frame error
-- draws on screen instead of leaving a blank/frozen display. Remove once the
-- script is confirmed running cleanly on real hardware.
local function runBody(event, touchState)
    local nowMs = getTime() * 10
    pumpTelemetry(nowMs)
    pumpArmStatus()

    if app.connection == "connecting" then
        pumpConnection(nowMs)
    elseif app.connection == "disconnected" and nowMs >= nextConnectAttemptMs then
        -- Keep retrying the handshake on our own -- otherwise a flight
        -- controller that wasn't ready yet (or a freshly swapped-in one)
        -- would need a script restart to ever be noticed.
        app.connection = "connecting"
        checkConnection()
    elseif app.connection == "connected" then
        -- Watchdog: once connected, nothing else re-checks that the FC is
        -- still there. getValue("FM") going stale (via pumpArmStatus above)
        -- is the signal that its telemetry has stopped arriving -- unplugged,
        -- swapped for another FC, or powered off. Reset everything back to
        -- first-start state so a different FC can be plugged in without
        -- restarting the script, rather than carrying over the old FC's
        -- cached settings, dirty edits, or in-flight save/profile flow.
        if app.arm:isStale() then
            if staleSinceMs == nil then
                staleSinceMs = nowMs
            elseif nowMs - staleSinceMs >= DISCONNECT_STALE_MS then
                resetToInitialState()
            end
        else
            staleSinceMs = nil
        end
    end

    lcd.clear(COLOR_BLACK)

    if app.connection ~= "connected" then
        lcd.drawText(10, 10, "Betaflight Dashboard", COLOR_WHITE)
        lcd.drawText(10, 40, connectionMessage(), COLOR_WHITE)
        return
    end

    local armed = app.arm:isArmed()
    if armed then
        lcd.drawFilledRectangle(0, 0, LCD_W, 20, COLOR_RED)
        lcd.drawText(10, 4, "ARMED -- read only", COLOR_WHITE)
        -- DIAGNOSTIC: shows the exact flight-mode text this FC is sending, to
        -- debug the arm-lock fail-safe showing armed when the craft is
        -- genuinely disarmed. Shortened to just the raw text (dropping
        -- stale/armed/n, already confirmed working) since the combined
        -- string was running off the right edge of the screen before the
        -- actual value was visible. Remove once confirmed working.
        local _, _, lastRawText = app.arm:debugInfo()
        lcd.drawText(150, 4, "FM='" .. tostring(lastRawText) .. "'", COLOR_WHITE)
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

    drawFooter(armed, nowMs)
end

-- IMPORTANT: EdgeTX's standalone-script host (radio/src/gui/colorlcd/
-- standalone_lua.cpp: StandaloneLuaWindow::checkEvents) calls run() expecting
-- EXACTLY ONE numeric return value: 0 means "keep running, please repaint the
-- screen", non-zero means "close this app". If run() returns nothing (nil),
-- the host never calls invalidate() and the drawn frame is silently never
-- shown -- this was the root cause of the screen appearing solid black with
-- no error. Every path below must return 0.
function run(event, touchState)
    if not setupOk then
        lcd.clear(COLOR_BLACK)
        lcd.drawText(5, 5, "BFDash failed to load:", COLOR_WHITE)
        lcd.drawText(5, 30, tostring(setupErr), COLOR_WHITE)
        return 0
    end

    local ok, runErr = pcall(runBody, event, touchState)
    if not ok then
        lcd.clear(COLOR_BLACK)
        lcd.drawText(5, 5, "BFDash crashed in run():", COLOR_WHITE)
        lcd.drawText(5, 30, tostring(runErr), COLOR_WHITE)
    end
    return 0
end

-- EdgeTX's script loader requires the top-level chunk to return a table with
-- a `run` field (required) and optionally `init`/`background` -- defining
-- these as bare globals is NOT sufficient; the loader marks the script
-- SCRIPT_SYNTAX_ERROR ("The script did not return a table") and never calls
-- run() at all, which is why nothing appeared on screen. Confirmed against
-- EdgeTX firmware source (radio/src/lua/interface.cpp).
return { init = init, run = run }
