--[[
DESCRIPTION: UI and activation state for the Terran pilot ability.
        - Adds a cloaking-style activation button to the player piloting system.
        - Effect duration increases with piloting system level.
        - Heavy hacking reverses the active-effect timer.
        - When the effect ends, piloting takes ion damage based on system level.
        - Exposes activated state for sc_pilot.lua.
DEPENDENCIES: sc_helpers.lua; sc_pilot.lua reads mods.sc_pilot_button.activated
]]

local helpers = mods.sc.helpers

local PILOT_AUGMENT = "TERRAN_SHIP_ARMOR_LIGHT"
local PILOT_SYSTEM_ID = 6

local BUTTON_OFFSET_X = 34
local BUTTON_OFFSET_Y = -50

local ACTIVATION_TIME = 4.5
local DURATION_BONUS_PER_LEVEL = 1.5
local COOLDOWN_TIME = 1
local COOLDOWN_BONUS_PER_LEVEL = 1

local buttonBase
local buttonCharging
local playerPilotingSystemBox
local currentButtonVisualLevel = 2

local activationTimer = {
    [0] = 1,
    [1] = 1
}

local activated = {
    [0] = false,
    [1] = false
}

local wasActivated = {
    [0] = false,
    [1] = false
}

local currentEffectDuration = {
    [0] = ACTIVATION_TIME,
    [1] = ACTIVATION_TIME
}

mods.sc_pilot_button = mods.sc_pilot_button or {}
mods.sc_pilot_button.activated = activated

local function get_text(textId)
    return Hyperspace.Text:GetText(textId)
end

local function format_text(textId, value)
    return string.gsub(get_text(textId), "\\1", tostring(value))
end

local function has_pilot_augment(ship)
    return helpers.ship_has_augment(ship, PILOT_AUGMENT)
end

local function get_piloting_effect_duration(pilotingSystem)
    return ACTIVATION_TIME
        + (pilotingSystem:GetMaxPower() - 1) * DURATION_BONUS_PER_LEVEL
end

local function get_piloting_cooldown_penalty(pilotingSystem)
    return COOLDOWN_TIME
        + (pilotingSystem:GetMaxPower() - 1) * COOLDOWN_BONUS_PER_LEVEL
end

local function get_piloting_visual_level(pilotingSystem)
    return math.min(4, pilotingSystem:GetMaxPower())
end

local function get_piloting_fill_mask(pilotingSystem)
    local visualLevel = get_piloting_visual_level(pilotingSystem)
    return 10, 66, 20, 19 + (visualLevel - 1) * 12
end

local function rebuild_button_visuals(visualLevel)
    local buttonStyle = "systemUI/button_cloaking" .. visualLevel

    buttonBase = Hyperspace.Resources:CreateImagePrimitiveString(
        buttonStyle .. "_base.png",
        BUTTON_OFFSET_X,
        BUTTON_OFFSET_Y,
        0,
        Graphics.GL_Color(1, 1, 1, 1),
        1,
        false
    )

    buttonCharging = Hyperspace.Resources:CreateImagePrimitiveString(
        buttonStyle .. "_charging_on.png",
        BUTTON_OFFSET_X,
        BUTTON_OFFSET_Y,
        0,
        Graphics.GL_Color(1, 1, 1, 1),
        1,
        false
    )
end

local function rebuild_activate_button(systemBox, pilotingSystem)
    local visualLevel = get_piloting_visual_level(pilotingSystem)
    local activateButton = Hyperspace.Button()

    activateButton:OnInit(
        "systemUI/button_cloaking" .. visualLevel,
        Hyperspace.Point(BUTTON_OFFSET_X, BUTTON_OFFSET_Y)
    )

    activateButton.hitbox.x = 11
    activateButton.hitbox.y = 36
    activateButton.hitbox.w = 20
    activateButton.hitbox.h = 30

    systemBox.table.activateButton = activateButton
    currentButtonVisualLevel = visualLevel

    rebuild_button_visuals(visualLevel)
end

local function refresh_button_style_if_needed(systemBox, pilotingSystem)
    local visualLevel = get_piloting_visual_level(pilotingSystem)

    if visualLevel ~= currentButtonVisualLevel then
        rebuild_activate_button(systemBox, pilotingSystem)
    end
end

local function is_piloting_box(systemBox)
    return systemBox.bPlayerUI
        and systemBox.pSystem.iSystemType == PILOT_SYSTEM_ID
end

local function piloting_ready(pilotingSystem)
    return not pilotingSystem:GetLocked()
        and pilotingSystem:Functioning()
        and pilotingSystem.iHackEffect <= 1
end

local function reset_pilot_state(shipId)
    activationTimer[shipId] = 1
    activated[shipId] = false
    wasActivated[shipId] = false
    currentEffectDuration[shipId] = ACTIVATION_TIME
end

local function reset_all_pilot_state()
    reset_pilot_state(0)
    reset_pilot_state(1)
end

