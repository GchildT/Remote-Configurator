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

    if app.arm:isArmed() then
        lcd.drawFilledRectangle(0, 0, LCD_W, 20, RED)
        lcd.drawText(10, 4, "ARMED -- read only", WHITE)
    end

    -- tab bar
    for i, name in ipairs(pageNames) do
        local x = (i - 1) * (LCD_W // #pageNames)
        local w = LCD_W // #pageNames
        if i == app.activeTab then
            lcd.drawFilledRectangle(x, 20, w, 24, BLUE)
        end
        lcd.drawText(x + 8, 24, name)
    end

    local activePage = pages[app.activeTab]
    activePage.update(app.state, app.arm:isArmed())
    activePage.event(event, touchState, app.state, app.session, nowMs, app.arm:isArmed())
end
