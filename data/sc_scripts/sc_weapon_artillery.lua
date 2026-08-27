--[[
DESCRIPTION: Scales tagged artillery weapons based on the artillery system's level.
        - Shot count starts at the tagged value and increases by 1 per artillery level.
        - Base cooldown starts at the blueprint cooldown and changes by the tagged value per artillery level.
TAGS:   <sc-artillery-level stat="shots" value="#"/>
        <sc-artillery-level stat="cooldown" value="#"/>
DEPENDENCIES: sc_tag.lua, sc_weapon_scaling.lua, Multiverse vter
]]

local vter = mods.multiverse.vter
local scaling = mods.sc.scaling

local artilleryLevel = {}
local baseCooldowns = {}

mods.sc.tag.register("weapon", "sc-artillery-level", artilleryLevel, "stat")

local function get_stat_value(statBoosts, statName)
    for _, statBoost in ipairs(statBoosts) do
        if statBoost.stat == statName then
            return statBoost.value
        end
    end
end

local function get_matching_artillery(ship, weapon)
    for artillery in vter(ship.artillerySystems) do
        if artillery.projectileFactory == weapon then
            return artillery
        end
    end
end

local function apply_artillery_level_shots(weapon, startingShots, artillery)
    local allowedTotal = math.min(weapon.blueprint.shots, startingShots + artillery.healthState.second - 1)

    scaling.apply_shot_limit(weapon, "artilleryShotsFiredThisVolley", allowedTotal)
end

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(_projectile, weapon)
        local statBoosts = artilleryLevel[weapon.blueprint.name]
        if not statBoosts then return end

        local startingShots = get_stat_value(statBoosts, "shots")
        if not startingShots then return end

        local artillery = get_matching_artillery(Hyperspace.ships(weapon.iShipId), weapon)
        if not artillery then return end

        apply_artillery_level_shots(weapon, startingShots, artillery)
    end
)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
        for artillery in vter(ship.artillerySystems) do
            local weapon = artillery.projectileFactory
            local weaponName = weapon.blueprint.name
            local statBoosts = artilleryLevel[weaponName]

            if statBoosts then
                local cooldownPerLevel = get_stat_value(statBoosts, "cooldown")

                if cooldownPerLevel then
                    if baseCooldowns[weaponName] == nil then
                        baseCooldowns[weaponName] = weapon.blueprint.cooldown
                    end

                    weapon.blueprint.cooldown = baseCooldowns[weaponName] + (artillery.healthState.second - 1) * cooldownPerLevel
                end
            end
        end
    end
)