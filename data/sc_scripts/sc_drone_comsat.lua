--[[
DESCRIPTION: Comsat drones provide temporary detector-style targeting while deployed.
        - Tagged drones use Sensors effective power as targeting strength.
        - Tagged drones self-destruct after the lifetime defined by <sc-comsat>.
        - Native combat-drone firing is disabled separately from the scan timer.
        - A separate Lua timer creates the scan projectile at the enemy ship.
TAG: <sc-comsat value="#"/>
DEPENDENCIES: sc_targeting_core.lua, sc_helpers.lua
]]

local vter = mods.multiverse.vter
local helpers = mods.sc.helpers
local targeting = mods.sc.targeting

local SCAN_BLUEPRINT = "TERRAN_COMSAT_PROJECTILE"
local SCAN_INTERVAL = Hyperspace.Blueprints:GetWeaponBlueprint(SCAN_BLUEPRINT).cooldown

local comsatDrones = {}
local comsatTimers = {
    [0] = {},
    [1] = {}
}
local scanTimers = {
    [0] = {},
    [1] = {}
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

local function get_comsat_strength(ship)
    if not helpers.ship_has_drone_matching(ship, drone_is_active_comsat) then return nil end

    local sensors = ship:GetSystem(7)
    if not sensors then return nil end

    return sensors:GetEffectivePower()
end

local function disable_native_comsat_fire(drone)
    drone.bDisrupted = true
    drone.bFire = false
end

local function create_comsat_scan(drone, targetShip)
    local target

    if drone:HasTarget() then
        target = Hyperspace.Pointf(drone.targetLocation.x, drone.targetLocation.y)
    else
        target = targetShip:GetRandomRoomCenter()
    end

    local blueprint = Hyperspace.Blueprints:GetWeaponBlueprint(SCAN_BLUEPRINT)

    Hyperspace.App.world.space:CreateLaserBlast(
        blueprint,
        target,
        targetShip.iShipId,
        drone.iShipId,
        target,
        targetShip.iShipId,
        0
    )
end

local function update_comsat_scan(ship, drone)
    local shipId = ship.iShipId
    local droneId = drone.selfId
    local remaining = (scanTimers[shipId][droneId] or SCAN_INTERVAL) - Hyperspace.FPS.SpeedFactor / 16

    if remaining <= 0 then
        local targetShip = Hyperspace.ships(1 - shipId)

        if targetShip and not targetShip.bDestroyed then
            create_comsat_scan(drone, targetShip)
        end

        remaining = SCAN_INTERVAL
    end

    scanTimers[shipId][droneId] = remaining
end

targeting.register_source("sc_comsat", get_comsat_strength)

local function reset_comsat_timers()
    comsatTimers[0] = {}
    comsatTimers[1] = {}
    scanTimers[0] = {}
    scanTimers[1] = {}
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
        drone:SetDestroyed(true, false)
    end
end

script.on_init(reset_comsat_timers)

script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, function()
    reset_comsat_timers()
end)

script.on_internal_event(Defines.InternalEvents.CONSTRUCT_SPACEDRONE, function(drone)
    if drone_is_comsat(drone) then
        disable_native_comsat_fire(drone)
    end
end)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    if not ship.droneSystem then return end

    local shipId = ship.iShipId
    local shipTimers = comsatTimers[shipId]

    for drone in vter(ship.droneSystem.drones) do
        local lifetime = comsatDrones[drone.blueprint.name]

        if lifetime then
            disable_native_comsat_fire(drone)
            update_comsat_lifetime(shipTimers, drone, lifetime)

            if drone_is_active_comsat(drone) then
                update_comsat_scan(ship, drone)
            else
                scanTimers[shipId][drone.selfId] = nil
            end
        end
    end
end)

script.on_internal_event(Defines.InternalEvents.DRONE_FIRE, function(projectile, spacedrone)
    if drone_is_comsat(spacedrone) then
        return Defines.Chain.PREEMPT
    end

    return Defines.Chain.CONTINUE
end)
