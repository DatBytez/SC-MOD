--[[
DESCRIPTION: Tests enemy boarding-party assembly in Drone Control.
        - Selects combat-capable enemy crew up to the Drone Control room's capacity.
        - Orders the selected crew to Drone Control using normal crew movement.
        - Reissues orders frequently to counter normal enemy crew AI.
        - Does not deploy drones or launch boarding pods yet.
DEPENDENCIES: None
]]

local DRONES_SYSTEM_ID = 4
local ORDER_INTERVAL = 5 -- SHIP_LOOP calls between movement orders.

local lastEnemyShip = nil
local orderTimer = 0

local function eligible_crew(crew, shipId)
    return crew.iShipId == shipId
        and crew.currentShipId == shipId
        and not crew:IsDrone()
        and not crew.bDead
        and not crew.bOutOfGame
        and crew:CanFight()
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if shipManager.iShipId ~= 1 then return end

    if shipManager ~= lastEnemyShip then
        lastEnemyShip = shipManager
        orderTimer = 0
    end

    if not shipManager:HasSystem(DRONES_SYSTEM_ID) then return end

    if orderTimer > 0 then
        orderTimer = orderTimer - 1
        return
    end
    orderTimer = ORDER_INTERVAL

    local droneRoomId = shipManager:GetSystemRoom(DRONES_SYSTEM_ID)
    if droneRoomId < 0 then return end

    local graph = Hyperspace.ShipGraph.GetShipInfo(shipManager.iShipId)
    if not graph then return end

    local roomCapacity = graph:GetNumSlots(droneRoomId)
    if roomCapacity <= 0 then return end

    local crewList = shipManager.vCrewList
    local selected = {}

    -- Keep eligible crew already in the destination room in the boarding group.
    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]
        if eligible_crew(crew, shipManager.iShipId) and crew.iRoomId == droneRoomId then
            selected[#selected + 1] = crew
            if #selected >= roomCapacity then break end
        end
    end

    -- Fill remaining places with eligible crew elsewhere on the ship.
    if #selected < roomCapacity then
        for i = 0, crewList:size() - 1 do
            local crew = crewList[i]
            if eligible_crew(crew, shipManager.iShipId) and crew.iRoomId ~= droneRoomId then
                selected[#selected + 1] = crew
                if #selected >= roomCapacity then break end
            end
        end
    end

    for _, crew in ipairs(selected) do
        if crew.iRoomId ~= droneRoomId then
            crew:MoveToRoom(droneRoomId, -1, true)
        end
    end
end)
