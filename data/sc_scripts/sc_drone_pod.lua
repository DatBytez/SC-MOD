local userdata_table = mods.multiverse.userdata_table

mods.sc_drone_pod = mods.sc_drone_pod or {}
local pod = mods.sc_drone_pod

local POD_SPECIES = "terran_pod"
local LAUNCH_POWER = "LAUNCH"
local POD_PROJECTILE_BLUEPRINT = "TERRAN_POD_PROJECTILE"
local POD_USERDATA = "mods.sc.dronePod"

pod.nextTransportId = pod.nextTransportId or 0
pod.activeTransports = pod.activeTransports or {}

-- Find one normal, friendly crew member in the same room as the pod drone.
-- The pod itself and all crew drones are deliberately excluded.
local function find_payload_crew(ownerShip, podCrew)
    local crewList = ownerShip.vCrewList
    if not crewList then return nil end

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if crew
            and crew ~= podCrew
            and crew.iShipId == ownerShip.iShipId
            and crew.currentShipId == ownerShip.iShipId
            and crew.iRoomId == podCrew.iRoomId
            and crew:IsCrew()
            and not crew:IsDrone()
            and not crew.bDead
            and not crew.bOutOfGame then
            return crew
        end
    end

    return nil
end

local function create_transport_payload(crew, sourceShipId, targetShipId)
    pod.nextTransportId = pod.nextTransportId + 1

    local payload = {
        transportId = pod.nextTransportId,
        crew = crew,
        crewSelfId = crew.extend and crew.extend.selfId or nil,
        sourceShipId = sourceShipId,
        sourceRoomId = crew.iRoomId,
        targetShipId = targetShipId,
        wasFrozen = crew.bFrozen,
        wasFrozenLocation = crew.bFrozenLocation
    }

    pod.activeTransports[payload.transportId] = payload
    return payload
end

local function mark_crew_in_transit(payload)
    local crew = payload.crew
    if not crew then return false end

    if userdata_table then
        local crewData = userdata_table(crew, POD_USERDATA)
        crewData.inTransit = true
        crewData.transportId = payload.transportId
    end

    -- Keep the actual CrewMember alive, but remove it from normal gameplay while
    -- the projectile is travelling. This preserves the complete crew entity.
    crew:SetOutOfGame()
    return true
end

local function clear_crew_transport_marker(crew, transportId)
    if not crew or not userdata_table then return end

    local crewData = userdata_table(crew, POD_USERDATA)
    if crewData.transportId == transportId then
        crewData.inTransit = false
        crewData.transportId = nil
    end
end

local function place_crew(payload, shipId, roomId)
    local crew = payload and payload.crew
    if not crew then return false end

    -- SetOutOfGame has no paired public method. bOutOfGame is exposed and is
    -- also used by existing MV-compatible scripts when reviving/moving crew.
    crew.bOutOfGame = false
    crew.bDead = false

    -- Move the original CrewMember object itself. iShipId remains its owner;
    -- currentShipId changes to the ship the crew is physically aboard.
    crew:SetCurrentShip(shipId)
    crew:SetRoom(roomId)

    -- Preserve any pre-launch frozen state rather than silently clearing it.
    crew.bFrozen = payload.wasFrozen
    crew.bFrozenLocation = payload.wasFrozenLocation

    clear_crew_transport_marker(crew, payload.transportId)
    return true
end

local function return_transport_to_source(transportId)
    local payload = pod.activeTransports[transportId]
    if not payload then return end

    local sourceShip = Hyperspace.Global.GetInstance():GetShipManager(payload.sourceShipId)
    if sourceShip and payload.crew then
        place_crew(payload, payload.sourceShipId, payload.sourceRoomId)
    else
        clear_crew_transport_marker(payload.crew, payload.transportId)
    end

    pod.activeTransports[transportId] = nil
end

local function launch_transport_projectile(podCrew, ownerShip, targetShip)
    if not userdata_table then return nil end

    local blueprint = Hyperspace.Blueprints:GetWeaponBlueprint(POD_PROJECTILE_BLUEPRINT)
    if not blueprint then return nil end

    local sourceShipId = podCrew.iShipId
    local targetShipId = targetShip.iShipId

    local sourcePosition = ownerShip:GetRoomCenter(podCrew.iRoomId)
    local targetPosition = targetShip:GetRandomRoomCenter()
    local heading = sourceShipId == 0 and 0 or 180

    local spaceManager = Hyperspace.App and Hyperspace.App.world and Hyperspace.App.world.space
    if not spaceManager then return nil end

    return spaceManager:CreateMissile(
        blueprint,
        sourcePosition,
        sourceShipId,
        sourceShipId,
        targetPosition,
        targetShipId,
        heading)
