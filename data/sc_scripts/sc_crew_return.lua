--[[
DESCRIPTION: Returns crew to their original ships when the opposing ship becomes non-hostile.
        - Returns player-owned crew from a non-hostile enemy ship.
        - Returns enemy-owned crew from the player ship when the enemy becomes non-hostile.
        - Does not return enemy crew to a destroyed or escaping ship.
        - Prefers airlock rooms, falling back to a random room.
DEPENDENCIES: sc_crew_copy.lua
]]

local crew_copy = mods.sc.crew_copy

local function get_random_room_id(shipManager)
    local location = shipManager:GetRandomRoomCenter()

    return Hyperspace.ShipGraph.GetShipInfo(shipManager.iShipId):GetSelectedRoom(location.x, location.y, false)
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

local function return_crew(sourceShip, destinationShip)
    local returningCrew = {}

    for i = 0, sourceShip.vCrewList:size() - 1 do
        local crew = sourceShip.vCrewList[i]

        if crew.iShipId == destinationShip.iShipId
            and crew.currentShipId == sourceShip.iShipId
            and not crew:IsDrone()
            and not crew:IsDead()
            and not crew:OutOfGame()
            and (
                not crew.extend.deathTimer
                or not crew.extend.deathTimer:Running()
            ) then

            returningCrew[#returningCrew + 1] = crew
        end
    end

    if #returningCrew == 0 then return end

    local airlockRoomIds = get_airlock_room_ids(destinationShip)

    for _, crew in ipairs(returningCrew) do
        local roomId

        if #airlockRoomIds > 0 then
            roomId = airlockRoomIds[math.random(#airlockRoomIds)]
        else
            roomId = get_random_room_id(destinationShip)
        end

        if roomId ~= nil and roomId >= 0 then
            crew_copy.move(crew, destinationShip, roomId)
        end
    end
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

    return_crew(enemyShip, shipManager)

    if enemyShip.bJumping then return end

    return_crew(shipManager, enemyShip)
end)