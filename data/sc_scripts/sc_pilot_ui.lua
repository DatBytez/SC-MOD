mods.sc_pilot_button = mods.sc_pilot_button or {}
mods.sc = mods.sc or {}
local helpers = mods.sc.helpers

local PILOT_AUGMENT = "TERRAN_SHIP_ARMOR_LIGHT"
local PILOT_SYSTEM_ID = 6
local pilotingButtonOffset_x = 34
local pilotingButtonOffset_y = -50

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

local ACTIVATION_TIME = 4.5
local DURATION_BONUS_PER_LEVEL = 1.5
local COOLDOWN_TIME = 1
local COOLDOWN_BONUS_PER_LEVEL = 1

local currentEffectDuration = {
    [0] = ACTIVATION_TIME,
    [1] = ACTIVATION_TIME
}

mods.sc_pilot_button.activated = activated
mods.sc_pilot_button.activationTimer = activationTimer
mods.sc_pilot_button.wasActivated = wasActivated
mods.sc_pilot_button.currentEffectDuration = currentEffectDuration
mods.sc_pilot_button.ACTIVATION_TIME = ACTIVATION_TIME
mods.sc_pilot_button.DURATION_BONUS_PER_LEVEL = DURATION_BONUS_PER_LEVEL


local function get_text(textId)
    return Hyperspace.Text:GetText(textId)
end

local function format_text(textId, value)
    local text = get_text(textId)
    return string.gsub(text, "\\1", tostring(value))
end

local function has_pilot_augment(ship)
    return helpers.ship_has_augment(ship, PILOT_AUGMENT)
end

local function get_piloting_effect_duration(shipSystem)
    if not shipSystem then
        return ACTIVATION_TIME
    end

    local systemLevel = shipSystem:GetMaxPower() or 1
    return ACTIVATION_TIME + math.max(0, systemLevel - 1) * DURATION_BONUS_PER_LEVEL
end

local function get_piloting_cooldown_penalty(shipSystem)
    if not shipSystem then
        return COOLDOWN_TIME
    end

    local systemLevel = shipSystem:GetMaxPower() or 1
    return COOLDOWN_TIME + math.max(0, systemLevel - 1) * COOLDOWN_BONUS_PER_LEVEL
end

local function get_piloting_visual_level(shipSystem)
    if not shipSystem then
        return 2
    end

    local systemLevel = shipSystem:GetMaxPower() or 1

    if systemLevel <= 1 then
        return 1
    elseif systemLevel == 2 then
        return 2
    elseif systemLevel == 3 then
        return 3
    else
        return 4
    end
end


local function get_piloting_fill_mask(shipSystem)
    local visualLevel = get_piloting_visual_level(shipSystem)

    if visualLevel == 1 then
        return 10, 66, 20, 19
    elseif visualLevel == 2 then
        return 10, 66, 20, 31
    elseif visualLevel == 3 then
        return 10, 66, 20, 43
    else
        return 10, 66, 20, 55
    end
end

local function get_piloting_button_style(shipSystem)
    local visualLevel = get_piloting_visual_level(shipSystem)

    if visualLevel == 1 then
        return "systemUI/button_cloaking1", 1
    elseif visualLevel == 2 then
        return "systemUI/button_cloaking2", 2
    elseif visualLevel == 3 then
        return "systemUI/button_cloaking3", 3
    else
        return "systemUI/button_cloaking4", 4
    end
end

local function get_piloting_button_files(shipSystem)
    local visualLevel = get_piloting_visual_level(shipSystem)

    if visualLevel == 1 then
        return "systemUI/button_cloaking1_base.png", "systemUI/button_cloaking1_charging_on.png", 1
    elseif visualLevel == 2 then
        return "systemUI/button_cloaking2_base.png", "systemUI/button_cloaking2_charging_on.png", 2
    elseif visualLevel == 3 then
        return "systemUI/button_cloaking3_base.png", "systemUI/button_cloaking3_charging_on.png", 3
    else
        return "systemUI/button_cloaking4_base.png", "systemUI/button_cloaking4_charging_on.png", 4
    end
end

local function rebuild_button_visuals(shipSystem)
    local baseFile, chargingFile = get_piloting_button_files(shipSystem)

    buttonBase = Hyperspace.Resources:CreateImagePrimitiveString(
        baseFile,
        pilotingButtonOffset_x,
        pilotingButtonOffset_y,
        0,
        Graphics.GL_Color(1, 1, 1, 1),
        1,
        false
    )

    buttonCharging = Hyperspace.Resources:CreateImagePrimitiveString(
        chargingFile,
        pilotingButtonOffset_x,
        pilotingButtonOffset_y,
        0,
        Graphics.GL_Color(1, 1, 1, 1),
        1,
        false
    )
end

local function rebuild_activate_button(systemBox, shipSystem)
    if not systemBox then
        return
    end

    local buttonStyle, visualLevel = get_piloting_button_style(shipSystem)

    local activateButton = Hyperspace.Button()
    activateButton:OnInit(
        buttonStyle,
        Hyperspace.Point(pilotingButtonOffset_x, pilotingButtonOffset_y)
    )
    activateButton.hitbox.x = 11
    activateButton.hitbox.y = 36
    activateButton.hitbox.w = 20
    activateButton.hitbox.h = 30

    systemBox.table.activateButton = activateButton
    currentButtonVisualLevel = visualLevel

    rebuild_button_visuals(shipSystem)
end

