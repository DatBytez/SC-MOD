local userdata_table = mods.multiverse.userdata_table

mods.sc_drone_pod = mods.sc_drone_pod or {}
local pod = mods.sc_drone_pod

local POD_SPECIES = "terran_pod"
local LAUNCH_POWER = "LAUNCH"

-- Stage 3: the travel object is now a projectile rather than a BOARDER drone.
-- This lets us create an ordinary CrewMember at impact instead of a drone crew.
local POD_PROJECTILE_BLUEPRINT = "TERRAN_POD_PROJECTILE"
local TEST_PAYLOAD_BLUEPRINT = "terran_marine"

pod.nextTransportId = pod.nextTransportId or 0
pod.activeTransports = pod.activeTransports or {}

local function create_transport_payload(sourceShipId, targetShipId)
    pod.nextTransportId = pod.nextTransportId + 1

    local payload = {
        transportId = pod.nextTransportId,
        mode = "blueprint_test",
        crewBlueprint = TEST_PAYLOAD_BLUEPRINT,
        sourceShipId = sourceShipId,
        targetShipId = targetShipId
    }

    pod.activeTransports[payload.transportId] = payload
    return payload
end

local function launch_transport_projectile(podCrew, ownerShip, targetShip)
    if not userdata_table then return nil end

    local blueprint = Hyperspace.Blueprints:GetWeaponBlueprint(POD_PROJECTILE_BLUEPRINT)
    if not blueprint then return nil end

    local sourceShipId = podCrew.iShipId
    local targetShipId = targetShip.iShipId

    -- Launch from the room containing the crew drone. For the boarding pod this
    -- should normally be the drone-control room.
    local sourcePosition = ownerShip:GetRoomCenter(podCrew.iRoomId)
    local targetPosition = targetShip:GetRandomRoomCenter()

    -- Normal player projectiles face right; enemy projectiles face left.
    local heading = sourceShipId == 0 and 0 or 180

    local spaceManager = Hyperspace.App and Hyperspace.App.world and Hyperspace.App.world.space
    if not spaceManager then return nil end

    local projectile = spaceManager:CreateMissile(
        blueprint,
        sourcePosition,
        sourceShipId,
        sourceShipId,
        targetPosition,
        targetShipId,
        heading)

    return projectile
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

    local targetShipId = 1 - podCrew.iShipId
    local targetShip = Hyperspace.Global.GetInstance():GetShipManager(targetShipId)
    if not targetShip then return end

    local projectile = launch_transport_projectile(podCrew, ownerShip, targetShip)
    if not projectile then return end

    local payload = create_transport_payload(podCrew.iShipId, targetShipId)

    -- The projectile carries only the transport ID plus enough identifying data
    -- for the current test. In the next stage activeTransports[transportId] can
    -- contain a serialized record of the actual crew member removed at launch.
    local podData = userdata_table(projectile, "mods.sc.dronePod")
    podData.launchedByPod = true
    podData.transportId = payload.transportId
    podData.crewBlueprint = payload.crewBlueprint
    podData.sourceShipId = payload.sourceShipId
    podData.targetShipId = payload.targetShipId
end)

-- Projectile impacts use the same DAMAGE_AREA_HIT hook used by MV/Fusion weapon
-- scripts. Nothing in the projectile blueprint spawns crew automatically; Lua
-- creates an ordinary CrewMember here so the result is not treated as a drone.
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

    local podData = userdata_table(projectile, "mods.sc.dronePod")
    if not podData or not podData.launchedByPod or podData.delivered then
        return Defines.Chain.CONTINUE
    end

    local roomId = Hyperspace.ShipGraph.GetShipInfo(shipManager.iShipId):GetSelectedRoom(
        location.x,
        location.y,
        true)

    if roomId == nil or roomId < 0 then
        return Defines.Chain.CONTINUE
    end

    local crewBlueprintName = podData.crewBlueprint or TEST_PAYLOAD_BLUEPRINT
    local crewBlueprint = Hyperspace.Blueprints:GetCrewBlueprint(crewBlueprintName)
    if not crewBlueprint then
        return Defines.Chain.CONTINUE
    end

    -- A crew member transported to the opposing ship is an intruder there.
    local intruder = podData.sourceShipId ~= shipManager.iShipId

    local spawnedCrew = shipManager:AddCrewMemberFromBlueprint(
        crewBlueprint,
        0,
        true,
        roomId,
        intruder)

    if spawnedCrew then
        podData.delivered = true

        if podData.transportId then
            pod.activeTransports[podData.transportId] = nil
        end
    end

    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.JUMP_LEAVE, function()
    pod.activeTransports = {}
end)