end

script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power, shipManager)
    if not power or not power.def or power.def.name ~= LAUNCH_POWER then
        return
    end

    local podCrew = power.crew
    if not podCrew then return end
    if podCrew:GetSpecies() ~= POD_SPECIES then return end

    local ownerShip = Hyperspace.Global.GetInstance():GetShipManager(podCrew.iShipId)
    if not ownerShip then return end

    -- The payload must already be physically present in the drone room when
    -- LAUNCH activates.
    local payloadCrew = find_payload_crew(ownerShip, podCrew)
    if not payloadCrew then return end

    local targetShipId = 1 - podCrew.iShipId
    local targetShip = Hyperspace.Global.GetInstance():GetShipManager(targetShipId)
    if not targetShip then return end

    -- Do not remove the crew unless projectile creation succeeds.
    local projectile = launch_transport_projectile(podCrew, ownerShip, targetShip)
    if not projectile then return end

    local payload = create_transport_payload(payloadCrew, podCrew.iShipId, targetShipId)

    local podData = userdata_table(projectile, POD_USERDATA)
    podData.launchedByPod = true
    podData.transportId = payload.transportId
    podData.sourceShipId = payload.sourceShipId
    podData.targetShipId = payload.targetShipId
    podData.delivered = false

    mark_crew_in_transit(payload)
end)

-- Deliver the exact CrewMember stored at launch into the room hit by the pod.
script.on_internal_event(Defines.InternalEvents.DAMAGE_AREA_HIT, function(shipManager, projectile, location, damage, shipFriendlyFire)
    if not projectile or not projectile.extend then
        return Defines.Chain.CONTINUE
    end

    if projectile.extend.name ~= POD_PROJECTILE_BLUEPRINT then
        return Defines.Chain.CONTINUE
    end

    if not userdata_table then
        return Defines.Chain.CONTINUE
    end

    local podData = userdata_table(projectile, POD_USERDATA)
    if not podData or not podData.launchedByPod or podData.delivered then
        return Defines.Chain.CONTINUE
    end

    local transportId = podData.transportId
    local payload = transportId and pod.activeTransports[transportId] or nil
    if not payload then
        return Defines.Chain.CONTINUE
    end

    local roomId = Hyperspace.ShipGraph.GetShipInfo(shipManager.iShipId):GetSelectedRoom(
        location.x,
        location.y,
        true)

    if roomId == nil or roomId < 0 then
        return Defines.Chain.CONTINUE
    end

    if place_crew(payload, shipManager.iShipId, roomId) then
        podData.delivered = true
        pod.activeTransports[transportId] = nil
    end

    return Defines.Chain.CONTINUE
end)

-- If the physical pod projectile is destroyed before delivery, return the crew
-- to its original room for now. A later version can change this to whatever
-- consequence is desired for an intercepted boarding pod.
script.on_internal_event(Defines.InternalEvents.PROJECTILE_UPDATE_POST, function(projectile, preempted)
    if not projectile or not projectile.extend then
        return Defines.Chain.CONTINUE
    end

    if projectile.extend.name ~= POD_PROJECTILE_BLUEPRINT or not userdata_table then
        return Defines.Chain.CONTINUE
    end

    local podData = userdata_table(projectile, POD_USERDATA)
    if not podData or not podData.launchedByPod or podData.delivered then
        return Defines.Chain.CONTINUE
    end

    if projectile:Dead() and podData.transportId then
        return_transport_to_source(podData.transportId)
    end

    return Defines.Chain.CONTINUE
end)

-- Never leave a real crew member stranded out-of-game when the encounter ends.
script.on_internal_event(Defines.InternalEvents.JUMP_LEAVE, function(shipManager)
    local transportIds = {}

    for transportId, _ in pairs(pod.activeTransports) do
        transportIds[#transportIds + 1] = transportId
    end

    for _, transportId in ipairs(transportIds) do
        return_transport_to_source(transportId)
    end
end)