--[[
DESCRIPTION: Returns player-owned crew from the enemy ship whenever that ship is non-hostile.
        - Returns crew to a random room containing an exterior airlock when possible.
        - Uses Hyperspace custom teleportation to preserve the existing CrewMember instead of copying it.
        - Temporarily allows teleportation for returning crew so non-teleportable species can still be recalled.
DEPENDENCIES: None
]]

local returningCrew = setmetatable({}, {__mode = "k"})

local function get_random_room_id(shipManager)
    local location = shipManager:GetRandomRoomCenter()

    return Hyperspace.ShipGraph.GetShipInfo(shipManager.iShipId):GetSelectedRoom(
        location.x,
        location.y,
        false
    )
end

local function get_airlock_room_ids(shipManager)
    local roomIds = {}
    local seenRooms = {}
    local airlocks = shipManager.ship.vOuterAirlocks

    for i = 0, airlocks:size() - 1 do
        local door = airlocks[i]
        local roomId = nil

        if door.iRoom1 < 0 then
            roomId = door.iRoom2
        elseif door.iRoom2 < 0 then
            roomId = door.iRoom1
        end

        if roomId ~= nil and roomId >= 0 and not seenRooms[roomId] then
            seenRooms[roomId] = true
            roomIds[#roomIds + 1] = roomId
        end
    end

    return roomIds
end

script.on_internal_event(
    Defines.InternalEvents.CALCULATE_STAT_POST,
    function(crew, stat, def, amount, value)
        if returningCrew[crew] and stat == Hyperspace.CrewStat.CAN_TELEPORT then
            value = true
        end

        return Defines.Chain.CONTINUE, amount, value
    end
)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if shipManager.iShipId ~= 0 then return end

    for crew in pairs(returningCrew) do
        if crew.bDead
            or crew.currentShipId == 0
            or (
                not crew.extend.customTele.teleporting
                and crew.extend.customTele.shipId == -1
            ) then

            returningCrew[crew] = nil
        end
    end

    local enemyShip = Hyperspace.Global.GetInstance():GetShipManager(1)

    if not enemyShip
        or enemyShip.bDestroyed
        or not enemyShip._targetable
        or enemyShip._targetable.hostile then
        return
    end

    local airlockRoomIds = get_airlock_room_ids(shipManager)

    for i = 0, enemyShip.vCrewList:size() - 1 do
        local crew = enemyShip.vCrewList[i]

        if crew.iShipId == 0
            and not crew:IsDrone()
            and not crew.bDead
            and not returningCrew[crew]
            and ((not crew.deathTimer) or not crew.deathTimer:Running()) then

            local roomId = nil

            if #airlockRoomIds > 0 then
                roomId = airlockRoomIds[math.random(#airlockRoomIds)]
            else
                roomId = get_random_room_id(shipManager)
            end

            if roomId ~= nil and roomId >= 0 then
                returningCrew[crew] = true
                crew.extend:InitiateTeleport(0, roomId, -1)
            end
        end
    end
end)