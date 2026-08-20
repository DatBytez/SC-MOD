--[[
DESCRIPTION: Generic system-box button and timer framework.
        - Registered buttons attach to a player system box.
        - Handles mouse input, timer progress, active state, and button rendering.
        - Registering scripts define visibility, readiness, duration, visuals,
          tooltips, timer behavior, and activation/deactivation effects.
]]

mods.sc.buttonTimer = mods.sc.buttonTimer or {}

local buttonTimer = mods.sc.buttonTimer
local buttons = {}
local buttonOrder = {}

local function new_state()
    return {timer = 1, active = false, duration = 1}
end

local function reset_all_states()
    for _, button in ipairs(buttonOrder) do
        button.state[0] = new_state()
        button.state[1] = new_state()
    end
end

local function set_active(button, ship, shipSystem, active)
    local state = button.state[ship.iShipId]
    if state.active == active then return end

    state.active = active

    if active and button.on_activate then
        button.on_activate(ship, shipSystem, state)
    elseif not active and button.on_deactivate then
        button.on_deactivate(ship, shipSystem, state)
    end
end

function buttonTimer.register(name, button)
    button.name = name
    button.state = {
        [0] = new_state(),
        [1] = new_state()
    }
    button.runtime = {}

    buttons[name] = button
    buttonOrder[#buttonOrder + 1] = button
end

function buttonTimer.is_active(name, shipId)
    return buttons[name].state[shipId].active
end

function buttonTimer.activate(name, ship)
    local button = buttons[name]
    local shipSystem = ship:GetSystem(button.systemId)

    if not shipSystem or not button.is_visible(ship, shipSystem) then
        return false
    end

    local state = button.state[ship.iShipId]

    if state.active or not button.is_ready(ship, shipSystem, state) then
        return false
    end

    state.duration = button.get_duration(ship, shipSystem)
    state.timer = 0

    set_active(button, ship, shipSystem, true)
    return true
end

-- Is this really necessary?
local function ensure_button_runtime(button, systemBox, ship)
    local shipSystem = systemBox.pSystem
    local visuals = button.get_visuals(ship, shipSystem)
    local runtime = button.runtime

    if runtime.systemBox ~= systemBox
        or runtime.visuals.key ~= visuals.key then

        local activateButton = Hyperspace.Button()

        activateButton:OnInit(visuals.buttonStyle, Hyperspace.Point(button.x, button.y))

        activateButton.hitbox.x = button.hitbox.x
        activateButton.hitbox.y = button.hitbox.y
        activateButton.hitbox.w = button.hitbox.w
        activateButton.hitbox.h = button.hitbox.h

        systemBox.extend.xOffset = button.systemBoxOffset
        systemBox.table["sc_button_" .. button.name] = activateButton

        runtime.systemBox = systemBox
        runtime.activateButton = activateButton
        runtime.visuals = visuals

        runtime.buttonBase = Hyperspace.Resources:CreateImagePrimitiveString(
            visuals.baseImage, button.x, button.y, 0, Graphics.GL_Color(1, 1, 1, 1), 1, false)

        runtime.buttonCharging = Hyperspace.Resources:CreateImagePrimitiveString(
        visuals.chargingImage, button.x, button.y, 0, Graphics.GL_Color(1, 1, 1, 1), 1, false)
    end

    return runtime
end

local function button_matches_system_box(button, systemBox)
    return systemBox.bPlayerUI
        and systemBox.pSystem.iSystemType == button.systemId
end

script.on_internal_event(Defines.InternalEvents.CONSTRUCT_SYSTEM_BOX, function(systemBox)
    local ship = Hyperspace.ships.player

    for _, button in ipairs(buttonOrder) do
        if button_matches_system_box(button, systemBox) then
            ensure_button_runtime(button, systemBox, ship)
        end
    end
end)

script.on_internal_event(Defines.InternalEvents.SYSTEM_BOX_MOUSE_MOVE, function(systemBox, x, y)
    local ship = Hyperspace.ships.player

    for _, button in ipairs(buttonOrder) do
        if button_matches_system_box(button, systemBox)
            and button.is_visible(ship, systemBox.pSystem) then

            local activateButton =
                ensure_button_runtime(button, systemBox, ship).activateButton

            activateButton:MouseMove(x - button.x, y - button.y, false)
        end
    end

    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.SYSTEM_BOX_MOUSE_CLICK, function(systemBox)
    local ship = Hyperspace.ships.player

    for _, button in ipairs(buttonOrder) do
        if button_matches_system_box(button, systemBox)
            and button.is_visible(ship, systemBox.pSystem) then

            local activateButton =
                ensure_button_runtime(button, systemBox, ship).activateButton

            if activateButton.bHover and activateButton.bActive then
                buttonTimer.activate(button.name, ship)
            end
        end
    end

    return Defines.Chain.CONTINUE
end)

script.on_init(reset_all_states)

script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, reset_all_states)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    for _, button in ipairs(buttonOrder) do
        local state = button.state[ship.iShipId]
        local shipSystem = ship:GetSystem(button.systemId)

        if not shipSystem then
            state.timer = 1
            state.active = false

        elseif not button.is_visible(ship, shipSystem) then
            local wasActive = state.active

            state.timer = 1
            state.active = false
            state.duration = button.get_duration(ship, shipSystem)

            if wasActive and button.on_reset then
                button.on_reset(ship, shipSystem, state)
            end

        else
            state.duration = button.get_duration(ship, shipSystem)

            local timerRate =
                button.get_timer_rate
                and button.get_timer_rate(ship, shipSystem, state)
                or 1 / state.duration

            state.timer = math.max( 0, math.min(1, state.timer + timerRate * Hyperspace.FPS.SpeedFactor / 16))

            set_active(button, ship, shipSystem, state.timer < 1)
        end
    end
end)

local function render_button(button, systemBox)
    local ship = Hyperspace.ships.player
    local shipSystem = systemBox.pSystem

    if not button.is_visible(ship, shipSystem) then return end

    local runtime = ensure_button_runtime(button, systemBox, ship)

    local state = button.state[ship.iShipId]
    local activateButton = runtime.activateButton

    state.duration = button.get_duration(ship, shipSystem)

    activateButton.bActive = not state.active and button.is_ready(ship, shipSystem, state)

    if activateButton.bHover and button.get_tooltip then
        local tooltip = button.get_tooltip(ship, shipSystem, state)

        if tooltip then
            Hyperspace.Mouse.tooltip = tooltip
            Hyperspace.Mouse.bForceTooltip = true
        end
    end

    Graphics.CSurface.GL_RenderPrimitive(runtime.buttonBase)

    if state.active then
        local mask = runtime.visuals.fillMask
        local height = math.ceil(state.timer * mask.h)

        Graphics.CSurface.GL_SetStencilMode(Graphics.STENCIL_SET, 1, 1)

        Graphics.CSurface.GL_DrawRect(button.x + mask.x, button.y - height + mask.bottomY, mask.w, height, Graphics.GL_Color(1, 1, 1, 1))

        Graphics.CSurface.GL_SetStencilMode(Graphics.STENCIL_USE, 1, 1)

        Graphics.CSurface.GL_RenderPrimitive(runtime.buttonCharging)

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
    function(systemBox)
        for _, button in ipairs(buttonOrder) do
            if button_matches_system_box(button, systemBox) then
                render_button(button, systemBox)
            end
        end
    end
)