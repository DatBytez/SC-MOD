--[[
DESCRIPTION: Button and timer behavior for the Terran pilot ability.
        - Adds the pilot activation button through the generic button framework.
        - Effect duration increases with Piloting system level.
        - Heavy hacking accelerates the active timer.
        - Applies the Piloting ion penalty when the effect finishes.
DEPENDENCIES: sc_pilot.lua, sc_button_ui.lua
]]

local pilot = mods.sc.pilot
local buttonTimer = mods.sc.buttonTimer

local PILOT_BUTTON = pilot.BUTTON_NAME
local PILOT_SYSTEM_ID = pilot.SYSTEM_ID

local BUTTON_OFFSET_X = 34
local BUTTON_OFFSET_Y = -50

local ACTIVATION_TIME = 4.5
local DURATION_BONUS_PER_LEVEL = 1.5
local COOLDOWN_TIME = 1
local COOLDOWN_BONUS_PER_LEVEL = 1
local HACK_TIMER_SPEED_BONUS_PER_LEVEL = 0.5

local function get_text(textId)
    return Hyperspace.Text:GetText(textId)
end

local function format_text(textId, value)
    return string.gsub(get_text(textId), "\\1", tostring(value))
end

local function get_piloting_effect_duration(pilotingSystem)
    return ACTIVATION_TIME
        + (pilotingSystem:GetMaxPower() - 1) * DURATION_BONUS_PER_LEVEL
end

local function get_piloting_cooldown_penalty(pilotingSystem)
    return COOLDOWN_TIME
        + (pilotingSystem:GetMaxPower() - 1) * COOLDOWN_BONUS_PER_LEVEL
end

local function get_pilot_button_visuals(ship, pilotingSystem)
    local visualLevel = math.min(4, math.floor(pilotingSystem:GetMaxPower()))
    local buttonStyle = string.format("systemUI/button_cloaking%d", visualLevel)

    return {
        key = visualLevel, buttonStyle = buttonStyle, 
        baseImage = buttonStyle .. "_base.png",
        chargingImage = buttonStyle .. "_charging_on.png",
        fillMask = { x = 10, bottomY = 66, w = 20, h = 19 + (visualLevel - 1) * 12 }
    }
end

local function pilot_button_ready(ship, pilotingSystem)
    return not pilotingSystem:GetLocked()
        and pilotingSystem:Functioning()
        and pilotingSystem.iHackEffect <= 1
        and pilotingSystem.bManned
end

local function get_pilot_button_tooltip(ship, pilotingSystem, state)
    if pilotingSystem:GetLocked() or state.active then
        return nil
    end

    if not pilotingSystem.bManned then
        return get_text("tooltip_sc_pilot_manned")
    end

    return format_text(
        "tooltip_sc_pilot_ready",
        string.format("%.1f", state.duration)
    )
end

local function pilot_timer_rate(ship, pilotingSystem, state)
    local rate = 1 / state.duration

    if pilotingSystem.iHackEffect > 1 then
        local hackingShip = Hyperspace.ships(1 - ship.iShipId)
        local hackingLevel = hackingShip.hackingSystem:GetEffectivePower()

        rate = rate * (1 + hackingLevel * HACK_TIMER_SPEED_BONUS_PER_LEVEL)
    end

    return rate
end

local function finish_pilot_effect(ship, pilotingSystem)
    pilot.clear_accuracy(ship)

    local damage = Hyperspace.Damage()
    damage.iIonDamage = get_piloting_cooldown_penalty(pilotingSystem)

    ship:DamageArea(
        ship:GetRoomCenter(pilotingSystem:GetRoomId()),
        damage,
        true
    )
end

buttonTimer.register(PILOT_BUTTON, {
    systemId = PILOT_SYSTEM_ID,
    systemBoxOffset = 54,

    x = BUTTON_OFFSET_X,
    y = BUTTON_OFFSET_Y,

    hitbox = { x = 11, y = 36, w = 20, h = 30 },

    is_visible = function(ship)
        return pilot.has_augment(ship)
    end,

    is_ready = pilot_button_ready,

    get_duration = function(ship, pilotingSystem)
        return get_piloting_effect_duration(pilotingSystem)
    end,

    get_timer_rate = pilot_timer_rate,
    get_visuals = get_pilot_button_visuals,
    get_tooltip = get_pilot_button_tooltip,

    on_activate = function(ship)
        pilot.refresh_accuracy(ship)
    end,

    on_deactivate = finish_pilot_effect,

    on_reset = function(ship)
        pilot.clear_accuracy(ship)
    end
})