--[[
DESCRIPTION: Compact fixed on-screen active shield cooldown diagnostic.
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

local PANEL_X = 20
local PANEL_Y = 115
local PANEL_W = 690
local PANEL_H = 130

local TEXT_X = PANEL_X + 8
local TEXT_Y = PANEL_Y + 6
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

local function get_drone_name(drone)
    if not drone or not drone.blueprint then return "none" end
    return drone.blueprint.name or "unk"
end

local function get_active_shield_drone_key(shipId, slot, drone)
    if not drone or not drone.blueprint then return nil end
    return tostring(shipId) .. ":" .. tostring(slot) .. ":" .. tostring(drone.blueprint.name)
end

local function get_script_cooldown(key)
    if not key or not mods.sc.activeShieldCooldowns then return 0 end
    return mods.sc.activeShieldCooldowns[key] or 0
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

local function count_incoming_enemy_projectiles(shipId)
    if not Hyperspace.App or not Hyperspace.App.world or not Hyperspace.App.world.space then
        return 0
    end

    local count = 0

    for projectile in vter(Hyperspace.App.world.space.projectiles) do
        local projectileIsActive = projectile._targetable ~= false and not projectile.passedTarget
        local projectileIsEnemy = projectile.ownerId ~= shipId
        local projectileIsAtShip = projectile.currentSpace == shipId

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
            local key = get_active_shield_drone_key(shipManager.iShipId, slotIndex, drone)
            local scriptCooldown = get_script_cooldown(key)
            local active = drone_is_active_and_powered(drone)

            return {
                slot = slotIndex,
                key = key,
                name = get_drone_name(drone),
                active = active,
                ready = active and scriptCooldown <= 0,
                deployed = drone.deployed,
                powered = drone.powered,
                dead = drone.bDead,
                scriptCooldown = scriptCooldown,
                weaponCooldown = drone.weaponCooldown or 0,
                getWeaponCooldown = get_drone_weapon_cooldown(drone)
            }
        end
    end

    return nil
end

local function count_ready_active_shield_drones(shipManager)
    if not shipManager then return 0 end

    local count = 0
    local slotIndex = 0

    for drone in vter(shipManager.spaceDrones) do
        slotIndex = slotIndex + 1

        if drone_is_active_and_powered(drone) then
            local key = get_active_shield_drone_key(shipManager.iShipId, slotIndex, drone)

            if get_script_cooldown(key) <= 0 then
                count = count + 1
            end
        end
    end

    return count
end

local function record_threat(eventType, projectile, targetShipId, usedOwnerFallback, isBeam, sourceName)
    local shipManager = get_ship(targetShipId)
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
        superBefore = get_super_shields(shipManager),
        droneStatus = droneStatus,
        readyCount = readyCount
    }

    add_recent_event(
        string.format(
            "T %s s%s %s r%d c%s",
            eventType,
            tostring(targetShipId),
            sourceName or "unk",
            readyCount,
            droneStatus and num(droneStatus.scriptCooldown) or "-"
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
        local targetShipId, usedOwnerFallback = get_projectile_target_ship_id(projectile, true)

        if targetShipId then
            record_threat(
                "DF",
                projectile,
                targetShipId,
                usedOwnerFallback,
                false,
                sourceName
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

    if not isBeam and projectile.currentSpace ~= projectile.ownerId then
        return Defines.Chain.CONTINUE
    end

    local weaponName = weapon and weapon.blueprint and weapon.blueprint.name or "unk"
    local targetShipId, usedOwnerFallback = get_projectile_target_ship_id(projectile, true)

    if targetShipId then
        record_threat(
            isBeam and "BF" or "PF",
            projectile,
            targetShipId,
            usedOwnerFallback,
            isBeam,
            weaponName
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
                "S s%d %d>%d in%d c%s",
                shipId,
                previousSuper,
                currentSuper,
                debug.lastSuperChange.incoming,
                status and num(status.scriptCooldown) or "-"
            )
        )
    end

    debug.lastSuperByShip[shipId] = currentSuper
end)

local function ship_line(shipId, label)
    local shipManager = get_ship(shipId)
    if not shipManager then return label .. " miss" end

    local status = get_drone_status(shipManager)
    local droneText = "noD"

    if status then
        droneText = string.format(
            "%s a%s r%s c%s/%s w%s d%s p%s x%s",
            status.name,
            yn(status.active),
            yn(status.ready),
            num(status.scriptCooldown),
            num(status.getWeaponCooldown),
            num(status.weaponCooldown),
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

    Graphics.CSurface.GL_DrawRect(
        PANEL_X,
        PANEL_Y,
        PANEL_W,
        PANEL_H,
        Graphics.GL_Color(0, 0, 0, 0.70)
    )

    Graphics.CSurface.GL_SetColor(
        Graphics.GL_Color(1, 1, 1, 1)
    )

    draw_line(0, string.format("t%d th%d pf%d df%d", debug.tickCount, debug.threatCount, debug.projectileFireCount, debug.droneFireCount))
    draw_line(1, ship_line(0, "P"))
    draw_line(2, ship_line(1, "E"))

    local threat = debug.lastThreat

    if threat then
        local gate = (threat.readyCount or 0) > 0 and "OK" or "BLK"
        draw_line(3, string.format("T %s s%s b%s %s sh%s r%d %s", threat.eventType, tostring(threat.targetShipId), yn(threat.isBeam), tostring(threat.sourceName), tostring(threat.superBefore), threat.readyCount or 0, gate))
        draw_line(4, string.format("o%s c%s d%s fb%s", tostring(threat.ownerId), tostring(threat.currentSpace), tostring(threat.destinationSpace), yn(threat.usedOwnerFallback)))
    else
        draw_line(3, "T none")
    end

    local superChange = debug.lastSuperChange

    if superChange then
        local status = superChange.droneStatus
        draw_line(5, string.format("S s%d %d>%d in%d r%d c%s", superChange.shipId, superChange.previous, superChange.current, superChange.incoming, superChange.readyCount or 0, status and num(status.scriptCooldown) or "-"))
    else
        draw_line(5, "S none")
    end

    for i = 1, MAX_RECENT_EVENTS do
        draw_line(5 + i, debug.recentEvents[i] or "-")
    end

    Graphics.CSurface.GL_PopMatrix()
end

script.on_render_event(
    Defines.RenderEvents.MOUSE_CONTROL,
    draw_panel,
    function() end
)
