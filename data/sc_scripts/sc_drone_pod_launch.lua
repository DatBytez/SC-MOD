--[[
DESCRIPTION: Launch portion of the post-teleport SetOutOfGame test.
        - Every eligible normal crew member in actual Drone Control gets one pod missile.
        - Each passenger gets its own preselected target room.
        - Every customTele destination is armed before one room-wide TeleportCrew().
        - NO transparent animation, mind control, SetOutOfGame, or other hiding is
          applied before/during native outbound teleport.
        - SetOutOfGame parking happens only after transport.lua observes that the
          passenger has fully arrived on the target ship.
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
    local ok, roomId = pcall(function() return ownerShip.droneSystem.roomId end)
    if not ok or roomId == nil or roomId < 0 then return nil end
    return roomId
end

local function find_payload_crews(ownerShip, podCrew, droneRoomId)
    local result = {}
    local crewList = ownerShip and ownerShip.vCrewList
    if not crewList then return result end

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

            result[#result + 1] = crew
        end
    end

    return result
end

local function has_hostile_target_ship()
    local enemyShip = Hyperspace.Global.GetInstance():GetShipManager(1)
    return enemyShip
        and not enemyShip.bDestroyed
        and enemyShip._targetable
        and enemyShip._targetable.hostile
end

local function select_target_room(targetShip)
    local targetPosition = targetShip and targetShip:GetRandomRoomCenter() or nil
    if not targetPosition then return nil, nil end

    local roomId =
        Hyperspace.ShipGraph.GetShipInfo(targetShip.iShipId)
            :GetSelectedRoom(targetPosition.x, targetPosition.y, true)

    if roomId == nil or roomId < 0 then return nil, nil end
    return roomId, targetPosition
end

local function create_pod_missile(podCrew, ownerShip, targetShip, targetPosition)
    local blueprint =
        Hyperspace.Blueprints:GetWeaponBlueprint(POD_PROJECTILE_BLUEPRINT)
    if not blueprint then return nil end

    local sourcePosition = ownerShip:GetRoomCenter(podCrew.iRoomId)
    local heading = podCrew.iShipId == 0 and 0 or 180

    return Hyperspace.App.world.space:CreateMissile(
        blueprint,
        sourcePosition,
        podCrew.iShipId,
        podCrew.iShipId,
        targetPosition,
        targetShip.iShipId,
        heading
    )
end

local function update_pod_deployment_guard(shipManager)
    if not shipManager or shipManager.iShipId ~= 0 then return end

    local droneSystem = shipManager.droneSystem
    if not droneSystem or not droneSystem.drones then return end

    local droneRoomId = get_drone_room_id(shipManager)
    local passengerReady = false

    if droneRoomId ~= nil then
        passengerReady =
            #find_payload_crews(shipManager, nil, droneRoomId) > 0
    end

    local podReady = passengerReady and has_hostile_target_ship()

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

local function clear_failed_batch(payloads)
    for _, payload in ipairs(payloads) do
        local crew = payload.crew

        if crew and crew.extend and crew.extend.customTele then
            crew.extend.customTele.shipId = -1
        end

        pod.activeTransports[payload.transportId] = nil
    end
end

script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    update_pod_deployment_guard
)

script.on_internal_event(
    Defines.InternalEvents.ACTIVATE_POWER,
    function(power)
        if not power or not power.def or power.def.name ~= LAUNCH_POWER then return end

        local podCrew = power.crew
        if not podCrew or podCrew:GetSpecies() ~= POD_SPECIES then return end

        local ownerShip =
            Hyperspace.Global.GetInstance():GetShipManager(podCrew.iShipId)
        if not ownerShip then return end

        local sourceRoomId = get_drone_room_id(ownerShip)
        if sourceRoomId == nil then return end

        local passengers = find_payload_crews(ownerShip, podCrew, sourceRoomId)
        if #passengers == 0 then return end

        local targetShipId = 1 - podCrew.iShipId
        local targetShip =
            Hyperspace.Global.GetInstance():GetShipManager(targetShipId)

        if not targetShip
            or targetShip.bDestroyed
            or not targetShip._targetable
            or not targetShip._targetable.hostile then
            return
        end

        local payloads = {}

        for _, passenger in ipairs(passengers) do
            local targetRoomId, targetPosition = select_target_room(targetShip)

            if targetRoomId == nil then
                pod.debug_line("LAUNCH BLOCK: no target room")
                return
            end

            local projectile =
                create_pod_missile(podCrew, ownerShip, targetShip, targetPosition)

            if not projectile then
                pod.debug_line("LAUNCH BLOCK: missile create failed")
                return
            end

            local payload =
                pod.create_transport_payload(
                    passenger,
                    projectile,
                    ownerShip.iShipId,
                    sourceRoomId,
                    targetShipId,
                    targetRoomId,
                    targetPosition
                )

            local projectileData = userdata_table(projectile, POD_USERDATA)
            projectileData.launchedByPod = true
            projectileData.transportId = payload.transportId
            projectileData.delivered = false

            payloads[#payloads + 1] = payload
        end

        for _, payload in ipairs(payloads) do
            local crew = payload.crew
            local customTele =
                crew and crew.extend and crew.extend.customTele or nil

            if not customTele then
                pod.debug_line(
                    "LAUNCH FAIL T" .. tostring(payload.transportId) .. ": no customTele"
                )
                clear_failed_batch(payloads)
                return
            end

            customTele.shipId = payload.targetShipId
            customTele.roomId = payload.targetRoomId
            customTele.slotId = -1

            pod.describe_crew(
                "ARMED T" .. tostring(payload.transportId)
                .. " targetR=" .. tostring(payload.targetRoomId),
                crew
            )
        end

        local callOk, returnedOrError =
            pcall(function()
                return ownerShip:TeleportCrew(sourceRoomId, false)
            end)

        if not callOk then
            pod.debug_line("OUTBOUND ERROR " .. tostring(returnedOrError))
            clear_failed_batch(payloads)
            return
        end

        local returned = returnedOrError

        if not returned then
            pod.debug_line("OUTBOUND FAIL returned=nil")
            clear_failed_batch(payloads)
            return
        end

        pod.debug_line(
            "OUTBOUND CALL passengers=" .. tostring(#payloads)
            .. " returned=" .. tostring(returned:size())
        )

        for _, payload in ipairs(payloads) do
            pod.debug_line(
                "OUTBOUND T" .. tostring(payload.transportId)
                .. " sameRef="
                .. tostring(pod.returned_vector_contains(returned, payload.crew))
            )
        end
    end
)
