
--[[
DESCRIPTION: Controls enemy Boarding Pod assembly and launch readiness.
        - Assembles boarding parties only while a Terran Boarding Pod is active.
        - Selects teleport-capable enemy crew up to Drone Control's capacity.
        - Excludes crew in or assigned to Piloting.
        - Temporarily disables normal AI for selected crew using NO_AI.
        - Orders selected crew to Drone Control through normal movement.
        - Allows enemy SC_LAUNCH when at least two eligible crew are in Drone Control.
        - Clears the boarding party after launch so another Pod can assemble a new party.
        - The existing Pod script transports all crew present in Drone Control.
        - Exposes movement and launch diagnostics to sc_debug.lua.
DEPENDENCIES: Hyperspace StatBoostManager, sc_drone_pod.lua
]]

local DRONES_SYSTEM_ID = 4
local PILOT_SYSTEM_ID = 6
local POD_SPECIES = "terran_pod"
local POD_POWER = "SC_LAUNCH"
local MIN_BOARDING_CREW = 3
local NO_AI_DURATION = 60
local ORDER_INTERVAL = 5
local MAX_EVENTS = 12

mods.sc = mods.sc or {}
mods.sc.dronePodAI = mods.sc.dronePodAI or {}
local debug = mods.sc.dronePodAI

debug.events = {}
debug.rows = {}
debug.state = "Waiting for enemy ship"
debug.tick = 0
debug.launches = 0
debug.readyCrew = 0

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
        and crew:CanTeleport()
end

local function available_for_boarding(crew, shipId, pilotRoomId)
    return eligible_crew(crew, shipId)
        and crew.iRoomId ~= pilotRoomId
        and (not crew.finalGoal or crew.finalGoal.roomId ~= pilotRoomId)
end

local function has_active_pod(shipManager)
    local crewList = shipManager.vCrewList

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if crew:GetSpecies() == POD_SPECIES
            and crew.iShipId == shipManager.iShipId
            and crew.currentShipId == shipManager.iShipId
            and not crew.bDead
            and not crew.bOutOfGame then

            return true
        end
    end

    return false
end

local function select_boarding_party(shipManager, droneRoomId, roomCapacity, pilotRoomId)
    local crewList = shipManager.vCrewList
    local party = {}

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if available_for_boarding(crew, shipManager.iShipId, pilotRoomId)
            and crew.iRoomId == droneRoomId then

            party[#party + 1] = crew
            if #party >= roomCapacity then return party end
        end
    end

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if available_for_boarding(crew, shipManager.iShipId, pilotRoomId)
            and crew.iRoomId ~= droneRoomId then

            party[#party + 1] = crew
            if #party >= roomCapacity then break end
        end
    end

    return party
end

local function count_boarding_crew(shipManager, droneRoomId)
    local crewList = shipManager.vCrewList
    local pilotRoomId = shipManager:GetSystemRoom(PILOT_SYSTEM_ID)
    local count = 0

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if crew.iRoomId == droneRoomId
            and available_for_boarding(crew, shipManager.iShipId, pilotRoomId) then

            count = count + 1
        end
    end

    return count
end

local function clear_boarding_party()
    selected = nil
    orderTimer = 0
    debug.rows = {}
end

-- Prevent enemy Pods from activating before two eligible crew are ready.
-- Player Pods retain their existing automatic activation behavior.
script.on_internal_event(Defines.InternalEvents.POWER_READY, function(power, ready)
    if not power.def
        or power.def.name ~= POD_POWER
        or not power.crew
        or power.crew.iShipId ~= 1
        or power.crew:GetSpecies() ~= POD_SPECIES then

        return Defines.Chain.CONTINUE, ready
    end

    if ready ~= 1 then
        return Defines.Chain.CONTINUE, ready
    end

    local enemyShip = Hyperspace.Global.GetInstance():GetShipManager(1)
    if not enemyShip
        or enemyShip.bDestroyed
        or not enemyShip.droneSystem then

        return Defines.Chain.CONTINUE, 0
    end

    local droneRoomId = enemyShip:GetSystemRoom(DRONES_SYSTEM_ID)
    if droneRoomId < 0 then
        return Defines.Chain.CONTINUE, 0
    end

    local targetShip = Hyperspace.Global.GetInstance():GetShipManager(0)
    if not targetShip
        or targetShip.bDestroyed
        or not targetShip._targetable
        or not targetShip._targetable.hostile then

        return Defines.Chain.CONTINUE, 0
    end

    if count_boarding_crew(enemyShip, droneRoomId) < MIN_BOARDING_CREW then
        return Defines.Chain.CONTINUE, 0
    end

    return Defines.Chain.CONTINUE, ready
end)

-- Once a Pod activates, release the old boarding-party selection.
-- Another active Pod may then assemble a new party from remaining crew.
script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power)
    if not power.def
        or power.def.name ~= POD_POWER
        or not power.crew
        or power.crew.iShipId ~= 1
        or power.crew:GetSpecies() ~= POD_SPECIES then

        return Defines.Chain.CONTINUE
    end

    debug.launches = debug.launches + 1
    add_event(string.format("Boarding Pod launch #%d", debug.launches))

    clear_boarding_party()
    debug.state = "Boarding Pod launched"

    return Defines.Chain.CONTINUE
end)

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
        lastNoAI = nil,
        boost = "PENDING",
        lastOrder = "NONE"
    }
