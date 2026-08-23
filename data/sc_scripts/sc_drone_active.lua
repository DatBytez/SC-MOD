--[[
DESCRIPTION: Active shield drones replace their fired projectile with a temporary super shield.
        - Tagged drones add a super shield at their location when they fire.
        - Active shield space drones receive additional movement and reaction updates.
        - Clears all super shields while an active shield drone is deployed and no enemy projectiles are incoming.
TAG: <sc-active-shield/>
SOURCE CREDIT: TNE_ACTIVE_DRONE_LUA.lua, Fusion drones.lua
]]

local droneTagParsers = mods.multiverse.droneTagParsers
local vter = mods.multiverse.vter
local helpers = mods.sc.helpers

mods.sc = mods.sc or {}
mods.sc.activeShield = mods.sc.activeShield or {}

local activeDrones = mods.sc.activeShield

mods.sc.tag.register("drone", "sc-active-shield", activeDrones)

local ACTIVE_SHIELD_DRONE_SPEED_MULTIPLIER = 2

local function drone_has_active_shield_tag(drone)
    if not drone.blueprint then return false end
    return activeDrones[drone.blueprint.name]
end

local function drone_is_active_and_powered(drone)
    return drone_has_active_shield_tag(drone) and drone.deployed and drone.powered and not drone.bDead
end

local function boost_active_shield_space_drones(shipManager)
    for drone in vter(shipManager.spaceDrones) do
        if drone_has_active_shield_tag(drone) and drone.powered and not drone.bDead then
            for _ = 1, (ACTIVE_SHIELD_DRONE_SPEED_MULTIPLIER - 1) do
                drone:OnLoop()
            end
        end
    end
end

local function ship_has_incoming_enemy_projectile(shipId)
    for projectile in vter(Hyperspace.App.world.space.projectiles) do
        local projectileIsActive = projectile._targetable ~= false and not projectile.passedTarget
        local projectileIsEnemy = projectile.ownerId ~= shipId
        local projectileIsAtShip = projectile.currentSpace == shipId or projectile.destinationSpace == shipId

        if projectileIsActive and projectileIsEnemy and projectileIsAtShip then
            return true
        end
    end

    return false
end

local function pop_all_super_shields(shipManager)
    local shieldSystem = shipManager.shieldSystem
    if not shieldSystem then return end

    local superPower = shieldSystem.shields.power.super
    local currentSuper = superPower.first
    if currentSuper <= 0 then return end

    local popLocation = shieldSystem.superUpLoc

    for i = 1, currentSuper do
        shieldSystem:CollisionReal(popLocation.x, popLocation.y, Hyperspace.Damage(), true)
    end

    superPower.first = 0
end

script.on_internal_event(Defines.InternalEvents.DRONE_FIRE, function(projectile, spacedrone)
    if not drone_has_active_shield_tag(spacedrone) then return end

    local shipManager = projectile.ownerId == 0 and Hyperspace.ships.player or Hyperspace.ships.enemy
    if not shipManager then
        projectile:Kill()
        return Defines.Chain.CONTINUE
    end

    projectile:Kill()

    local shieldSystem = shipManager.shieldSystem
    if not shieldSystem then return Defines.Chain.CONTINUE end

    local droneLocation = spacedrone.currentLocation
    shieldSystem:AddSuperShield(Hyperspace.Point(droneLocation.x, droneLocation.y))

    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    boost_active_shield_space_drones(shipManager)

    if not helpers.ship_has_drone_matching(shipManager, drone_is_active_and_powered) then return end
    if ship_has_incoming_enemy_projectile(shipManager.iShipId) then return end

    pop_all_super_shields(shipManager)
end)