--[[
DESCRIPTION: Controls Terran Drop Pod deployment and outbound crew transport.
        - TERRAN_POD is deployable only when eligible crew are in Drone Control and a hostile target ship is present.
        - LAUNCH selects every eligible crew member in Drone Control and fires one independent transport projectile for each.
        - Crew are removed from the source ship only after their transport projectile is successfully created.
        - The temporary pod crew-drone is retired after launching without taking health damage.
DEPENDENCIES: sc_drone_pod_core.lua, Multiverse userdata_table
]]

local userdata_table = mods.multiverse.userdata_table
local pod = mods.sc_drone_pod

local POD_SPECIES = "terran_pod"
local LAUNCH_POWER = "LAUNCH"
local POD_PROJECTILE_BLUEPRINT = "TERRAN_POD_PROJECTILE"
local POD_DRONE_BLUEPRINT = "TERRAN_POD"
local POD_USERDATA = "mods.sc.dronePod"
local POD_BLOCK_DESTROYED_TIMER = 0.1

local function get_drone_room_id(ownerShip)
    if not ownerShip or not ownerShip.droneSystem then return nil end

    local ok, roomId = pcall(function()
        return ownerShip.droneSystem.roomId
    end)

    if not ok or roomId == nil or roomId < 0 then return nil end

    return roomId
end

local function find_payload_crew(ownerShip, podCrew, droneRoomId)
    local crewList = ownerShip.vCrewList
    if not crewList then return nil end

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if crew
            and crew ~= podCrew
            and crew.iShipId == ownerShip.iShipId
            and crew.currentShipId == ownerShip.iShipId
            and crew.iRoomId == droneRoomId
            and crew:IsCrew()
            and not crew:IsDrone()
            and not crew.bDead
            and not crew.bOutOfGame then

            return crew
        end
    end

    return nil
end

local function find_payload_crews(ownerShip, podCrew, droneRoomId)
    local payloadCrews = {}
    local crewList = ownerShip.vCrewList

    if not crewList then return payloadCrews end

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if crew
            and crew ~= podCrew
            and crew.iShipId == ownerShip.iShipId
            and crew.currentShipId == ownerShip.iShipId
            and crew.iRoomId == droneRoomId
            and crew:IsCrew()
            and not crew:IsDrone()
            and not crew.bDead
            and not crew.bOutOfGame then

            payloadCrews[#payloadCrews + 1] = crew
        end
    end

    return payloadCrews
end

local function has_hostile_target_ship()
    local enemyShip = Hyperspace.Global.GetInstance():GetShipManager(1)

    if not enemyShip
        or enemyShip.bDestroyed
        or not enemyShip._targetable then
        return false
    end

    return enemyShip._targetable.hostile
end

local function update_pod_deployment_guard(shipManager)
    if shipManager.iShipId ~= 0 then return end

    local droneSystem = shipManager.droneSystem
    if not droneSystem or not droneSystem.drones then return end

    local droneRoomId = get_drone_room_id(shipManager)
    local payloadReady = false

    if droneRoomId ~= nil then
        payloadReady = find_payload_crew(shipManager, nil, droneRoomId) ~= nil
    end

    local podReady = payloadReady and has_hostile_target_ship()

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
    local spaceManager = Hyperspace.App.world.space

    return spaceManager:CreateMissile(
        blueprint,
        sourcePosition,
        sourceShipId,
        sourceShipId,
        targetPosition,
        targetShipId,
        heading
    )
end

local function remove_pod_crew(podCrew)
    pcall(function()
        podCrew:EmptySlot()
    end)

    podCrew:SetCloneReady(false)
    podCrew:SetOutOfGame()
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

    local targetShipId = 1 - podCrew.iShipId
    local targetShip = Hyperspace.Global.GetInstance():GetShipManager(targetShipId)

    if not targetShip
        or targetShip.bDestroyed
        or not targetShip._targetable
        or not targetShip._targetable.hostile then
        return
    end

    for _, payloadCrew in ipairs(payloadCrews) do
        local projectile = launch_transport_projectile(podCrew, ownerShip, targetShip)

        if projectile then
            local payload = pod.create_transport_payload(payloadCrew, podCrew.iShipId, targetShipId)
            local podData = userdata_table(projectile, POD_USERDATA)

            podData.launchedByPod = true
            podData.transportId = payload.transportId
            podData.sourceShipId = payload.sourceShipId
            podData.targetShipId = payload.targetShipId
            podData.delivered = false

            if not pod.remove_original_crew(payloadCrew, payload.transportId) then
                pod.activeTransports[payload.transportId] = nil
            end
        end
    end

    remove_pod_crew(podCrew)
end)