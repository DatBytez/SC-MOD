--[[
DESCRIPTION: Active shield drones create temporary super shields while threats are incoming.
        - Tagged shield drones must be deployed, powered, and alive to enable the shield behavior.
        - Incoming projectiles create defensive super shields.
        - Incoming drone projectiles create defensive super shields when fired.
        - Incoming beams create defensive super shields when fired.
        - Threat shields use the active shield drone's real cooldown.
        - Clears all super shields while an active shield drone is deployed and no enemy projectiles or beams are incoming.
TAG: <sc-active-shield value="1"/>
SOURCE CREDIT: TNE_ACTIVE_DRONE_LUA.lua, Fusion drones.lua
]]

local vter = mods.multiverse.vter

mods.sc = mods.sc or {}
mods.sc.activeShield = mods.sc.activeShield or {}
mods.sc.activeShieldState = mods.sc.activeShieldState or {
    threats = 0,
    used = 0,
    blocked = 0,
    lastThreat = nil,
    lastUse = nil,
    lastBlock = nil
}

local activeDrones = mods.sc.activeShield
local activeShieldState = mods.sc.activeShieldState

mods.sc.tag.register("drone", "sc-active-shield", activeDrones, function(tagNode)
    local valueAttribute = tagNode:first_attribute("value")
    if not valueAttribute then return 1 end

    local value = tonumber(valueAttribute:value()) or 1
    return math.max(1, math.floor(value))
end)

local BEAM_DANGER_DURATION = 1.5
local PROJECTILE_DANGER_DURATION = 0.25

local beamDangerTimer = {
    [0] = 0,
    [1] = 0
}

local projectileDangerTimer = {
    [0] = 0,
    [1] = 0
}

local droneProjectileThreats = setmetatable({}, {__mode = "k"})
local activeShieldCycleSpent = setmetatable({}, {__mode = "k"})

local function drone_has_active_shield_tag(drone)
    if not drone or not drone.blueprint then return false end
    return activeDrones[drone.blueprint.name]
end

local function get_active_shield_levels(drone)
    if not drone or not drone.blueprint then return 1 end

    local shieldLevels = activeDrones[drone.blueprint.name]

    if shieldLevels == true then
        return 1
    end

    shieldLevels = tonumber(shieldLevels) or 1
    return math.max(1, math.floor(shieldLevels))
end

local function drone_is_active_and_powered(drone)
    return drone_has_active_shield_tag(drone) and drone.deployed and drone.powered and not drone.bDead
end

local function get_drone_owner_id(drone)
    local success, ownerId = pcall(function()
        return drone:GetOwnerId()
    end)

    if success then
        return ownerId
    end

    return nil
end

local function update_active_shield_cycle_lock(drone)
    if not drone_has_active_shield_tag(drone) then return end

    if activeShieldCycleSpent[drone] and (drone.weaponCooldown or 0) <= 0 then
        activeShieldCycleSpent[drone] = nil
    end
end

local function update_active_shield_cycle_locks(shipManager)
    for drone in vter(shipManager.spaceDrones) do
        update_active_shield_cycle_lock(drone)
    end
end

local function drone_can_activate_shield(drone, ignoreCooldown)
    if not drone_is_active_and_powered(drone) then return false end

    update_active_shield_cycle_lock(drone)

    if activeShieldCycleSpent[drone] then
        return false
    end

    if not ignoreCooldown and (drone.weaponCooldown or 0) > 0 then
        return false
    end

    return true
end

local function ship_has_active_shield_drone(shipManager)
    for drone in vter(shipManager.spaceDrones) do
        if drone_is_active_and_powered(drone) then
            return true
        end
    end

    return false
end

local function get_ready_active_shield_drone(shipManager)
    for drone in vter(shipManager.spaceDrones) do
        if drone_can_activate_shield(drone, false) then
            return drone
        end
    end

    return nil
end

local function put_active_shield_drone_on_cooldown(drone)
    local cooldown = drone:GetWeaponCooldown()

    if cooldown and cooldown > 0 then
        drone.weaponCooldown = cooldown
    end
end

local function count_incoming_enemy_projectiles(shipId)
    local count = 0

    for projectile in vter(Hyperspace.App.world.space.projectiles) do
        local projectileIsActive = projectile._targetable ~= false and not projectile.passedTarget
        local projectileIsEnemy = projectile.ownerId ~= shipId
        local projectileIsAtShip = projectile.currentSpace == shipId or projectile.destinationSpace == shipId

        if projectileIsActive and projectileIsEnemy and projectileIsAtShip then
            count = count + 1
        end
    end

    return count
end

local function add_super_shield(shipManager)
    local shieldSystem = shipManager.shieldSystem
    if not shieldSystem then return end

    local shieldLocation = shieldSystem.superUpLoc
    shieldSystem:AddSuperShield(Hyperspace.Point(shieldLocation.x, shieldLocation.y))
end

local function activate_matrix_shield(shipManager, sourceName, isBeam, activeShieldDrone, ignoreCooldown)
    activeShieldDrone = activeShieldDrone or get_ready_active_shield_drone(shipManager)

    if not activeShieldDrone or not drone_can_activate_shield(activeShieldDrone, ignoreCooldown) then
        activeShieldState.blocked = activeShieldState.blocked + 1
        activeShieldState.lastBlock = {
            shipId = shipManager.iShipId,
            sourceName = sourceName,
            isBeam = isBeam
        }

        return false
    end

    local shieldLevels = get_active_shield_levels(activeShieldDrone)

    for i = 1, shieldLevels do
        add_super_shield(shipManager)
    end

    activeShieldCycleSpent[activeShieldDrone] = true
    put_active_shield_drone_on_cooldown(activeShieldDrone)

    activeShieldState.used = activeShieldState.used + 1
    activeShieldState.lastUse = {
        shipId = shipManager.iShipId,
        sourceName = sourceName,
        isBeam = isBeam,
        droneName = activeShieldDrone.blueprint and activeShieldDrone.blueprint.name or nil,
        shieldLevels = shieldLevels,
        weaponCooldown = activeShieldDrone.weaponCooldown or 0
    }

    return true
