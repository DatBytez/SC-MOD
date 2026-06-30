--[[
This code is a reimplementation of TNE_ACTIVE_DRONE_LUA.lua from TNE.

SC active shield fallback behavior:
- Drones tagged with <sc-active-shield> still add a super shield when they fire.
- While a ship has one of these active shield drones deployed and powered, all of
  that ship's super shields are popped whenever there are no enemy projectiles
  currently incoming toward that ship.
]]

mods.multiverse.droneTagParsers = mods.multiverse.droneTagParsers or {}
local droneTagParsers = mods.multiverse.droneTagParsers
local vter = mods.multiverse.vter

mods.sc = mods.sc or {}
mods.sc.activeShield = mods.sc.activeShield or {}

local activeDrones = mods.sc.activeShield

-- Set to true temporarily if you want to confirm when the fallback pop runs.
local DEBUG_ACTIVE_SHIELD = true

-- Extra movement/reaction updates for active shield drones.
-- 1 = normal speed, 2 = one extra OnLoop per frame, 3 = two extra OnLoops, etc.
local ACTIVE_SHIELD_DRONE_SPEED_MULTIPLIER = 2

local function debug_log(message)
    if not DEBUG_ACTIVE_SHIELD then return end

    local fullMessage = "[SC ACTIVE SHIELD] " .. tostring(message)
    if type(log) == "function" then
        log(fullMessage)
    elseif type(print) == "function" then
        print(fullMessage)
    end
end

local function get_ship_from_owner(ownerId)
    if ownerId == 0 then
        return Hyperspace.ships.player
    else
        return Hyperspace.ships.enemy
    end
end

local function get_super_power(shipManager)
    if not shipManager then return nil end
    if not shipManager.shieldSystem then return nil end
    if not shipManager.shieldSystem.shields then return nil end
    if not shipManager.shieldSystem.shields.power then return nil end
    if not shipManager.shieldSystem.shields.power.super then return nil end

    return shipManager.shieldSystem.shields.power.super
end

local function get_pop_location(shipManager)
    local shieldSystem = shipManager and shipManager.shieldSystem
    if shieldSystem then
        if shieldSystem.superUpLoc then return shieldSystem.superUpLoc end
        if shieldSystem.center then return shieldSystem.center end
    end

    if shipManager and shipManager.GetRandomRoomCenter then
        return shipManager:GetRandomRoomCenter()
    end

    return Hyperspace.Point(0, 0)
end

local function drone_has_active_shield_tag(drone)
    if not drone then return false end
    if not drone.blueprint then return false end
    if not drone.blueprint.name then return false end

    return activeDrones[drone.blueprint.name] == true
end

local function drone_is_active_and_powered(drone)
    if not drone_has_active_shield_tag(drone) then return false end
    if drone.deployed ~= true then return false end
    if drone.powered ~= true then return false end
    if drone.bDead == true then return false end

    return true
end

local function ship_has_active_powered_shield_drone(shipManager)
    if not shipManager then return false end
    if not shipManager.droneSystem or not shipManager.droneSystem.drones then return false end

    for drone in vter(shipManager.droneSystem.drones) do
        if drone_is_active_and_powered(drone) then
            return true
        end
    end

    return false
end

local function space_drone_is_active_shield_drone(drone)
    if not drone_has_active_shield_tag(drone) then return false end
    if drone.powered ~= true then return false end
    if drone.bDead == true then return false end

    return true
end

local function boost_active_shield_space_drones(shipManager)
    if not shipManager then return end
    if ACTIVE_SHIELD_DRONE_SPEED_MULTIPLIER <= 1 then return end
    if not shipManager.spaceDrones then return end

    local speedBoost = ACTIVE_SHIELD_DRONE_SPEED_MULTIPLIER - 1
    local extraUpdates = math.floor(speedBoost)
    if extraUpdates <= 0 then return end

    for drone in vter(shipManager.spaceDrones) do
        if space_drone_is_active_shield_drone(drone) then
            -- Match the behavior used in drones.lua: manually accelerate drone
            -- weapon cooldown, then run extra drone OnLoop updates so movement and
            -- targeting/reaction logic also advances faster.
            if drone.currentSpeed and drone.weaponCooldown and drone.weaponCooldown >= 0 then
                drone.weaponCooldown = drone.weaponCooldown - Hyperspace.FPS.SpeedFactor / 16 * speedBoost
                if drone.weaponCooldown <= 0 then
                    drone.weaponCooldown = -1
                end
            end

            for _ = 1, extraUpdates do
                drone:OnLoop()
            end
        end
    end
end

local function ship_has_incoming_enemy_projectile(shipId)
    local world = Hyperspace.App and Hyperspace.App.world
    local spaceManager = world and world.space
    if not spaceManager or not spaceManager.projectiles then return false end

    for projectile in vter(spaceManager.projectiles) do
        if projectile then
            local projectileIsActive = projectile._targetable ~= false and not projectile.passedTarget
            local projectileIsEnemy = projectile.ownerId ~= shipId
            local projectileIsAtShip = projectile.currentSpace == shipId or projectile.destinationSpace == shipId

            if projectileIsActive and projectileIsEnemy and projectileIsAtShip then
                return true
            end
        end
    end

    return false
end

local function pop_all_super_shields(shipManager)
    local shieldSystem = shipManager and shipManager.shieldSystem
    local superPower = get_super_power(shipManager)
    if not shieldSystem or not superPower then return end

    local currentSuper = superPower.first or 0
    if currentSuper <= 0 then return end

    local popLocation = get_pop_location(shipManager)

    for i = 1, currentSuper do
        shieldSystem:CollisionReal(popLocation.x, popLocation.y, Hyperspace.Damage(), true)
    end
    superPower.first = 0

    debug_log("popped all super shields ship=" .. tostring(shipManager.iShipId) ..
              " count=" .. tostring(currentSuper))
end

table.insert(droneTagParsers, function(droneNode)
    local nameAttr = droneNode:first_attribute("name")
    if not nameAttr then return end

    local droneName = nameAttr:value()

    local tagNode = droneNode:first_node("sc-active-shield")
    if not tagNode then return end

    activeDrones[droneName] = true
end)

------------------------------------------------------------------------------------

script.on_internal_event(Defines.InternalEvents.DRONE_FIRE, function(projectile, spacedrone)
    if not projectile then return end
    if not spacedrone or not spacedrone.blueprint then return end

    if not drone_has_active_shield_tag(spacedrone) then
        return
    end

    local shipManager = get_ship_from_owner(projectile.ownerId)
    if not shipManager then
        projectile:Kill()
        return Defines.Chain.CONTINUE
    end

    projectile:Kill()

    local shieldSystem = shipManager.shieldSystem
    if not shieldSystem then
        return Defines.Chain.CONTINUE
    end

    local droneLocation = spacedrone.currentLocation
    shieldSystem:AddSuperShield(Hyperspace.Point(droneLocation.x, droneLocation.y))

    return Defines.Chain.CONTINUE
end)

------------------------------------------------------------------------------------

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if not shipManager then return end

    boost_active_shield_space_drones(shipManager)

    local shipId = shipManager.iShipId
    if shipId == nil then return end

    if not ship_has_active_powered_shield_drone(shipManager) then return end
    if ship_has_incoming_enemy_projectile(shipId) then return end

    pop_all_super_shields(shipManager)
end)
