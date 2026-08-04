-- Test No. 2

--[[
    This code is an almost direct copy of the MV advanced-sensors.lua.
    XML tag functionality was added for SC detector augments.

    Test No. 2 keeps the existing detector accuracy and cloak-charge behavior.
    Detector radius is registered only with the shared weapon-radius system.
]]

local vter = mods.multiverse.vter
local time_increment = mods.multiverse.time_increment

mods.sc = mods.sc or {}
mods.sc.detector = mods.sc.detector or {}
mods.sc.detector.TEST_NUMBER = 2
mods.sc.detectorAugments = mods.sc.detectorAugments or {}

local detectorAugments = mods.sc.detectorAugments

mods.sc.tag.register_augment_flag_tag(
    "sc-detector",
    detectorAugments
)

local function ship_has_sc_detector(ship)
    if not ship then return false end

    for augName, _ in pairs(detectorAugments) do
        if ship:HasAugmentation(augName) > 0 then
            return true
        end
    end

    return false
end

local function weapon_is_missile(weapon)
    if not weapon or not weapon.blueprint then
        return false
    end

    local blueprint = weapon.blueprint

    return blueprint.typeName == "MISSILES"
        or blueprint.type == "MISSILE"
        or blueprint.type == 2
        or blueprint.name == "TERRAN_MISSILE_HALO"
end

local function get_detector_accuracy_bonus(ship, weapon)
    local sensors = ship and ship:GetSystem(7)

    if not ship
        or not sensors
        or not ship_has_sc_detector(ship) then

        return nil
    end

    local accuracyBonus =
        sensors:GetEffectivePower() * 2.5

    if weapon_is_missile(weapon) then
        accuracyBonus = accuracyBonus * 2
    end

    return math.ceil(accuracyBonus)
end

local function apply_detector_radius_modifier(
    ship,
    weapon,
    radius,
    baseRadius
)
    local accuracyBonus =
        get_detector_accuracy_bonus(
            ship,
            weapon
        )

    if not accuracyBonus then
        return radius
    end

    return math.max(
        0,
        radius - accuracyBonus * 4
    )
end

mods.sc.detector.ship_has_detector =
    ship_has_sc_detector

mods.sc.detector.weapon_is_missile =
    weapon_is_missile

mods.sc.detector.get_accuracy_bonus =
    get_detector_accuracy_bonus

mods.sc.detector.apply_radius_modifier =
    apply_detector_radius_modifier

-- Shared scaling loads before this file, so registration is immediate.
mods.sc.scaling.register_weapon_radius_modifier(
    "sc_detector",
    apply_detector_radius_modifier,
    200
)

-- Cloak charging
script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    function(ship)
        local sensors = ship:GetSystem(7)

        if sensors
            and ship.weaponSystem
            and ship.weaponSystem.weapons
            and ship.weaponSystem.iHackEffect < 2 then

            local enemyShip =
                Hyperspace.ships(1 - ship.iShipId)

            local cloakCharge =
                ship_has_sc_detector(ship)
                and enemyShip
                and enemyShip.cloakSystem
                and enemyShip.cloakSystem.bTurnedOn

            if cloakCharge then
                for weapon in vter(
                    ship.weaponSystem.weapons
                ) do
                    if weapon.powered
                        and weapon.subCooldown.second
                            <= weapon.subCooldown.first
                        and not weapon.table[
                            "mods.multiverse.manualDecharge"
                        ] then

                        local oldFirst =
                            weapon.cooldown.first

                        local oldSecond =
                            weapon.cooldown.second

                        weapon.cooldown.first =
                            weapon.cooldown.first
                            + sensors:GetEffectivePower()
                            * 0.25
                            * time_increment()

                        weapon.cooldown.first =
                            math.min(
                                weapon.cooldown.first,
                                weapon.cooldown.second
                            )

                        if weapon.cooldown.second
                                == weapon.cooldown.first
                            and oldFirst < oldSecond
                            and weapon.chargeLevel
                                < weapon.blueprint.chargeLevels then

                            weapon.chargeLevel =
                                weapon.chargeLevel + 1

                            weapon.weaponVisual.boostLevel = 0
                            weapon.weaponVisual.boostAnim
                                :SetCurrentFrame(0)

                            if weapon.chargeLevel
                                < weapon.blueprint.chargeLevels then

                                weapon.cooldown.first = 0
                            end
                        else
                            weapon.subCooldown.first =
                                weapon.subCooldown.first
                                + time_increment()

                            weapon.subCooldown.first =
                                math.min(
                                    weapon.subCooldown.first,
                                    weapon.subCooldown.second
                                )
                        end
                    end
                end
            end
        end
    end
)

-- Bonus accuracy
script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_FIRE,
    function(projectile, weapon)
        local ship =
            Hyperspace.ships(projectile.ownerId)

        local accuracyBonus =
            get_detector_accuracy_bonus(
                ship,
                weapon
            )

        if accuracyBonus
            and projectile.extend
            and projectile.extend.customDamage then

            projectile.extend.customDamage.accuracyMod =
                projectile.extend.customDamage.accuracyMod
                + accuracyBonus
        end
    end
)
