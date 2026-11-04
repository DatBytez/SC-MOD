--[[
DESCRIPTION: Applies the Sensors effects provided by active Terran Comsat drones.
        - Active Comsats temporarily increase the installed Sensors level by 2.
        - Sensors effective power provides Detector-style targeting strength.
        - Coordinates the temporary Sensors levels with sc_augment_upgrade.lua.
DEPENDENCIES: sc_drone_comsat.lua, sc_targeting_core.lua, sc_augment_upgrade.lua
]]

local comsat = mods.sc.comsat
local targeting = mods.sc.targeting

local SENSORS_SYSTEM_ID = Hyperspace.ShipSystem.NameToSystemId("sensors")
local SENSOR_LEVEL_BOOST = 2

local sensorLevelsApplied = {
    [0] = 0,
    [1] = 0
}
local sensorOriginalMax = {
    [0] = nil,
    [1] = nil
}

local function get_comsat_strength(ship)
    if not comsat.has_active(ship) then return nil end

    local sensors = ship:GetSystem(SENSORS_SYSTEM_ID)
    if not sensors then return nil end

    return sensors:GetEffectivePower()
end

-- Reserve the temporary Sensors levels during the same frame a Comsat deactivates.
-- sc_augment_upgrade.lua loads first and must not clamp the system before removal.
function comsat.get_temporary_sensor_cap_bonus(ship)
    if not ship then return 0 end

    if comsat.has_active(ship) or sensorLevelsApplied[ship.iShipId] > 0 then
        return SENSOR_LEVEL_BOOST
    end

    return 0
end

local function update_sensor_levels(ship)
    local shipId = ship.iShipId
    local sensors = ship:GetSystem(SENSORS_SYSTEM_ID)
    local applied = sensorLevelsApplied[shipId]

    if not sensors then
        sensorLevelsApplied[shipId] = 0
        sensorOriginalMax[shipId] = nil
        return
    end

    local wanted = comsat.has_active(ship) and SENSOR_LEVEL_BOOST or 0
    local difference = wanted - applied
    if difference == 0 then return end

    if difference > 0 then
        if applied == 0 then
            sensorOriginalMax[shipId] = sensors.maxLevel
        end

        sensors.maxLevel = math.max(sensors.maxLevel, sensors.powerState.second + difference)
    end

    local direction = difference > 0 and 1 or -1

    for _ = 1, math.abs(difference) do
        local previousLevel = sensors.powerState.second
        sensors:UpgradeSystem(direction)
        local actualChange = sensors.powerState.second - previousLevel

        if actualChange == 0 then break end
        sensorLevelsApplied[shipId] = math.max(0, sensorLevelsApplied[shipId] + actualChange)
    end

    sensors:CheckMaxPower()
    sensors:CheckForRepower()

    if sensorLevelsApplied[shipId] == 0 then
        -- Player maxLevel is managed by sc_augment_upgrade.lua on the next loop.
        -- Restore the original cap for enemy ships, which do not use that manager.
        if shipId ~= 0 and sensorOriginalMax[shipId] then
            sensors.maxLevel = sensorOriginalMax[shipId]
        end

        sensorOriginalMax[shipId] = nil
    end
end

local function remove_sensor_levels(shipId)
    local ship = Hyperspace.ships(shipId)

    if ship and sensorLevelsApplied[shipId] > 0 then
        local sensors = ship:GetSystem(SENSORS_SYSTEM_ID)

        if sensors then
            for _ = 1, sensorLevelsApplied[shipId] do
                sensors:UpgradeSystem(-1)
            end

            sensors:CheckMaxPower()
            sensors:CheckForRepower()

            if shipId ~= 0 and sensorOriginalMax[shipId] then
                sensors.maxLevel = sensorOriginalMax[shipId]
            end
        end
    end

    sensorLevelsApplied[shipId] = 0
    sensorOriginalMax[shipId] = nil
end

targeting.register_source("sc_comsat", get_comsat_strength)

script.on_init(function()
    sensorLevelsApplied[0] = 0
    sensorLevelsApplied[1] = 0
    sensorOriginalMax[0] = nil
    sensorOriginalMax[1] = nil
end)

script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, function()
    remove_sensor_levels(0)
    remove_sensor_levels(1)
end)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, update_sensor_levels)