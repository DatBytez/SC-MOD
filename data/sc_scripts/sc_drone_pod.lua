local userdata_table = mods.multiverse.userdata_table

mods.sc_drone_pod = mods.sc_drone_pod or {}
local pod = mods.sc_drone_pod

local POD_SPECIES = "terran_pod"
local LAUNCH_POWER = "LAUNCH"
local POD_PROJECTILE_BLUEPRINT = "TERRAN_POD_PROJECTILE"
local POD_DRONE_BLUEPRINT = "TERRAN_POD"
local POD_USERDATA = "mods.sc.dronePod"

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

local function get_drone_room_id(ownerShip)
    -- Strict rule: payload crew may only be selected from the actual
    -- Drone Control system room. If that room cannot be resolved, abort.
    if not ownerShip or not ownerShip.droneSystem then
        return nil
    end

    local ok, roomId = pcall(
        function()
            return ownerShip.droneSystem.roomId
        end
    )

    if not ok or roomId == nil or roomId < 0 then
        return nil
    end

    return roomId
end

local function describe_drone_room_payloads(ownerShip, podCrew, droneRoomId)
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
            and crew.iRoomId == droneRoomId
            and crew:IsCrew()
            and not crew:IsDrone()
            and not crew.bDead
            and not crew.bOutOfGame then

            found[#found + 1] =
                tostring(crew_self_id(crew))
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


local function update_pod_deployment_guard(shipManager)
    -- This guard is player-only. Enemy use can be handled separately later if
    -- desired, but it should not affect enemy drone AI now.
    if not shipManager or shipManager.iShipId ~= 0 then
        return
    end

    local droneSystem = shipManager.droneSystem
    if not droneSystem or not droneSystem.drones then
        return
    end

    -- Strictly use the actual Drone Control room. If it cannot be resolved,
    -- the pod remains blocked rather than falling back to another room.
    local droneRoomId = get_drone_room_id(shipManager)
    local payloadReady = false

    if droneRoomId ~= nil then
        payloadReady =
            find_payload_crew(
                shipManager,
                nil,
                droneRoomId
            ) ~= nil
    end

    local normalPower = nil
    local blockedPower = droneSystem:GetMaxPower() + 1

    for i = 0, droneSystem.drones:size() - 1 do
        local drone = droneSystem.drones[i]

        if drone
            and drone.blueprint
            and drone.blueprint.name == POD_DRONE_BLUEPRINT then

            normalPower = drone.blueprint.power

            -- Never alter an already powered/deployed pod. The guard exists to
            -- prevent a new deployment, not to interfere with one in progress.
            if not drone.powered and not drone.deployed then
                local desiredPower =
                    payloadReady
                    and normalPower
                    or math.max(normalPower, blockedPower)

                if drone.powerRequired ~= desiredPower then
                    drone.powerRequired = desiredPower

                    local stateText =
                        payloadReady
                        and "READY"
                        or "BLOCKED"

                    if pod.lastDeploymentGuardState ~= stateText then
                        pod.lastDeploymentGuardState = stateText

                        debug_line(
                            "POD GUARD " .. stateText
                            .. ": droneR="
                            .. tostring(droneRoomId)
                            .. " power="
                            .. tostring(desiredPower)
                        )
                    end
                end
            end
        end
    end
end

script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    function(shipManager)
        update_pod_deployment_guard(shipManager)
    end
)


local function snapshot_crew_powers(crew)
    local snapshots = {}
    local powers = crew and crew.extend and crew.extend.crewPowers

    if not powers then
        return snapshots
    end

    for i = 0, powers:size() - 1 do
        local power = powers[i]

        if power then
            local cooldownCurrent =
                power.powerCooldown and power.powerCooldown.first or 0

            local cooldownTotal =
                power.powerCooldown and power.powerCooldown.second or 0

            local cooldownFraction = 1

            if cooldownTotal and cooldownTotal > 0 then
                cooldownFraction =
                    math.max(
                        0,
                        math.min(1, cooldownCurrent / cooldownTotal)
                    )
            end

            snapshots[#snapshots + 1] = {
                index = i,
                name =
                    power.def and power.def.name
                    or nil,
                cooldownCurrent = cooldownCurrent,
                cooldownTotal = cooldownTotal,
                cooldownFraction = cooldownFraction,
                chargesCurrent =
                    power.powerCharges
                    and power.powerCharges.first
                    or nil,
                chargesTotal =
                    power.powerCharges
                    and power.powerCharges.second
                    or nil
            }
        end
    end

    return snapshots
end

local function find_matching_power(crew, savedPower)
    local powers = crew and crew.extend and crew.extend.crewPowers
    if not powers or not savedPower then
        return nil
    end

    -- Same-race recreation should preserve power order. Prefer the original
    -- index when its definition name still matches.
    if savedPower.index ~= nil
        and savedPower.index >= 0
        and savedPower.index < powers:size() then

        local indexedPower = powers[savedPower.index]

        if indexedPower then
            local indexedName =
                indexedPower.def and indexedPower.def.name
                or nil

            if savedPower.name == nil
                or savedPower.name == indexedName then
                return indexedPower
            end
        end
    end

    -- Named fallback handles cases where another power changes the ordering.
    if savedPower.name ~= nil then
        for i = 0, powers:size() - 1 do
            local power = powers[i]

            if power
                and power.def
                and power.def.name == savedPower.name then
                return power
            end
        end
    end

    return nil
