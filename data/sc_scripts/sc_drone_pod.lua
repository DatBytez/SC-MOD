local userdata_table = mods.multiverse.userdata_table

mods.sc_drone_pod = mods.sc_drone_pod or {}
local pod = mods.sc_drone_pod

local POD_SPECIES = "terran_pod"
local LAUNCH_POWER = "LAUNCH"
local POD_PROJECTILE_BLUEPRINT = "TERRAN_POD_PROJECTILE"
local POD_USERDATA = "mods.sc.dronePod"
local DRONE_SYSTEM_ID = 4

pod.nextTransportId = pod.nextTransportId or 0
pod.activeTransports = pod.activeTransports or {}
pod.debugLines = pod.debugLines or {}

local function debug_line(text)
    table.insert(pod.debugLines, tostring(text))

    while #pod.debugLines > 22 do
        table.remove(pod.debugLines, 1)
    end
end

local function bool_text(value)
    return value and "T" or "F"
end

local function crew_self_id(crew)
    if crew and crew.extend then
        return crew.extend.selfId
    end
    return nil
end

local function describe_crew(crew)
    if not crew then
        return "nil"
    end

    local health = crew.health
    local hp = health and health.first or "?"
    local maxHp = health and health.second or "?"

    return "id=" .. tostring(crew_self_id(crew))
        .. " owner=" .. tostring(crew.iShipId)
        .. " cur=" .. tostring(crew.currentShipId)
        .. " room=" .. tostring(crew.iRoomId)
        .. " hp=" .. tostring(hp) .. "/" .. tostring(maxHp)
        .. " out=" .. bool_text(crew.bOutOfGame)
        .. " dead=" .. bool_text(crew.bDead)
end

local function find_crew_list(crew)
    if not crew then
        return "none"
    end

    for shipId = 0, 1 do
        local ship = Hyperspace.Global.GetInstance():GetShipManager(shipId)
        local crewList = ship and ship.vCrewList

        if crewList then
            for i = 0, crewList:size() - 1 do
                if crewList[i] == crew then
                    return "S" .. tostring(shipId) .. "[" .. tostring(i) .. "]"
                end
            end
        end
    end

    return "none"
end

local function get_drone_room_id(ownerShip, podCrew)
    -- Prefer the actual Drone Control system object. This avoids assuming the
    -- temporary pod crew itself always occupies the Drone Control room.
    if ownerShip and ownerShip.droneSystem then
        local ok, roomId = pcall(
            function()
                return ownerShip.droneSystem.roomId
            end
        )

        if ok and roomId ~= nil and roomId >= 0 then
            return roomId, "droneSystem.roomId"
        end
    end

    -- Fallback to ShipManager:GetSystemRoom if available in the running build.
    if ownerShip then
        local ok, roomId = pcall(
            function()
                return ownerShip:GetSystemRoom(DRONE_SYSTEM_ID)
            end
        )

        if ok and roomId ~= nil and roomId >= 0 then
            return roomId, "GetSystemRoom(4)"
        end
    end

    -- Last-resort compatibility fallback.
    return podCrew and podCrew.iRoomId or -1, "pod room fallback"
end

