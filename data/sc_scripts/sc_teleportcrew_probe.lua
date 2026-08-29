--[[
DESCRIPTION: Isolated diagnostic for ShipManager:TeleportCrew(roomId, intruders).
        - Does NOT launch a boarding-pod projectile.
        - Does NOT use the existing boarding-pod core/launch/transport scripts.
        - Uses TERRAN_POD's LAUNCH power only as a convenient test trigger.
        - Calls TeleportCrew on the actual Drone Control room and records exactly
          what happens to the returned CrewMember objects afterward.

TEST SETUP:
        - Temporarily disable sc_drone_pod_core.lua, sc_drone_pod_launch.lua,
          and sc_drone_pod_transport.lua in hyperspace.xml.append.
        - Load this script instead.
        - Put EXACTLY ONE normal crew member in Drone Control for the cleanest
          first test.
        - Deploy TERRAN_POD while a hostile ship is present.
]]

local userdata_table = mods.multiverse.userdata_table

mods.sc_teleportcrew_probe = mods.sc_teleportcrew_probe or {}
local probe = mods.sc_teleportcrew_probe

local POD_SPECIES = "terran_pod"
local LAUNCH_POWER = "LAUNCH"
local POD_DRONE_BLUEPRINT = "TERRAN_POD"
local POD_BLOCK_DESTROYED_TIMER = 0.1
local PROBE_USERDATA = "mods.sc.teleportCrewProbe"

probe.nextToken = probe.nextToken or 0
probe.records = probe.records or {}
probe.debugLines = probe.debugLines or {}
probe.loopCount = probe.loopCount or 0

