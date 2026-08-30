--[[
DESCRIPTION: Controls Terran Drop Pod deployment and crew transport.
        - TERRAN_POD is deployable only when eligible crew are in Drone Control and a hostile target ship is present.
        - LAUNCH fires one TERRAN_POD_PROJECTILE for each eligible crew member in Drone Control.
        - Crew are snapshotted and retired when their projectile launches, then recreated when it reaches the target.
        - Crew carried by a destroyed projectile are killed through FTL's normal crew-death handling so cloning can apply.
        - In-flight crew are abandoned without being returned or killed when the source ship jumps away.
        - The temporary pod crew-drone is removed by the LAUNCH power's native selfHealth effect.
DEPENDENCIES: sc_crew_copy.lua, Multiverse userdata_table
]]

local userdata_table = mods.multiverse.userdata_table
local crew_copy = mods.sc.crew_copy

mods.sc_drone_pod = mods.sc_drone_pod or {}
local pod = mods.sc_drone_pod

local POD_SPECIES = "terran_pod"
local LAUNCH_POWER = "LAUNCH"
local POD_PROJECTILE_BLUEPRINT = "TERRAN_POD_PROJECTILE"
local POD_DRONE_BLUEPRINT = "TERRAN_POD"
local POD_USERDATA = "mods.sc.dronePod"
local POD_BLOCK_DESTROYED_TIMER = 0.1

pod.nextTransportId = pod.nextTransportId or 0
pod.activeTransports = pod.activeTransports or {}

local function get_drone_room_id(shipManager)
    local droneSystem = shipManager.droneSystem
    if not droneSystem then return nil end

    local ok, roomId = pcall(function()
        return droneSystem.roomId
    end)

    if not ok or roomId == nil or roomId < 0 then return nil end

    return roomId
end

local function is_payload_crew(crew, ownerShip, podCrew, droneRoomId)
    return crew
        and crew ~= podCrew
        and crew.iShipId == ownerShip.iShipId
        and crew.currentShipId == ownerShip.iShipId
        and crew.iRoomId == droneRoomId
        and crew:IsCrew()
        and not crew:IsDrone()
        and not crew.bDead
        and not crew.bOutOfGame
end

local function find_payload_crew(ownerShip, podCrew, droneRoomId)
    local crewList = ownerShip.vCrewList

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if is_payload_crew(crew, ownerShip, podCrew, droneRoomId) then
            return crew
        end
    end

    return nil
end

local function find_payload_crews(ownerShip, podCrew, droneRoomId)
    local payloadCrews = {}
    local crewList = ownerShip.vCrewList

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if is_payload_crew(crew, ownerShip, podCrew, droneRoomId) then
            payloadCrews[#payloadCrews + 1] = crew
        end
    end

    return payloadCrews
end

local function get_hostile_target_ship(sourceShipId)
    local targetShip = Hyperspace.Global.GetInstance():GetShipManager(1 - sourceShipId)

    if not targetShip
        or targetShip.bDestroyed
        or not targetShip._targetable
        or not targetShip._targetable.hostile then
        return nil
    end

    return targetShip
end

local function update_pod_deployment_guard(shipManager)
    if shipManager.iShipId ~= 0 then return end

    local droneSystem = shipManager.droneSystem
    if not droneSystem or not droneSystem.drones then return end

    local droneRoomId = get_drone_room_id(shipManager)
    local payloadReady = droneRoomId ~= nil
        and find_payload_crew(shipManager, nil, droneRoomId) ~= nil

    local podReady = payloadReady and get_hostile_target_ship(shipManager.iShipId) ~= nil

    for i = 0, droneSystem.drones:size() - 1 do
        local drone = droneSystem.drones[i]

        if drone
            and drone.blueprint
            and drone.blueprint.name == POD_DRONE_BLUEPRINT
            and not drone.bDead
            and not drone.deployed
            and not drone.powered then

            local desiredTimer = podReady and 0 or POD_BLOCK_DESTROYED_TIMER

            if math.abs(drone.destroyedTimer - desiredTimer) > 0.0001 then
                drone.destroyedTimer = desiredTimer
            end
        end
    end
end

local function launch_transport_projectile(podCrew, ownerShip, targetShip)
    local blueprint = Hyperspace.Blueprints:GetWeaponBlueprint(POD_PROJECTILE_BLUEPRINT)
    if not blueprint then return nil end

    local sourceShipId = podCrew.iShipId
    local targetShipId = targetShip.iShipId
    local sourcePosition = ownerShip:GetRoomCenter(podCrew.iRoomId)
    local targetPosition = targetShip:GetRandomRoomCenter()
    local heading = sourceShipId == 0 and 0 or 180

    return Hyperspace.App.world.space:CreateMissile(
        blueprint,
        sourcePosition,
        sourceShipId,
        sourceShipId,
        targetPosition,
        targetShipId,
        heading
    )
end

local function create_transport_payload(crew)
    local snapshot = crew_copy.snapshot(crew)
    if not snapshot then return nil end

    pod.nextTransportId = pod.nextTransportId + 1

    local payload = {
        transportId = pod.nextTransportId,
        snapshot = snapshot
    }

    pod.activeTransports[payload.transportId] = payload
    return payload
end

local function kill_transport_crew(transportId)
    local payload = pod.activeTransports[transportId]
    if not payload then return end

    pod.activeTransports[transportId] = nil

    local snapshot = payload.snapshot
    local sourceShip = snapshot
        and Hyperspace.Global.GetInstance():GetShipManager(snapshot.currentShipId)
        or nil

    if not sourceShip or sourceShip.bDestroyed then return end

    local crew = crew_copy.recreate(snapshot, sourceShip, snapshot.roomId)

    if crew then
        crew:Kill(false)
    end
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, update_pod_deployment_guard)

