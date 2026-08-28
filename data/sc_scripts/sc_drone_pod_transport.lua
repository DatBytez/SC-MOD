--[[
DESCRIPTION: Handles Terran Drop Pod delivery, failed transports, and boarded crew return.
        - Recreates transported crew in the room struck by TERRAN_POD_PROJECTILE.
        - Returns in-flight crew if their projectile dies before delivery or the source ship jumps.
        - Tracks delivered boarders and returns them when the living target ship becomes non-hostile.
        - Does not rescue boarders when the target ship is destroyed.
DEPENDENCIES: sc_drone_pod_core.lua, Multiverse userdata_table
]]

local userdata_table = mods.multiverse.userdata_table
local pod = mods.sc_drone_pod

local POD_PROJECTILE_BLUEPRINT = "TERRAN_POD_PROJECTILE"
local POD_USERDATA = "mods.sc.dronePod"

local function track_delivered_boarder(payload, crew, roomId)
    pod.returnableBoarders[payload.transportId] = {
        transportId = payload.transportId,
        crew = crew,
        sourceShipId = payload.sourceShipId,
        sourceRoomId = payload.sourceRoomId,
        targetShipId = payload.targetShipId,
        targetRoomId = roomId
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

    local sourceShip = Hyperspace.Global.GetInstance():GetShipManager(record.sourceShipId)
    if not sourceShip then
        return false, "source ship missing"
    end

    local currentSnapshot = pod.snapshot_crew(crew)
    if not currentSnapshot then
        return false, "snapshot failed"
    end

    local targetShip = Hyperspace.Global.GetInstance():GetShipManager(record.targetShipId)
    local oldTargetRoom = crew.iRoomId

    if not pod.remove_original_crew(crew, record.transportId) then
        return false, "enemy removal failed"
    end

    local returnPayload = {
        transportId = record.transportId,
        sourceShipId = record.sourceShipId,
        sourceRoomId = record.sourceRoomId,
        targetShipId = record.sourceShipId,
        snapshot = currentSnapshot
    }

    local returnedCrew = pod.recreate_crew(returnPayload, sourceShip, record.sourceRoomId)

    if returnedCrew then
        return true, returnedCrew
    end

    if targetShip and not targetShip.bDestroyed then
        local restoredBoarder = pod.recreate_crew(returnPayload, targetShip, oldTargetRoom)

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

    for transportId in pairs(pod.returnableBoarders) do
        transportIds[#transportIds + 1] = transportId
    end

    table.sort(transportIds)

    for _, transportId in ipairs(transportIds) do
        local record = pod.returnableBoarders[transportId]

        if record then
            if not record.crew or record.crew.bDead or record.crew.bOutOfGame then
                pod.returnableBoarders[transportId] = nil
            elseif return_boarder_to_source(record) then
                pod.returnableBoarders[transportId] = nil
            end
        end
    end
end

local function update_boarder_return_state(shipManager)
    if shipManager.iShipId ~= 0 then return end

    local enemyShip = Hyperspace.Global.GetInstance():GetShipManager(1)
    local enemyPresent =
        enemyShip ~= nil
        and not enemyShip.bDestroyed
        and enemyShip._targetable ~= nil

    local hostile = enemyPresent and enemyShip._targetable.hostile or false

    if next(pod.returnableBoarders) ~= nil
        and enemyPresent
        and pod.lastBoarderHostileState == true
        and hostile == false then

        return_all_boarders()
    end

    pod.lastBoarderHostileState = hostile
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, update_boarder_return_state)

script.on_internal_event(
    Defines.InternalEvents.DAMAGE_AREA_HIT,
    function(shipManager, projectile, location)
        if not projectile or not projectile.extend then
            return Defines.Chain.CONTINUE
        end

        if projectile.extend.name ~= POD_PROJECTILE_BLUEPRINT then
            return Defines.Chain.CONTINUE
        end

        local podData = userdata_table(projectile, POD_USERDATA)

        if not podData.launchedByPod or podData.delivered then
            return Defines.Chain.CONTINUE
        end

        local transportId = podData.transportId
        local payload = transportId and pod.activeTransports[transportId] or nil

        if not payload then
            return Defines.Chain.CONTINUE
        end

        local roomId = Hyperspace.ShipGraph
            .GetShipInfo(shipManager.iShipId)
            :GetSelectedRoom(location.x, location.y, true)

        if roomId == nil or roomId < 0 then
            return Defines.Chain.CONTINUE
        end

        local newCrew = pod.recreate_crew(payload, shipManager, roomId)

        if newCrew then
            podData.delivered = true
            track_delivered_boarder(payload, newCrew, roomId)
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

        local podData = userdata_table(projectile, POD_USERDATA)

        if not podData.launchedByPod or podData.delivered then
            return Defines.Chain.CONTINUE
        end

        if projectile:Dead() and podData.transportId then
            pod.return_transport_to_source(podData.transportId)
        end

        return Defines.Chain.CONTINUE
    end
)

script.on_internal_event(Defines.InternalEvents.JUMP_LEAVE, function()
    local transportIds = {}

    for transportId in pairs(pod.activeTransports) do
        transportIds[#transportIds + 1] = transportId
    end

    for _, transportId in ipairs(transportIds) do
        pod.return_transport_to_source(transportId)
    end
end)
