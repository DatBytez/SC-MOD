--[[
DESCRIPTION: Scales the Yamato artillery weapon based on the artillery system's level.
        - Each additional artillery system level adds 1 shot and 5 seconds base cooldown.
TAG: <sc-artillery-level stat="shots" value="#"/>
DEPENDENCIES: sc_tag.lua, sc_projectile_scaling.lua, Multiverse vter
]]

local vter = mods.multiverse.vter
local scaling = mods.sc.scaling

local artilleryLevel = {}

mods.sc.tag.register("weapon",  "sc-artillery-level",  artilleryLevel,  "stat")

local function get_matching_artillery(ship, weapon)
    for artillery in vter(ship.artillerySystems) do
        if artillery.projectileFactory == weapon then
            return artillery
        end
    end
end

local function apply_artillery_level_shots(weapon, startingShots, artillery)

    local systemLevel = artillery.healthState.second

    local allowedTotal = math.min(weapon.blueprint.shots, startingShots + systemLevel - 1)

    scaling.apply_shot_limit(weapon, "artilleryShotsFiredThisVolley", allowedTotal)
end

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(_projectile, weapon)

        local statBoosts = artilleryLevel[weapon.blueprint.name]

        if not statBoosts then
            return
        end

        local artillery = get_matching_artillery(Hyperspace.ships(weapon.iShipId), weapon)

        if not artillery then
            return
        end

        for _, statBoost in ipairs(statBoosts) do
            if statBoost.stat == "shots" then
                apply_artillery_level_shots(weapon, statBoost.value, artillery)
            end
        end
    end
)

local function get_yamato_base_cooldown(systemLevel)
    return 20 + (systemLevel - 1) * 5
end

script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP, function(ship)

        for artillery in vter(ship.artillerySystems) do
            local weapon = artillery.projectileFactory

            if weapon and weapon.blueprint and weapon.blueprint.name
                == "ARTILLERY_YAMATO_LASER" then

                local systemLevel =
                    artillery.healthState.second

                if systemLevel > 0 then
                    weapon.blueprint.cooldown =
                        get_yamato_base_cooldown(
                            systemLevel
                        )
                end
            end
        end
    end
)