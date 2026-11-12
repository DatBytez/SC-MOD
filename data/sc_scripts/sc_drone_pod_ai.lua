--[[
DESCRIPTION: Controls enemy Boarding Pod assembly and launch readiness.
        - Assembles boarding parties only while a Terran Boarding Pod is available.
        - Selects teleport-capable enemy crew while reserving one aboard when necessary.
        - Excludes crew actively manning Piloting.
        - Suppresses normal AI for selected crew while a Boarding Pod is available.
        - Orders selected crew to Drone Control through normal movement.
        - Requires the smaller of Drone Control slots - 1 or available boarding crew.
        - Does not reserve an eligible boarder when an ineligible crew member can pilot.
        - Locks the required crew count until the Pod launches or disappears.
        - The existing Pod script transports all crew present in Drone Control.
DEPENDENCIES: sc_helpers.lua, sc_drone_pod.lua
]]

local system_id_from_name = mods.sc.helpers.system_id_from_name

local DRONES_SYSTEM_ID = system_id_from_name("drones")
local PILOT_SYSTEM_ID = system_id_from_name("pilot")
local POD_SPECIES = "terran_pod"
local POD_POWER = "SC_LAUNCH"
local ORDER_INTERVAL = 5

local lastEnemyShip = nil
local selected = nil
local selectedIds = {}
local boardingActive = false
local orderTimer = 0
local minimumCrew = 0

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

local function available_for_boarding(crew, shipId)
    return eligible_crew(crew, shipId)
        and not (
            crew.iManningId == PILOT_SYSTEM_ID
            and crew.bActiveManning
        )
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

local function count_available_boarding_crew(shipManager)
    local crewList = shipManager.vCrewList
    local count = 0

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if available_for_boarding(crew, shipManager.iShipId) then
            count = count + 1
        end
    end

    return count
end

local function select_boarding_party(shipManager, droneRoomId, partySize)
    local crewList = shipManager.vCrewList
    local party = {}

    if partySize <= 0 then return party end

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if available_for_boarding(crew, shipManager.iShipId)
            and crew.iRoomId == droneRoomId then

            party[#party + 1] = crew
            if #party >= partySize then return party end
        end
    end

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if available_for_boarding(crew, shipManager.iShipId)
            and crew.iRoomId ~= droneRoomId then

            party[#party + 1] = crew
            if #party >= partySize then break end
        end
    end

    return party
end

local function count_boarding_crew(shipManager, droneRoomId)
    local crewList = shipManager.vCrewList
    local count = 0

    for i = 0, crewList:size() - 1 do
        local crew = crewList[i]

        if crew.iRoomId == droneRoomId
            and available_for_boarding(crew, shipManager.iShipId) then

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
end

-- Suppress normal AI while the crew member belongs to
-- an active boarding party.
script.on_internal_event(Defines.InternalEvents.CALCULATE_STAT_POST, function(crew, stat, _def, amount, value)
    if stat == Hyperspace.CrewStat.NO_AI
        and boardingActive
        and selectedIds[crew.extend.selfId] then

        return Defines.Chain.CONTINUE, amount, true
    end

    return Defines.Chain.CONTINUE, amount, value
end)

-- Do not recalculate the target as crew enter Drone Control.
-- The required number is fixed when assembly begins.
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

-- Clear the locked boarding party after the Pod launches.
script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power)
    if not power.def
        or power.def.name ~= POD_POWER
        or not power.crew
        or power.crew.iShipId ~= 1
        or power.crew:GetSpecies() ~= POD_SPECIES then

        return Defines.Chain.CONTINUE
    end

    clear_boarding_party()

    return Defines.Chain.CONTINUE
end)

local function reset_state()
    lastEnemyShip = nil
    clear_boarding_party()
end

script.on_init(reset_state)
script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, reset_state)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if shipManager.iShipId ~= 1 then return end

    if shipManager ~= lastEnemyShip then
        lastEnemyShip = shipManager
        clear_boarding_party()
    end

    if not shipManager:HasSystem(DRONES_SYSTEM_ID) then
        clear_boarding_party()
        return
    end

    local droneRoomId = shipManager:GetSystemRoom(DRONES_SYSTEM_ID)
    if droneRoomId < 0 then
        clear_boarding_party()
        return
    end

    if not has_active_pod(shipManager) then
        if boardingActive then
            clear_boarding_party()
        end

        return
    end

    local graph = Hyperspace.ShipGraph.GetShipInfo(shipManager.iShipId)
    if not graph then return end

    local roomCapacity = graph:GetNumSlots(droneRoomId)
    if roomCapacity <= 0 then return end

    if not selected or #selected == 0 then
        local eligibleCrew = count_eligible_crew(shipManager)
        local availableCrew = count_available_boarding_crew(shipManager)

        local protectedPilot = availableCrew < eligibleCrew
        local reserveCrew = (
            protectedPilot
            or has_ineligible_pilot_candidate(shipManager)
        ) and 0 or 1

        minimumCrew = math.max(
            0, math.min(
                roomCapacity - 1,
                availableCrew - reserveCrew
            )
        )

        selected = select_boarding_party(
            shipManager, droneRoomId, minimumCrew
        )

        selectedIds = {}

        for _, crew in ipairs(selected) do
            selectedIds[crew.extend.selfId] = true
        end
    end

    boardingActive = #selected > 0

    local issueOrders = orderTimer <= 0

    if issueOrders then
        orderTimer = ORDER_INTERVAL
    else
        orderTimer = orderTimer - 1
    end

    for _, crew in ipairs(selected) do
        if eligible_crew(crew, shipManager.iShipId)
            and issueOrders
            and crew.iRoomId ~= droneRoomId then

            pcall(function()
                crew:MoveToRoom(droneRoomId, -1, true)
            end)
        end
    end
end)