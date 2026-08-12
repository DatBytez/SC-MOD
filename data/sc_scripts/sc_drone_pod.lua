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
pod.returnableBoarders = pod.returnableBoarders or {}

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


local function find_payload_crews(ownerShip, podCrew, droneRoomId)
    local payloadCrews = {}
    local crewList = ownerShip and ownerShip.vCrewList

    if not crewList then
        return payloadCrews
    end

    -- Build the complete list before any crew are removed from play. This
    -- keeps discovery independent from EmptySlot()/SetOutOfGame() changes.
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
    local enemyShip =
        Hyperspace.Global.GetInstance():GetShipManager(1)

    if not enemyShip
        or enemyShip.bDestroyed
        or not enemyShip._targetable then
        return false
    end

    return enemyShip._targetable.hostile
end

local POD_BLOCK_DESTROYED_TIMER = 0.1

local function update_pod_deployment_guard(shipManager)
    -- Player-only deployment lock. Enemy drone behavior is unchanged.
    if not shipManager or shipManager.iShipId ~= 0 then
        return
    end

    local droneSystem = shipManager.droneSystem
    if not droneSystem or not droneSystem.drones then
        return
    end

    -- Strictly use the actual Drone Control room. Crew in any other room must
    -- never make TERRAN_POD available.
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

    local podReady = payloadReady and has_hostile_target_ship()

    for i = 0, droneSystem.drones:size() - 1 do
        local drone = droneSystem.drones[i]

        if drone
            and drone.blueprint
            and drone.blueprint.name == POD_DRONE_BLUEPRINT
            and not drone.bDead
            and not drone.deployed
            and not drone.powered then

            local desiredTimer =
                podReady
                and 0
                or POD_BLOCK_DESTROYED_TIMER

            -- Keep the timer pinned to the desired state. If FTL advances a
            -- positive destroyedTimer internally, the next SHIP_LOOP restores
            -- the small lock value rather than allowing it to finish.
            if math.abs(drone.destroyedTimer - desiredTimer) > 0.0001 then
                drone.destroyedTimer = desiredTimer
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
            pcall(
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
                end
            )
        end
    end
end

