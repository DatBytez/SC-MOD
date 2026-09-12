--[[
DESCRIPTION: Minimal beam-fire diagnostic.
    Diagnostic only; gameplay logic does not depend on this file.

PURPOSE:
    Test which hooks can identify when beam weapons are firing or actively hitting.
    Expected console output:
        FRIENDLY BEAM (source)
        ENEMY BEAM (source)

NOTES:
    - FRIENDLY means projectile ownerId == 0.
    - ENEMY means projectile ownerId == 1.
    - DAMAGE_BEAM is a reactive source: it confirms a beam is interacting with a ship,
      but it may occur after the first beam damage step has begun.
]]

mods.sc_beam_debug = mods.sc_beam_debug or {}
local debug = mods.sc_beam_debug

debug.seen = debug.seen or {}

local function run_has_started()
    return Hyperspace.App
        and Hyperspace.App.world
        and Hyperspace.App.world.bStartedGame
end

local function safe_get(root, key)
    if root == nil then return nil end

    local ok, value = pcall(function()
        return root[key]
    end)

    if not ok then return nil end
    return value
end

local function safe_projectile_type(projectile)
    if not projectile then return nil end

    local ok, value = pcall(function()
        return projectile:GetType()
    end)

    if not ok then return nil end
    return value
end

local function safe_drone_owner_id(drone)
    if not drone then return nil end

    local ok, ownerId = pcall(function()
        return drone:GetOwnerId()
    end)

    if not ok then return nil end
    return ownerId
end

local function get_projectile_name(projectile)
    local extend = safe_get(projectile, "extend")
    return safe_get(extend, "name") or "UNKNOWN_PROJECTILE"
end

local function get_weapon_name(weapon)
    local blueprint = safe_get(weapon, "blueprint")
    return safe_get(blueprint, "name") or "UNKNOWN_WEAPON"
end

local function get_owner_id(projectile, weapon, drone, shipManager)
    local ownerId = safe_get(projectile, "ownerId")

    if ownerId == nil then
        ownerId = safe_get(weapon, "iShipId")
    end

    if ownerId == nil then
        ownerId = safe_drone_owner_id(drone)
    end

    -- DAMAGE_BEAM fallback: if a beam is hitting player ship 0, assume enemy owner;
    -- if hitting enemy ship 1, assume friendly owner.
    if ownerId == nil and shipManager and shipManager.iShipId ~= nil then
        ownerId = 1 - shipManager.iShipId
    end

    return tonumber(ownerId)
end

local function get_beam_side(projectile, weapon, drone, shipManager)
    local ownerId = get_owner_id(projectile, weapon, drone, shipManager)

    if ownerId == 0 then return "FRIENDLY" end
    if ownerId == 1 then return "ENEMY" end

    return "UNKNOWN"
end

local function log_beam(source, projectile, weapon, drone, shipManager)
    if not run_has_started() then return end

    local side = get_beam_side(projectile, weapon, drone, shipManager)
    local weaponName = weapon and get_weapon_name(weapon) or get_projectile_name(projectile)
    local projectileKey = tostring(projectile or weapon or drone or "no-object")
    local key = source .. "|" .. side .. "|" .. weaponName .. "|" .. projectileKey

    -- DAMAGE_BEAM can fire repeatedly while the same beam crosses tiles/rooms.
    -- Keep one print per source/projectile so the console stays readable.
    if debug.seen[key] then return end
    debug.seen[key] = true

    print(side .. " BEAM (" .. source .. ")")
end

local function weapon_is_beam_by_blueprint_type(weapon)
    local blueprint = safe_get(weapon, "blueprint")
    return safe_get(blueprint, "typeName") == "BEAM"
end

local function projectile_is_beam_by_type(projectile)
    return safe_projectile_type(projectile) == 5
end

local function beam_hit_is_new_tile_or_room(beamHitType)
    return beamHitType == Defines.BeamHit.NEW_TILE
        or beamHitType == Defines.BeamHit.NEW_ROOM
end

-- Source 1: Weapon blueprint typeName.
-- This should catch normal weapon/projectile firing as early as PROJECTILE_FIRE.
script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    if weapon_is_beam_by_blueprint_type(weapon) then
        log_beam("projectile-fire-weapon-type", projectile, weapon, nil, nil)
    end

    return Defines.Chain.CONTINUE
end)

-- Source 2: Projectile:GetType() == 5.
-- Fusion scripts use projectile:GetType() == 5 as a beam check.
script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    if projectile_is_beam_by_type(projectile) then
        log_beam("projectile-fire-projectile-type-5", projectile, weapon, nil, nil)
    end

    return Defines.Chain.CONTINUE
end)

-- Source 3: Drone-fire projectile type.
-- This helps test whether beam drones bypass normal weapon-based PROJECTILE_FIRE checks.
script.on_internal_event(Defines.InternalEvents.DRONE_FIRE, function(projectile, drone)
    if projectile_is_beam_by_type(projectile) then
        log_beam("drone-fire-projectile-type-5", projectile, nil, drone, nil)
    end

    return Defines.Chain.CONTINUE
end)

-- Source 4: DAMAGE_BEAM.
-- This is not a pure firing detector; it confirms an active beam hit on a ship.
script.on_internal_event(Defines.InternalEvents.DAMAGE_BEAM, function(shipManager, projectile, location, damage, realNewTile, beamHitType)
    if projectile_is_beam_by_type(projectile) and beam_hit_is_new_tile_or_room(beamHitType) then
        log_beam("damage-beam-new-tile-room", projectile, nil, nil, shipManager)
    end

    return Defines.Chain.CONTINUE, beamHitType
end)