end

local function reset_test()
    lastEnemyShip = nil
    clear_boarding_party()
    debug.events = {}
    debug.state = "Waiting for enemy ship"
    debug.tick = 0
    debug.roomId = nil
    debug.capacity = nil
    debug.launches = 0
    debug.readyCrew = 0
end

script.on_init(reset_test)
script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, reset_test)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if shipManager.iShipId ~= 1 then return end

    debug.tick = debug.tick + 1

    if shipManager ~= lastEnemyShip then
        lastEnemyShip = shipManager
        clear_boarding_party()
        debug.events = {}
        debug.launches = 0
        add_event("New enemy ship")
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

    debug.roomId = droneRoomId
    debug.readyCrew = count_boarding_crew(shipManager, droneRoomId)

    -- Only assemble crew when a Boarding Pod is deployed.
    if not has_active_pod(shipManager) then
        if selected then
            clear_boarding_party()
        end

        debug.state = "Waiting for active Boarding Pod"
        return
    end

    if not selected or #selected == 0 then
        local graph = Hyperspace.ShipGraph.GetShipInfo(shipManager.iShipId)
        if not graph then
            debug.state = "Cannot get ship graph"
            return
        end

        local roomCapacity = graph:GetNumSlots(droneRoomId)
        debug.capacity = roomCapacity

        if roomCapacity <= 0 then
            debug.state = "Drone Control has no slots"
            return
        end

        local pilotRoomId = shipManager:GetSystemRoom(PILOT_SYSTEM_ID)

        selected = select_boarding_party(
            shipManager, droneRoomId, roomCapacity, pilotRoomId
        )

        debug.rows = {}

        if #selected > 0 then
            add_event(string.format(
                "Room %d: %d slots, %d crew selected",
                droneRoomId, roomCapacity, #selected
            ))
        end

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
                add_event(string.format(
                    "%s: boost ERROR: %s",
                    record.name, tostring(err):sub(1, 70)
                ))
            end
        end
    end

    debug.state = string.format(
        "Boarding assembly: %d/%d ready",
        debug.readyCrew, MIN_BOARDING_CREW
    )

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
            local noAi = read_no_ai(crew)

            if record.lastNoAI ~= noAi then
                add_event(string.format("%s: NO_AI=%s", record.name, noAi))
                record.lastNoAI = noAi
            end

            if record.lastGoal ~= nil and record.lastGoal ~= goalRoom then
                record.goalChanges = record.goalChanges + 1
                add_event(string.format(
                    "%s: goal %d -> %d",
                    record.name, record.lastGoal, goalRoom
                ))
            end

            if issueOrders and currentRoom ~= droneRoomId then
                local ok, moved = pcall(function()
                    return crew:MoveToRoom(droneRoomId, -1, true)
                end)

                record.orders = record.orders + 1

                if not ok then
                    record.rejected = record.rejected + 1
                    record.lastOrder = "ERROR"
                    add_event(string.format(
                        "%s: MoveToRoom ERROR: %s",
                        record.name, tostring(moved):sub(1, 60)
                    ))
                elseif moved then
                    record.accepted = record.accepted + 1
                    record.lastOrder = "OK"
                else
                    record.rejected = record.rejected + 1
                    record.lastOrder = "FALSE"

                    if record.rejected <= 3 then
                        add_event(string.format(
                            "%s: MoveToRoom returned false",
                            record.name
                        ))
                    end
                end

                goalRoom = crew.finalGoal and crew.finalGoal.roomId or goalRoom
            end

            record.room = currentRoom
            record.goal = goalRoom
            record.noAi = noAi
            record.lastGoal = goalRoom
            record.arrived = currentRoom == droneRoomId
        else
            record.room = crew.iRoomId
            record.goal = -1
            record.noAi = "N/A"
            record.lastOrder = "INACTIVE"
            record.arrived = false
        end
    end
end)
