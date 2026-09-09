local loader = loadScript and assert(loadScript("/SCRIPTS/TOOLS/BFDash/loader.lua"))() or dofile("src/SCRIPTS/TOOLS/BFDash/loader.lua")
local include = loader.include

local msp = include("transport/msp.lua")
local mspMsgs = include("mspMsgs.lua")
local stateMod = include("state.lua")
local safety = include("safety.lua")

local pidsPage = include("pages/pids.lua")
local ratesPage = include("pages/rates.lua")
local filtersPage = include("pages/filters.lua")
local vtxPage = include("pages/vtx.lua")

local CRSF_FRAMETYPE_MSP_RESP = 0x7B
local CRSF_FRAMETYPE_FLIGHT_MODE = 0x21
local FLIGHT_MODE_STALE_MS = 3000
local REQUEST_TIMEOUT_MS = 800

local pages = { pidsPage, ratesPage, filtersPage, vtxPage }
local pageNames = { "PIDs", "Rates", "Filters", "VTX" }

local app = {
    activeTab = 1,
    connection = "connecting", -- connecting | connected | unsupported | disconnected
    session = msp.new(REQUEST_TIMEOUT_MS),
    arm = safety.new(),
    state = stateMod.new(),
    lastFlightModeMs = 0,
    profileSlot = 1,
}

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

local function checkConnection()
    app.session:request(mspMsgs.CMD.FC_VARIANT, "")
end

local function onConnectionResponse(cmd, payload, isError)
    if isError then
        app.connection = "disconnected"
        return
    end
    local variant = mspMsgs.decodeFcVariant(payload)
    app.connection = mspMsgs.isBetaflight(variant) and "connected" or "unsupported"
end

function init()
    checkConnection()
end

local FOOTER_Y = LCD_H - 40
local saveFlow = "idle" -- idle | saving | eeprom | done

local function drawFooter(armed)
    if armed then
        return
    end
    lcd.drawFilledRectangle(0, FOOTER_Y, 100, 40, GREEN)
    lcd.drawText(10, FOOTER_Y + 12, "Save")
    lcd.drawFilledRectangle(110, FOOTER_Y, 100, 40, GREY)
    lcd.drawText(120, FOOTER_Y + 12, "Cancel")

    if app.state:isAnyDirty() then
        lcd.drawText(220, FOOTER_Y + 12, "* unsaved changes")
    end
end

local function handleFooterTouch(touchState)
    if not touchState or not touchState.tap then
        return
    end
    local tx, ty = touchState.x, touchState.y
    if ty < FOOTER_Y or ty > FOOTER_Y + 40 then
        return
    end
    if tx >= 0 and tx <= 100 and app.state:isAnyDirty() and saveFlow == "idle" then
        saveFlow = "saving"
    elseif tx >= 110 and tx <= 210 then
        for _, key in ipairs({ "pids", "rates", "filters", "vtx" }) do
            app.state:reload(key)
        end
    end
end

-- Profile-slot selector: a row of three tappable "1"/"2"/"3" labels below the
-- tab bar. Switching slots issues two separate MSP_SELECT_SETTING requests
-- (one for the PID profile, one for the rate profile) sequenced through the
-- single-request-at-a-time msp session, then invalidates all four cached
-- state keys so each page's update() re-fetches fresh data for the new slot.
local PROFILE_Y = 44
local PROFILE_ROW_H = 16
local PROFILE_BOX_W = 30
local PROFILE_BOX_GAP = 6
local PROFILE_BOX_X0 = 60

local profileFlow = "idle" -- idle | selectPid | selectRate
local pendingSlot = nil

