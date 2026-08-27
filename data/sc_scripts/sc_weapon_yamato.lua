--[[
DESCRIPTION: Scales the Yamato artillery weapon based on the artillery system's installed level.
        - Level 1: 2 shots, 20 second base cooldown.
        - Each additional artillery system level adds 1 shot and 5 seconds base cooldown.
        - Artillery power is left entirely to FTL's normal cooldown scaling.
TAG: <sc-artillery-level stat="shots" value="#"/>
DEPENDENCIES: sc_tag.lua, Multiverse userdata_table, Multiverse vter
]]

local userdata_table = mods.multiverse.userdata_table
local vter = mods.multiverse.vter

local artilleryLevel = {}

mods.sc.tag.register(
    "weapon",
    "sc-artillery-level",
    artilleryLevel,
    "stat"
)

local function get_matching_artillery(ship, weapon)
    for artillery in vter(ship.artillerySystems) do
        if artillery.projectileFactory == weapon then
            return artillery
        end
    end
end

-- ------------------------
-- ARTILLERY LEVEL SHOTS
-- ------------------------

local function apply_artillery_level_shots(
    weapon,
    startingShots,
    artillery
)
    local weaponData =
        userdata_table(
            weapon,
            "mods.sc.weaponStuff"
        )

    weaponData.shotsFiredThisVolley =
        (weaponData.shotsFiredThisVolley or 0) + 1

    -- healthState.second represents the installed/max system level.
    --
    -- Level 1 = startingShots
    -- Level 2 = startingShots + 1
    -- Level 3 = startingShots + 2
    -- Level 4 = startingShots + 3
    local systemLevel = artillery.healthState.second

    local allowedTotal =
        math.min(
            weapon.blueprint.shots,
            startingShots + systemLevel - 1
        )

    if weaponData.shotsFiredThisVolley >= allowedTotal then
        weapon.queuedProjectiles:clear()
    end

    if weapon.queuedProjectiles:size() == 0 then
        weaponData.shotsFiredThisVolley = 0
    end
end

script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_FIRE,
    function(_projectile, weapon)

        local statBoosts =
            artilleryLevel[weapon.blueprint.name]

        if not statBoosts then
            return
        end

        local artillery =
            get_matching_artillery(
                Hyperspace.ships(weapon.iShipId),
                weapon
            )

        if not artillery then
            return
        end

        for _, statBoost in ipairs(statBoosts) do
            if statBoost.stat == "shots" then
                apply_artillery_level_shots(
                    weapon,
                    statBoost.value,
                    artillery
                )
            end
        end
    end
)

-- ------------------------
-- YAMATO BASE COOLDOWN
-- ------------------------

local function get_yamato_base_cooldown(systemLevel)
    return 20 + (systemLevel - 1) * 5
end

script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    function(ship)

        for artillery in vter(ship.artillerySystems) do
            local weapon = artillery.projectileFactory

            if weapon
            and weapon.blueprint
            and weapon.blueprint.name
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