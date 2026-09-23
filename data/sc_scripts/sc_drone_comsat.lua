--[[
DESCRIPTION: Comsat drones provide temporary detector-style targeting while deployed.
        - Tagged drones use Sensors effective power as targeting strength.
        - Active Comsats provide 2 temporary bonus power to Sensors.
        - Drone parts spent deploying a Comsat are refunded after deployment.
        - Tagged drones self-destruct after the lifetime defined by <sc-comsat>.
        - The Comsat uses the DEFENSE drone type so it can deploy on the friendly side without an enemy ship.
        - Native defense-drone shots are blocked.
        - A separate Lua timer creates the Comsat scan hit animation at a random enemy room when an enemy ship is present.
TAG: <sc-comsat value="#"/>
DEPENDENCIES: sc_targeting_core.lua, sc_helpers.lua
]]

local vter = mods.multiverse.vter
local helpers = mods.sc.helpers
local targeting = mods.sc.targeting

local SCAN_BLUEPRINT = "TERRAN_COMSAT_PROJECTILE"
local SENSOR_POWER_BONUS = 2

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
local sensorBonusApplied = {
    [0] = 0,
    [1] = 0
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

local function update_sensor_bonus(ship)
    local shipId = ship.iShipId
    local sensors = ship:GetSystem(7)

    if not sensors then
        sensorBonusApplied[shipId] = 0
        return
    end

    local wanted = ship_has_active_comsat(ship) and SENSOR_POWER_BONUS or 0
    local current = sensorBonusApplied[shipId]
    local diff = wanted - current

    if diff ~= 0 then
        sensors.iBonusPower = math.max(0, sensors.iBonusPower + diff)
        sensorBonusApplied[shipId] = wanted
    end
end

local function remove_sensor_bonus(shipId)
    local ship = Hyperspace.ships(shipId)
    local sensors = ship and ship:GetSystem(7)
    local applied = sensorBonusApplied[shipId]

    if sensors and applied ~= 0 then
        sensors.iBonusPower = math.max(0, sensors.iBonusPower - applied)
    end

    sensorBonusApplied[shipId] = 0
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

targeting.register_source("sc_comsat", get_comsat_strength)

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
            drone:SetDestroyed(true, false)
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
    sensorBonusApplied[0] = 0
    sensorBonusApplied[1] = 0
end)

script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, function()
    remove_sensor_bonus(0)
    remove_sensor_bonus(1)
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

    update_sensor_bonus(ship)
end)

script.on_internal_event(Defines.InternalEvents.DRONE_FIRE, function(projectile, spacedrone)
    if drone_is_comsat(spacedrone) then
        return Defines.Chain.PREEMPT
    end

    return Defines.Chain.CONTINUE
end)
