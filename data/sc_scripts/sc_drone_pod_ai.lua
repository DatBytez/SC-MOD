--[[
DESCRIPTION: Tests enemy boarding-party assembly in Drone Control with normal crew AI suppressed.
        - Selects combat-capable enemy crew up to the Drone Control room's capacity.
        - Temporarily disables normal AI for selected crew using the NO_AI stat.
        - Orders the selected crew to Drone Control using normal crew movement.
        - Does not deploy drones or launch boarding pods yet.
DEPENDENCIES: Hyperspace StatBoostManager
]]

local DRONES_SYSTEM_ID = 4
local NO_AI_DURATION = 30 -- Seconds of normal AI suppression per selected crew member.
local ORDER_INTERVAL = 5 -- SHIP_LOOP calls between movement orders.

local noAiBoost = Hyperspace.StatBoostDefinition()
noAiBoost.stat = Hyperspace.CrewStat.NO_AI
noAiBoost.boostType = Hyperspace.StatBoostDefinition.BoostType.SET
noAiBoost.boostSource = Hyperspace.StatBoostDefinition.BoostSource.AUGMENT
noAiBoost.shipTarget = Hyperspace.StatBoostDefinition.ShipTarget.ALL
noAiBoost.crewTarget = Hyperspace.StatBoostDefinition.CrewTarget.ALL
noAiBoost.value = true
noAiBoost.duration = NO_AI_DURATION
noAiBoost.realBoostId = Hyperspace.StatBoostDefinition.statBoostDefs:size()
Hyperspace.StatBoostDefinition.statBoostDefs:push_back(noAiBoost)

local lastEnemyShip = nil
local selected = nil
local orderTimer = 0

local function eligible_crew(crew, shipId)
    return crew.iShipId == shipId
        and crew.currentShipId == shipId
        and not crew:IsDrone()
        and not crew.bDead
        and not crew.bOutOfGame
        and crew:CanFight()
end

local function select_boarding_party(shipManager, droneRoomId, roomCapacity)
    local crewList = shipManager.vCrewList
    local party = {}

    -- Keep eligible crew already in the destination room in the boarding group.
    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]
        if eligible_crew(crew, shipManager.iShipId) and crew.iRoomId == droneRoomId then
            party[#party + 1] = crew
            if #party >= roomCapacity then return party end
        end
    end

    -- Fill remaining places with eligible crew elsewhere on the ship.
    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]
        if eligible_crew(crew, shipManager.iShipId) and crew.iRoomId ~= droneRoomId then
            party[#party + 1] = crew
            if #party >= roomCapacity then break end
        end
    end

    return party
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if shipManager.iShipId ~= 1 then return end

    if shipManager ~= lastEnemyShip then
        lastEnemyShip = shipManager
        selected = nil
        orderTimer = 0
    end

    if not shipManager:HasSystem(DRONES_SYSTEM_ID) then return end

    local droneRoomId = shipManager:GetSystemRoom(DRONES_SYSTEM_ID)
    if droneRoomId < 0 then return end

    if not selected then
        local graph = Hyperspace.ShipGraph.GetShipInfo(shipManager.iShipId)
        if not graph then return end

        local roomCapacity = graph:GetNumSlots(droneRoomId)
        if roomCapacity <= 0 then return end

        selected = select_boarding_party(shipManager, droneRoomId, roomCapacity)

        -- Apply the temporary boost only once, so its duration can expire normally.
        for _, crew in ipairs(selected) do
            Hyperspace.StatBoostManager.GetInstance():CreateTimedAugmentBoost(
                Hyperspace.StatBoost(noAiBoost), crew
            )
        end
    end

    if orderTimer > 0 then
        orderTimer = orderTimer - 1
        return
    end
    orderTimer = ORDER_INTERVAL

    for _, crew in ipairs(selected) do
        if eligible_crew(crew, shipManager.iShipId) and crew.iRoomId ~= droneRoomId then
            crew:MoveToRoom(droneRoomId, -1, true)
        end
    end
end)