local function clearCachedState()
    for _, key in ipairs({ "pids", "rates", "filters", "vtx" }) do
        app.state.staged[key] = nil
        app.state.clean[key] = nil
    end
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
    if armed or not touchState or not touchState.tap then
        return
    end
    if saveFlow ~= "idle" or profileFlow ~= "idle" then
        return
    end
    if app.state:isAnyDirty() then
        return -- avoid silently discarding unsaved edits when switching slots
    end
    local tx, ty = touchState.x, touchState.y
    if ty < PROFILE_Y or ty > PROFILE_Y + PROFILE_ROW_H then
        return
    end
    for i = 1, 3 do
        local x = PROFILE_BOX_X0 + (i - 1) * (PROFILE_BOX_W + PROFILE_BOX_GAP)
        if tx >= x and tx <= x + PROFILE_BOX_W and i ~= app.profileSlot then
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
            app.session:request(mspMsgs.CMD.SELECT_SETTING, mspMsgs.encodeSelectSetting("rate", pendingSlot - 1))
            profileFlow = "selectRate"
        elseif status == "timeout" or status == "error" then
            profileFlow = "idle"
            pendingSlot = nil
        end
        return true
    elseif profileFlow == "selectRate" then
        local status = app.session:poll(nowMs)
        if status == "done" then
            app.profileSlot = pendingSlot
            clearCachedState()
            profileFlow = "idle"
            pendingSlot = nil
        elseif status == "timeout" or status == "error" then
            profileFlow = "idle"
            pendingSlot = nil
        end
        return true
    end
    return false
end

function run(event, touchState)
    local nowMs = getTime() * 10
    pumpTelemetry(nowMs)

    if app.connection == "connecting" then
        local status = app.session:poll(nowMs)
        if status == "done" or status == "error" then
            onConnectionResponse(app.session:result())
        elseif status == "timeout" then
            app.connection = "disconnected"
        end
    end

    lcd.clear()

    if app.connection ~= "connected" then
        lcd.drawText(10, 10, "Betaflight Dashboard", MIDSIZE)
        local msg = ({
            connecting = "Connecting to flight controller...",
            unsupported = "Connected, but flight controller is not Betaflight.",
            disconnected = "No response from flight controller. Check link.",
        })[app.connection]
        lcd.drawText(10, 40, msg)
        return
    end

    local armed = app.arm:isArmed()
    if armed then
        lcd.drawFilledRectangle(0, 0, LCD_W, 20, RED)
        lcd.drawText(10, 4, "ARMED -- read only", WHITE)
    end

    for i, name in ipairs(pageNames) do
        local x = (i - 1) * (LCD_W // #pageNames)
        local w = LCD_W // #pageNames
        if i == app.activeTab then
            lcd.drawFilledRectangle(x, 20, w, 24, BLUE)
        end
        lcd.drawText(x + 8, 24, name)
        if not armed and touchState and touchState.tap
            and touchState.y >= 20 and touchState.y <= 44
            and touchState.x >= x and touchState.x < x + w then
            app.activeTab = i
        end
    end

    drawProfileRow(armed)

    local activePage = pages[app.activeTab]

    if saveFlow == "saving" then
        activePage.beginSave(app.session, app.state)
        saveFlow = "eeprom"
    elseif saveFlow == "eeprom" then
        local status = app.session:poll(nowMs)
        if status == "done" then
            app.state:markClean("pids")
            app.state:markClean("rates")
            app.state:markClean("filters")
            app.state:markClean("vtx")
            app.session:request(mspMsgs.CMD.EEPROM_WRITE, "")
            saveFlow = "done"
        elseif status == "timeout" or status == "error" then
            saveFlow = "idle" -- Save failed; state stays dirty, footer still shows unsaved changes
        end
    elseif saveFlow == "done" then
        local status = app.session:poll(nowMs)
        if status == "done" or status == "timeout" or status == "error" then
            saveFlow = "idle"
        end
    elseif pumpProfileFlow(nowMs) then
        -- profile-slot switch in progress; skip page update/event this tick
    else
        activePage.update(app.state, armed)
        activePage.event(event, touchState, app.state, app.session, nowMs, armed)
    end

    drawFooter(armed)
    handleFooterTouch(touchState)
    handleProfileTouch(touchState, armed)
end
