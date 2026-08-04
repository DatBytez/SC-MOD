-- Test No. 3

mods.sc_accuracy = mods.sc_accuracy or {}
mods.sc_accuracy.dodgeToAccuracy = mods.sc_accuracy.dodgeToAccuracy or {
    [0] = 0,
    [1] = 0
}

mods.sc = mods.sc or {}
mods.sc.pilot = mods.sc.pilot or {}

local PILOT_AUGMENT = "TERRAN_SHIP_ARMOR_LIGHT"
local PILOT_SYSTEM_ID = 6
local RADIUS_PER_ACCURACY = 1.5
local MIN_RADIUS = 1

local dodgeRefreshInProgress = {
    [0] = false,
    [1] = false
}

local dodgeEventSerial = {
    [0] = 0,
    [1] = 0
}

local function has_pilot_augment(ship)
    return ship
        and ship:HasAugmentation(PILOT_AUGMENT) > 0
end

local function piloting_manned(ship)
    local piloting =
        ship and ship:GetSystem(PILOT_SYSTEM_ID)

    return piloting and piloting.bManned or false
end

local function pilot_effect_active(ship)
    local shipId = ship and ship.iShipId

    return shipId ~= nil
        and mods.sc_pilot_button
        and mods.sc_pilot_button.activated
        and mods.sc_pilot_button.activated[shipId]
        and has_pilot_augment(ship)
        and piloting_manned(ship)
end

local function update_accuracy_bonus_from_dodge(ship, dodge)
    if not ship then
        return 0
    end

    local shipId = ship.iShipId or 0

    if not pilot_effect_active(ship) then
        mods.sc_accuracy.dodgeToAccuracy[shipId] = 0
        return 0
    end

    local effectiveDodge = dodge or 0

    if ship.cloakSystem
        and ship.cloakSystem.bTurnedOn then

        effectiveDodge = effectiveDodge + 60
    end

    local removedAmount =
        math.floor(effectiveDodge / 2)

    mods.sc_accuracy.dodgeToAccuracy[shipId] =
        removedAmount

    return removedAmount
end

-- Refreshes the pilot accuracy value immediately, including while paused.
-- ShipManager:GetDodgeFactor() invokes GET_DODGE_FACTOR, so this uses the
-- same dodge source and cloak handling as the normal unpaused calculation.
local function refresh_accuracy_bonus(ship)
    if not ship then
        return 0
    end

    local shipId = ship.iShipId or 0

    if not pilot_effect_active(ship) then
        mods.sc_accuracy.dodgeToAccuracy[shipId] = 0
        return 0
    end

    if dodgeRefreshInProgress[shipId] then
        return mods.sc_accuracy.dodgeToAccuracy[shipId] or 0
    end

    dodgeRefreshInProgress[shipId] = true

    local serialBefore =
        dodgeEventSerial[shipId] or 0

    local success, dodge = pcall(
        function()
            return ship:GetDodgeFactor()
        end
    )

    dodgeRefreshInProgress[shipId] = false

    -- GetDodgeFactor normally invokes the event below, which already writes
    -- the value using the exact event dodge input. Only use the returned value
    -- as a fallback if the event was not invoked for some reason.
    if success
        and type(dodge) == "number"
        and (dodgeEventSerial[shipId] or 0)
            == serialBefore then

        update_accuracy_bonus_from_dodge(
            ship,
            dodge
        )
    end

    return mods.sc_accuracy.dodgeToAccuracy[shipId] or 0
end

mods.sc.pilot.refresh_accuracy_bonus =
    refresh_accuracy_bonus

-- The legacy radius core and the shared preview calculator both call this
-- exact function, so the pilot result cannot drift between the two systems.
local function apply_pilot_radius_modifier(
    ship,
    weapon,
    radius,
    baseRadius
)
    local shipId = ship and ship.iShipId
    if shipId == nil then
        return radius
    end

    if not pilot_effect_active(ship) then
        return radius
    end

    local accuracyBonus =
        mods.sc_accuracy.dodgeToAccuracy[shipId]
        or 0

    if accuracyBonus <= 0 then
        return radius
    end

    return math.max(
        MIN_RADIUS,
        radius
            - accuracyBonus
            * RADIUS_PER_ACCURACY
    )
end

mods.sc.pilot.apply_radius_modifier =
    apply_pilot_radius_modifier

-- Preserve the currently working radius-core behavior.
mods.sc.radius.register_modifier(
    "pilot_accuracy",
    apply_pilot_radius_modifier
)

local function register_shared_preview_modifier()
    if not mods.sc or not mods.sc.scaling then
        return
    end

    local register =
        mods.sc.scaling.register_weapon_radius_modifier
        or mods.sc.scaling.register_preview_modifier

    if register then
        register(
            "pilot_accuracy",
            apply_pilot_radius_modifier
        )
    end
end

-- This succeeds immediately if the shared file has already loaded. The
-- on_load retry supports the current repository order, where sc_pilot.lua
-- loads before sc_projectile_scaling.lua.
register_shared_preview_modifier()
script.on_load(register_shared_preview_modifier)

script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_FIRE,
    function(projectile, weapon)
        if not projectile
            or not projectile.extend
            or not projectile.extend.customDamage then
            return
        end

        local ship =
            Hyperspace.ships(projectile.ownerId)

        if not ship then return end

        local shipId = projectile.ownerId or 0

        if not pilot_effect_active(ship) then
            mods.sc_accuracy.dodgeToAccuracy[shipId] = 0
            return
        end

        local accuracyBonus =
            refresh_accuracy_bonus(ship)

        projectile.extend.customDamage.accuracyMod =
            projectile.extend.customDamage.accuracyMod
            + accuracyBonus

        local mult = 1.0 + (accuracyBonus * 0.01)
        local speedX = projectile.speed.x
        local speedY = projectile.speed.y

        projectile.speed = Hyperspace.Pointf(
            speedX * mult,
            speedY * mult
        )

        projectile.speed_magnitude =
            projectile.speed_magnitude * mult
    end
)

script.on_internal_event(
    Defines.InternalEvents.GET_DODGE_FACTOR,
    function(shipMgr, dodge)
        if not shipMgr then
            return Defines.Chain.CONTINUE, dodge
        end

        local shipId = shipMgr.iShipId or 0

        dodgeEventSerial[shipId] =
            (dodgeEventSerial[shipId] or 0) + 1

        update_accuracy_bonus_from_dodge(
            shipMgr,
            dodge
        )

        -- dodge = dodge - removedAmount
        return Defines.Chain.CONTINUE, dodge
    end
)
