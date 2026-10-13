--[[
DESCRIPTION: Compact fixed on-screen active shield drone diagnostic.
    Diagnostic only; gameplay logic does not depend on this file.
]]

local vter = mods.multiverse.vter

mods.sc = mods.sc or {}
mods.sc.activeShieldCooldownDebug = {
    tickCount = 0,
    projectileFireCount = 0,
    droneFireCount = 0,
    threatCount = 0,
    lastThreat = nil,
    lastSuperChange = nil,
    lastSuperByShip = {},
    recentEvents = {}
}

local debug = mods.sc.activeShieldCooldownDebug

local TEXT_X = 20
local TEXT_Y = 115
local LINE_HEIGHT = 16
local FONT = 10

local MAX_RECENT_EVENTS = 3

local function draw_line(line, text)
    Graphics.freetype.easy_print(
        FONT,
        TEXT_X,
        TEXT_Y + line * LINE_HEIGHT,
        text
    )
end

local function yn(value)
    return value and "Y" or "N"
end

local function num(value)
    if value == nil then return "-" end
    return string.format("%.1f", value)
end

local function add_recent_event(text)
    table.insert(debug.recentEvents, 1, text)

    if #debug.recentEvents > MAX_RECENT_EVENTS then
        table.remove(debug.recentEvents)
    end
end

local function get_ship(shipId)
    if shipId ~= 0 and shipId ~= 1 then return nil end
    return Hyperspace.ships(shipId)
end

local function get_super_shields(shipManager)
    if not shipManager or not shipManager.shieldSystem then return 0 end
    return shipManager.shieldSystem.shields.power.super.first or 0
end

local function drone_has_active_shield_tag(drone)
    if not drone or not drone.blueprint then return false end
    if not mods.sc.activeShield then return false end
    return mods.sc.activeShield[drone.blueprint.name]
end

local function drone_is_active_and_powered(drone)
    return drone_has_active_shield_tag(drone) and drone.deployed and drone.powered and not drone.bDead
end

local function get_drone_weapon_cooldown(drone)
    local success, cooldown = pcall(function()
        return drone:GetWeaponCooldown()
    end)

    if success then
        return cooldown
    end

    return nil
end

local function get_drone_owner_id(drone)
    local success, ownerId = pcall(function()
        return drone:GetOwnerId()
    end)

    if success then
        return ownerId
    end

    return nil
end

local function get_drone_type_text(drone)
    if not drone or not drone.blueprint then return "-" end

    if drone.blueprint.typeName then
        return tostring(drone.blueprint.typeName)
    end

    if drone.blueprint.type then
        return tostring(drone.blueprint.type)
    end

    return "-"
end

local function get_drone_name(drone)
    if not drone or not drone.blueprint then return "none" end
    return drone.blueprint.name or "unk"
end

local function ship_has_active_shield_drone(shipManager)
    if not shipManager then return false end

    for drone in vter(shipManager.spaceDrones) do
        if drone_is_active_and_powered(drone) then
            return true
        end
    end

    return false
end

local function get_projectile_target_ship_id(projectile, allowOwnerFallback)
    local targetShipId = projectile.destinationSpace
    local usedOwnerFallback = false

    if targetShipId == nil or targetShipId < 0 then
        if not allowOwnerFallback or projectile.ownerId == nil then
            return nil, false
        end

        targetShipId = 1 - projectile.ownerId
        usedOwnerFallback = true
    end

    if targetShipId ~= 0 and targetShipId ~= 1 then
        return nil, usedOwnerFallback
    end

    if projectile.ownerId == targetShipId then
        return nil, usedOwnerFallback
    end

    return targetShipId, usedOwnerFallback
end

local function get_drone_projectile_target_ship_id(projectile, spacedrone)
    local droneOwnerId = get_drone_owner_id(spacedrone)

    if droneOwnerId == 0 or droneOwnerId == 1 then
        return 1 - droneOwnerId, true, droneOwnerId
    end

    if projectile and (projectile.currentSpace == 0 or projectile.currentSpace == 1) then
        return projectile.currentSpace, false, droneOwnerId
    end

    local targetShipId, fallback = get_projectile_target_ship_id(projectile, true)
    return targetShipId, fallback, droneOwnerId
end

