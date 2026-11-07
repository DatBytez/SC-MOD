--[[
DESCRIPTION: Tests enemy boarding-party assembly in Drone Control with normal crew AI suppressed.
        - Selects combat-capable enemy crew up to the Drone Control room's capacity.
        - Temporarily disables normal AI for selected crew using the NO_AI stat.
        - Orders the selected crew to Drone Control using normal crew movement.
        - Exposes movement, task, goal, and NO_AI diagnostics to sc_debug.lua.
        - Does not deploy drones or launch boarding pods yet.
DEPENDENCIES: Hyperspace StatBoostManager
]]

local DRONES_SYSTEM_ID = 4
local NO_AI_DURATION = 30 -- Seconds of normal AI suppression per selected crew member.
local ORDER_INTERVAL = 5 -- SHIP_LOOP calls between movement orders.
local MAX_EVENTS = 12

mods.sc = mods.sc or {}
mods.sc.dronePodAI = mods.sc.dronePodAI or {}
local debug = mods.sc.dronePodAI

debug.events = {}
debug.rows = {}
debug.state = "Waiting for enemy ship"
debug.tick = 0

local function add_event(message)
    table.insert(debug.events, 1, message)
    if #debug.events > MAX_EVENTS then
        table.remove(debug.events)
    end
end

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

local function read_no_ai(crew)
    local ok, _, value = pcall(function()
        return crew.extend:CalculateStat(Hyperspace.CrewStat.NO_AI)
    end)
    if not ok then return "ERROR" end
    return value and "TRUE" or "FALSE"
end

local function make_record(crew)
    return {
        crew = crew,
        id = crew.extend.selfId,
        name = crew:GetName(),
        orders = 0,
        accepted = 0,
        rejected = 0,
        goalChanges = 0,
        lastGoal = nil,
        lastTask = nil,
        lastNoAI = nil,
        boost = "PENDING",
        lastOrder = "NONE"
    }
end

local function reset_test()
    lastEnemyShip = nil
    selected = nil
    orderTimer = 0
    debug.events = {}
    debug.rows = {}
    debug.state = "Waiting for enemy ship"
    debug.tick = 0
    debug.roomId = nil
    debug.capacity = nil
end

script.on_init(reset_test)
script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, reset_test)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if shipManager.iShipId ~= 1 then return end
    debug.tick = debug.tick + 1

    if shipManager ~= lastEnemyShip then
        lastEnemyShip = shipManager
        selected = nil
        orderTimer = 0
        debug.rows = {}
        debug.events = {}
        add_event("New enemy ship: selecting boarding crew")
    end

    if not shipManager:HasSystem(DRONES_SYSTEM_ID) then
        debug.state = "Enemy has no Drone Control"
        debug.roomId = nil
        debug.capacity = nil
        return
    end

    local droneRoomId = shipManager:GetSystemRoom(DRONES_SYSTEM_ID)
    if droneRoomId < 0 then
        debug.state = "Drone Control room is invalid"
        return
    end

    if not selected then
        local graph = Hyperspace.ShipGraph.GetShipInfo(shipManager.iShipId)
        if not graph then
            debug.state = "Cannot get ship graph"
            return
        end

        local roomCapacity = graph:GetNumSlots(droneRoomId)
        debug.roomId = droneRoomId
        debug.capacity = roomCapacity
        if roomCapacity <= 0 then
            debug.state = "Drone Control has no slots"
            return
        end

        selected = select_boarding_party(shipManager, droneRoomId, roomCapacity)
        debug.rows = {}
        add_event(string.format("Room %d: %d slots, %d crew selected", droneRoomId, roomCapacity, #selected))

        for _, crew in ipairs(selected) do
            local record = make_record(crew)
            debug.rows[#debug.rows + 1] = record
            local ok, err = pcall(function()
                Hyperspace.StatBoostManager.GetInstance():CreateTimedAugmentBoost(
                    Hyperspace.StatBoost(noAiBoost), crew
                )
            end)
            record.boost = ok and "APPLIED" or "ERROR"
            if ok then
                add_event(string.format("%s: NO_AI boost applied", record.name))
            else
                add_event(string.format("%s: boost ERROR: %s", record.name, tostring(err):sub(1, 70)))
            end
        end
    end

    debug.state = "Monitoring boarding assembly (no launch)"
    local issueOrders = orderTimer <= 0
    if issueOrders then
        orderTimer = ORDER_INTERVAL
    else
        orderTimer = orderTimer - 1
    end

    for _, record in ipairs(debug.rows) do
        local crew = record.crew
        if eligible_crew(crew, shipManager.iShipId) then
            local currentRoom = crew.iRoomId
            local goalRoom = crew.finalGoal and crew.finalGoal.roomId or -1
            local taskId = crew.task and crew.task.taskId or -1
            local noAi = read_no_ai(crew)

            if record.lastNoAI ~= noAi then
                add_event(string.format("%s: NO_AI=%s", record.name, noAi))
                record.lastNoAI = noAi
            end
            if record.lastGoal ~= nil and record.lastGoal ~= goalRoom then
                record.goalChanges = record.goalChanges + 1
                add_event(string.format("%s: goal %d -> %d", record.name, record.lastGoal, goalRoom))
            end
            if record.lastTask ~= nil and record.lastTask ~= taskId then
                add_event(string.format("%s: task %d -> %d", record.name, record.lastTask, taskId))
            end

            if issueOrders and currentRoom ~= droneRoomId then
                local ok, moved = pcall(function()
                    return crew:MoveToRoom(droneRoomId, -1, true)
                end)
                record.orders = record.orders + 1
                if not ok then
                    record.rejected = record.rejected + 1
                    record.lastOrder = "ERROR"
                    add_event(string.format("%s: MoveToRoom ERROR: %s", record.name, tostring(moved):sub(1, 60)))
                elseif moved then
                    record.accepted = record.accepted + 1
                    record.lastOrder = "OK"
                else
                    record.rejected = record.rejected + 1
                    record.lastOrder = "FALSE"
                    if record.rejected <= 3 then
                        add_event(string.format("%s: MoveToRoom returned false", record.name))
                    end
                end
                goalRoom = crew.finalGoal and crew.finalGoal.roomId or goalRoom
            end

            record.room = currentRoom
            record.goal = goalRoom
            record.task = taskId
            record.noAi = noAi
            record.lastGoal = goalRoom
            record.lastTask = taskId
            record.arrived = currentRoom == droneRoomId
        else
            record.room = crew.iRoomId
            record.goal = -1
            record.task = -1
            record.noAi = "N/A"
            record.lastOrder = "INACTIVE"
            record.arrived = false
        end
    end
end)
