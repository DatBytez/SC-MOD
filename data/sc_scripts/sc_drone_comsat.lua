--[[
DESCRIPTION: Controls Terran Comsat drone deployment and lifetime behavior.
        - Tagged drones are destroyed when their lifetime ends or if depowered early, entering the normal rebuild cycle.
        - A separate Lua timer creates the Comsat scan hit animation at a random enemy room when an enemy ship is present.
TAG: <sc-comsat value="#"/>
DEPENDENCIES: sc_tag.lua
]]

local vter = mods.multiverse.vter
local helpers = mods.sc.helpers

mods.sc.comsat = mods.sc.comsat or {}
local comsat = mods.sc.comsat

local SCAN_BLUEPRINT = "TERRAN_COMSAT_PROJECTILE"

local scanBlueprint = Hyperspace.Blueprints:GetWeaponBlueprint(SCAN_BLUEPRINT)
local SCAN_INTERVAL = scanBlueprint.cooldown

local comsatDrones = {}
local comsatTimers = {
    [0] = {},
    [1] = {}
}
local scanTimers = {
    [0] = {},
    [1] = {}
}
local comsatWasDeployed = {
    [0] = {},
    [1] = {}
}

mods.sc.tag.register("drone", "sc-comsat", comsatDrones, "value")

function comsat.is_comsat(drone)
    return drone
        and drone.blueprint
        and comsatDrones[drone.blueprint.name] ~= nil
end

function comsat.is_active(drone)
    return comsat.is_comsat(drone)
        and drone.deployed
        and drone.powered
        and not drone.bDead
end

function comsat.has_active(ship)
    if not ship or not ship.droneSystem then return false end

    for drone in vter(ship.droneSystem.drones) do
        if comsat.is_active(drone) then return true end
    end

    return false
end

local function update_comsat_refund(ship, drone)
    local shipId = ship.iShipId
    local droneId = drone.selfId
    local deployed = drone.deployed and not drone.bDead
    local wasDeployed = comsatWasDeployed[shipId][droneId]

    if wasDeployed == nil then
        comsatWasDeployed[shipId][droneId] = deployed
        return
    end

    if deployed and not wasDeployed then
        ship:ModifyDroneCount(1)
    end

    comsatWasDeployed[shipId][droneId] = deployed
end

local function create_comsat_scan(shipId)
    local targetShip = Hyperspace.ships(1 - shipId)
    if not targetShip or targetShip.bDestroyed then return false end

    local roomCenter = targetShip:GetRandomRoomCenter()
    local target = Hyperspace.Pointf(roomCenter.x, roomCenter.y)

    local scan = Hyperspace.App.world.space:CreateLaserBlast(
        scanBlueprint,
        target,
        targetShip.iShipId,
        shipId,
        target,
        targetShip.iShipId,
        0
    )

    if not scan then return false end

    scan.death_animation:Start(false)
    return true
end

local function update_comsat_scan(shipId, drone)
    local droneId = drone.selfId
    local remaining = (scanTimers[shipId][droneId] or 0) - Hyperspace.FPS.SpeedFactor / 16

    if remaining <= 0 and create_comsat_scan(shipId) then
        remaining = SCAN_INTERVAL
    end

    scanTimers[shipId][droneId] = remaining
end

local function reset_comsat_state()
    comsatTimers[0] = {}
    comsatTimers[1] = {}
    scanTimers[0] = {}
    scanTimers[1] = {}
    comsatWasDeployed[0] = {}
    comsatWasDeployed[1] = {}
end

local function update_comsat_lifetime(shipTimers, drone, lifetime)
    local droneId = drone.selfId

    if drone.bDead then
        shipTimers[droneId] = nil
        return
    end

    if not drone.powered then
        if drone.deployed or shipTimers[droneId] then
            drone:SetDestroyed(true, true)
        end

        shipTimers[droneId] = nil
        return
    end

    if not drone.deployed then
        shipTimers[droneId] = nil
        return
    end

    local remaining = (shipTimers[droneId] or lifetime) - Hyperspace.FPS.SpeedFactor / 16
    shipTimers[droneId] = remaining

    if remaining <= 0 then
        shipTimers[droneId] = nil
        drone:SetDestroyed(true, true)
    end
end

script.on_init(reset_comsat_state)

script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, reset_comsat_state)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    if not ship.droneSystem then return end

    local shipId = ship.iShipId
    local shipTimers = comsatTimers[shipId]

    for drone in vter(ship.droneSystem.drones) do
        local lifetime = comsatDrones[drone.blueprint.name]

        if lifetime then
            update_comsat_refund(ship, drone)
            update_comsat_lifetime(shipTimers, drone, lifetime)

            if comsat.is_active(drone) then
                update_comsat_scan(shipId, drone)
            else
                scanTimers[shipId][drone.selfId] = nil
            end
        end
    end
end)

script.on_internal_event(Defines.InternalEvents.DRONE_FIRE, function(projectile, spacedrone)
    if comsat.is_comsat(spacedrone) then
        return Defines.Chain.PREEMPT
    end

    return Defines.Chain.CONTINUE
end)