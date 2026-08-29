--[[
DESCRIPTION: Tests SetOutOfGame as the boarding-pod waiting state.
        - Outbound native teleport completes first.
        - Once the exact CrewMember is fully registered on the target ship,
          SetOutOfGame() parks it while the missile travels.
        - No transparent sprite, temporary mind control, or calculated-stat
          suppression is used in this test.
        - Missile impact restores the parked object in-place.
        - Lost missiles/non-hostile targets restore the object first, then use
          the existing individual custom teleport back to its home ship.
        - Continuous non-hostile return remains per passenger.
DEPENDENCIES: sc_drone_pod_core.lua, Multiverse userdata_table
]]

local userdata_table = mods.multiverse.userdata_table
local pod = mods.sc_drone_pod

local POD_PROJECTILE_BLUEPRINT = "TERRAN_POD_PROJECTILE"
local POD_USERDATA = "mods.sc.dronePod"

local function target_ship_is_non_hostile(shipId)
    local ship = Hyperspace.Global.GetInstance():GetShipManager(shipId)

    if not ship or ship.bDestroyed or not ship._targetable then
        return false
    end

    return ship._targetable.hostile == false
end

local function finish_delivery(payload)
    if not payload or not payload.crew then return end

    local crew = payload.crew

    if not pod.restore_from_out_of_game(payload, "impact") then
        return
    end

    pod.describe_crew(
        "DELIVERY RESTORED T" .. tostring(payload.transportId),
        crew
    )

    if crew.currentShipId ~= payload.targetShipId then
        pod.debug_line(
            "DELIVERY PLACEMENT FAIL T" .. tostring(payload.transportId)
            .. " expectedCur=" .. tostring(payload.targetShipId)
            .. " actualCur=" .. tostring(crew.currentShipId)
        )
        return
    end

    payload.state = "delivered"

    pod.returnableBoarders[payload.transportId] = {
        transportId = payload.transportId,
        crew = crew,
        sourceShipId = payload.sourceShipId,
        sourceRoomId = payload.sourceRoomId,
        targetShipId = payload.targetShipId,
        targetRoomId = payload.targetRoomId,
        state = "active"
    }

    pod.debug_line(
        "TARGET SAME REF T" .. tostring(payload.transportId)
        .. " " .. tostring(
            pod.ship_contains_reference(payload.targetShipId, crew)
        )
    )

    pod.activeTransports[payload.transportId] = nil
end

local function finish_cancelled_return(payload)
    if not payload or not payload.crew then return end

    pod.restore_from_out_of_game(payload, "home")

    pod.describe_crew(
        "RETURNED HOME T" .. tostring(payload.transportId),
        payload.crew
    )

    pod.activeTransports[payload.transportId] = nil
end

local function start_cancelled_return(payload)
    if not payload or not payload.crew then return false end

    local crew = payload.crew

    if not pod.restore_from_out_of_game(payload, "cancel") then
        return false
    end

    if crew.currentShipId == payload.sourceShipId then
        finish_cancelled_return(payload)
        return true
    end

    if crew.currentShipId ~= payload.targetShipId then
        payload.state = "return_pending"

        pod.debug_line(
            "RETURN WAIT T" .. tostring(payload.transportId)
            .. " cur=" .. tostring(crew.currentShipId)
        )

        return false
    end

    if crew.bDead or crew.bOutOfGame then
        pod.debug_line(
            "RETURN BLOCK T" .. tostring(payload.transportId)
            .. " still dead/out"
        )
        return false
    end

    local ok, err =
        pcall(function()
            crew.extend:InitiateTeleport(
                payload.sourceShipId,
                payload.sourceRoomId,
                -1
            )
        end)

    if not ok then
        pod.debug_line(
            "RETURN START FAIL T" .. tostring(payload.transportId)
            .. " " .. tostring(err)
        )
        return false
    end

    payload.state = "returning"

    pod.describe_crew(
        "RETURN START T" .. tostring(payload.transportId),
        crew
    )

    return true
end

local function request_cancelled_return(payload, reason)
    if not payload or payload.cancelRequested then return end

    payload.cancelRequested = true

    pod.debug_line(
        tostring(reason or "CANCEL")
        .. " T" .. tostring(payload.transportId)
    )

    if payload.state ~= "outbound" then
        start_cancelled_return(payload)
    end
end