local function count_incoming_enemy_projectiles(shipId)
    if not Hyperspace.App or not Hyperspace.App.world or not Hyperspace.App.world.space then
        return 0
    end

    local count = 0

    for projectile in vter(Hyperspace.App.world.space.projectiles) do
        local projectileIsActive = projectile._targetable ~= false and not projectile.passedTarget
        local projectileIsEnemy = projectile.ownerId ~= shipId
        local projectileIsAtShip = projectile.currentSpace == shipId or projectile.destinationSpace == shipId

        if projectileIsActive and projectileIsEnemy and projectileIsAtShip then
            count = count + 1
        end
    end

    return count
end

local function get_drone_status(shipManager)
    if not shipManager then return nil end

    local slotIndex = 0

    for drone in vter(shipManager.spaceDrones) do
        slotIndex = slotIndex + 1

        if drone_has_active_shield_tag(drone) then
            local active = drone_is_active_and_powered(drone)
            local weaponCooldown = drone.weaponCooldown or 0

            return {
                slot = slotIndex,
                name = get_drone_name(drone),
                typeText = get_drone_type_text(drone),
                active = active,
                ready = active and weaponCooldown <= 0,
                deployed = drone.deployed,
                powered = drone.powered,
                dead = drone.bDead,
                weaponCooldown = weaponCooldown,
                getWeaponCooldown = get_drone_weapon_cooldown(drone),
                ownerId = get_drone_owner_id(drone)
            }
        end
    end

    return nil
end

local function count_ready_active_shield_drones(shipManager)
    if not shipManager then return 0 end

    local count = 0

    for drone in vter(shipManager.spaceDrones) do
        if drone_is_active_and_powered(drone) and (drone.weaponCooldown or 0) <= 0 then
            count = count + 1
        end
    end

    return count
end

local function record_threat(eventType, projectile, targetShipId, usedOwnerFallback, isBeam, sourceName, droneOwnerId)
    local shipManager = get_ship(targetShipId)

    if not ship_has_active_shield_drone(shipManager) then
        return
    end

    local droneStatus = get_drone_status(shipManager)
    local readyCount = count_ready_active_shield_drones(shipManager)

    debug.threatCount = debug.threatCount + 1

    debug.lastThreat = {
        eventType = eventType,
        sourceName = sourceName or "unk",
        isBeam = isBeam,
        ownerId = projectile and projectile.ownerId or nil,
        currentSpace = projectile and projectile.currentSpace or nil,
        destinationSpace = projectile and projectile.destinationSpace or nil,
        targetShipId = targetShipId,
        usedOwnerFallback = usedOwnerFallback,
        droneOwnerId = droneOwnerId,
        superBefore = get_super_shields(shipManager),
        droneStatus = droneStatus,
        readyCount = readyCount
    }

    add_recent_event(
        string.format(
            "T %s s%s %s r%d w%s",
            eventType,
            tostring(targetShipId),
            sourceName or "unk",
            readyCount,
            droneStatus and num(droneStatus.weaponCooldown) or "-"
        )
    )
end

script.on_internal_event(Defines.InternalEvents.ON_TICK, function()
    if not Hyperspace.App
        or not Hyperspace.App.world
        or not Hyperspace.App.world.bStartedGame then
        return
    end

    debug.tickCount = debug.tickCount + 1
end)

script.on_internal_event(Defines.InternalEvents.DRONE_FIRE, function(projectile, spacedrone)
    debug.droneFireCount = debug.droneFireCount + 1

    local sourceName = get_drone_name(spacedrone)
    local sourceTagged = drone_has_active_shield_tag(spacedrone)

    if projectile and not sourceTagged then
        local targetShipId, usedOwnerFallback, droneOwnerId = get_drone_projectile_target_ship_id(projectile, spacedrone)

        if targetShipId then
            record_threat(
                "DF",
                projectile,
                targetShipId,
                usedOwnerFallback,
                false,
                sourceName,
                droneOwnerId
            )
        end
    end

    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    debug.projectileFireCount = debug.projectileFireCount + 1

    if not projectile then
        return Defines.Chain.CONTINUE
    end

    local isBeam = weapon and weapon.blueprint and weapon.blueprint.typeName == "BEAM"
    local weaponName = weapon and weapon.blueprint and weapon.blueprint.name or "unk"
    local targetShipId, usedOwnerFallback = get_projectile_target_ship_id(projectile, isBeam)

    if targetShipId then
        record_threat(
            isBeam and "BF" or "PF",
            projectile,
            targetShipId,
            usedOwnerFallback,
            isBeam,
            weaponName,
            nil
        )
    end

    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if not shipManager then return end

    local shipId = shipManager.iShipId
    local currentSuper = get_super_shields(shipManager)
    local previousSuper = debug.lastSuperByShip[shipId]

    if previousSuper ~= nil and currentSuper ~= previousSuper then
        local status = get_drone_status(shipManager)

        debug.lastSuperChange = {
            shipId = shipId,
            previous = previousSuper,
            current = currentSuper,
            incoming = count_incoming_enemy_projectiles(shipId),
            droneStatus = status,
            readyCount = count_ready_active_shield_drones(shipManager)
        }

        add_recent_event(
            string.format(
                "S s%d %d>%d in%d w%s",
                shipId,
                previousSuper,
                currentSuper,
                debug.lastSuperChange.incoming,
                status and num(status.weaponCooldown) or "-"
            )
        )
    end

    debug.lastSuperByShip[shipId] = currentSuper
end)