end

local function restore_crew_powers(crew, savedPowers)
    if not crew or not savedPowers then
        return
    end

    for _, savedPower in ipairs(savedPowers) do
        local power = find_matching_power(crew, savedPower)

        if power then
            local restoreOk, restoreText = pcall(
                function()
                    local newCooldownTotal =
                        power.powerCooldown.second

                    if newCooldownTotal and newCooldownTotal > 0 then
                        power.powerCooldown.first =
                            newCooldownTotal
                            * savedPower.cooldownFraction
                    elseif savedPower.cooldownCurrent ~= nil then
                        power.powerCooldown.first =
                            savedPower.cooldownCurrent
                    end

                    -- Preserve remaining charges when the ability uses them.
                    -- Keep the recreated power's current maximum, since that
                    -- may reflect the current definition/stat modifiers.
                    if savedPower.chargesCurrent ~= nil
                        and power.powerCharges then

                        local newChargesTotal =
                            power.powerCharges.second

                        if newChargesTotal ~= nil
                            and newChargesTotal >= 0 then

                            power.powerCharges.first =
                                math.max(
                                    0,
                                    math.min(
                                        savedPower.chargesCurrent,
                                        newChargesTotal
                                    )
                                )
                        else
                            power.powerCharges.first =
                                savedPower.chargesCurrent
                        end
                    end

                    return "name=" .. tostring(savedPower.name)
                        .. " cd="
                        .. string.format(
                            "%.2f/%.2f",
                            power.powerCooldown.first,
                            power.powerCooldown.second
                        )
                        .. " fraction="
                        .. string.format(
                            "%.2f",
                            savedPower.cooldownFraction
                        )
                        .. " charges="
                        .. tostring(power.powerCharges.first)
                        .. "/"
                        .. tostring(power.powerCharges.second)
                end
            )

            if restoreOk then
                debug_line("POWER restore: " .. restoreText)
            else
                debug_line(
                    "POWER restore ERROR: "
                    .. tostring(savedPower.name)
                    .. " "
                    .. tostring(restoreText)
                )
            end
        else
            debug_line(
                "POWER restore missing: "
                .. tostring(savedPower.name)
                .. " index="
                .. tostring(savedPower.index)
            )
        end
    end
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
        powers = snapshot_crew_powers(crew),
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

    -- Release the crew's occupied room tile before marking the source entity
    -- out-of-game. SetOutOfGame() removes the crew from normal play, but by
    -- itself it does not reliably clear the Room slot occupancy.
    local emptySlotOk, emptySlotError = pcall(
        function()
            crew:EmptySlot()
        end
    )

    debug_line(
        "EmptySlot: ok=" .. tostring(emptySlotOk)
        .. (emptySlotOk and "" or " error=" .. tostring(emptySlotError))
    )

    if not emptySlotOk then
        -- Do not consume the crew if its room tile cannot be released.
        if userdata_table then
            local crewData = userdata_table(crew, POD_USERDATA)
            crewData.inTransit = false
            crewData.transportId = nil
        end
        return false
    end

    -- Prevent the discarded source entity from becoming clone-ready.
    crew:SetCloneReady(false)

    -- The transport now owns a snapshot of this crew's state. The original
    -- CrewMember is intentionally retired and is never reused at destination.
    crew:SetOutOfGame()

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

    -- Restore power recharge/charge state immediately, before the recreated
    -- crew receives its next normal update and can auto-activate a reset power.
    restore_crew_powers(newCrew, snapshot.powers)

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

        local droneRoomId = get_drone_room_id(ownerShip)

        if droneRoomId == nil then
            debug_line("FAIL: Drone Control room unavailable")
            return
        end

        debug_line(
            "DRONE ROOM: R" .. tostring(droneRoomId)
            .. " podR=" .. tostring(podCrew.iRoomId)
            .. " strict=true"
        )

        local payloadCrew =
            find_payload_crew(ownerShip, podCrew, droneRoomId)

        if not payloadCrew then
            debug_line(
                "FAIL: no normal crew in drone room R"
                .. tostring(droneRoomId)
            )
            debug_line(
                "DRONE ROOM eligible crew: "
                .. describe_drone_room_payloads(
                    ownerShip,
                    podCrew,
                    droneRoomId
                )
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
            .. " powers=" .. tostring(#(snapshot.powers or {}))
        )

        for _, savedPower in ipairs(snapshot.powers or {}) do
            debug_line(
                "POWER save: name=" .. tostring(savedPower.name)
                .. " cd="
                .. string.format(
                    "%.2f/%.2f",
                    savedPower.cooldownCurrent or 0,
                    savedPower.cooldownTotal or 0
                )
                .. " fraction="
                .. string.format(
                    "%.2f",
                    savedPower.cooldownFraction or 0
                )
                .. " charges="
                .. tostring(savedPower.chargesCurrent)
                .. "/"
                .. tostring(savedPower.chargesTotal)
            )
        end

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