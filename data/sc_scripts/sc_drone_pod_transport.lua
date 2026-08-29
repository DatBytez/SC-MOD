--[[
DESCRIPTION: Keeps immediately-teleported boarding-pod passengers hidden until
             their individual missiles arrive.
        - Outbound crew are already native-teleported to their preselected rooms.
        - Missile impact only reveals the corresponding original CrewMember.
        - Intercepted/missed missiles cause the hidden original CrewMember to
          custom-teleport back to the source ship before being revealed.
        - Every tracked away passenger is checked continuously; if the living
          ship they occupy is non-hostile, they are returned to their home ship.
        - Hidden passengers are temporarily mind controlled while waiting on the
          enemy so its AI should treat them as allied rather than intruders.
DEPENDENCIES: sc_drone_pod_core.lua, Multiverse userdata_table
]]

local userdata_table =
    mods.multiverse.userdata_table

local pod = mods.sc_drone_pod

local POD_PROJECTILE_BLUEPRINT =
    "TERRAN_POD_PROJECTILE"
local POD_USERDATA = "mods.sc.dronePod"

local function finish_delivery(payload)
    if not payload or not payload.crew then
        return
    end

    local crew = payload.crew

    pod.set_hidden(
        crew,
        false,
        nil
    )

    payload.state = "delivered"

    pod.returnableBoarders[
        payload.transportId
    ] = {
        transportId =
            payload.transportId,
        crew = crew,
        sourceShipId =
            payload.sourceShipId,
        sourceRoomId =
            payload.sourceRoomId,
        targetShipId =
            payload.targetShipId,
        targetRoomId =
            payload.targetRoomId,
        state = "active"
    }

    pod.describe_crew(
        "REVEALED T"
        .. tostring(payload.transportId),
        crew
    )

    pod.debug_line(
        "TARGET SAME REF T"
        .. tostring(payload.transportId)
        .. " "
        .. tostring(
            pod.ship_contains_reference(
                payload.targetShipId,
                crew
            )
        )
    )

    pod.activeTransports[
        payload.transportId
    ] = nil
end

local function finish_cancelled_return(payload)
    if not payload or not payload.crew then
        return
    end

    local crew = payload.crew

    pod.set_hidden(
        crew,
        false,
        nil
    )

    pod.describe_crew(
        "RETURNED HOME T"
        .. tostring(payload.transportId),
        crew
    )

    pod.activeTransports[
        payload.transportId
    ] = nil
end

local function start_cancelled_return(payload)
    if not payload or not payload.crew then
        return false
    end

    local crew = payload.crew

    if crew.bDead or crew.bOutOfGame then
        pod.activeTransports[
            payload.transportId
        ] = nil
        return false
    end

    if crew.currentShipId
        == payload.sourceShipId then

        finish_cancelled_return(
            payload
        )
        return true
    end

    if crew.currentShipId
        ~= payload.targetShipId then

        payload.state =
            "return_pending"
        return false
    end

    local ok =
        pcall(function()
            crew.extend:InitiateTeleport(
                payload.sourceShipId,
                payload.sourceRoomId,
                -1
            )
        end)

    if not ok then
        pod.debug_line(
            "RETURN START FAIL T"
            .. tostring(payload.transportId)
        )
        return false
    end

    payload.state =
        "returning_hidden"

    pod.describe_crew(
        "RETURN START T"
        .. tostring(payload.transportId),
        crew
    )

    return true
end

local function request_cancelled_return(payload)
    if not payload
        or payload.cancelRequested then
        return
    end

    payload.cancelRequested = true

    pod.debug_line(
        "MISSILE LOST T"
        .. tostring(payload.transportId)
        .. " -- return hidden passenger"
    )

    start_cancelled_return(
        payload
    )
end

