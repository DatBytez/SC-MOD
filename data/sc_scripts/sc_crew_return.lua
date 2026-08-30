--[[
DESCRIPTION: Returns player-owned crew from the enemy ship whenever that ship is non-hostile.
        - Returns crew to a random room containing an exterior airlock when possible.
        - Falls back to a random player-ship room if no exterior airlock room exists.
        - Uses the shared crew-copy system to recreate returning crew on the player ship.
        - Ignores dead and out-of-game CrewMembers left behind in the enemy crew vector.
DEPENDENCIES: sc_crew_copy.lua
]]

local crew_copy = mods.sc.crew_copy

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

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if shipManager.iShipId ~= 0 then return end

    local enemyShip = Hyperspace.Global.GetInstance():GetShipManager(1)

    if not enemyShip
        or enemyShip.bDestroyed
        or not enemyShip._targetable
        or enemyShip._targetable.hostile then
        return
    end

    local returningCrew = {}

    -- Build the list before moving anyone because crew_copy.move() retires
    -- the original CrewMember and recreates it on the player ship.
    for i = 0, enemyShip.vCrewList:size() - 1 do
        local crew = enemyShip.vCrewList[i]

        if crew.iShipId == 0
            and not crew:IsDrone()
            and not crew.bDead
            and not crew.bOutOfGame
            and ((not crew.deathTimer) or not crew.deathTimer:Running()) then

            returningCrew[#returningCrew + 1] = crew
        end
    end

    if #returningCrew == 0 then return end

    local airlockRoomIds = get_airlock_room_ids(shipManager)

    for _, crew in ipairs(returningCrew) do
        local roomId = nil

        if #airlockRoomIds > 0 then
            roomId = airlockRoomIds[math.random(#airlockRoomIds)]
        else
            roomId = get_random_room_id(shipManager)
        end

        if roomId ~= nil and roomId >= 0 then
            crew_copy.move(crew, shipManager, roomId)
        end
    end
end)
