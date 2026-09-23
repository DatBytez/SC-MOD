--[[
DESCRIPTION: Fixed on-screen Comsat / Sensors diagnostic.
    Diagnostic only; gameplay logic does not depend on this file.

PURPOSE:
    Display the current Sensors and Comsat state in one fixed panel.
    Values update in place instead of scrolling through console output.
]]

local vter = mods.multiverse.vter

local COMSAT_NAME = "TERRAN_COMSAT"
local SENSORS_ID = 7

local PANEL_X = 20
local PANEL_Y = 235
local PANEL_W = 410
local PANEL_H = 225

local TEXT_X = PANEL_X + 10
local TEXT_Y = PANEL_Y + 8
local LINE_HEIGHT = 20
local FONT = 10

local function yes_no(value)
    return value and "YES" or "NO"
end

local function get_comsat_state(ship)
    if not ship or not ship.droneSystem then
        return 0, 0
    end

    local count = 0
    local activeCount = 0

    for drone in vter(ship.droneSystem.drones) do
        if drone.blueprint and drone.blueprint.name == COMSAT_NAME then
            count = count + 1

            if drone.deployed
                and drone.powered
                and not drone.bDead then

                activeCount = activeCount + 1
            end
        end
    end

    return count, activeCount
end

local function get_debug_value(name, shipId, default)
    local debug = mods.sc and mods.sc.comsatDebug
    local values = debug and debug[name]

    if not values then return default end

    local value = values[shipId]
    if value == nil then return default end

    return value
end

local function draw_line(line, text)
    Graphics.freetype.easy_print(
        FONT,
        TEXT_X,
        TEXT_Y + line * LINE_HEIGHT,
        text
    )
end

local function draw_panel()
    if not Hyperspace.App
        or not Hyperspace.App.world
        or not Hyperspace.App.world.bStartedGame then
        return
    end

    local ship = Hyperspace.ships.player
    if not ship then return end

    local sensors = ship:GetSystem(SENSORS_ID)
    if not sensors then return end

    local comsatCount, activeCount = get_comsat_state(ship)
    local trackedBonus = get_debug_value("sensorBonusApplied", 0, 0)
    local baseBonus = get_debug_value("sensorBonusBase", 0, "N/A")
    local lastAction = get_debug_value("lastBonusAction", 0, "None")

    Graphics.CSurface.GL_PushMatrix()
    Graphics.CSurface.GL_LoadIdentity()

    Graphics.CSurface.GL_DrawRect(
        PANEL_X,
        PANEL_Y,
        PANEL_W,
        PANEL_H,
        Graphics.GL_Color(0, 0, 0, 0.82)
    )

    Graphics.CSurface.GL_SetColor(Graphics.GL_Color(1, 1, 1, 1))

    draw_line(0, "COMSAT SENSOR DEBUG")
    draw_line(1, string.format(
        "Comsat: %d   Active: %s   Active Count: %d",
        comsatCount,
        yes_no(activeCount > 0),
        activeCount
    ))
    draw_line(2, string.format(
        "Installed Level: %d   User Power: %d",
        sensors.powerState.second,
        sensors.powerState.first
    ))
    draw_line(3, string.format(
        "Effective Power: %d   Bonus Power: %d",
        sensors:GetEffectivePower(),
        sensors.iBonusPower
    ))
    draw_line(4, string.format(
        "Last Bonus Power: %d   Battery Power: %d",
        sensors.iLastBonusPower,
        sensors.iBatteryPower
    ))
    draw_line(5, string.format(
        "Tracked Comsat Bonus: %d   Base At Activation: %s",
        trackedBonus,
        tostring(baseBonus)
    ))
    draw_line(6, string.format(
        "GetMaxPower: %d   maxLevel: %d",
        sensors:GetMaxPower(),
        sensors.maxLevel
    ))
    draw_line(7, string.format(
        "Health: %d/%d   Last User Power: %d",
        sensors.healthState.first,
        sensors.healthState.second,
        sensors.lastUserPower
    ))
    draw_line(8, "Last Action:")
    draw_line(9, tostring(lastAction))

    Graphics.CSurface.GL_PopMatrix()
end

script.on_render_event(
    Defines.RenderEvents.MOUSE_CONTROL,
    draw_panel,
    function() end
)