script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power)
    if power.def.name ~= LAUNCH_POWER then return end

    local podCrew = power.crew
    if not podCrew or podCrew:GetSpecies() ~= POD_SPECIES then return end

    local ownerShip = Hyperspace.Global.GetInstance():GetShipManager(podCrew.iShipId)
    if not ownerShip then return end

    local droneRoomId = get_drone_room_id(ownerShip)
    if droneRoomId == nil then return end

    local payloadCrews = find_payload_crews(ownerShip, podCrew, droneRoomId)
    if #payloadCrews == 0 then return end

    local targetShip = get_hostile_target_ship(podCrew.iShipId)
    if not targetShip then return end

    for _, payloadCrew in ipairs(payloadCrews) do
        local projectile = launch_transport_projectile(podCrew, ownerShip, targetShip)

        if projectile then
            local payload = create_transport_payload(payloadCrew)

            if payload then
                userdata_table(projectile, POD_USERDATA).transportId = payload.transportId

                if not crew_copy.retire(payloadCrew) then
                    pod.activeTransports[payload.transportId] = nil
                end
            end
        end
    end
end)

script.on_internal_event(
    Defines.InternalEvents.DAMAGE_AREA_HIT,
    function(shipManager, projectile, location)
        if not projectile or not projectile.extend then
            return Defines.Chain.CONTINUE
        end

        if projectile.extend.name ~= POD_PROJECTILE_BLUEPRINT then
            return Defines.Chain.CONTINUE
        end

        local transportId = userdata_table(projectile, POD_USERDATA).transportId
        local payload = transportId and pod.activeTransports[transportId] or nil

        if not payload then return Defines.Chain.CONTINUE end

        local roomId = Hyperspace.ShipGraph
            .GetShipInfo(shipManager.iShipId)
            :GetSelectedRoom(location.x, location.y, true)

        if roomId == nil or roomId < 0 then
            return Defines.Chain.CONTINUE
        end

        if crew_copy.recreate(payload.snapshot, shipManager, roomId) then
            pod.activeTransports[transportId] = nil
        end

        return Defines.Chain.CONTINUE
    end
)

script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_UPDATE_POST,
    function(projectile)
        if not projectile or not projectile.extend then
            return Defines.Chain.CONTINUE
        end

        if projectile.extend.name ~= POD_PROJECTILE_BLUEPRINT then
            return Defines.Chain.CONTINUE
        end

        local transportId = userdata_table(projectile, POD_USERDATA).transportId

        if transportId
            and pod.activeTransports[transportId]
            and projectile:Dead() then

            kill_transport_crew(transportId)
        end

        return Defines.Chain.CONTINUE
    end
)

script.on_internal_event(Defines.InternalEvents.JUMP_LEAVE, function()
    -- The ship has left while these crew are still in transit. Forget the
    -- transports so projectile cleanup cannot return or kill the crew later.
    pod.activeTransports = {}
end)
