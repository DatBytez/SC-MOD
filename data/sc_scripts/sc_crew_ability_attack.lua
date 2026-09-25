--[[
DESCRIPTION: Implements reusable targeted projectile crew abilities.
        - Powers with the <sc-attack projectile="..."/> tag enter targeting mode when activated.
        - Clicking a room on the enemy ship fires the configured projectile.
        - Right-clicking cancels targeting.
        - Targeting ends immediately after the projectile is fired.
TAG: <sc-attack projectile="WEAPON_BLUEPRINT"/>
DEPENDENCIES: sc_tag.lua
]]

mods.sc.crewAttackProjectiles = mods.sc.crewAttackProjectiles or {}

local attackProjectiles = mods.sc.crewAttackProjectiles

local attackActive = false
local attackCrew = nil
local attackProjectile = nil

local function parse_attack_projectile(tagNode)
    local projectileAttr = tagNode:first_attribute("projectile")

    if not projectileAttr then return nil end

    return projectileAttr:value()
end

mods.sc.tag.register(
    "power",
    "sc-attack",
    attackProjectiles,
    parse_attack_projectile
)

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

local function clear_attack()
    attackActive = false
    attackCrew = nil
    attackProjectile = nil
    Hyperspace.Mouse.bHideMouse = false
end

script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power)
    local projectileName = attackProjectiles[power.def.name]

    if not projectileName then
        return Defines.Chain.CONTINUE
    end

    if not power.crew then
        return Defines.Chain.CONTINUE
    end

    attackActive = true
    attackCrew = power.crew
    attackProjectile = projectileName

    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.ON_TICK, function()
    if not attackActive then return end

    if not Hyperspace.App.world.bStartedGame
        or Hyperspace.App.menu.shipBuilder.bOpen
        or not attackCrew
        or attackCrew.bDead
        or attackCrew.bOutOfGame
        or attackCrew.bMindControlled then

        clear_attack()
        return
    end

    local crewControl = Hyperspace.App.gui.crewControl
    crewControl.potentialSelectedCrew:clear()
    crewControl.selectedCrew:clear()

    Hyperspace.Mouse.animateDoor = 0
    Hyperspace.Mouse.bHideMouse = true
end)

script.on_render_event(Defines.RenderEvents.MOUSE_CONTROL, function()
    if not attackActive then return end

    local mousePosition = Hyperspace.Mouse.position
    local enemyShip = Hyperspace.ships.enemy
    local validTarget = false

    if enemyShip then
        local targetPosition = convert_mouse_to_enemy_position(mousePosition)
        local roomId = get_room_at_location(enemyShip, targetPosition)

        validTarget = roomId >= 0
    end

    local crosshair = Hyperspace.Resources:GetImageId(
        "mouse/mouse_crosshairs2_1.png"
    )

    local target

    if validTarget then
        target = Hyperspace.Resources:GetImageId(
            "mouse/mouse_crosshairs.png"
        )
    else
        target = Hyperspace.Resources:GetImageId(
            "mouse/mouse_crosshairs_valid.png"
        )
    end

    Graphics.CSurface.GL_BlitPixelImage(
        crosshair,
        mousePosition.x,
        mousePosition.y,
        32,
        32,
        0,
        Graphics.GL_Color(1, 1, 1, 1),
        false
    )

    Graphics.CSurface.GL_BlitPixelImage(
        target,
        mousePosition.x,
        mousePosition.y,
        32,
        32,
        0,
        Graphics.GL_Color(1, 1, 1, 1),
        false
    )
end, function() end)

script.on_internal_event(Defines.InternalEvents.ON_MOUSE_R_BUTTON_DOWN, function()
    if not attackActive then
        return Defines.Chain.CONTINUE
    end

    clear_attack()

    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.ON_MOUSE_L_BUTTON_DOWN, function()
    if not attackActive then
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

    local blueprint = Hyperspace.Blueprints:GetWeaponBlueprint(attackProjectile)

    if not blueprint then
        clear_attack()
        return Defines.Chain.CONTINUE
    end

    local sourceShipId = attackCrew.currentShipId
    local sourceOffset = sourceShipId == 0 and 40 or -40

    local sourcePosition = Hyperspace.Pointf(
        attackCrew.x + sourceOffset,
        attackCrew.y
    )

    local target = Hyperspace.Pointf(
        targetPosition.x,
        targetPosition.y
    )

    local heading = sourceShipId == 0 and 0 or 180

    local projectile = Hyperspace.App.world.space:CreateMissile(
        blueprint,
        sourcePosition,
        sourceShipId,
        attackCrew.iShipId,
        target,
        enemyShip.iShipId,
        heading
    )

    if projectile then
        projectile.damage.crystalShard = true
    end

    clear_attack()

    return Defines.Chain.CONTINUE
end)