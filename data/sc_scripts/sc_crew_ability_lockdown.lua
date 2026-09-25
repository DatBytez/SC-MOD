--[[
DESCRIPTION: Implements the Terran Ghost Lockdown ability.
        - Activating SC_LOCKDOWN enters targeting mode.
        - Clicking a room on the enemy ship fires one TERRAN_LOCKDOWN_PROJECTILE.
        - Targeting ends immediately after the projectile is fired.
]]

local LOCKDOWN_POWER = "SC_LOCKDOWN"
local LOCKDOWN_CREW = "terran_ghost_2"
local LOCKDOWN_PROJECTILE = "TERRAN_LOCKDOWN_PROJECTILE"

local lockdownActive = false
local lockdownCrew = nil

local function get_room_at_location(ship, location)
    return Hyperspace.ShipGraph
        .GetShipInfo(ship.iShipId)
        :GetSelectedRoom(location.x, location.y, true)
end

local function convert_mouse_to_enemy_position(mousePosition)
    local combatControl = Hyperspace.App.gui.combatControl
    local position = combatControl.position
    local targetPosition = combatControl.targetPosition

    return Hyperspace.Point(
        mousePosition.x - position.x - targetPosition.x,
        mousePosition.y - position.y - targetPosition.y
    )
end

local function clear_lockdown()
    lockdownActive = false
    lockdownCrew = nil
end

script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power)
    if power.def.name ~= LOCKDOWN_POWER then
        return Defines.Chain.CONTINUE
    end

    if not power.crew or power.crew.species ~= LOCKDOWN_CREW then
        return Defines.Chain.CONTINUE
    end

    lockdownActive = true
    lockdownCrew = power.crew

    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.ON_TICK, function()
    if not lockdownActive then return end

    if not Hyperspace.App.world.bStartedGame
        or Hyperspace.App.menu.shipBuilder.bOpen
        or not lockdownCrew
        or lockdownCrew.bDead
        or lockdownCrew.bOutOfGame
        or lockdownCrew.bMindControlled then

        clear_lockdown()
        return
    end

    local crewControl = Hyperspace.App.gui.crewControl
    crewControl.potentialSelectedCrew:clear()
    crewControl.selectedCrew:clear()

    Hyperspace.Mouse.animateDoor = 0
end)

script.on_internal_event(Defines.InternalEvents.ON_MOUSE_L_BUTTON_DOWN, function()
    if not lockdownActive then
        return Defines.Chain.CONTINUE
    end

    local commandGui = Hyperspace.App.gui

    if commandGui.bPaused
        or commandGui.event_pause
        or commandGui.menu_pause then

        return Defines.Chain.CONTINUE
    end

    local enemyShip = Hyperspace.ships.enemy

    if not enemyShip then
        return Defines.Chain.CONTINUE
    end

    local mousePosition = Hyperspace.Mouse.position
    local targetPosition = convert_mouse_to_enemy_position(mousePosition)

    local roomId = get_room_at_location(enemyShip, targetPosition)

    if roomId < 0 then
        return Defines.Chain.CONTINUE
    end

    local blueprint = Hyperspace.Blueprints:GetWeaponBlueprint(LOCKDOWN_PROJECTILE)

    if not blueprint then
        clear_lockdown()
        return Defines.Chain.CONTINUE
    end

    local sourceShipId = lockdownCrew.currentShipId

    local sourcePosition = Hyperspace.Pointf(
        lockdownCrew.x,
        lockdownCrew.y
    )

    local target = Hyperspace.Pointf(
        targetPosition.x,
        targetPosition.y
    )

    local heading = sourceShipId == 0 and 0 or 180

    Hyperspace.App.world.space:CreateMissile(
        blueprint,
        sourcePosition,
        sourceShipId,
        lockdownCrew.iShipId,
        target,
        enemyShip.iShipId,
        heading
    )

    clear_lockdown()

    return Defines.Chain.CONTINUE
end)