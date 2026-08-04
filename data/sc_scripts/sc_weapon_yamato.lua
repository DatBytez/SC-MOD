-- Test No. 1

local userdata_table = mods.multiverse.userdata_table
local vter = mods.multiverse.vter

mods.sc = mods.sc or {}
mods.sc.chainArtillery = mods.sc.chainArtillery or {}

local chainArtillery = mods.sc.chainArtillery

mods.sc.tag.register_tag(
    "sc-chain-artillery",
    chainArtillery
)

local function get_matching_artillery(ship, weapon)
    if not ship or not weapon then
        return nil
    end

    for artillery in vter(ship.artillerySystems) do
        if artillery.projectileFactory == weapon then
            return artillery
        end
    end

    return nil
end

-- -----------------------
-- CHAIN ARTILLERY STATS
-- -----------------------
script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_FIRE,
    function(projectile, weapon)
        local statBoosts = chainArtillery[
            weapon
            and weapon.blueprint
            and weapon.blueprint.name
        ]

        if not statBoosts then
            return
        end

        local ship = Hyperspace.ships(weapon.iShipId)
        if not ship then
            return
        end

        local artillery = get_matching_artillery(
            ship,
            weapon
        )

        if not artillery then
            return
        end

        local power = math.max(
            0,
            artillery:GetEffectivePower() or 0
        )

        for _, statBoost in ipairs(statBoosts) do
            local amount = statBoost.amount or 1

            if statBoost.stat == "accuracyMod" then
                if projectile.extend
                    and projectile.extend.customDamage then

                    local base =
                        projectile.extend.customDamage
                            .accuracyMod
                        or 0

                    projectile.extend.customDamage
                        .accuracyMod =
                        base + power * amount
                end

            elseif statBoost.stat == "shots" then
                mods.sc.apply_chain_artillery_shots(
                    weapon,
                    amount
                )

            elseif statBoost.stat == "radius" then
                -- Handled by the shared weapon-radius modifier below.

            else
                local base =
                    projectile.damage[statBoost.stat]
                    or 0

                projectile.damage[statBoost.stat] =
                    base + power * amount
            end
        end
    end
)

-- -----------------------
-- CHAIN ARTILLERY SHOTS
-- -----------------------
function mods.sc.apply_chain_artillery_shots(
    weapon,
    startingShots
)
    if not weapon or not startingShots then
        return
    end

    local blueprint = weapon.blueprint
    local name = blueprint and blueprint.name

    if not blueprint or not name then
        return
    end

    local ship = Hyperspace.ships(weapon.iShipId)
    if not ship then
        return
    end

    local artillery = get_matching_artillery(
        ship,
        weapon
    )

    if not artillery then
        return
    end

    local weaponData = userdata_table(
        weapon,
        "mods.sc.weaponStuff"
    )

    local key = "shotsFiredThisVolley_" .. name
    weaponData[key] = (weaponData[key] or 0) + 1

    local power = math.max(
        0,
        artillery:GetEffectivePower() or 0
    )

    local cap = blueprint.shots or 1
    local allowedTotal = math.min(
        cap,
        startingShots + power
    )

    if weaponData[key] >= allowedTotal then
        weapon.queuedProjectiles:clear()
    end

    if weapon.queuedProjectiles:size() == 0 then
        weaponData[key] = 0
    end
end

-- ------------------------
-- CHAIN ARTILLERY RADIUS
-- ------------------------
local function apply_chain_artillery_radius(
    ship,
    weapon,
    radius,
    baseRadius
)
    local statBoosts = chainArtillery[
        weapon
        and weapon.blueprint
        and weapon.blueprint.name
    ]

    if not statBoosts then
        return radius
    end

    local artillery = get_matching_artillery(
        ship,
        weapon
    )

    if not artillery then
        return radius
    end

    local perLevel = nil

    for _, statBoost in ipairs(statBoosts) do
        if statBoost.stat == "radius" then
            perLevel = statBoost.amount or 0
            break
        end
    end

    if perLevel == nil then
        return radius
    end

    local power = math.max(
        0,
        artillery:GetEffectivePower() or 0
    )

    return math.max(
        0,
        radius + perLevel * power
    )
end

-- Artillery radius is another scaling contribution, so it runs before pilot
-- and detector modifiers.
mods.sc.scaling.register_weapon_radius_modifier(
    "chain_artillery",
    apply_chain_artillery_radius,
    0
)

-- ------------------------
-- CHAIN ARTILLERY COOLDOWN
-- ------------------------
-- SOURCE: Arc Fishing.lua
-- TODO: Still charges a little while enemy is in stealth. I kinda do not mind.
script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    function(shipManager)
        for artillery in vter(
            shipManager.artillerySystems
        ) do
            if artillery.projectileFactory
                    .blueprint.name
                == "ARTILLERY_YAMATO_LASER" then

                local power = math.max(
                    0,
                    artillery.powerState.first or 0
                )

                local weapon = artillery.projectileFactory

                if power > 0
                    and weapon.cooldown.first
                        ~= weapon.cooldown.second then

                    local powerScale =
                        -0.25 * (power - 2)

                    weapon.cooldown.first = math.max(
                        0,
                        weapon.cooldown.first
                            + powerScale
                            * Hyperspace.FPS.SpeedFactor
                            / 16
                    )
                end
            end
        end
    end
)
