--[[
DESCRIPTION: Terran pilot ability behavior and button definition.
        - Registers the pilot ability with the generic button/timer framework.
        - Converts half of current dodge into projectile accuracy while active.
        - Reduces weapon radius and increases projectile speed from that accuracy bonus.
        - Applies the piloting ion penalty when the active timer finishes.
DEPENDENCIES: sc_pilot_ui.lua, sc_helpers.lua, sc_radius_core.lua
]]

mods.sc_accuracy = mods.sc_accuracy or {}
mods.sc_accuracy.dodgeToAccuracy = mods.sc_accuracy.dodgeToAccuracy or {
    [0] = 0,
    [1] = 0
}

mods.sc.pilot = mods.sc.pilot or {}

local helpers = mods.sc.helpers
local buttonTimer = mods.sc.buttonTimer

local PILOT_BUTTON = "terran_pilot"
local PILOT_AUGMENT = "TERRAN_SHIP_ARMOR_LIGHT"
local PILOT_SYSTEM_ID = 6

local BUTTON_OFFSET_X = 34
local BUTTON_OFFSET_Y = -50

local ACTIVATION_TIME = 4.5
local DURATION_BONUS_PER_LEVEL = 1.5
local COOLDOWN_TIME = 1
local COOLDOWN_BONUS_PER_LEVEL = 1
local HACK_TIMER_SPEED_BONUS_PER_LEVEL = 0.5

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

local function get_text(textId)
    return Hyperspace.Text:GetText(textId)
end

local function format_text(textId, value)
    return string.gsub(
        get_text(textId),
        "\\1",
        tostring(value)
    )
end

local function has_pilot_augment(ship)
    return helpers.ship_has_augment(
        ship,
        PILOT_AUGMENT
    )
end

local function get_piloting_effect_duration(
    pilotingSystem
)
    return ACTIVATION_TIME
        + (pilotingSystem:GetMaxPower() - 1)
        * DURATION_BONUS_PER_LEVEL
end

local function get_piloting_cooldown_penalty(
    pilotingSystem
)
    return COOLDOWN_TIME
        + (pilotingSystem:GetMaxPower() - 1)
        * COOLDOWN_BONUS_PER_LEVEL
end

local function pilot_effect_active(ship)
    return buttonTimer.is_active(
        PILOT_BUTTON,
        ship.iShipId
    )
        and has_pilot_augment(ship)
        and ship:GetSystem(
            PILOT_SYSTEM_ID
        ).bManned
end

local function update_accuracy_bonus_from_dodge(
    ship,
    dodge
)
    local shipId = ship.iShipId

    if not pilot_effect_active(ship) then
        mods.sc_accuracy.dodgeToAccuracy[
            shipId
        ] = 0

        return 0
    end

    local effectiveDodge = dodge or 0

    if ship.cloakSystem
        and ship.cloakSystem.bTurnedOn then

        effectiveDodge =
            effectiveDodge + 60
    end

    local removedAmount =
        math.floor(effectiveDodge / 2)

    mods.sc_accuracy.dodgeToAccuracy[
        shipId
    ] = removedAmount

    return removedAmount
end

-- Refreshes the pilot accuracy value immediately, including while paused.
-- ShipManager:GetDodgeFactor() invokes GET_DODGE_FACTOR, so this uses the
-- same dodge source and cloak handling as the normal unpaused calculation.
local function refresh_accuracy_bonus(ship)
    local shipId = ship.iShipId

    if not pilot_effect_active(ship) then
        mods.sc_accuracy.dodgeToAccuracy[
            shipId
        ] = 0

        return 0
    end

    if dodgeRefreshInProgress[shipId] then
        return mods.sc_accuracy
            .dodgeToAccuracy[shipId]
            or 0
    end

    dodgeRefreshInProgress[shipId] =
        true

    local serialBefore =
        dodgeEventSerial[shipId] or 0

    local success, dodge =
        pcall(function()
            return ship:GetDodgeFactor()
        end)

    dodgeRefreshInProgress[shipId] =
        false

    -- GetDodgeFactor normally invokes GET_DODGE_FACTOR, which writes the
    -- exact event value. Use the returned dodge only if that event did not run.
    if success
        and type(dodge) == "number"
        and (dodgeEventSerial[shipId] or 0)
            == serialBefore then

        update_accuracy_bonus_from_dodge(
            ship,
            dodge
        )
    end

    return mods.sc_accuracy
        .dodgeToAccuracy[shipId]
        or 0
end

mods.sc.pilot.refresh_accuracy_bonus =
    refresh_accuracy_bonus

local function get_pilot_button_visuals(
    ship,
    pilotingSystem
)
    local visualLevel =
        math.min(
            4,
            math.floor(
                pilotingSystem:GetMaxPower()
            )
        )

    local buttonStyle =
        string.format(
            "systemUI/button_cloaking%d",
            visualLevel
        )

    return {
        key = visualLevel,
        buttonStyle = buttonStyle,
        baseImage =
            buttonStyle .. "_base.png",
        chargingImage =
            buttonStyle
            .. "_charging_on.png",
        fillMask = {
            x = 10,
            bottomY = 66,
            w = 20,
            h =
                19
                + (visualLevel - 1)
                * 12
        }
    }