script.on_internal_event(Defines.InternalEvents.CONSTRUCT_SYSTEM_BOX, function(systemBox)
    if not is_piloting_box(systemBox) then return end

    systemBox.extend.xOffset = 54
    playerPilotingSystemBox = systemBox

    rebuild_activate_button(systemBox, systemBox.pSystem)
end)

script.on_internal_event(Defines.InternalEvents.SYSTEM_BOX_MOUSE_MOVE, function(systemBox, x, y)
    if not is_piloting_box(systemBox) then
        return Defines.Chain.CONTINUE
    end

    if not has_pilot_augment(Hyperspace.ships.player) then
        return Defines.Chain.CONTINUE
    end

    systemBox.table.activateButton:MouseMove(
        x - BUTTON_OFFSET_X,
        y - BUTTON_OFFSET_Y,
        false
    )

    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.SYSTEM_BOX_MOUSE_CLICK, function(systemBox)
    if not is_piloting_box(systemBox) then
        return Defines.Chain.CONTINUE
    end

    local shipManager = Hyperspace.ships.player
    if not has_pilot_augment(shipManager) then
        return Defines.Chain.CONTINUE
    end

    local activateButton = systemBox.table.activateButton

    if activateButton.bHover and activateButton.bActive then
        activationTimer[shipManager.iShipId] = 0
        activated[shipManager.iShipId] = true
    end

    return Defines.Chain.CONTINUE
end)

script.on_init(function()
    reset_all_pilot_state()
    currentButtonVisualLevel = 2
    playerPilotingSystemBox = nil
    rebuild_button_visuals(2)
end)

script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, function()
    reset_all_pilot_state()
    currentButtonVisualLevel = 2
end)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    local shipId = shipManager.iShipId

    if not has_pilot_augment(shipManager) then
        reset_pilot_state(shipId)
        return
    end

    local pilotingSystem = shipManager:GetSystem(PILOT_SYSTEM_ID)

    if shipId == 0 and playerPilotingSystemBox then
        refresh_button_style_if_needed(playerPilotingSystemBox, pilotingSystem)
    end

    local effectDuration = get_piloting_effect_duration(pilotingSystem)
    currentEffectDuration[shipId] = effectDuration

    local timerRate = 1 / effectDuration
    if pilotingSystem.iHackEffect > 1 then
        timerRate = -timerRate
    end

    activationTimer[shipId] = math.max(
        0,
        math.min(
            1,
            activationTimer[shipId] + timerRate * Hyperspace.FPS.SpeedFactor / 16
        )
    )

    activated[shipId] = activationTimer[shipId] < 1

    if wasActivated[shipId] and not activated[shipId] then
        local damage = Hyperspace.Damage()
        damage.iIonDamage = get_piloting_cooldown_penalty(pilotingSystem)

        shipManager:DamageArea(
            shipManager:GetRoomCenter(pilotingSystem:GetRoomId()),
            damage,
            true
        )
    end

    wasActivated[shipId] = activated[shipId]
end)

local function piloting_render(systemBox)
    if not is_piloting_box(systemBox) then return end

    local shipManager = Hyperspace.ships.player
    if not has_pilot_augment(shipManager) then return end

    local activateButton = systemBox.table.activateButton
    local pilotingSystem = shipManager:GetSystem(PILOT_SYSTEM_ID)
    local shipId = shipManager.iShipId

    activateButton.bActive =
        piloting_ready(pilotingSystem)
        and pilotingSystem.bManned
        and not activated[shipId]

    if activateButton.bHover
        and not pilotingSystem:GetLocked()
        and not activated[shipId] then

        if not pilotingSystem.bManned then
            Hyperspace.Mouse.tooltip = get_text("tooltip_sc_pilot_manned")
        else
            local effectDuration = string.format(
                "%.1f",
                currentEffectDuration[shipId]
            )

            Hyperspace.Mouse.tooltip = format_text(
                "tooltip_sc_pilot_ready",
                effectDuration
            )
        end

        Hyperspace.Mouse.bForceTooltip = true
    end

    Graphics.CSurface.GL_RenderPrimitive(buttonBase)

    if activated[shipId] then
        local maskX, maskBottomY, maskW, maskH =
            get_piloting_fill_mask(pilotingSystem)

        local height = math.ceil(activationTimer[shipId] * maskH)

        Graphics.CSurface.GL_SetStencilMode(Graphics.STENCIL_SET, 1, 1)
        Graphics.CSurface.GL_DrawRect(
            BUTTON_OFFSET_X + maskX,
            BUTTON_OFFSET_Y - height + maskBottomY,
            maskW,
            height,
            Graphics.GL_Color(1, 1, 1, 1)
        )
        Graphics.CSurface.GL_SetStencilMode(Graphics.STENCIL_USE, 1, 1)
        Graphics.CSurface.GL_RenderPrimitive(buttonCharging)
        Graphics.CSurface.GL_SetStencilMode(Graphics.STENCIL_IGNORE, 1, 1)
    else
        activateButton:OnRender()
    end
end

script.on_render_event(
    Defines.RenderEvents.SYSTEM_BOX,
    function()
        return Defines.Chain.CONTINUE
    end,
    piloting_render
)