local function describe_available_payload_rooms(ownerShip, podCrew)
    local crewList = ownerShip and ownerShip.vCrewList
    if not crewList then
        return "none"
    end

    local found = {}

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if crew
            and crew ~= podCrew
            and crew.iShipId == ownerShip.iShipId
            and crew.currentShipId == ownerShip.iShipId
            and crew:IsCrew()
            and not crew:IsDrone()
            and not crew.bDead
            and not crew.bOutOfGame then

            found[#found + 1] =
                tostring(crew_self_id(crew))
                .. "@R" .. tostring(crew.iRoomId)
        end
    end

    if #found == 0 then
        return "none"
    end

    return table.concat(found, ",")
end

local function find_payload_crew(ownerShip, podCrew, droneRoomId)
    local crewList = ownerShip.vCrewList
    if not crewList then
        return nil
    end

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

local function snapshot_crew(crew)
    if not crew then
        return nil
    end

    local health = crew.health

    return {
        name = crew:GetName(),
        species = crew:GetSpecies(),
        health = health and health.first or nil,
        maxHealth = health and health.second or nil,
        originalSelfId = crew_self_id(crew)
    }
end

local function create_transport_payload(crew, sourceShipId, targetShipId)
    pod.nextTransportId = pod.nextTransportId + 1

    local payload = {
        transportId = pod.nextTransportId,
        sourceShipId = sourceShipId,
        sourceRoomId = crew.iRoomId,
        targetShipId = targetShipId,
        snapshot = snapshot_crew(crew)
    }

    pod.activeTransports[payload.transportId] = payload
    return payload
end

local function remove_original_crew(crew, transportId)
    if not crew then
        return false
    end

    debug_line(
        "REMOVE before: "
        .. describe_crew(crew)
        .. " list=" .. find_crew_list(crew)
    )

    if userdata_table then
        local crewData = userdata_table(crew, POD_USERDATA)
        crewData.inTransit = true
        crewData.transportId = transportId
    end

    -- SetOutOfGame proved to remove the crew from normal play immediately.
    -- We are no longer trying to revive this object. Instead, its state has
    -- already been copied into the transport payload.
    crew:SetOutOfGame()

    -- Explicitly prevent the removed source entity from becoming clone-ready.
    -- The replacement crew will be created from the saved transport snapshot.
    crew:SetCloneReady(false)

    debug_line(
        "REMOVE after:  "
        .. describe_crew(crew)
        .. " list=" .. find_crew_list(crew)
    )

    return true
end

local function recreate_crew(payload, shipManager, roomId)
    if not payload or not payload.snapshot or not shipManager then
        debug_line("RECREATE failed: missing payload/ship")
        return nil
    end

    local snapshot = payload.snapshot
    local intruder = payload.sourceShipId ~= shipManager.iShipId

    debug_line(
        "RECREATE request: transport=" .. tostring(payload.transportId)
        .. " name=" .. tostring(snapshot.name)
        .. " race=" .. tostring(snapshot.species)
        .. " target=S" .. tostring(shipManager.iShipId)
        .. " R" .. tostring(roomId)
        .. " intruder=" .. bool_text(intruder)
        .. " sex=fixed false"
    )

    -- Use AddCrewMemberFromString so every impact creates a brand-new CrewMember
    -- and the transported crew's saved name can be supplied directly.
    --
    -- The earlier test failed because snapshot.male was nil, not because this
    -- creation method was unsuitable. Sex is irrelevant for SC-MOD here, so a
    -- real boolean is supplied explicitly instead.
    local spawnOk, spawnResult = pcall(
        function()
            return shipManager:AddCrewMemberFromString(
                snapshot.name,
                snapshot.species,
                intruder,
                roomId,
                true,
                false
            )
        end
    )

    debug_line(
        "RECREATE call: ok=" .. tostring(spawnOk)
        .. " returned=" .. tostring(spawnResult ~= nil)
    )

    if not spawnOk then
        debug_line("RECREATE call error: " .. tostring(spawnResult))
        return nil
    end

    local newCrew = spawnResult
    if not newCrew then
        debug_line("RECREATE failed: spawn returned nil")
        return nil
    end

    local newSelfId = crew_self_id(newCrew)
    local previousSelfId = pod.lastSpawnedCrewSelfId

    debug_line(
        "NEW CREW: transport=" .. tostring(payload.transportId)
        .. " previous=" .. tostring(previousSelfId)
        .. " new=" .. tostring(newSelfId)
        .. " distinct=" .. tostring(
            previousSelfId == nil or previousSelfId ~= newSelfId
        )
    )

    pod.lastSpawnedCrewSelfId = newSelfId

    local inspectOk, inspectText = pcall(
        function()
            return describe_crew(newCrew)
                .. " list=" .. find_crew_list(newCrew)
        end
    )

    if inspectOk then
        debug_line(
            "RECREATE spawned: oldId="
            .. tostring(snapshot.originalSelfId)
            .. " new " .. inspectText
        )
    else
        debug_line(
            "RECREATE spawned; inspect ERROR: "
            .. tostring(inspectText)
        )
    end

    -- Restore current health after creation.
    if snapshot.health then
        local healthOk, healthText = pcall(
            function()
                local currentHealth = newCrew:GetIntegerHealth()
                local targetHealth = snapshot.health

                if targetHealth < 1 then
                    targetHealth = 1
                end

                local healthDelta = targetHealth - currentHealth

                if math.abs(healthDelta) > 0.001 then
                    newCrew:DirectModifyHealth(healthDelta)
                end

                return "from=" .. tostring(currentHealth)
                    .. " target=" .. tostring(targetHealth)
                    .. " delta=" .. tostring(healthDelta)
                    .. " now=" .. tostring(newCrew:GetIntegerHealth())
            end
        )

        if healthOk then
            debug_line("HEALTH restore: " .. healthText)
        else
            debug_line(
                "HEALTH restore ERROR: "
                .. tostring(healthText)
            )
        end
    end

    return newCrew
end

local function return_transport_to_source(transportId)
    local payload = pod.activeTransports[transportId]
    if not payload then
        return
    end

    local sourceShip =
        Hyperspace.Global.GetInstance():GetShipManager(payload.sourceShipId)

    if sourceShip then
        local returnedCrew =
            recreate_crew(payload, sourceShip, payload.sourceRoomId)

        if returnedCrew then
            debug_line(
                "RETURNED transport " .. tostring(transportId)
                .. " to source"
            )
        else
            debug_line(
                "RETURN FAILED transport " .. tostring(transportId)
            )
        end
    else
        debug_line(
            "RETURN FAILED transport " .. tostring(transportId)
            .. ": source ship missing"
        )
    end

    pod.activeTransports[transportId] = nil
end

local function launch_transport_projectile(podCrew, ownerShip, targetShip)
    if not userdata_table then
        return nil
    end

    local blueprint =
        Hyperspace.Blueprints:GetWeaponBlueprint(POD_PROJECTILE_BLUEPRINT)

    if not blueprint then
        return nil
    end

    local sourceShipId = podCrew.iShipId
    local targetShipId = targetShip.iShipId

    local sourcePosition = ownerShip:GetRoomCenter(podCrew.iRoomId)
    local targetPosition = targetShip:GetRandomRoomCenter()
    local heading = sourceShipId == 0 and 0 or 180

    local spaceManager =
        Hyperspace.App
        and Hyperspace.App.world
        and Hyperspace.App.world.space

    if not spaceManager then
        return nil
    end

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

script.on_internal_event(
    Defines.InternalEvents.ACTIVATE_POWER,
    function(power, shipManager)
        if not power
            or not power.def
            or power.def.name ~= LAUNCH_POWER then
            return
        end

        local podCrew = power.crew
        if not podCrew then
            return
        end

        if podCrew:GetSpecies() ~= POD_SPECIES then
            return
        end

        pod.debugLines = {}

        debug_line(
            "LAUNCH power: pod S" .. tostring(podCrew.iShipId)
            .. " podR=" .. tostring(podCrew.iRoomId)
        )

        local ownerShip =
            Hyperspace.Global.GetInstance():GetShipManager(podCrew.iShipId)

        if not ownerShip then
            debug_line("FAIL: owner ship missing")
            return
        end

        local droneRoomId, droneRoomSource =
            get_drone_room_id(ownerShip, podCrew)

        debug_line(
            "DRONE ROOM: R" .. tostring(droneRoomId)
            .. " via " .. tostring(droneRoomSource)
            .. " podR=" .. tostring(podCrew.iRoomId)
        )

        local payloadCrew =
            find_payload_crew(ownerShip, podCrew, droneRoomId)

        if not payloadCrew then
            debug_line(
                "FAIL: no normal crew in drone room R"
                .. tostring(droneRoomId)
            )
            debug_line(
                "AVAILABLE normal crew: "
                .. describe_available_payload_rooms(ownerShip, podCrew)
            )
            return
        end

        debug_line(
            "PAYLOAD selected: "
            .. describe_crew(payloadCrew)
            .. " list=" .. find_crew_list(payloadCrew)
        )

        local targetShipId = 1 - podCrew.iShipId
        local targetShip =
            Hyperspace.Global.GetInstance():GetShipManager(targetShipId)

        if not targetShip then
            debug_line("FAIL: target ship missing")
            return
        end

        local projectile =
            launch_transport_projectile(podCrew, ownerShip, targetShip)

        debug_line(
            "CreateMissile=" .. tostring(projectile ~= nil)
            .. " target=S" .. tostring(targetShipId)
        )

        if not projectile then
            return
        end

        local payload =
            create_transport_payload(
                payloadCrew,
                podCrew.iShipId,
                targetShipId
            )

        local snapshot = payload.snapshot

        debug_line(
            "SNAPSHOT id=" .. tostring(payload.transportId)
            .. " oldCrewId=" .. tostring(snapshot.originalSelfId)
            .. " name=" .. tostring(snapshot.name)
            .. " race=" .. tostring(snapshot.species)
            .. " hp=" .. tostring(snapshot.health)
        )

        local podData = userdata_table(projectile, POD_USERDATA)
        podData.launchedByPod = true
        podData.transportId = payload.transportId
        podData.sourceShipId = payload.sourceShipId
        podData.targetShipId = payload.targetShipId
        podData.delivered = false

        debug_line(
            "PROJECTILE userdata id="
            .. tostring(podData.transportId)
        )

        if remove_original_crew(payloadCrew, payload.transportId) then
            -- Do not retain the source CrewMember pointer. From this point on,
            -- the transport consists only of serialized state plus its ID.
            payloadCrew = nil
        else
            pod.activeTransports[payload.transportId] = nil
            debug_line("FAIL: source crew was not removed")
        end
    end
)

script.on_internal_event(
    Defines.InternalEvents.DAMAGE_AREA_HIT,
    function(
        shipManager,
        projectile,
        location,
        damage,
        shipFriendlyFire
    )
        if not projectile or not projectile.extend then
            return Defines.Chain.CONTINUE
        end

        if projectile.extend.name ~= POD_PROJECTILE_BLUEPRINT then
            return Defines.Chain.CONTINUE
        end

        if not userdata_table then
            return Defines.Chain.CONTINUE
        end

        debug_line(
            "HIT callback: ship=S" .. tostring(shipManager.iShipId)
            .. " loc=" .. tostring(location.x)
            .. "," .. tostring(location.y)
        )

        local podData = userdata_table(projectile, POD_USERDATA)

        debug_line(
            "HIT userdata: launched="
            .. tostring(podData and podData.launchedByPod)
            .. " id=" .. tostring(podData and podData.transportId)
            .. " delivered="
            .. tostring(podData and podData.delivered)
        )

        if not podData
            or not podData.launchedByPod
            or podData.delivered then
            return Defines.Chain.CONTINUE
        end

        local transportId = podData.transportId
        local payload =
            transportId
            and pod.activeTransports[transportId]
            or nil

        if not payload then
            debug_line("HIT failed: transport payload missing")
            return Defines.Chain.CONTINUE
        end

        local roomId =
            Hyperspace.ShipGraph
                .GetShipInfo(shipManager.iShipId)
                :GetSelectedRoom(
                    location.x,
                    location.y,
                    true
                )

        debug_line("HIT resolved room=R" .. tostring(roomId))

        if roomId == nil or roomId < 0 then
            debug_line("HIT failed: invalid room")
            return Defines.Chain.CONTINUE
        end

        local newCrew =
            recreate_crew(payload, shipManager, roomId)

        if newCrew then
            podData.delivered = true
            pod.activeTransports[transportId] = nil

            debug_line(
                "DELIVERED transport "
                .. tostring(transportId)
            )
        else
            debug_line(
                "DELIVERY FAILED transport "
                .. tostring(transportId)
            )
        end

        return Defines.Chain.CONTINUE
    end
)

script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_UPDATE_POST,
    function(projectile, preempted)
        if not projectile or not projectile.extend then
            return Defines.Chain.CONTINUE
        end

        if projectile.extend.name ~= POD_PROJECTILE_BLUEPRINT
            or not userdata_table then
            return Defines.Chain.CONTINUE
        end

        local podData = userdata_table(projectile, POD_USERDATA)

        if not podData
            or not podData.launchedByPod
            or podData.delivered then
            return Defines.Chain.CONTINUE
        end

        if projectile:Dead() and podData.transportId then
            debug_line(
                "PROJECTILE lost: returning transport "
                .. tostring(podData.transportId)
            )

            return_transport_to_source(podData.transportId)
        end

        return Defines.Chain.CONTINUE
    end
)

script.on_internal_event(
    Defines.InternalEvents.JUMP_LEAVE,
    function(shipManager)
        local transportIds = {}

        for transportId, _ in pairs(pod.activeTransports) do
            transportIds[#transportIds + 1] = transportId
        end

        for _, transportId in ipairs(transportIds) do
            debug_line(
                "JUMP cleanup: returning transport "
                .. tostring(transportId)
            )

            return_transport_to_source(transportId)
        end
    end
)