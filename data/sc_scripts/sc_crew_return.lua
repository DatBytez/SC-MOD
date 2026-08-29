--[[
DESCRIPTION: Returns player-owned crew from the enemy ship whenever that ship is present and non-hostile.
        - Operates on friendly crew regardless of how they reached the enemy ship.
        - Moves crew back to the player ship using the shared crew-copy system.
        - Does not return crew from a destroyed ship.
DEPENDENCIES: sc_crew_copy.lua
]]

local crew_copy = mods.sc.crew_copy

local function get_random_room_id(shipManager)
    local location = shipManager:GetRandomRoomCenter()

    return Hyperspace.ShipGraph
        .GetShipInfo(shipManager.iShipId)
        :GetSelectedRoom(location.x, location.y, false)
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

    local crewList = enemyShip.vCrewList
    if not crewList then return end

    local returningCrew = {}

    -- Build the list before moving anyone so modifying crew state does not
    -- affect iteration over the enemy ship's crew vector.
    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if crew
            and crew.iShipId == shipManager.iShipId
            and crew.currentShipId == enemyShip.iShipId
            and crew:IsCrew()
            and not crew:IsDrone()
            and not crew.bDead
            and not crew.bOutOfGame
            and ((not crew.deathTimer) or not crew.deathTimer:Running()) then

            returningCrew[#returningCrew + 1] = crew
        end
    end

    for _, crew in ipairs(returningCrew) do
        local roomId = get_random_room_id(shipManager)

        if roomId ~= nil and roomId >= 0 then
            crew_copy.move(crew, shipManager, roomId)
        end
    end
end)
