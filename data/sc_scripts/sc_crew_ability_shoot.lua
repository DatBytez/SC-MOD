--[[
DESCRIPTION: Implements reusable targeted projectile crew abilities.
        - Powers with the <sc-shoot projectile="..."/> tag enter targeting mode when activated.
        - Clicking a room on the enemy ship fires the configured projectile.
        - Right-clicking cancels targeting.
        - Targeting ends immediately after the projectile is fired.
        - Resource costs are refunded if targeting is canceled.
TAG: <sc-shoot projectile="WEAPON_BLUEPRINT"/>
DEPENDENCIES: sc_tag.lua, sc_crew_ability_cost.lua
]]

mods.sc.crewShootProjectiles = mods.sc.crewShootProjectiles or {}

local shootProjectiles = mods.sc.crewShootProjectiles
local cost = mods.sc.cost

local shootActive = false
local shootCrew = nil
local shootPower = nil
local shootProjectile = nil

local POWER_NOT_READY_ACTIVATED = 2

local function parse_shoot_projectile(tagNode)
    local projectileAttr = tagNode:first_attribute("projectile")

    if not projectileAttr then return nil end

    return projectileAttr:value()
end

mods.sc.tag.register(
    "power",
    "sc-shoot",
    shootProjectiles,
    parse_shoot_projectile
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

local function clear_shoot(refundResource)
    if refundResource and shootPower then
        cost.refund(shootPower)
    end

    shootActive = false
    shootCrew = nil
    shootPower = nil
    shootProjectile = nil
    Hyperspace.Mouse.bHideMouse = false
end

script.on_internal_event(Defines.InternalEvents.POWER_READY, function(power, powerState)
    if shootActive and power == shootPower then
        powerState = POWER_NOT_READY_ACTIVATED
    end

    return Defines.Chain.CONTINUE, powerState
end)

script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power)
    local projectileName = shootProjectiles[power.def.name]

    if not projectileName then
        return Defines.Chain.CONTINUE
    end

    if not power.crew then
        return Defines.Chain.CONTINUE
    end

    shootActive = true
    shootCrew = power.crew
    shootPower = power
    shootProjectile = projectileName

    power.powerCooldown.first = power.powerCooldown.second

    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.ON_TICK, function()
    if not shootActive then return end

    if not Hyperspace.App.world.bStartedGame
        or Hyperspace.App.menu.shipBuilder.bOpen
        or not shootCrew
        or shootCrew.bDead
        or shootCrew.bOutOfGame
        or shootCrew.bMindControlled then

        clear_shoot(true)
        return
    end

    shootPower.powerCooldown.first =
        shootPower.powerCooldown.second

    local crewControl = Hyperspace.App.gui.crewControl
    crewControl.potentialSelectedCrew:clear()
    crewControl.selectedCrew:clear()

    Hyperspace.Mouse.animateDoor = 0
    Hyperspace.Mouse.bHideMouse = true
end)

script.on_render_event(Defines.RenderEvents.MOUSE_CONTROL, function()
    if not shootActive then return end

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
    if not shootActive then
        return Defines.Chain.CONTINUE
    end

    clear_shoot(true)

    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.ON_MOUSE_L_BUTTON_DOWN, function()
    if not shootActive then
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

    local blueprint = Hyperspace.Blueprints:GetWeaponBlueprint(shootProjectile)

    if not blueprint then
        clear_shoot(true)
        return Defines.Chain.CONTINUE
    end

    local sourceShipId = shootCrew.currentShipId
    local sourceOffset = sourceShipId == 0 and 40 or -40

    local sourcePosition = Hyperspace.Pointf(
        shootCrew.x + sourceOffset,
        shootCrew.y
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
        shootCrew.iShipId,
        target,
        enemyShip.iShipId,
        heading
    )

    if not projectile then
        clear_shoot(true)
        return Defines.Chain.CONTINUE
    end

    projectile.damage.crystalShard = true

    cost.commit(shootPower)
    shootPower.powerCooldown.first = 0

    clear_shoot(false)

    return Defines.Chain.CONTINUE
end)