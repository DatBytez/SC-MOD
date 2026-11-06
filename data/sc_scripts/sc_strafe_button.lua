--[[
DESCRIPTION: Button and timer behavior for the Terran Strafe ability.
        - Adds the Strafe activation button to the system assigned by <sc-strafe>.
        - Effect duration increases with the assigned system's level.
        - Heavy hacking of the assigned system accelerates the active timer.
        - Applies the assigned system's ion penalty when the effect finishes.
        - Piloting must be manned to activate Strafe.
DEPENDENCIES: sc_strafe.lua, sc_button_ui.lua
]]

local strafe = mods.sc.strafe
local buttonTimer = mods.sc.buttonTimer

local STRAFE_BUTTON = strafe.BUTTON_NAME
local PILOT_SYSTEM_ID = strafe.PILOT_SYSTEM_ID

local BUTTON_OFFSET_X = 34
local BUTTON_OFFSET_Y = -50

local ACTIVATION_TIME = 4.5
local DURATION_BONUS_PER_LEVEL = 1.5
local COOLDOWN_TIME = 1
local COOLDOWN_BONUS_PER_LEVEL = 1
local HACK_TIMER_SPEED_BONUS_PER_LEVEL = 0.5

local function get_strafe_button_visuals(ship, strafeSystem)
    local visualLevel = math.min(4, math.floor(strafeSystem:GetMaxPower()))
    local buttonStyle = string.format("systemUI/button_cloaking%d", visualLevel)

    return {
        key = visualLevel, buttonStyle = buttonStyle,
        baseImage = buttonStyle .. "_base.png",
        chargingImage = buttonStyle .. "_charging_on.png",
        fillMask = { x = 10, bottomY = 66, w = 20, h = 19 + (visualLevel - 1) * 12 }
    }
end

local function strafe_button_ready(ship, strafeSystem)
    local pilotingSystem = ship:GetSystem(PILOT_SYSTEM_ID)

    return pilotingSystem
        and pilotingSystem.bManned
        and not strafeSystem:GetLocked()
        and strafeSystem:Functioning()
        and strafeSystem.iHackEffect <= 1
end

local function get_strafe_button_tooltip(ship, strafeSystem, state)
    if strafeSystem:GetLocked() or state.active then return end

    local pilotingSystem = ship:GetSystem(PILOT_SYSTEM_ID)

    if not pilotingSystem or not pilotingSystem.bManned then
        return Hyperspace.Text:GetText("tooltip_sc_strafe_manned")
    end

    return string.gsub(Hyperspace.Text:GetText("tooltip_sc_strafe_ready"), "\\1", string.format("%.1f", state.duration))
end

local function strafe_timer_rate(ship, strafeSystem, state)
    local rate = 1 / state.duration

    if strafeSystem.iHackEffect > 1 then
        local hackingShip = Hyperspace.ships(1 - ship.iShipId)
        local hackingLevel = hackingShip.hackingSystem:GetEffectivePower()

        rate = rate * (1 + hackingLevel * HACK_TIMER_SPEED_BONUS_PER_LEVEL)
    end

    return rate
end

local function finish_strafe_effect(ship, strafeSystem)
    strafe.clear_accuracy(ship)

    local damage = Hyperspace.Damage()
    damage.iIonDamage = COOLDOWN_TIME + (strafeSystem:GetMaxPower() - 1) * COOLDOWN_BONUS_PER_LEVEL

    ship:DamageArea(ship:GetRoomCenter(strafeSystem:GetRoomId()), damage, true)
end

buttonTimer.register(STRAFE_BUTTON, {
    systemId = strafe.get_system_id,
    systemBoxOffset = 54,

    x = BUTTON_OFFSET_X,
    y = BUTTON_OFFSET_Y,

    hitbox = { x = 11, y = 36, w = 20, h = 30 },

    is_visible = strafe.has_augment,

    is_ready = strafe_button_ready,

    get_duration = function(ship, strafeSystem)
        return ACTIVATION_TIME + (strafeSystem:GetMaxPower() - 1) * DURATION_BONUS_PER_LEVEL
    end,

    get_timer_rate = strafe_timer_rate,
    get_visuals = get_strafe_button_visuals,
    get_tooltip = get_strafe_button_tooltip,

    on_activate = function(ship)
        strafe.refresh_accuracy(ship)
    end,

    on_deactivate = finish_strafe_effect,

    on_reset = function(ship)
        strafe.clear_accuracy(ship)
    end
})