local function refresh_button_style_if_needed(systemBox, shipSystem)
    local visualLevel = get_piloting_visual_level(shipSystem)

    if visualLevel ~= currentButtonVisualLevel or not systemBox.table.activateButton then
        rebuild_activate_button(systemBox, shipSystem)
    end
end

local function is_piloting_box(systemBox)
    return systemBox
        and systemBox.pSystem
        and systemBox.bPlayerUI
        and systemBox.pSystem.iSystemType == PILOT_SYSTEM_ID
end

local function piloting_ready(shipSystem)
    return shipSystem
        and not shipSystem:GetLocked()
        and shipSystem:Functioning()
        and shipSystem.iHackEffect <= 1
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

local function piloting_construct_system_box(systemBox)
    if is_piloting_box(systemBox) then
        systemBox.extend.xOffset = 54

        playerPilotingSystemBox = systemBox

        local shipManager = Hyperspace.ships.player
        local pilotingSystem = shipManager and shipManager:GetSystem(PILOT_SYSTEM_ID)
        rebuild_activate_button(systemBox, pilotingSystem)
    end
end

script.on_internal_event(Defines.InternalEvents.CONSTRUCT_SYSTEM_BOX, piloting_construct_system_box)

local function piloting_mouse_move(systemBox, x, y)
    if is_piloting_box(systemBox) then
        local shipManager = Hyperspace.ships.player
        if not has_pilot_augment(shipManager) then
            return Defines.Chain.CONTINUE
        end

        local activateButton = systemBox.table.activateButton
        if activateButton then
            activateButton:MouseMove(
                x - pilotingButtonOffset_x,
                y - pilotingButtonOffset_y,
                false
            )
        end
    end
    return Defines.Chain.CONTINUE
end

script.on_internal_event(Defines.InternalEvents.SYSTEM_BOX_MOUSE_MOVE, piloting_mouse_move)

local function piloting_click(systemBox, shift)
    if is_piloting_box(systemBox) then
        local activateButton = systemBox.table.activateButton
        local shipManager = Hyperspace.ships.player
        if not shipManager or not has_pilot_augment(shipManager) then
            return Defines.Chain.CONTINUE
        end

        local shipId = shipManager.iShipId or 0
        local pilotingSystem = shipManager:GetSystem(PILOT_SYSTEM_ID)
        if not pilotingSystem then return Defines.Chain.CONTINUE end

        if activateButton and activateButton.bHover and activateButton.bActive then
            activationTimer[shipId] = 0
            activated[shipId] = true
        end
    end
    return Defines.Chain.CONTINUE
end

script.on_internal_event(Defines.InternalEvents.SYSTEM_BOX_MOUSE_CLICK, piloting_click)

script.on_init(function()
    rebuild_button_visuals(nil)
    reset_all_pilot_state()
    currentButtonVisualLevel = 2
    playerPilotingSystemBox = nil
end)

script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, function(shipManager)
    reset_all_pilot_state()
    currentButtonVisualLevel = 2
end)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if not shipManager then return end

    local shipId = shipManager.iShipId or 0
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
    local multiplier = 1 / effectDuration

    if pilotingSystem.iHackEffect > 1 then
        multiplier = multiplier * -1
    end

    activationTimer[shipId] = math.max(
        0,
        math.min(
            1,
            activationTimer[shipId] + multiplier * Hyperspace.FPS.SpeedFactor / 16
        )
    )

    activated[shipId] = activationTimer[shipId] < 1

    if wasActivated[shipId] and not activated[shipId] then
        local dmg = Hyperspace.Damage()
        dmg.iIonDamage = get_piloting_cooldown_penalty(pilotingSystem)
        shipManager:DamageArea(shipManager:GetRoomCenter(pilotingSystem:GetRoomId()), dmg, true)
    end

    wasActivated[shipId] = activated[shipId]
end)

local function piloting_render(systemBox, ignoreStatus)
    if is_piloting_box(systemBox) then
        local activateButton = systemBox.table.activateButton
        if not activateButton then return end

        local shipManager = Hyperspace.ships.player
        if not shipManager or not has_pilot_augment(shipManager) then return end

        local pilotingSystem = shipManager:GetSystem(PILOT_SYSTEM_ID)
        local shipId = shipManager.iShipId or 0

        activateButton.bActive =
            piloting_ready(pilotingSystem)
            and pilotingSystem.bManned
            and not activated[shipId]

        if activateButton.bHover and not pilotingSystem:GetLocked() and not activated[shipId] then
            Hyperspace.Mouse.bForceTooltip = true
            local effectDuration = string.format("%.1f", currentEffectDuration[shipId] or ACTIVATION_TIME)
            if not pilotingSystem.bManned then
                Hyperspace.Mouse.tooltip = get_text("tooltip_sc_pilot_manned")
            else
                Hyperspace.Mouse.tooltip = format_text("tooltip_sc_pilot_ready", effectDuration)
            end
        end

        Graphics.CSurface.GL_RenderPrimitive(buttonBase)

        if activated[shipId] then
            local maskX, maskBottomY, maskW, maskH = get_piloting_fill_mask(pilotingSystem)
            local height = math.ceil(activationTimer[shipId] * maskH)

            Graphics.CSurface.GL_SetStencilMode(Graphics.STENCIL_SET, 1, 1)
            Graphics.CSurface.GL_DrawRect(
                pilotingButtonOffset_x + maskX,
                pilotingButtonOffset_y - height + maskBottomY,
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
end

script.on_render_event(
    Defines.RenderEvents.SYSTEM_BOX,
    function(systemBox, ignoreStatus)
        return Defines.Chain.CONTINUE
    end,
    piloting_render
)