local function debug_line(text)
    probe.debugLines[#probe.debugLines + 1] = tostring(text)

    while #probe.debugLines > 20 do
        table.remove(probe.debugLines, 1)
    end
end

local function get_drone_room_id(shipManager)
    if not shipManager or not shipManager.droneSystem then
        return nil
    end

    local ok, roomId = pcall(function()
        return shipManager.droneSystem.roomId
    end)

    if not ok or roomId == nil or roomId < 0 then
        return nil
    end

    return roomId
end

local function has_hostile_target_ship()
    local enemyShip =
        Hyperspace.Global.GetInstance():GetShipManager(1)

    return enemyShip
        and not enemyShip.bDestroyed
        and enemyShip._targetable
        and enemyShip._targetable.hostile
end

local function normal_crew_count_in_room(shipManager, roomId)
    local count = 0

    if not shipManager or not shipManager.vCrewList then
        return count
    end

    for i = 0, shipManager.vCrewList:size() - 1 do
        local crew = shipManager.vCrewList[i]

        if crew
            and crew.iShipId == shipManager.iShipId
            and crew.currentShipId == shipManager.iShipId
            and crew.iRoomId == roomId
            and crew:IsCrew()
            and not crew:IsDrone()
            and not crew.bDead
            and not crew.bOutOfGame then

            count = count + 1
        end
    end

    return count
end

local function ship_contains_reference(shipId, crew)
    local shipManager =
        Hyperspace.Global.GetInstance():GetShipManager(shipId)

    if not shipManager or not shipManager.vCrewList or not crew then
        return false
    end

    for i = 0, shipManager.vCrewList:size() - 1 do
        if shipManager.vCrewList[i] == crew then
            return true
        end
    end

    return false
end

local function safe_slot_text(crew)
    local text = "?"

    pcall(function()
        text =
            tostring(crew.currentSlot.roomId)
            .. ":"
            .. tostring(crew.currentSlot.slotId)
    end)

    return text
end

local function safe_out_of_game(crew)
    local value = "?"

    pcall(function()
        value = tostring(crew:OutOfGame())
    end)

    return value
end

local function safe_functional(crew)
    local value = "?"

    pcall(function()
        value = tostring(crew:Functional())
    end)

    return value
end

local function state_values(crew)
    local customTele =
        crew
        and crew.extend
        and crew.extend.customTele
        or nil

    return {
        owner = crew and crew.iShipId or "nil",
        current = crew and crew.currentShipId or "nil",
        room = crew and crew.iRoomId or "nil",
        slot = crew and safe_slot_text(crew) or "nil",
        dead = crew and tostring(crew.bDead) or "nil",
        out = crew and safe_out_of_game(crew) or "nil",
        functional = crew and safe_functional(crew) or "nil",
        anim =
            crew
            and crew.crewAnim
            and tostring(crew.crewAnim.status)
            or "nil",
        teleTarget =
            customTele
            and tostring(customTele.shipId)
            or "nil",
        teleporting =
            customTele
            and tostring(customTele.teleporting)
            or "nil",
        playerList =
            crew and tostring(ship_contains_reference(0, crew)) or "nil",
        enemyList =
            crew and tostring(ship_contains_reference(1, crew)) or "nil"
    }
end

local function state_key(values)
    return table.concat(
        {
            tostring(values.owner),
            tostring(values.current),
            tostring(values.room),
            tostring(values.slot),
            tostring(values.dead),
            tostring(values.out),
            tostring(values.functional),
            tostring(values.anim),
            tostring(values.teleTarget),
            tostring(values.teleporting),
            tostring(values.playerList),
            tostring(values.enemyList)
        },
        "|"
    )
end

local function log_state(prefix, token, crew)
    local values = state_values(crew)

    debug_line(
        prefix
        .. " T" .. tostring(token)
        .. " own=" .. tostring(values.owner)
        .. " cur=" .. tostring(values.current)
        .. " room=" .. tostring(values.room)
        .. " slot=" .. tostring(values.slot)
        .. " dead=" .. tostring(values.dead)
        .. " out=" .. tostring(values.out)
        .. " func=" .. tostring(values.functional)
        .. " anim=" .. tostring(values.anim)
        .. " tele=" .. tostring(values.teleTarget)
        .. "/" .. tostring(values.teleporting)
        .. " lists="
        .. (values.playerList == "true" and "P" or "-")
        .. (values.enemyList == "true" and "E" or "-")
    )

    return values
end

local function tag_candidate_crew(shipManager, roomId)
    local candidates = {}

    for i = 0, shipManager.vCrewList:size() - 1 do
        local crew = shipManager.vCrewList[i]

        if crew
            and crew.iShipId == shipManager.iShipId
            and crew.currentShipId == shipManager.iShipId
            and crew.iRoomId == roomId
            and crew:IsCrew()
            and not crew:IsDrone()
            and not crew.bDead
            and not crew.bOutOfGame then

            probe.nextToken = probe.nextToken + 1

            local token = probe.nextToken
            local crewData =
                userdata_table(
                    crew,
                    PROBE_USERDATA
                )

            crewData.token = token

            candidates[#candidates + 1] = {
                token = token,
                crew = crew
            }

            log_state(
                "BEFORE",
                token,
                crew
            )
        end
    end

    return candidates
end

local function token_for_crew(crew)
    if not crew then
        return "?"
    end

    local ok, crewData = pcall(
        userdata_table,
        crew,
        PROBE_USERDATA
    )

    if ok and crewData and crewData.token then
        return crewData.token
    end

    return "?"
end

local function find_candidate(candidates, crew)
    for _, candidate in ipairs(candidates) do
        if candidate.crew == crew then
            return candidate
        end
    end

    return nil
end

local function get_random_enemy_room(enemyShip)
    if not enemyShip then
        return nil
    end

    local targetPosition =
        enemyShip:GetRandomRoomCenter()

    if not targetPosition then
        return nil
    end

    local roomId =
        Hyperspace.ShipGraph
            .GetShipInfo(enemyShip.iShipId)
            :GetSelectedRoom(
                targetPosition.x,
                targetPosition.y,
                true
            )

    if roomId == nil or roomId < 0 then
        return nil
    end

    return roomId
end

local function run_teleportcrew_probe(shipManager, roomId)
    probe.records = {}
    probe.loopCount = 0

    local enemyShip =
        Hyperspace.Global.GetInstance():GetShipManager(1)

    if not enemyShip
        or enemyShip.bDestroyed
        or not enemyShip._targetable
        or not enemyShip._targetable.hostile then

        debug_line("FAIL no living hostile enemy")
        return
    end

    local targetRoomId =
        get_random_enemy_room(enemyShip)

    if targetRoomId == nil then
        debug_line("FAIL could not select enemy room")
        return
    end

    local candidates =
        tag_candidate_crew(
            shipManager,
            roomId
        )

    if #candidates == 0 then
        debug_line("FAIL no candidates")
        return
    end

    debug_line(
        "PREARM target ship="
        .. tostring(enemyShip.iShipId)
        .. " room="
        .. tostring(targetRoomId)
    )

    -- KEY TEST:
    -- Give every candidate a valid custom teleport destination BEFORE
    -- ShipManager:TeleportCrew() starts teleport-out.
    --
    -- Earlier probes assigned this after TeleportCrew() returned. Those crew
    -- reached currentShipId=-1 with teleTarget=1, but never entered the native
    -- custom-teleport completion queue. This version makes the destination
    -- valid before the first teleport frame.
    for _, candidate in ipairs(candidates) do
        local crew = candidate.crew
        local customTele =
            crew
            and crew.extend
            and crew.extend.customTele
            or nil

        if not customTele then
            debug_line(
                "PREARM FAIL T"
                .. tostring(candidate.token)
                .. " no customTele"
            )
            return
        end

        customTele.shipId =
            enemyShip.iShipId

        customTele.roomId =
            targetRoomId

        customTele.slotId =
            -1

        log_state(
            "PREARMED",
            candidate.token,
            crew
        )
    end

    debug_line(
        "CALL TeleportCrew sourceR="
        .. tostring(roomId)
        .. " candidates="
        .. tostring(#candidates)
    )

    local callOk, returnedOrError =
        pcall(function()
            return shipManager:TeleportCrew(
                roomId,
                false
            )
        end)

    if not callOk then
        debug_line(
            "CALL ERROR "
            .. tostring(returnedOrError)
        )
        return
    end

    local returned = returnedOrError

    if not returned then
        debug_line("RETURN nil")
        return
    end

    local sizeOk, returnedCount =
        pcall(function()
            return returned:size()
        end)

    if not sizeOk then
        debug_line(
            "RETURN not-vector "
            .. tostring(returnedCount)
        )
        return
    end

    debug_line(
        "RETURN vector size="
        .. tostring(returnedCount)
    )

    for i = 0, returnedCount - 1 do
        local crew = returned[i]
        local token = token_for_crew(crew)
        local candidate =
            find_candidate(
                candidates,
                crew
            )

        debug_line(
            "RETURN[" .. tostring(i)
            .. "] T" .. tostring(token)
            .. " samePreRef="
            .. tostring(candidate ~= nil)
        )

        local values =
            log_state(
                "AFTER CALL",
                token,
                crew
            )

        probe.records[#probe.records + 1] = {
            crew = crew,
            token = token,
            targetShipId = enemyShip.iShipId,
            targetRoomId = targetRoomId,
            lastState = state_key(values),
            unchangedLoops = 0,
            arrivalLogged = false
        }
    end

    for _, candidate in ipairs(candidates) do
        local wasReturned = false

        for i = 0, returnedCount - 1 do
            if returned[i] == candidate.crew then
                wasReturned = true
                break
            end
        end

        if not wasReturned then
            debug_line(
                "NOT RETURNED T"
                .. tostring(candidate.token)
            )
        end
    end
end

local function update_probe_records()
    if #probe.records == 0 then
        return
    end

    probe.loopCount = probe.loopCount + 1

    for _, record in ipairs(probe.records) do
        local crew = record.crew

        if crew then
            local values = state_values(crew)
            local key = state_key(values)

            if key ~= record.lastState then
                record.lastState = key
                record.unchangedLoops = 0

                log_state(
                    "CHANGE",
                    record.token,
                    crew
                )

                if not record.arrivalLogged
                    and crew.currentShipId == record.targetShipId then

                    record.arrivalLogged = true

                    debug_line(
                        "ARRIVED T"
                        .. tostring(record.token)
                        .. " sameRef="
                        .. tostring(
                            ship_contains_reference(
                                record.targetShipId,
                                crew
                            )
                        )
                        .. " room="
                        .. tostring(crew.iRoomId)
                    )
                end
            else
                record.unchangedLoops =
                    record.unchangedLoops + 1

                if not record.arrivalLogged
                    and crew.currentShipId == record.targetShipId then

                    record.arrivalLogged = true

                    debug_line(
                        "ARRIVED T"
                        .. tostring(record.token)
                        .. " sameRef="
                        .. tostring(
                            ship_contains_reference(
                                record.targetShipId,
                                crew
                            )
                        )
                        .. " room="
                        .. tostring(crew.iRoomId)
                    )
                end

                -- A few periodic "still here" checkpoints help distinguish
                -- a truly stuck state from a state transition we missed.
                if record.unchangedLoops == 60
                    or record.unchangedLoops == 180
                    or record.unchangedLoops == 360 then

                    log_state(
                        "STILL "
                        .. tostring(record.unchangedLoops),
                        record.token,
                        crew
                    )
                end
            end
        else
            debug_line(
                "CHANGE T"
                .. tostring(record.token)
                .. " crew reference became nil"
            )
        end
    end
end

-- Preserve the convenient player-only pod deployment lock while the normal
-- boarding-pod launch script is disabled for this test.
script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    function(shipManager)
        if not shipManager or shipManager.iShipId ~= 0 then
            return
        end

        update_probe_records()

        local droneSystem = shipManager.droneSystem
        if not droneSystem or not droneSystem.drones then
            return
        end

        local roomId = get_drone_room_id(shipManager)

        local ready =
            roomId ~= nil
            and normal_crew_count_in_room(
                shipManager,
                roomId
            ) > 0
            and has_hostile_target_ship()

        local blockedPower =
            POD_BLOCK_DESTROYED_TIMER

        for i = 0, droneSystem.drones:size() - 1 do
            local drone = droneSystem.drones[i]

            if drone
                and drone.blueprint
                and drone.blueprint.name == POD_DRONE_BLUEPRINT
                and not drone.bDead
                and not drone.deployed
                and not drone.powered then

                local desiredTimer =
                    ready
                    and 0
                    or blockedPower

                if math.abs(
                    drone.destroyedTimer
                    - desiredTimer
                ) > 0.0001 then

                    drone.destroyedTimer =
                        desiredTimer
                end
            end
        end
    end
)

script.on_internal_event(
    Defines.InternalEvents.ACTIVATE_POWER,
    function(power)
        if not power
            or not power.def
            or power.def.name ~= LAUNCH_POWER then
            return
        end

        local podCrew = power.crew

        if not podCrew
            or podCrew:GetSpecies() ~= POD_SPECIES then
            return
        end

        local ownerShip =
            Hyperspace.Global.GetInstance():GetShipManager(
                podCrew.iShipId
            )

        if not ownerShip
            or ownerShip.iShipId ~= 0 then
            return
        end

        local roomId =
            get_drone_room_id(ownerShip)

        if roomId == nil then
            debug_line("FAIL no Drone Control room")
            return
        end

        local count =
            normal_crew_count_in_room(
                ownerShip,
                roomId
            )

        debug_line(
            "=== TELEPORTCREW PROBE ==="
        )

        if count == 0 then
            debug_line(
                "FAIL no normal crew in R"
                .. tostring(roomId)
            )
            return
        end

        if count > 1 then
            debug_line(
                "NOTE room has "
                .. tostring(count)
                .. " normal crew; method may act on all"
            )
        end

        run_teleportcrew_probe(
            ownerShip,
            roomId
        )
    end
)