end

local function pilot_button_ready(
    ship,
    pilotingSystem
)
    return not pilotingSystem:GetLocked()
        and pilotingSystem:Functioning()
        and pilotingSystem.iHackEffect <= 1
        and pilotingSystem.bManned
end

local function get_pilot_button_tooltip(
    ship,
    pilotingSystem,
    state
)
    if pilotingSystem:GetLocked()
        or state.active then

        return nil
    end

    if not pilotingSystem.bManned then
        return get_text(
            "tooltip_sc_pilot_manned"
        )
    end

    return format_text(
        "tooltip_sc_pilot_ready",
        string.format(
            "%.1f",
            state.duration
        )
    )
end

local function pilot_timer_rate(
    ship,
    pilotingSystem,
    state
)
    local rate = 1 / state.duration

    if pilotingSystem.iHackEffect > 1 then
        local hackingShip =
            Hyperspace.ships(
                1 - ship.iShipId
            )

        local hackingLevel =
            hackingShip.hackingSystem
                :GetEffectivePower()

        rate =
            rate
            * (
                1
                + hackingLevel
                * HACK_TIMER_SPEED_BONUS_PER_LEVEL
            )
    end

    return rate
end

local function clear_pilot_accuracy(ship)
    mods.sc_accuracy.dodgeToAccuracy[
        ship.iShipId
    ] = 0
end

local function finish_pilot_effect(
    ship,
    pilotingSystem
)
    clear_pilot_accuracy(ship)

    local damage = Hyperspace.Damage()

    damage.iIonDamage =
        get_piloting_cooldown_penalty(
            pilotingSystem
        )

    ship:DamageArea(
        ship:GetRoomCenter(
            pilotingSystem:GetRoomId()
        ),
        damage,
        true
    )
end

buttonTimer.register(
    PILOT_BUTTON,
    {
        systemId = PILOT_SYSTEM_ID,
        systemBoxOffset = 54,

        x = BUTTON_OFFSET_X,
        y = BUTTON_OFFSET_Y,

        hitbox = {
            x = 11,
            y = 36,
            w = 20,
            h = 30
        },

        is_visible = function(ship)
            return has_pilot_augment(ship)
        end,

        is_ready =
            pilot_button_ready,

        get_duration =
            function(
                ship,
                pilotingSystem
            )
                return
                    get_piloting_effect_duration(
                        pilotingSystem
                    )
            end,

        get_timer_rate =
            pilot_timer_rate,

        get_visuals =
            get_pilot_button_visuals,

        get_tooltip =
            get_pilot_button_tooltip,

        on_activate =
            function(ship)
                refresh_accuracy_bonus(
                    ship
                )
            end,

        on_deactivate =
            finish_pilot_effect,

        on_reset =
            function(ship)
                clear_pilot_accuracy(
                    ship
                )
            end
    }
)

-- Refresh the dodge-derived accuracy inside the modifier itself so Radius Core
-- remains generic and does not need pilot-specific state handling.
local function apply_pilot_radius_modifier(
    ship,
    weapon,
    radius,
    baseRadius
)
    if not pilot_effect_active(ship) then
        return radius
    end

    local accuracyBonus =
        refresh_accuracy_bonus(ship)

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

mods.sc.radius.register_modifier(
    "pilot_accuracy",
    apply_pilot_radius_modifier,
    100
)

script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_FIRE,
    function(projectile)
        local ship =
            Hyperspace.ships(
                projectile.ownerId
            )

        local shipId =
            projectile.ownerId

        if not pilot_effect_active(ship) then
            mods.sc_accuracy
                .dodgeToAccuracy[
                    shipId
                ] = 0

            return
        end

        local accuracyBonus =
            refresh_accuracy_bonus(ship)

        projectile.extend
            .customDamage
            .accuracyMod =
            projectile.extend
                .customDamage
                .accuracyMod
            + accuracyBonus

        local speedMultiplier =
            1 + accuracyBonus * 0.01

        projectile.speed =
            Hyperspace.Pointf(
                projectile.speed.x
                    * speedMultiplier,
                projectile.speed.y
                    * speedMultiplier
            )

        projectile.speed_magnitude =
            projectile.speed_magnitude
            * speedMultiplier
    end
)

script.on_internal_event(
    Defines.InternalEvents.GET_DODGE_FACTOR,
    function(ship, dodge)
        local shipId = ship.iShipId

        dodgeEventSerial[shipId] =
            (dodgeEventSerial[shipId] or 0)
            + 1

        update_accuracy_bonus_from_dodge(
            ship,
            dodge
        )

        return Defines.Chain.CONTINUE,
            dodge
    end
)

script.on_internal_event(
    Defines.InternalEvents.JUMP_ARRIVE,
    function()
        mods.sc_accuracy
            .dodgeToAccuracy[0] = 0

        mods.sc_accuracy
            .dodgeToAccuracy[1] = 0
    end
)