local function update_active_transports()
    local park = {}
    local deliver = {}
    local retryReturn = {}
    local returnedHome = {}

    for transportId, payload in pairs(pod.activeTransports) do
        local crew = payload and payload.crew or nil

        if not crew then
            pod.debug_line("LOST REF T" .. tostring(transportId))
            pod.activeTransports[transportId] = nil

        elseif payload.state == "outbound" then
            if crew.currentShipId == -1 then
                if not payload.outboundLimboLogged then
                    payload.outboundLimboLogged = true
                    pod.describe_crew(
                        "OUTBOUND LIMBO T" .. tostring(transportId),
                        crew
                    )
                end

            elseif crew.currentShipId == payload.targetShipId then
                pod.describe_crew(
                    "ARRIVED TARGET T" .. tostring(transportId),
                    crew
                )

                if payload.cancelRequested then
                    retryReturn[#retryReturn + 1] = payload
                elseif payload.impact then
                    deliver[#deliver + 1] = payload
                else
                    park[#park + 1] = payload
                end
            end

        elseif payload.state == "parked_waiting" then
            if payload.cancelRequested then
                retryReturn[#retryReturn + 1] = payload
            elseif payload.impact then
                deliver[#deliver + 1] = payload
            end

        elseif payload.state == "return_pending" then
            if crew.currentShipId == payload.targetShipId then
                retryReturn[#retryReturn + 1] = payload
            elseif crew.currentShipId == payload.sourceShipId then
                returnedHome[#returnedHome + 1] = payload
            end

        elseif payload.state == "returning"
            and crew.currentShipId == payload.sourceShipId then

            returnedHome[#returnedHome + 1] = payload
        end
    end

    for _, payload in ipairs(park) do
        pod.park_out_of_game(payload)
    end

    for _, payload in ipairs(deliver) do
        finish_delivery(payload)
    end

    for _, payload in ipairs(retryReturn) do
        start_cancelled_return(payload)
    end

    for _, payload in ipairs(returnedHome) do
        finish_cancelled_return(payload)
    end
end

local function start_boarder_return(record)
    if not record or record.state ~= "active" or not record.crew then return end

    local crew = record.crew

    if crew.bDead or crew.bOutOfGame then
        record.state = "dead"
        return
    end

    local ok =
        pcall(function()
            crew.extend:InitiateTeleport(
                record.sourceShipId,
                record.sourceRoomId,
                -1
            )
        end)

    if ok then
        record.state = "returning"

        pod.debug_line(
            "NONHOSTILE RETURN T" .. tostring(record.transportId)
        )
    end
end

local function update_returnable_boarders()
    local removeIds = {}

    for transportId, record in pairs(pod.returnableBoarders) do
        local crew = record and record.crew or nil

        if not crew or crew.bDead or crew.bOutOfGame then
            removeIds[#removeIds + 1] = transportId

        elseif crew.currentShipId == record.sourceShipId then
            removeIds[#removeIds + 1] = transportId
        end
    end

    for _, transportId in ipairs(removeIds) do
        pod.returnableBoarders[transportId] = nil
    end
end

local function away_crew_is_on_non_hostile_ship(sourceShipId, crew)
    if not crew then return false end

    local currentShipId = crew.currentShipId

    if currentShipId == nil or currentShipId < 0 or currentShipId == sourceShipId then
        return false
    end

    return target_ship_is_non_hostile(currentShipId)
end

local function update_non_hostile_returns()
    for _, record in pairs(pod.returnableBoarders) do
        if record
            and record.state == "active"
            and record.crew
            and away_crew_is_on_non_hostile_ship(
                record.sourceShipId,
                record.crew
            ) then

            start_boarder_return(record)
        end
    end

    for _, payload in pairs(pod.activeTransports) do
        if payload
            and payload.crew
            and not payload.cancelRequested
            and target_ship_is_non_hostile(payload.targetShipId) then

            request_cancelled_return(
                payload,
                "NONHOSTILE CANCEL"
            )
        end
    end
end

script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    function(shipManager)
        if not shipManager or shipManager.iShipId ~= 0 then return end

        update_active_transports()
        update_returnable_boarders()
        update_non_hostile_returns()
    end
)

script.on_internal_event(
    Defines.InternalEvents.DAMAGE_AREA_HIT,
    function(shipManager, projectile, location)
        if not projectile or not projectile.extend then
            return Defines.Chain.CONTINUE
        end

        if projectile.extend.name ~= POD_PROJECTILE_BLUEPRINT then
            return Defines.Chain.CONTINUE
        end

        local projectileData = userdata_table(projectile, POD_USERDATA)

        if not projectileData.launchedByPod or projectileData.delivered then
            return Defines.Chain.CONTINUE
        end

        local transportId = projectileData.transportId

        local payload =
            transportId and pod.activeTransports[transportId] or nil

        if not payload then
            return Defines.Chain.CONTINUE
        end

        local actualRoomId =
            Hyperspace.ShipGraph.GetShipInfo(shipManager.iShipId)
                :GetSelectedRoom(location.x, location.y, true)

        projectileData.delivered = true
        payload.impact = true
        payload.actualImpactRoomId = actualRoomId

        pod.debug_line(
            "MISSILE IMPACT T" .. tostring(transportId)
            .. " plannedR=" .. tostring(payload.targetRoomId)
            .. " actualR=" .. tostring(actualRoomId)
        )

        if payload.state == "parked_waiting" then
            finish_delivery(payload)
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

        local projectileData = userdata_table(projectile, POD_USERDATA)

        if not projectileData.launchedByPod or projectileData.delivered then
            return Defines.Chain.CONTINUE
        end

        if projectile:Dead() and projectileData.transportId then
            local payload =
                pod.activeTransports[projectileData.transportId]

            if payload then
                projectileData.delivered = true

                request_cancelled_return(
                    payload,
                    "MISSILE LOST"
                )
            end
        end

        return Defines.Chain.CONTINUE
    end
)

script.on_internal_event(
    Defines.InternalEvents.JUMP_LEAVE,
    function()
        for _, payload in pairs(pod.activeTransports) do
            request_cancelled_return(
                payload,
                "JUMP CANCEL"
            )
        end
    end
)
