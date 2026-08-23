--[[
DESCRIPTION: Comsat drones provide temporary detector-style targeting while deployed.
        - Tagged drones use Sensors effective power as targeting strength.
        - Tagged drones self-destruct after the lifetime defined by <sc-comsat>.
        - Hides the scan projectile in flight while preserving its impact animation.
TAG: <sc-comsat value="#"/>
DEPENDENCIES: sc_targeting_core.lua, sc_helpers.lua
]]

local vter = mods.multiverse.vter
local helpers = mods.sc.helpers
local targeting = mods.sc.targeting

local comsatDrones = {}
local comsatTimers = {
    [0] = {},
    [1] = {}
}

mods.sc.tag.register("drone", "sc-comsat", comsatDrones, "value")

local function drone_is_active_comsat(drone)
    return comsatDrones[drone.blueprint.name] ~= nil and drone.deployed and drone.powered and not drone.bDead
end

local function get_comsat_strength(ship)
    if not helpers.ship_has_drone_matching(ship, drone_is_active_comsat) then return nil end

    local sensors = ship:GetSystem(7)
    if not sensors then return nil end

    return sensors:GetEffectivePower()
end

targeting.register_source("sc_comsat", get_comsat_strength)

local function reset_comsat_timers()
    comsatTimers[0] = {}
    comsatTimers[1] = {}
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

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    if not ship.droneSystem then return end

    local shipTimers = comsatTimers[ship.iShipId]

    for drone in vter(ship.droneSystem.drones) do
        local lifetime = comsatDrones[drone.blueprint.name]
        if lifetime then
            update_comsat_lifetime(shipTimers, drone, lifetime)
        end
    end
end)

script.on_internal_event(Defines.InternalEvents.DRONE_FIRE, function(projectile, spacedrone)
    if not comsatDrones[spacedrone.blueprint.name] then return end

    if projectile.flight_animation then
        projectile.flight_animation.fScale = 0
    end
end)