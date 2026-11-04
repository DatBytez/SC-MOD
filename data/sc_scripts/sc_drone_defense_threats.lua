--[[
DESCRIPTION: Detects incoming threats for Terran Defense Matrix drones.
        - Ship projectiles trigger Defense Matrix when fired.
        - Drone projectiles trigger Defense Matrix when fired.
        - Beams trigger Defense Matrix when fired or when reaching the ship.
        - Native Defense Matrix drone shots are converted into shield activations.
DEPENDENCIES: sc_drone_defense.lua
]]

local defense = mods.sc.defenseMatrix

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

function defense.update_threat_timers(shipId, frameTime)
    beamDangerTimer[shipId] = math.max(0, (beamDangerTimer[shipId] or 0) - frameTime)
    projectileDangerTimer[shipId] = math.max(0, (projectileDangerTimer[shipId] or 0) - frameTime)
end

function defense.has_recent_threat(shipId)
    return beamDangerTimer[shipId] > 0
        or projectileDangerTimer[shipId] > 0
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
    local droneOwnerId = defense.get_owner_id(spacedrone)

    if droneOwnerId == 0 or droneOwnerId == 1 then
        return 1 - droneOwnerId
    end

    if projectile and (projectile.currentSpace == 0 or projectile.currentSpace == 1) then
        return projectile.currentSpace
    end

    return get_projectile_target_ship_id(projectile, true)
end

local function create_threat_shield(targetShipId, isBeam)
    local shipManager = Hyperspace.ships(targetShipId)
    if not shipManager or not shipManager.shieldSystem then return false end
    if not defense.has_active_drone(shipManager) then return false end

    if isBeam then
        beamDangerTimer[targetShipId] = BEAM_DANGER_DURATION
    else
        projectileDangerTimer[targetShipId] = PROJECTILE_DANGER_DURATION
    end

    return defense.activate(shipManager, nil, false)
end

local function add_super_shield_from_native_fire(spacedrone)
    local ownerId = defense.get_owner_id(spacedrone)
    if ownerId ~= 0 and ownerId ~= 1 then return false end

    local shipManager = Hyperspace.ships(ownerId)
    if not shipManager or not shipManager.shieldSystem then return false end

    projectileDangerTimer[ownerId] = PROJECTILE_DANGER_DURATION

    return defense.activate(shipManager, spacedrone, true)
end

script.on_internal_event(Defines.InternalEvents.DRONE_FIRE, function(projectile, spacedrone)
    if defense.has_tag(spacedrone) then
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
    create_threat_shield(targetShipId, false)

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