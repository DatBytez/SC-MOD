--[[
DESCRIPTION: Diagnostic core for post-teleport SetOutOfGame boarding-pod parking.
        - Keeps the actual CrewMember object.
        - Does NOT use transparent animation, temporary mind control, or runtime
          crew-stat suppression.
        - Passenger first completes the proven native teleport to the enemy ship.
        - Only after full target-side arrival is CrewMember:SetOutOfGame() called.
        - Missile impact restores the same object with the engine-derived sequence:
              bOutOfGame = false
              bDead = false
              fStunTime = 0
              Restart()
        - Original stun time is restored after Restart() for test cleanliness.
TEST STATUS: Experimental.
DEPENDENCIES: Multiverse userdata_table
]]

local userdata_table = mods.multiverse.userdata_table

mods.sc_drone_pod = mods.sc_drone_pod or {}
local pod = mods.sc_drone_pod

local POD_USERDATA = "mods.sc.dronePod"

pod.nextTransportId = pod.nextTransportId or 0
pod.activeTransports = pod.activeTransports or {}
pod.returnableBoarders = pod.returnableBoarders or {}
pod.debugLines = pod.debugLines or {}

function pod.debug_line(text)
    pod.debugLines[#pod.debugLines + 1] = tostring(text)
    while #pod.debugLines > 24 do
        table.remove(pod.debugLines, 1)
    end
end

local function slot_text(crew)
    local result = "?"
    pcall(function()
        result = tostring(crew.currentSlot.roomId) .. ":" .. tostring(crew.currentSlot.slotId)
    end)
    return result
end

function pod.ship_contains_reference(shipId, crew)
    local shipManager = Hyperspace.Global.GetInstance():GetShipManager(shipId)
    if not shipManager or not shipManager.vCrewList or not crew then return false end
    for i = 0, shipManager.vCrewList:size() - 1 do
        if shipManager.vCrewList[i] == crew then return true end
    end
    return false
end

function pod.list_membership(crew)
    if not crew then return "--" end
    local inPlayer = pod.ship_contains_reference(0, crew)
    local inEnemy = pod.ship_contains_reference(1, crew)
    return (inPlayer and "P" or "-") .. (inEnemy and "E" or "-")
end

local function safe_health(crew)
    local value = "?"
    pcall(function()
        value = tostring(crew:GetIntegerHealth())
    end)
    return value
end

function pod.describe_crew(prefix, crew)
    if not crew then
        pod.debug_line(prefix .. " crew=nil")
        return
    end

    local data = userdata_table(crew, POD_USERDATA)
    local customTele = crew.extend and crew.extend.customTele or nil

    pod.debug_line(
        prefix
        .. " cur=" .. tostring(crew.currentShipId)
        .. " room=" .. tostring(crew.iRoomId)
        .. " slot=" .. slot_text(crew)
        .. " out=" .. tostring(crew.bOutOfGame == true)
        .. " dead=" .. tostring(crew.bDead == true)
        .. " hp=" .. safe_health(crew)
        .. " lists=" .. pod.list_membership(crew)
        .. " parked=" .. tostring(data.podParked == true)
        .. " tele=" .. tostring(customTele and customTele.shipId or "nil")
        .. "/" .. tostring(customTele and customTele.teleporting or "nil")
    )
end

function pod.create_transport_payload(
    crew, projectile, sourceShipId, sourceRoomId,
    targetShipId, targetRoomId, targetPosition
)
    pod.nextTransportId = pod.nextTransportId + 1

    local payload = {
        transportId = pod.nextTransportId,
        crew = crew,
        projectile = projectile,
        sourceShipId = sourceShipId,
        sourceRoomId = sourceRoomId,
        targetShipId = targetShipId,
        targetRoomId = targetRoomId,
        targetPosition = targetPosition,
        state = "outbound",
        impact = false,
        actualImpactRoomId = nil,
        cancelRequested = false,
        outboundLimboLogged = false
    }

    pod.activeTransports[payload.transportId] = payload
    return payload
end

function pod.returned_vector_contains(returned, crew)
    if not returned or not crew then return false end
    for i = 0, returned:size() - 1 do
        if returned[i] == crew then return true end
    end
    return false
end

function pod.park_out_of_game(payload)
    if not payload or not payload.crew then return false end

    local crew = payload.crew
    local data = userdata_table(crew, POD_USERDATA)

    if data.podParked then return true end

    if crew.currentShipId ~= payload.targetShipId then
        pod.debug_line(
            "PARK BLOCK T" .. tostring(payload.transportId)
            .. " cur=" .. tostring(crew.currentShipId)
        )
        return false
    end

    data.savedStunTime = crew.fStunTime or 0
    data.podParked = true
    data.transportId = payload.transportId

    pod.describe_crew("BEFORE SOG T" .. tostring(payload.transportId), crew)

    local ok, err = pcall(function()
        crew:SetOutOfGame()
    end)

    if not ok then
        data.podParked = false
        pod.debug_line(
            "SOG ERROR T" .. tostring(payload.transportId) .. " " .. tostring(err)
        )
        return false
    end

    payload.state = "parked_waiting"
    pod.describe_crew("AFTER SOG T" .. tostring(payload.transportId), crew)

    return true
end

function pod.restore_from_out_of_game(payload, reason)
    if not payload or not payload.crew then return false end

    local crew = payload.crew
    local data = userdata_table(crew, POD_USERDATA)

    if not data.podParked then return true end

    pod.describe_crew(
        "BEFORE RESTORE T" .. tostring(payload.transportId)
        .. " " .. tostring(reason or ""),
        crew
    )

    local savedStunTime = data.savedStunTime or 0

    local ok, err = pcall(function()
        crew.bOutOfGame = false
        crew.bDead = false
        crew.fStunTime = 0
        crew:Restart()
        crew.fStunTime = savedStunTime
    end)

    if not ok then
        pod.debug_line(
            "RESTORE ERROR T" .. tostring(payload.transportId) .. " " .. tostring(err)
        )
        return false
    end

    data.podParked = false
    data.transportId = nil
    data.savedStunTime = nil

    pod.describe_crew("AFTER RESTORE T" .. tostring(payload.transportId), crew)
    return true
end
