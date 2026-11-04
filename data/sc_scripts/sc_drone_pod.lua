--[[
DESCRIPTION: Controls Terran Drop Pod deployment and launch eligibility.
        - TERRAN_POD is deployable only when eligible crew are in Drone Control and a hostile target ship is present.
        - Launching sends every eligible crew member in Drone Control through the Drop Pod transport system.
DEPENDENCIES: sc_drone_pod_transport.lua
]]

local pod = mods.sc.dronePod

local POD_SPECIES = "terran_pod"
local POD_DRONE_BLUEPRINT = "TERRAN_POD"
local LAUNCH_POWER = "SC_LAUNCH"

local function get_drone_room_id(shipManager)
    local droneSystem = shipManager.droneSystem
    if not droneSystem then return nil end

    local roomId = droneSystem.roomId
    if roomId < 0 then return nil end

    return roomId
end

local function is_payload_crew(crew, ownerShip, droneRoomId)
    return crew.iShipId == ownerShip.iShipId
        and crew.iRoomId == droneRoomId
        and not crew:IsDrone()
        and not crew.bDead
        and not crew.bOutOfGame
end

local function find_payload_crew(ownerShip, droneRoomId)
    local crewList = ownerShip.vCrewList

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if is_payload_crew(crew, ownerShip, droneRoomId) then
            return crew
        end
    end

    return nil
end

local function find_payload_crews(ownerShip, droneRoomId)
    local payloadCrews = {}
    local crewList = ownerShip.vCrewList

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if is_payload_crew(crew, ownerShip, droneRoomId) then
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
    if not droneSystem then return end

    local droneRoomId = get_drone_room_id(shipManager)
    local payloadReady = droneRoomId ~= nil
        and find_payload_crew(shipManager, droneRoomId) ~= nil

    local podReady = payloadReady and get_hostile_target_ship(shipManager.iShipId) ~= nil

    for i = 0, droneSystem.drones:size() - 1 do
        local drone = droneSystem.drones[i]

        if drone.blueprint.name == POD_DRONE_BLUEPRINT
            and not drone.bDead
            and not drone.deployed
            and not drone.powered then

            local desiredTimer = podReady and 0 or 0.1

            if math.abs(drone.destroyedTimer - desiredTimer) > 0.0001 then
                drone.destroyedTimer = desiredTimer
            end
        end
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

    local payloadCrews = find_payload_crews(ownerShip, droneRoomId)
    if #payloadCrews == 0 then return end

    local targetShip = get_hostile_target_ship(podCrew.iShipId)
    if not targetShip then return end

    for _, payloadCrew in ipairs(payloadCrews) do
        pod.launch(payloadCrew, ownerShip, targetShip)
    end
end)