end

local function add_super_shield_if_ready(shipManager, sourceName, isBeam)
    return activate_matrix_shield(shipManager, sourceName, isBeam, nil, false)
end

local function add_super_shield_from_native_fire(spacedrone)
    local ownerId = get_drone_owner_id(spacedrone)
    if ownerId ~= 0 and ownerId ~= 1 then return false end

    local shipManager = Hyperspace.ships(ownerId)
    if not shipManager or not shipManager.shieldSystem then return false end

    projectileDangerTimer[ownerId] = PROJECTILE_DANGER_DURATION
    return activate_matrix_shield(shipManager, "native_fire", false, spacedrone, true)
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

local function get_projectile_target_ship_id(projectile, allowOwnerFallback)
    local targetShipId = projectile.destinationSpace

    if targetShipId == nil or targetShipId < 0 then
        if not allowOwnerFallback or projectile.ownerId == nil then
            return nil
        end

        targetShipId = 1 - projectile.ownerId
    end

    if targetShipId ~= 0 and targetShipId ~= 1 then
        return nil
    end

    if projectile.ownerId == targetShipId then
        return nil
    end

    return targetShipId
end

local function get_drone_projectile_target_ship_id(projectile, spacedrone)
    local droneOwnerId = get_drone_owner_id(spacedrone)

    if droneOwnerId == 0 or droneOwnerId == 1 then
        return 1 - droneOwnerId
    end

    if projectile and (projectile.currentSpace == 0 or projectile.currentSpace == 1) then
        return projectile.currentSpace
    end

    return get_projectile_target_ship_id(projectile, true)
end

local function create_threat_shield(targetShipId, isBeam, sourceName)
    local shipManager = Hyperspace.ships(targetShipId)
    if not shipManager or not shipManager.shieldSystem then return false end
    if not ship_has_active_shield_drone(shipManager) then return false end

    activeShieldState.threats = activeShieldState.threats + 1
    activeShieldState.lastThreat = {
        shipId = targetShipId,
        sourceName = sourceName,
        isBeam = isBeam
    }

    if isBeam then
        beamDangerTimer[targetShipId] = BEAM_DANGER_DURATION
    else
        projectileDangerTimer[targetShipId] = PROJECTILE_DANGER_DURATION
    end

    return add_super_shield_if_ready(shipManager, sourceName, isBeam)
end

script.on_internal_event(Defines.InternalEvents.DRONE_FIRE, function(projectile, spacedrone)
    if drone_has_active_shield_tag(spacedrone) then
        add_super_shield_from_native_fire(spacedrone)

        if projectile then
            projectile:Kill()
        end

        return Defines.Chain.PREEMPT
    end

    if not projectile then
        return Defines.Chain.CONTINUE
    end

    local targetShipId = get_drone_projectile_target_ship_id(projectile, spacedrone)
    if not targetShipId then
        return Defines.Chain.CONTINUE
    end

    droneProjectileThreats[projectile] = true

    local sourceName = spacedrone and spacedrone.blueprint and spacedrone.blueprint.name or "drone"
    create_threat_shield(targetShipId, false, sourceName)

    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    if not projectile then
        return Defines.Chain.CONTINUE
    end

    local isBeam = weapon and weapon.blueprint and weapon.blueprint.typeName == "BEAM"

    if not isBeam and droneProjectileThreats[projectile] then
        return Defines.Chain.CONTINUE
    end

    local targetShipId = get_projectile_target_ship_id(projectile, isBeam)

    if not targetShipId then
        return Defines.Chain.CONTINUE
    end

    local sourceName = weapon and weapon.blueprint and weapon.blueprint.name or "weapon"
    create_threat_shield(targetShipId, isBeam, sourceName)

    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.DAMAGE_BEAM, function(shipManager, projectile, location, damage, newTile, beamHit)
    if not shipManager then
        return Defines.Chain.CONTINUE, beamHit
    end

    local shipId = shipManager.iShipId

    if projectile and projectile.ownerId == shipId then
        return Defines.Chain.CONTINUE, beamHit
    end

    if create_threat_shield(shipId, true, "DAMAGE_BEAM") then
        return Defines.Chain.PREEMPT, beamHit
    end

    return Defines.Chain.CONTINUE, beamHit
end)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    local shipId = shipManager.iShipId
    local frameTime = Hyperspace.FPS.SpeedFactor / 16

    update_active_shield_cycle_locks(shipManager)

    beamDangerTimer[shipId] = math.max(0, (beamDangerTimer[shipId] or 0) - frameTime)
    projectileDangerTimer[shipId] = math.max(0, (projectileDangerTimer[shipId] or 0) - frameTime)

    if not ship_has_active_shield_drone(shipManager) then return end

    local incomingProjectiles = count_incoming_enemy_projectiles(shipId)
    local hasActiveThreat = incomingProjectiles > 0
        or beamDangerTimer[shipId] > 0
        or projectileDangerTimer[shipId] > 0

    if hasActiveThreat then
        return
    end

    pop_all_super_shields(shipManager)
end)
