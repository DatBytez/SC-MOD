--[[
DESCRIPTION: Tests enemy boarding-party assembly in Drone Control with normal crew AI suppressed.
        - Selects combat-capable enemy crew up to the Drone Control room's capacity.
        - Retries selection when no crew are available during enemy ship initialization.
        - Temporarily disables normal AI for selected crew using the NO_AI stat.
        - Orders selected crew to Drone Control using normal crew movement.
        - Exposes diagnostic state to sc_debug.lua; does not launch pods.
DEPENDENCIES: Hyperspace StatBoostManager
]]

local DRONES_SYSTEM_ID = 4
local NO_AI_DURATION = 30
local ORDER_INTERVAL = 5

mods.sc = mods.sc or {}
mods.sc.dronePodAI = mods.sc.dronePodAI or {}
local diagnostics = mods.sc.dronePodAI

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

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]
        if eligible_crew(crew, shipManager.iShipId) and crew.iRoomId == droneRoomId then
            party[#party + 1] = crew
            if #party >= roomCapacity then return party end
        end
    end

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]
        if eligible_crew(crew, shipManager.iShipId) and crew.iRoomId ~= droneRoomId then
            party[#party + 1] = crew
            if #party >= roomCapacity then break end
        end
    end

    return party
end

local function reset_state(shipManager)
    lastEnemyShip = shipManager
    selected = nil
    orderTimer = 0
    diagnostics.ship = shipManager
    diagnostics.room = -1
    diagnostics.capacity = 0
    diagnostics.selected = {}
    diagnostics.ordersAccepted = 0
    diagnostics.ordersRejected = 0
    diagnostics.boostsAttempted = 0
    diagnostics.status = "Waiting for Drone Control"
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if shipManager.iShipId ~= 1 then return end

    if shipManager ~= lastEnemyShip then
        reset_state(shipManager)
    end

    if not shipManager:HasSystem(DRONES_SYSTEM_ID) then
        diagnostics.status = "Enemy has no Drone Control"
        return
    end

    local droneRoomId = shipManager:GetSystemRoom(DRONES_SYSTEM_ID)
    if droneRoomId < 0 then
        diagnostics.status = "Drone Control room unavailable"
        return
    end

    local graph = Hyperspace.ShipGraph.GetShipInfo(shipManager.iShipId)
    if not graph then return end

    local roomCapacity = graph:GetNumSlots(droneRoomId)
    diagnostics.room = droneRoomId
    diagnostics.capacity = roomCapacity
    if roomCapacity <= 0 then return end

    -- An empty Lua table is truthy. Retry while empty so early SHIP_LOOP calls
    -- cannot permanently lock in an empty party before enemy crew spawn.
    if not selected or #selected == 0 then
        selected = select_boarding_party(shipManager, droneRoomId, roomCapacity)
        diagnostics.selected = selected

        if #selected == 0 then
            diagnostics.status = "No eligible crew yet; retrying"
            return
        end

        diagnostics.status = "Boarding party selected"
        for _, crew in ipairs(selected) do
            diagnostics.boostsAttempted = diagnostics.boostsAttempted + 1
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
            if crew:MoveToRoom(droneRoomId, -1, true) then
                diagnostics.ordersAccepted = diagnostics.ordersAccepted + 1
            else
                diagnostics.ordersRejected = diagnostics.ordersRejected + 1
            end
        end
    end
end)