local function snapshot_crew_appearance(crew)
    local appearance = {
        colorChoices = {},
        layerColors = {}
    }

    if not crew then
        return appearance
    end

    pcall(
        function()
            -- Save the selected blueprint color indices. A freshly recreated
            -- crew can otherwise randomize these choices again.
            if crew.blueprint and crew.blueprint.colorChoices then
                for i = 0, crew.blueprint.colorChoices:size() - 1 do
                    appearance.colorChoices[#appearance.colorChoices + 1] =
                        crew.blueprint.colorChoices[i]
                end
            end

            -- Also save the exact live rendered RGBA values. This preserves
            -- colors even if another script changed the animation colors after
            -- the original blueprint choices were selected.
            if crew.crewAnim and crew.crewAnim.layerColors then
                for i = 0, crew.crewAnim.layerColors:size() - 1 do
                    local color = crew.crewAnim.layerColors[i]

                    appearance.layerColors[#appearance.layerColors + 1] = {
                        r = color.r,
                        g = color.g,
                        b = color.b,
                        a = color.a
                    }
                end
            end
        end
    )

    return appearance
end

local function restore_crew_appearance(crew, appearance)
    if not crew or not appearance then
        return
    end

    pcall(
        function()
            -- Restore the saved selected indices into this CrewMember's own
            -- blueprint copy.
            if crew.blueprint
                and crew.blueprint.colorChoices
                and appearance.colorChoices then

                crew.blueprint.colorChoices:clear()

                for _, choice in ipairs(appearance.colorChoices) do
                    crew.blueprint.colorChoices:push_back(choice)
                end
            end

            -- Hyperspace itself rebuilds CrewAnimation.layerColors when
            -- preserving colors across crew transformations. Do the same here,
            -- but use the exact RGBA values captured from the transported crew.
            if crew.crewAnim
                and crew.crewAnim.layerColors
                and appearance.layerColors then

                crew.crewAnim.layerColors:clear()

                for _, color in ipairs(appearance.layerColors) do
                    crew.crewAnim.layerColors:push_back(
                        Graphics.GL_Color(
                            color.r,
                            color.g,
                            color.b,
                            color.a
                        )
                    )
                end
            end
        end
    )
end

local function snapshot_crew_skills(crew)
    local skills = {}

    if not crew or not crew.blueprint or not crew.blueprint.skillLevel then
        return skills
    end

    pcall(
        function()
            local skillCount =
                math.min(6, crew.blueprint.skillLevel:size())

            for skillId = 0, skillCount - 1 do
                local skillPair = crew.blueprint.skillLevel[skillId]

                skills[#skills + 1] = {
                    id = skillId,

                    -- Hyperspace's own clone handling saves .first as the
                    -- accumulated raw skill progress and restores it with
                    -- CrewMember:SetSkillProgress().
                    progress = skillPair.first
                }
            end
        end
    )

    return skills
end

local function restore_crew_skills(crew, savedSkills)
    if not crew or not savedSkills then
        return
    end

    pcall(
        function()
            for _, savedSkill in ipairs(savedSkills) do
                crew:SetSkillProgress(
                    savedSkill.id,
                    savedSkill.progress
                )
            end
        end
    )
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
        appearance = snapshot_crew_appearance(crew),
        skills = snapshot_crew_skills(crew)
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

    if userdata_table then
        local crewData = userdata_table(crew, POD_USERDATA)
        crewData.inTransit = true
        crewData.transportId = transportId
    end

    -- Release the crew's occupied room tile before marking the source entity
    -- out-of-game. SetOutOfGame() removes the crew from normal play, but by
    -- itself it does not reliably clear the Room slot occupancy.
    local emptySlotOk = pcall(
        function()
            crew:EmptySlot()
        end
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

    return true
end

local function recreate_crew(payload, shipManager, roomId)
    if not payload or not payload.snapshot or not shipManager then
        return nil
    end

    local snapshot = payload.snapshot
    local intruder = payload.sourceShipId ~= shipManager.iShipId

    -- Use AddCrewMemberFromString so every impact creates a brand-new CrewMember
    -- and the transported crew's saved name can be supplied directly.
    -- Sex is irrelevant for SC-MOD here, so a fixed boolean is supplied.
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

    if not spawnOk then
        return nil
    end

    local newCrew = spawnResult
    if not newCrew then
        return nil
    end

    -- AddCrewMemberFromString can randomize crew color selections again.
    -- Restore the transported crew's saved blueprint choices and exact live
    -- animation layer colors before normal rendering continues.
    restore_crew_appearance(newCrew, snapshot.appearance)

    -- Preserve raw progression for all six vanilla crew skills.
    restore_crew_skills(newCrew, snapshot.skills)

    -- Restore power recharge/charge state immediately, before the recreated
    -- crew receives its next normal update and can auto-activate a reset power.
    restore_crew_powers(newCrew, snapshot.powers)

    -- Restore current health after creation.
    if snapshot.health then
        pcall(
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
            end
        )
    end

    return newCrew
end

local function returnable_boarder_count()
    local count = 0

    for _, _ in pairs(pod.returnableBoarders) do
        count = count + 1
    end

    return count
end

local function track_delivered_boarder(payload, crew, roomId)
    if not payload or not crew then
        return
    end

    pod.returnableBoarders[payload.transportId] = {
        transportId = payload.transportId,
        crew = crew,
        sourceShipId = payload.sourceShipId,
        sourceRoomId = payload.sourceRoomId,
        targetShipId = payload.targetShipId,
        targetRoomId = roomId
    }
end

local function make_return_payload(record, snapshot)
    return {
        transportId = record.transportId,
        sourceShipId = record.sourceShipId,
        sourceRoomId = record.sourceRoomId,
        targetShipId = record.sourceShipId,
        snapshot = snapshot
    }
end

local function return_boarder_to_source(record)
    if not record or not record.crew then
        return false, "crew missing"
    end

    local crew = record.crew

    if crew.bDead or crew.bOutOfGame then
        return false, "crew dead/out"
    end

    local sourceShip =
        Hyperspace.Global.GetInstance():GetShipManager(record.sourceShipId)

    if not sourceShip then
        return false, "source ship missing"
    end

    -- Save the boarder's CURRENT state, so damage, ability recharge,
    -- appearance, and skill progress gained after boarding are preserved.
    local currentSnapshot = snapshot_crew(crew)
    if not currentSnapshot then
        return false, "snapshot failed"
    end

    local targetShip =
        Hyperspace.Global.GetInstance():GetShipManager(record.targetShipId)

    local oldTargetRoom = crew.iRoomId

    -- Retire the boarder on the enemy ship using the same proven EmptySlot()
    -- cleanup used by outbound transport.
    if not remove_original_crew(crew, record.transportId) then
        return false, "enemy removal failed"
    end

    local returnPayload =
        make_return_payload(record, currentSnapshot)

    local returnedCrew =
        recreate_crew(
            returnPayload,
            sourceShip,
            record.sourceRoomId
        )

    if returnedCrew then
        return true, returnedCrew
    end

    -- If creation on the source ship fails, try to restore the boarder on the
    -- non-hostile target ship rather than silently deleting the crew.
    if targetShip and not targetShip.bDestroyed then
        local restoredBoarder =
            recreate_crew(
                returnPayload,
                targetShip,
                oldTargetRoom
            )

        if restoredBoarder then
            record.crew = restoredBoarder
            record.targetRoomId = oldTargetRoom
            return false, "source recreate failed; restored on target"
        end
    end

    return false, "recreate failed"
end

local function return_all_boarders()
    local transportIds = {}

    for transportId, _ in pairs(pod.returnableBoarders) do
        transportIds[#transportIds + 1] = transportId
    end

    table.sort(transportIds)

    for _, transportId in ipairs(transportIds) do
        local record = pod.returnableBoarders[transportId]

        if record then
            if not record.crew
                or record.crew.bDead
                or record.crew.bOutOfGame then

                pod.returnableBoarders[transportId] = nil
            else
                local ok =
                    return_boarder_to_source(record)

                if ok then
                    pod.returnableBoarders[transportId] = nil
                end
            end
        end
    end
end

local function update_boarder_return_state(shipManager)
    if not shipManager or shipManager.iShipId ~= 0 then
        return
    end

    local enemyShip =
        Hyperspace.Global.GetInstance():GetShipManager(1)

    local enemyPresent =
        enemyShip ~= nil
        and not enemyShip.bDestroyed
        and enemyShip._targetable ~= nil

    local hostile =
        enemyPresent
        and enemyShip._targetable.hostile
        or false

    local trackedCount = returnable_boarder_count()

    -- Only a living, still-present target becoming non-hostile causes an
    -- automatic return. Destruction does not rescue boarded crew.
    if trackedCount > 0
        and enemyPresent
        and pod.lastBoarderHostileState == true
        and hostile == false then

        return_all_boarders()
    end

    pod.lastBoarderHostileState = hostile
end

script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    function(shipManager)
        update_boarder_return_state(shipManager)
    end
)


local function return_transport_to_source(transportId)
    local payload = pod.activeTransports[transportId]
    if not payload then
        return
    end

    local sourceShip =
        Hyperspace.Global.GetInstance():GetShipManager(payload.sourceShipId)

    if sourceShip then
        recreate_crew(payload, sourceShip, payload.sourceRoomId)
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

        local ownerShip =
            Hyperspace.Global.GetInstance():GetShipManager(podCrew.iShipId)

        if not ownerShip then
            return
        end

        local droneRoomId = get_drone_room_id(ownerShip)

        if droneRoomId == nil then
            return
        end

        local payloadCrews =
            find_payload_crews(ownerShip, podCrew, droneRoomId)

        if #payloadCrews == 0 then
            return
        end

        local targetShipId = 1 - podCrew.iShipId
        local targetShip =
            Hyperspace.Global.GetInstance():GetShipManager(targetShipId)

        if not targetShip
            or targetShip.bDestroyed
            or not targetShip._targetable
            or not targetShip._targetable.hostile then
            return
        end

        -- Every eligible crew member gets a completely independent transport:
        -- one snapshot, one projectile, one transport ID, and one delivery.
        for _, payloadCrew in ipairs(payloadCrews) do
            local projectile =
                launch_transport_projectile(
                    podCrew,
                    ownerShip,
                    targetShip
                )

            if projectile then
                local payload =
                    create_transport_payload(
                        payloadCrew,
                        podCrew.iShipId,
                        targetShipId
                    )

                local podData =
                    userdata_table(projectile, POD_USERDATA)

                podData.launchedByPod = true
                podData.transportId = payload.transportId
                podData.sourceShipId = payload.sourceShipId
                podData.targetShipId = payload.targetShipId
                podData.delivered = false

                if not remove_original_crew(
                    payloadCrew,
                    payload.transportId
                ) then
                    -- The projectile already exists, but without an active
                    -- transport its impact callback will have nothing to
                    -- recreate. The original crew remains on the source ship.
                    pod.activeTransports[payload.transportId] = nil
                end
            end
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

        local podData = userdata_table(projectile, POD_USERDATA)

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

        if roomId == nil or roomId < 0 then
            return Defines.Chain.CONTINUE
        end

        local newCrew =
            recreate_crew(payload, shipManager, roomId)

        if newCrew then
            podData.delivered = true

            track_delivered_boarder(
                payload,
                newCrew,
                roomId
            )

            pod.activeTransports[transportId] = nil
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
            return_transport_to_source(transportId)
        end
    end
)