local function update_active_transports()
    local deliver = {}
    local retryReturn = {}
    local returnedHome = {}

    for transportId,
        payload
        in pairs(pod.activeTransports) do

        local crew =
            payload
            and payload.crew
            or nil

        if not crew then
            pod.debug_line(
                "LOST REF T"
                .. tostring(transportId)
            )

            pod.activeTransports[
                transportId
            ] = nil

        elseif crew.bDead then
            pod.debug_line(
                "PASSENGER DEAD T"
                .. tostring(transportId)
            )

            pod.activeTransports[
                transportId
            ] = nil

        elseif payload.state == "outbound" then
            if crew.currentShipId == -1 then
                -- TeleportCrew has already selected/removed this passenger,
                -- so changing mind-control state here cannot affect the
                -- room-wide outbound selection. If this limbo frame is visible
                -- to Lua, set the allegiance before target-side arrival.
                pod.set_hidden_mind_control(
                    crew,
                    true
                )

                if not payload.outboundLimboLogged then
                    payload.outboundLimboLogged =
                        true

                    pod.debug_line(
                        "OUTBOUND LIMBO+MC T"
                        .. tostring(transportId)
                    )
                end

            elseif crew.currentShipId
                == payload.targetShipId then

                -- Some engine timings can complete the native transfer without
                -- exposing a full Lua loop at currentShipId=-1. Enforce the
                -- temporary mind-control state again on arrival.
                pod.set_hidden_mind_control(
                    crew,
                    true
                )

                payload.state =
                    "hidden_waiting"

                pod.describe_crew(
                    "ARRIVED HIDDEN T"
                    .. tostring(transportId),
                    crew
                )

                if payload.cancelRequested then
                    retryReturn[#retryReturn + 1] =
                        payload
                elseif payload.impact then
                    deliver[#deliver + 1] =
                        payload
                end
            end

        elseif payload.state == "hidden_waiting" then
            -- Keep the hidden passenger allied to the ship it is waiting on.
            if crew.currentShipId
                == payload.targetShipId then

                pod.set_hidden_mind_control(
                    crew,
                    true
                )
            end

            if payload.cancelRequested then
                retryReturn[#retryReturn + 1] =
                    payload
            elseif payload.impact then
                deliver[#deliver + 1] =
                    payload
            end

        elseif payload.state == "return_pending" then
            if crew.currentShipId
                == payload.targetShipId then

                pod.set_hidden_mind_control(
                    crew,
                    true
                )

                retryReturn[#retryReturn + 1] =
                    payload

            elseif crew.currentShipId
                == payload.sourceShipId then

                returnedHome[#returnedHome + 1] =
                    payload
            end

        elseif payload.state == "returning_hidden" then
            if crew.currentShipId == -1 then
                -- Once the passenger has actually left the away ship, restore
                -- its original allegiance so it arrives home friendly.
                pod.set_hidden_mind_control(
                    crew,
                    false
                )

            elseif crew.currentShipId
                == payload.sourceShipId then

                returnedHome[#returnedHome + 1] =
                    payload
            end
        end
    end

    for _, payload in ipairs(deliver) do
        finish_delivery(payload)
    end

    for _, payload in ipairs(retryReturn) do
        start_cancelled_return(
            payload
        )
    end

    for _, payload in ipairs(returnedHome) do
        finish_cancelled_return(
            payload
        )
    end
end

local function start_boarder_return(record)
    if not record
        or record.state ~= "active"
        or not record.crew then
        return
    end

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
            "NONHOSTILE RETURN T"
            .. tostring(record.transportId)
        )
    end
end

local function update_returnable_boarders()
    local removeIds = {}

    for transportId,
        record
        in pairs(pod.returnableBoarders) do

        local crew =
            record
            and record.crew
            or nil

        if not crew
            or crew.bDead
            or crew.bOutOfGame then

            removeIds[#removeIds + 1] =
                transportId

        elseif crew.currentShipId
            == record.sourceShipId then

            removeIds[#removeIds + 1] =
                transportId
        end
    end

    for _, transportId in ipairs(removeIds) do
        pod.returnableBoarders[
            transportId
        ] = nil
    end
end

local function away_ship_is_non_hostile(
    sourceShipId,
    crew
)
    if not crew then
        return false
    end

    local currentShipId =
        crew.currentShipId

    if currentShipId == nil
        or currentShipId < 0
        or currentShipId == sourceShipId then
        return false
    end

    local currentShip =
        Hyperspace.Global.GetInstance()
            :GetShipManager(
                currentShipId
            )

    -- Preserve the existing "do not rescue from a destroyed ship" behavior.
    if not currentShip
        or currentShip.bDestroyed
        or not currentShip._targetable then
        return false
    end

    return currentShip._targetable.hostile == false
end

local function update_non_hostile_returns()
    -- This is intentionally NOT edge-triggered. Every tracked passenger is
    -- checked independently on every player SHIP_LOOP. This means passengers
    -- that arrive after surrender, or passengers from several pod launches,
    -- cannot miss a one-frame hostile->non-hostile transition.

    for _, record
        in pairs(pod.returnableBoarders) do

        if record
            and record.state == "active"
            and record.crew
            and away_ship_is_non_hostile(
                record.sourceShipId,
                record.crew
            ) then

            start_boarder_return(
                record
            )
        end
    end

    -- Hidden passengers whose missiles are still travelling are also returned
    -- continuously if the ship they are waiting on becomes non-hostile.
    for _, payload
        in pairs(pod.activeTransports) do

        if payload
            and payload.crew
            and not payload.cancelRequested
            and away_ship_is_non_hostile(
                payload.sourceShipId,
                payload.crew
            ) then

            request_cancelled_return(
                payload
            )
        end
    end
end

script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    function(shipManager)
        if not shipManager
            or shipManager.iShipId ~= 0 then
            return
        end

        update_active_transports()
        update_returnable_boarders()
        update_non_hostile_returns()
    end
)

script.on_internal_event(
    Defines.InternalEvents.DAMAGE_AREA_HIT,
    function(
        shipManager,
        projectile,
        location
    )
        if not projectile
            or not projectile.extend then
            return Defines.Chain.CONTINUE
        end

        if projectile.extend.name
            ~= POD_PROJECTILE_BLUEPRINT then
            return Defines.Chain.CONTINUE
        end

        local projectileData =
            userdata_table(
                projectile,
                POD_USERDATA
            )

        if not projectileData.launchedByPod
            or projectileData.delivered then
            return Defines.Chain.CONTINUE
        end

        local transportId =
            projectileData.transportId

        local payload =
            transportId
            and pod.activeTransports[
                transportId
            ]
            or nil

        if not payload then
            return Defines.Chain.CONTINUE
        end

        local actualRoomId =
            Hyperspace.ShipGraph
                .GetShipInfo(
                    shipManager.iShipId
                )
                :GetSelectedRoom(
                    location.x,
                    location.y,
                    true
                )

        projectileData.delivered = true

        payload.impact = true
        payload.actualImpactRoomId =
            actualRoomId

        pod.debug_line(
            "MISSILE IMPACT T"
            .. tostring(transportId)
            .. " plannedR="
            .. tostring(payload.targetRoomId)
            .. " actualR="
            .. tostring(actualRoomId)
        )

        if payload.crew
            and payload.crew.currentShipId
                == payload.targetShipId then

            finish_delivery(
                payload
            )
        end

        return Defines.Chain.CONTINUE
    end
)

script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_UPDATE_POST,
    function(projectile)
        if not projectile
            or not projectile.extend then
            return Defines.Chain.CONTINUE
        end

        if projectile.extend.name
            ~= POD_PROJECTILE_BLUEPRINT then
            return Defines.Chain.CONTINUE
        end

        local projectileData =
            userdata_table(
                projectile,
                POD_USERDATA
            )

        if not projectileData.launchedByPod
            or projectileData.delivered then
            return Defines.Chain.CONTINUE
        end

        if projectile:Dead()
            and projectileData.transportId then

            local payload =
                pod.activeTransports[
                    projectileData.transportId
                ]

            if payload then
                projectileData.delivered = true
                request_cancelled_return(
                    payload
                )
            end
        end

        return Defines.Chain.CONTINUE
    end
)

script.on_internal_event(
    Defines.InternalEvents.JUMP_LEAVE,
    function()
        for _, payload
            in pairs(pod.activeTransports) do
            request_cancelled_return(
                payload
            )
        end
    end
)
