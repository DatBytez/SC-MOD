--[[
DESCRIPTION: Comsat drones provide temporary detector-style targeting while deployed.
        - Tagged drones use Sensors effective power as targeting strength.
        - Active Comsats temporarily increase the installed Sensors level by 2.
        - Drone parts spent deploying a Comsat are refunded after deployment.
        - Tagged drones are destroyed when their lifetime ends or if depowered early, entering the normal rebuild cycle.
        - The Comsat uses the DEFENSE drone type so it can deploy on the friendly side without an enemy ship.
        - Native defense-drone shots are blocked.
        - A separate Lua timer creates the Comsat scan hit animation at a random enemy room when an enemy ship is present.
TAG: <sc-comsat value="#"/>
DEPENDENCIES: sc_targeting_core.lua, sc_helpers.lua, sc_augment_upgrade.lua
]]

local vter = mods.multiverse.vter
local helpers = mods.sc.helpers
local targeting = mods.sc.targeting

mods.sc.comsat = mods.sc.comsat or {}
local comsat = mods.sc.comsat

local SCAN_BLUEPRINT = "TERRAN_COMSAT_PROJECTILE"
local SENSOR_LEVEL_BOOST = 2

local scanBlueprint = Hyperspace.Blueprints:GetWeaponBlueprint(SCAN_BLUEPRINT)
local SCAN_INTERVAL = scanBlueprint.cooldown

local comsatDrones = {}
local comsatTimers = {
    [0] = {},
    [1] = {}
}
local scanTimers = {
    [0] = {},
    [1] = {}
}
local comsatWasDeployed = {
    [0] = {},
    [1] = {}
}
local sensorLevelsApplied = {
    [0] = 0,
    [1] = 0
}
local sensorOriginalMax = {
    [0] = nil,
    [1] = nil
}

mods.sc.tag.register("drone", "sc-comsat", comsatDrones, "value")

local function drone_is_comsat(drone)
    return drone
        and drone.blueprint
        and comsatDrones[drone.blueprint.name] ~= nil
end

local function drone_is_active_comsat(drone)
    return drone_is_comsat(drone)
        and drone.deployed
        and drone.powered
        and not drone.bDead
end

local function ship_has_active_comsat(ship)
    return ship
        and ship.droneSystem
        and helpers.ship_has_drone_matching(ship, drone_is_active_comsat)
end

local function get_comsat_strength(ship)
    if not ship_has_active_comsat(ship) then return nil end

    local sensors = ship:GetSystem(7)
    if not sensors then return nil end

    return sensors:GetEffectivePower()
end

-- Reserve the temporary Sensors levels during the same frame a Comsat deactivates.
-- sc_augment_upgrade.lua loads first and must not clamp the system before removal.
function comsat.get_temporary_sensor_cap_bonus(ship)
    if not ship then return 0 end

    if ship_has_active_comsat(ship) or sensorLevelsApplied[ship.iShipId] > 0 then
        return SENSOR_LEVEL_BOOST
    end

    return 0
end

local function update_sensor_levels(ship)
    local shipId = ship.iShipId
    local sensors = ship:GetSystem(7)
    local applied = sensorLevelsApplied[shipId]

    if not sensors then
        sensorLevelsApplied[shipId] = 0
        sensorOriginalMax[shipId] = nil
        return
    end

    local wanted = ship_has_active_comsat(ship) and SENSOR_LEVEL_BOOST or 0
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
        -- With no active Comsat, this subtracts exactly the temporary levels.
        -- Do not reset the counter before the upgrade-cap script can see it.
        local sensors = ship:GetSystem(7)
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

local function update_comsat_refund(ship, drone)
    local shipId = ship.iShipId
    local droneId = drone.selfId
    local deployed = drone.deployed and not drone.bDead
    local wasDeployed = comsatWasDeployed[shipId][droneId]

    if wasDeployed == nil then
        comsatWasDeployed[shipId][droneId] = deployed
        return
    end

    if deployed and not wasDeployed then
        ship:ModifyDroneCount(1)
    end

    comsatWasDeployed[shipId][droneId] = deployed
end

local function create_comsat_scan(shipId)
    local targetShip = Hyperspace.ships(1 - shipId)
    if not targetShip or targetShip.bDestroyed then return false end

    local roomCenter = targetShip:GetRandomRoomCenter()
    local target = Hyperspace.Pointf(roomCenter.x, roomCenter.y)

    local scan = Hyperspace.App.world.space:CreateLaserBlast(
        scanBlueprint,
        target,
        targetShip.iShipId,
        shipId,
        target,
        targetShip.iShipId,
        0
    )

    scan.death_animation:Start(false)

    return true
end

local function update_comsat_scan(shipId, drone)
    local droneId = drone.selfId
    local remaining = (scanTimers[shipId][droneId] or 0) - Hyperspace.FPS.SpeedFactor / 16

    if remaining <= 0 and create_comsat_scan(shipId) then
        remaining = SCAN_INTERVAL
    end

    scanTimers[shipId][droneId] = remaining
end

-- targeting.register_source("sc_comsat", get_comsat_strength)
if targeting and targeting.register_source then
    targeting.register_source("sc_comsat", get_comsat_strength)
end

local function reset_comsat_state()
    comsatTimers[0] = {}
    comsatTimers[1] = {}
    scanTimers[0] = {}
    scanTimers[1] = {}
    comsatWasDeployed[0] = {}
    comsatWasDeployed[1] = {}
end

local function update_comsat_lifetime(shipTimers, drone, lifetime)
    if drone.bDead then return end

    local droneId = drone.selfId

    if not drone.powered then
        if drone.deployed or shipTimers[droneId] then
            drone:SetDestroyed(true, true)
        end

        shipTimers[droneId] = nil
        return
    end

    if not drone.deployed then
        shipTimers[droneId] = nil
        return
    end

    local remaining = (shipTimers[droneId] or lifetime) - Hyperspace.FPS.SpeedFactor / 16
    shipTimers[droneId] = remaining

    if remaining <= 0 then
        drone:SetDestroyed(true, true)
    end
end

script.on_init(function()
    reset_comsat_state()
    sensorLevelsApplied[0] = 0
    sensorLevelsApplied[1] = 0
    sensorOriginalMax[0] = nil
    sensorOriginalMax[1] = nil
end)

script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, function()
    remove_sensor_levels(0)
    remove_sensor_levels(1)
    reset_comsat_state()
end)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    local shipId = ship.iShipId

    if ship.droneSystem then
        local shipTimers = comsatTimers[shipId]

        for drone in vter(ship.droneSystem.drones) do
            local lifetime = comsatDrones[drone.blueprint.name]

            if lifetime then
                update_comsat_refund(ship, drone)
                update_comsat_lifetime(shipTimers, drone, lifetime)

                if drone_is_active_comsat(drone) then
                    update_comsat_scan(shipId, drone)
                else
                    scanTimers[shipId][drone.selfId] = nil
                end
            end
        end
    end

    update_sensor_levels(ship)
end)

script.on_internal_event(Defines.InternalEvents.DRONE_FIRE, function(projectile, spacedrone)
    if drone_is_comsat(spacedrone) then
        return Defines.Chain.PREEMPT
    end

    return Defines.Chain.CONTINUE
end)
