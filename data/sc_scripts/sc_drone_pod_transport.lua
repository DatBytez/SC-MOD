--[[
DESCRIPTION: Manages Terran Drop Pod transport projectiles and in-flight crew state.
        - Creates one transport projectile for each crew member being launched.
        - Snapshots and retires transported crew after projectile creation.
        - Associates each projectile with its transported crew snapshot.
        - Handles killing transported crew when their projectile is destroyed.
DEPENDENCIES: sc_crew_copy.lua, Multiverse userdata_table
]]

local userdata_table = mods.multiverse.userdata_table
local crew_copy = mods.sc.crew_copy

mods.sc = mods.sc or {}
mods.sc.dronePod = mods.sc.dronePod or {}

local pod = mods.sc.dronePod

local POD_PROJECTILE_BLUEPRINT = "TERRAN_POD_PROJECTILE"
local POD_USERDATA = "mods.sc.dronePod"

pod.nextTransportId = pod.nextTransportId or 0
pod.activeTransports = pod.activeTransports or {}

local function launch_transport_projectile(payloadCrew, ownerShip, targetShip)
    local blueprint = Hyperspace.Blueprints:GetWeaponBlueprint(POD_PROJECTILE_BLUEPRINT)
    if not blueprint then return nil end

    local sourceShipId = ownerShip.iShipId
    local targetShipId = targetShip.iShipId
    local sourceSlot = payloadCrew.currentSlot

    local slotPosition = Hyperspace.ShipGraph
        .GetShipInfo(sourceShipId)
        :GetSlotWorldPosition(sourceSlot.slotId, sourceSlot.roomId)

    local sourcePosition = Hyperspace.Pointf(slotPosition.x, slotPosition.y)
    local targetPosition = targetShip:GetRandomRoomCenter()
    local heading = sourceShipId == 0 and 0 or 180

    local projectile = Hyperspace.App.world.space:CreateMissile(blueprint, sourcePosition, sourceShipId, sourceShipId, targetPosition, targetShipId, heading)

    if projectile then
        projectile.damage.crystalShard = true
    end

    return projectile
end

local function create_transport_payload(crew)
    local snapshot = crew_copy.snapshot(crew)

    pod.nextTransportId = pod.nextTransportId + 1

    local payload = {
        transportId = pod.nextTransportId,
        snapshot = snapshot
    }

    pod.activeTransports[payload.transportId] = payload
    return payload
end

function pod.launch(payloadCrew, ownerShip, targetShip)
    local projectile = launch_transport_projectile(payloadCrew, ownerShip, targetShip)
    if not projectile then return false end

    local payload = create_transport_payload(payloadCrew)

    userdata_table(projectile, POD_USERDATA).transportId = payload.transportId

    if not crew_copy.retire(payloadCrew) then
        pod.activeTransports[payload.transportId] = nil
        return false
    end

    return true
end

function pod.get_transport(projectile)
    if not projectile or projectile.extend.name ~= POD_PROJECTILE_BLUEPRINT then
        return nil, nil
    end

    local transportId = userdata_table(projectile, POD_USERDATA).transportId

    return transportId, transportId and pod.activeTransports[transportId] or nil
end

function pod.complete_transport(transportId)
    pod.activeTransports[transportId] = nil
end

function pod.kill_transport(transportId)
    local payload = pod.activeTransports[transportId]
    if not payload then return end

    pod.activeTransports[transportId] = nil

    local snapshot = payload.snapshot
    local sourceShip = Hyperspace.Global.GetInstance():GetShipManager(snapshot.currentShipId)

    if not sourceShip or sourceShip.bDestroyed then return end

    local crew = crew_copy.recreate(snapshot, sourceShip, snapshot.roomId)

    if crew then
        crew:Kill(false)
    end
end

function pod.clear_transports()
    pod.activeTransports = {}
end