local function state_line()
    local state = mods.sc.activeShieldState
    if not state then return "st none" end

    local threatSource = state.lastThreat and state.lastThreat.sourceName or "-"
    local useSource = state.lastUse and state.lastUse.sourceName or "-"
    local blockSource = state.lastBlock and state.lastBlock.sourceName or "-"

    return string.format(
        "st th%d u%d b%d t%s u%s b%s",
        state.threats or 0,
        state.used or 0,
        state.blocked or 0,
        tostring(threatSource),
        tostring(useSource),
        tostring(blockSource)
    )
end

local function ship_line(shipId, label)
    local shipManager = get_ship(shipId)
    if not shipManager then return label .. " miss" end

    local status = get_drone_status(shipManager)
    local droneText = "noD"

    if status then
        droneText = string.format(
            "%s ty%s a%s r%s w%s/%s o%s d%s p%s x%s",
            status.name,
            status.typeText,
            yn(status.active),
            yn(status.ready),
            num(status.weaponCooldown),
            num(status.getWeaponCooldown),
            tostring(status.ownerId),
            yn(status.deployed),
            yn(status.powered),
            yn(status.dead)
        )
    end

    return string.format(
        "%s sh%d in%d r%d %s",
        label,
        get_super_shields(shipManager),
        count_incoming_enemy_projectiles(shipId),
        count_ready_active_shield_drones(shipManager),
        droneText
    )
end

local function draw_panel()
    if not Hyperspace.App
        or not Hyperspace.App.world
        or not Hyperspace.App.world.bStartedGame then
        return
    end

    Graphics.CSurface.GL_PushMatrix()
    Graphics.CSurface.GL_LoadIdentity()

    Graphics.CSurface.GL_SetColor(
        Graphics.GL_Color(1, 1, 1, 1)
    )

    draw_line(0, string.format("t%d th%d pf%d df%d", debug.tickCount, debug.threatCount, debug.projectileFireCount, debug.droneFireCount))
    draw_line(1, ship_line(0, "P"))
    draw_line(2, ship_line(1, "E"))
    draw_line(3, state_line())

    local threat = debug.lastThreat

    if threat then
        local gate = (threat.readyCount or 0) > 0 and "OK" or "BLK"
        draw_line(4, string.format("T %s s%s b%s %s sh%s r%d %s", threat.eventType, tostring(threat.targetShipId), yn(threat.isBeam), tostring(threat.sourceName), tostring(threat.superBefore), threat.readyCount or 0, gate))
        draw_line(5, string.format("pO%s dO%s c%s d%s fb%s", tostring(threat.ownerId), tostring(threat.droneOwnerId), tostring(threat.currentSpace), tostring(threat.destinationSpace), yn(threat.usedOwnerFallback)))
    else
        draw_line(4, "T none")
    end

    local superChange = debug.lastSuperChange

    if superChange then
        local status = superChange.droneStatus
        draw_line(6, string.format("S s%d %d>%d in%d r%d w%s", superChange.shipId, superChange.previous, superChange.current, superChange.incoming, superChange.readyCount or 0, status and num(status.weaponCooldown) or "-"))
    else
        draw_line(6, "S none")
    end

    for i = 1, MAX_RECENT_EVENTS do
        draw_line(6 + i, debug.recentEvents[i] or "-")
    end

    Graphics.CSurface.GL_PopMatrix()
end

script.on_render_event(
    Defines.RenderEvents.MOUSE_CONTROL,
    draw_panel,
    function() end
)
