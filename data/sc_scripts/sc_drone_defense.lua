--[[
DESCRIPTION: Active shield drones create temporary super shields while threats are incoming.
        - Tagged drones must be deployed, powered, and alive to enable the shield behavior.
        - Incoming projectiles create defensive super shields.
        - Incoming drone projectiles create defensive super shields when fired.
        - Incoming beams create defensive super shields when fired.
        - Threat shields use the active drone's real weapon cooldown.
        - Clears all super shields while an active shield drone is deployed and no enemy projectiles or beams are incoming.
TAG: <sc-active-shield/>
SOURCE CREDIT: TNE_ACTIVE_DRONE_LUA.lua, Fusion drones.lua
]]

local vter = mods.multiverse.vter

mods.sc = mods.sc or {}
mods.sc.activeShield = mods.sc.activeShield or {}

local activeDrones = mods.sc.activeShield

mods.sc.tag.register("drone", "sc-active-shield", activeDrones)

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

local function drone_has_active_shield_tag(drone)
    if not drone or not drone.blueprint then return false end
    return activeDrones[drone.blueprint.name]
end

local function drone_is_active_and_powered(drone)
    return drone_has_active_shield_tag(drone) and drone.deployed and drone.powered and not drone.bDead
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
        if drone_is_active_and_powered(drone) and (drone.weaponCooldown or 0) <= 0 then
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

local function add_super_shield_if_ready(shipManager)
    local defenseDrone = get_ready_active_shield_drone(shipManager)
    if not defenseDrone then return false end

    add_super_shield(shipManager)
    put_active_shield_drone_on_cooldown(defenseDrone)

    return true
end

local function add_super_shields_until(shipManager, desiredSuperShields)
    local shieldSystem = shipManager.shieldSystem
    if not shieldSystem then return end

    local superPower = shieldSystem.shields.power.super
    local currentSuper = superPower.first

    for i = currentSuper + 1, desiredSuperShields do
        if not add_super_shield_if_ready(shipManager) then break end
    end
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

local function get_drone_projectile_target_ship_id(projectile)
    if projectile.ownerId ~= nil and (projectile.ownerId == 0 or projectile.ownerId == 1) then
        return 1 - projectile.ownerId
    end

    return get_projectile_target_ship_id(projectile, true)
end

local function create_threat_shield(targetShipId, isBeam)
    local shipManager = Hyperspace.ships(targetShipId)
    if not shipManager or not shipManager.shieldSystem then return false end
    if not ship_has_active_shield_drone(shipManager) then return false end

    if isBeam then
        beamDangerTimer[targetShipId] = BEAM_DANGER_DURATION
    else
        projectileDangerTimer[targetShipId] = PROJECTILE_DANGER_DURATION
    end

    return add_super_shield_if_ready(shipManager)
end

script.on_internal_event(Defines.InternalEvents.DRONE_FIRE, function(projectile, spacedrone)
    if drone_has_active_shield_tag(spacedrone) then
        if projectile then
            projectile:Kill()
        end

        return Defines.Chain.CONTINUE
    end

    if not projectile then
        return Defines.Chain.CONTINUE
    end

    local targetShipId = get_drone_projectile_target_ship_id(projectile)
    if not targetShipId then
        return Defines.Chain.CONTINUE
    end

    droneProjectileThreats[projectile] = true

    if create_threat_shield(targetShipId, false) then
        projectile:Kill()
        return Defines.Chain.PREEMPT
    end

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

    create_threat_shield(targetShipId, isBeam)

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

    if create_threat_shield(shipId, true) then
        return Defines.Chain.PREEMPT, beamHit
    end

    return Defines.Chain.CONTINUE, beamHit
end)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    local shipId = shipManager.iShipId
    local frameTime = Hyperspace.FPS.SpeedFactor / 16

    beamDangerTimer[shipId] = math.max(0, (beamDangerTimer[shipId] or 0) - frameTime)
    projectileDangerTimer[shipId] = math.max(0, (projectileDangerTimer[shipId] or 0) - frameTime)

    if not ship_has_active_shield_drone(shipManager) then return end

    local incomingProjectiles = count_incoming_enemy_projectiles(shipId)
    local desiredSuperShields = incomingProjectiles

    if beamDangerTimer[shipId] > 0 then
        desiredSuperShields = desiredSuperShields + 1
    end

    if projectileDangerTimer[shipId] > 0 and desiredSuperShields <= 0 then
        desiredSuperShields = 1
    end

    if desiredSuperShields > 0 then
        add_super_shields_until(shipManager, desiredSuperShields)
        return
    end

    pop_all_super_shields(shipManager)
end)
