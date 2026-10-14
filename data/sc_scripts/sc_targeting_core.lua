--[[
DESCRIPTION: Shared accuracy and targeting-radius effects for Detector-style sources.
        - Adds projectile accuracy and reduces weapon targeting radius.
DEPENDENCIES: sc_radius_core.lua
]]

mods.sc.targeting = mods.sc.targeting or {}
local targeting = mods.sc.targeting

local ACCURACY_PER_STRENGTH = 2.5
local MISSILE_ACCURACY_MULTIPLIER = 2
local RADIUS_REDUCTION_PER_ACCURACY = 4

local sources = {}

function targeting.register_source(name, strengthProvider)
    sources[name] = strengthProvider
end

local function get_strength(ship)
    if not ship then return nil end

    local strongest

    for _, provider in pairs(sources) do
        local strength = provider(ship)

        if strength ~= nil and (strongest == nil or strength > strongest) then
            strongest = strength
        end
    end

    return strongest
end

local function weapon_is_missile(weapon)
    return weapon.blueprint.typeName == "MISSILES"
        or weapon.blueprint.name == "TERRAN_MISSILE_HALO"
end

local function get_accuracy_bonus(ship, weapon)
    local strength = get_strength(ship)
    if strength == nil then return nil end

    local accuracyBonus = strength * ACCURACY_PER_STRENGTH

    if weapon_is_missile(weapon) then
        accuracyBonus = accuracyBonus * MISSILE_ACCURACY_MULTIPLIER
    end

    return math.ceil(accuracyBonus)
end

mods.sc.radius.register_modifier("sc_targeting", function(ship, weapon, radius)
    local accuracyBonus = get_accuracy_bonus(ship, weapon)
    if accuracyBonus == nil then return radius end

    return math.max(0, radius - accuracyBonus * RADIUS_REDUCTION_PER_ACCURACY)
end, 200)

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    local accuracyBonus = get_accuracy_bonus(Hyperspace.ships(projectile.ownerId), weapon)
    if accuracyBonus == nil then return end

    projectile.extend.customDamage.accuracyMod = projectile.extend.customDamage.accuracyMod + accuracyBonus
end)
