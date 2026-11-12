--[[
DESCRIPTION: Controls enemy Boarding Pod assembly and launch readiness.
        - Assembles boarding parties only while a Terran Boarding Pod is available.
        - Selects teleport-capable enemy crew while reserving one aboard when necessary.
        - Excludes crew in or assigned to Piloting when its room is valid.
        - Suppresses normal AI for selected crew while a Boarding Pod is available.
        - Orders selected crew to Drone Control through normal movement.
        - Requires the smaller of Drone Control slots - 1 or eligible boarding crew.
        - Does not reserve an eligible boarder when an ineligible crew member can pilot.
        - Locks the required crew count until the Pod launches or disappears.
        - The existing Pod script transports all crew present in Drone Control.
        - Exposes movement and launch diagnostics to sc_debug.lua.
DEPENDENCIES: sc_helpers.lua, sc_drone_pod.lua
]]

local system_id_from_name = mods.sc.helpers.system_id_from_name

local DRONES_SYSTEM_ID = system_id_from_name("drones")
local PILOT_SYSTEM_ID = system_id_from_name("pilot")
local POD_SPECIES = "terran_pod"
local POD_POWER = "SC_LAUNCH"
local ORDER_INTERVAL = 5

mods.sc = mods.sc or {}
mods.sc.dronePodAI = mods.sc.dronePodAI or {}
local debug = mods.sc.dronePodAI

debug.events = {}
debug.rows = {}
debug.state = "Waiting for enemy ship"
debug.tick = 0
debug.launches = 0
debug.readyCrew = 0
debug.eligibleCrew = 0
debug.minimumCrew = 0

local lastEnemyShip = nil
local selected = nil
local selectedIds = {}
local boardingActive = false
local orderTimer = 0
local minimumCrew = 0

local function add_event(message)
    table.insert(debug.events, 1, message)
end

local function eligible_crew(crew, shipId)
    return crew.iShipId == shipId
        and crew.currentShipId == shipId
        and not crew:IsDrone()
        and not crew.bDead
        and not crew.bOutOfGame
        and crew:CanTeleport()
end

local function has_ineligible_pilot_candidate(shipManager)
    local crewList = shipManager.vCrewList

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if crew.iShipId == shipManager.iShipId
            and crew.currentShipId == shipManager.iShipId
            and not crew:IsDrone()
            and not crew.bDead
            and not crew.bOutOfGame
            and crew:CanMan()
            and not eligible_crew(crew, shipManager.iShipId) then

            return true
        end
    end

    return false
end

local function available_for_boarding(crew, shipId, pilotRoomId)
    return eligible_crew(crew, shipId)
        and (pilotRoomId < 0
            or (crew.iRoomId ~= pilotRoomId
                and (not crew.finalGoal or crew.finalGoal.roomId ~= pilotRoomId)))
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

local function count_eligible_crew(shipManager)
    local crewList = shipManager.vCrewList
    local count = 0

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if eligible_crew(crew, shipManager.iShipId) then
            count = count + 1
        end
    end

    return count
end

local function select_boarding_party(shipManager, droneRoomId, partySize, pilotRoomId)
    local crewList = shipManager.vCrewList
    local party = {}

    if partySize <= 0 then return party end

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if available_for_boarding(crew, shipManager.iShipId, pilotRoomId)
            and crew.iRoomId == droneRoomId then

            party[#party + 1] = crew
            if #party >= partySize then return party end
        end
    end

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if available_for_boarding(crew, shipManager.iShipId, pilotRoomId)
            and crew.iRoomId ~= droneRoomId then

            party[#party + 1] = crew
            if #party >= partySize then break end
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
    selectedIds = {}
    boardingActive = false
    orderTimer = 0
    minimumCrew = 0
    debug.rows = {}
    debug.minimumCrew = 0
    debug.eligibleCrew = 0
end

script.on_internal_event(Defines.InternalEvents.CALCULATE_STAT_POST, function(crew, stat, _def, amount, value)
    if stat == Hyperspace.CrewStat.NO_AI
        and boardingActive
        and selectedIds[crew.extend.selfId] then

        return Defines.Chain.CONTINUE, amount, true
    end

    return Defines.Chain.CONTINUE, amount, value
end)

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

    if not boardingActive or minimumCrew < 1 then
        return Defines.Chain.CONTINUE, 0
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

    if count_boarding_crew(enemyShip, droneRoomId) < minimumCrew then
        return Defines.Chain.CONTINUE, 0
    end

    return Defines.Chain.CONTINUE, ready
end)

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
        boost = "ACTIVE",
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
        clear_boarding_party()
        debug.state = "Enemy has no Drone Control"
        debug.roomId = nil
        debug.capacity = nil
        return
    end

    local droneRoomId = shipManager:GetSystemRoom(DRONES_SYSTEM_ID)
    if droneRoomId < 0 then
        clear_boarding_party()
        debug.state = "Drone Control room is invalid"
        return
    end

    debug.roomId = droneRoomId
    debug.readyCrew = count_boarding_crew(shipManager, droneRoomId)

    if not has_active_pod(shipManager) then
        if boardingActive then
            clear_boarding_party()
        end

        debug.state = "Waiting for Boarding Pod"
        return
    end

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

    if not selected or #selected == 0 then
        local pilotRoomId = shipManager:GetSystemRoom(PILOT_SYSTEM_ID)
        local eligibleCrew = count_eligible_crew(shipManager)
        local reserveCrew = has_ineligible_pilot_candidate(shipManager) and 0 or 1

        minimumCrew = math.max(
            0, math.min(roomCapacity - 1, eligibleCrew - reserveCrew)
        )

        debug.eligibleCrew = eligibleCrew
        debug.minimumCrew = minimumCrew

        selected = select_boarding_party(
            shipManager, droneRoomId, minimumCrew, pilotRoomId
        )

        debug.rows = {}
        selectedIds = {}

        add_event(string.format(
            "Slots=%d Eligible=%d Required=%d Selected=%d",
            roomCapacity, eligibleCrew, minimumCrew, #selected
        ))

        for _, crew in ipairs(selected) do
            selectedIds[crew.extend.selfId] = true

            local record = make_record(crew)
            debug.rows[#debug.rows + 1] = record

            add_event(string.format("%s: NO_AI enabled", record.name))
        end
    end

    boardingActive = #selected > 0

    debug.state = string.format(
        "Boarding assembly: %d/%d ready (eligible=%d)",
        debug.readyCrew, minimumCrew, debug.eligibleCrew
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