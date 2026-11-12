--[[
DESCRIPTION: Displays enemy Boarding Pod AI selection and movement diagnostics.
        - Shows each enemy crew member's teleport eligibility and Piloting exclusion.
        - Shows each crew member's current manning system and active manning state.
        - Shows selected crew's NO_AI state, movement destination, and order results.
        - Collects text outside the render callback to avoid userdata errors during drawing.
DEPENDENCIES: sc_helpers.lua, sc_drone_pod_ai.lua
]]

local PILOT_SYSTEM_ID = mods.sc.helpers.system_id_from_name("pilot")

local TEXT_X = 20
local TEXT_Y = 175
local LINE_HEIGHT = 15
local FONT = 10
local MAX_CREW_LINES = 12
local MAX_EVENT_LINES = 5

local displayLines = {
    "TERRAN BOARDING POD AI DIAGNOSTICS",
    "Waiting for enemy ship"
}

local function yesno(value)
    return value and "Y" or "N"
end

local function safe_read(callback, fallback)
    local ok, result = pcall(callback)
    if not ok then return fallback end
    return result
end

local function name_of(crew)
    return tostring(safe_read(function()
        return crew:GetName()
    end, "?"))
end

local function room_goal(crew)
    return safe_read(function()
        return crew.finalGoal.roomId
    end, -1)
end

local function no_ai(crew)
    local ok, _, value = pcall(function()
        return crew.extend:CalculateStat(Hyperspace.CrewStat.NO_AI)
    end)

    if not ok then return "ERR" end
    return yesno(value)
end

local function build_snapshot(ship)
    local lines = {"TERRAN BOARDING POD AI DIAGNOSTICS"}
    local function add(message)
        lines[#lines + 1] = message
    end

    local state = mods.sc and mods.sc.dronePodAI

    if not state then
        add("sc_drone_pod_ai.lua not loaded")
        return lines
    end

    add("Status: " .. tostring(state.state or "Waiting"))

    add(string.format(
        "Tick=%s Drone room=%s Slots=%s Selected=%d",
        tostring(state.tick or 0),
        tostring(state.roomId or "-"),
        tostring(state.capacity or "-"),
        #(state.rows or {})
    ))

    add(string.format(
        "Eligible=%s Boardable=%s Required=%s Ready=%s",
        tostring(state.eligibleCrew or 0),
        tostring(state.availableCrew or 0),
        tostring(state.minimumCrew or 0),
        tostring(state.readyCrew or 0)
    ))

    if not ship then
        add("No enemy ship")
        return lines
    end

    local pilotRoom = safe_read(function()
        return ship:GetSystemRoom(PILOT_SYSTEM_ID)
    end, -1)

    add("P=room/goal protected  Man=system/active  *=selected")
    add("Crew: current/goal T P AI D/X/O")

    local crewList = ship.vCrewList
    local limit = math.min(crewList:size(), MAX_CREW_LINES)
    local records = state.rows or {}

    for i = 0, limit - 1 do
        local crew = crewList[i]
        local row

        for _, record in ipairs(records) do
            if record.crew == crew then
                row = record
                break
            end
        end

        local room = safe_read(function()
            return crew.iRoomId
        end, -1)

        local goal = room_goal(crew)

        local canTeleport = safe_read(function()
            return crew:CanTeleport()
        end, false)

        local protected = room == pilotRoom
            or goal == pilotRoom

        local owner = safe_read(function()
            return crew.iShipId
        end, -1)

        local currentShip = safe_read(function()
            return crew.currentShipId
        end, -1)

        local manningId = safe_read(function()
            return crew.iManningId
        end, "ERR")

        local activeManning = safe_read(function()
            return crew.bActiveManning
        end, false)

        local flags = string.format(
            "D%s X%s O%s",
            yesno(safe_read(function()
                return crew:IsDrone()
            end, true)),
            yesno(safe_read(function()
                return crew.bDead
            end, true)),
            yesno(safe_read(function()
                return crew.bOutOfGame
            end, true))
        )

        add(string.format(
            "%s%s %s/%s T%s P%s AI%s %s (%s/%s)",
            row and "*" or " ",
            name_of(crew),
            tostring(room),
            tostring(goal),
            yesno(canTeleport),
            yesno(protected),
            no_ai(crew),
            flags,
            tostring(owner),
            tostring(currentShip)
        ))

        add(string.format(
            "  Man=%s/%s",
            tostring(manningId),
            yesno(activeManning)
        ))

        if row then
            add(string.format(
                "  move OK=%d FAIL=%d last=%s boost=%s goals=%d arrived=%s",
                row.accepted or 0,
                row.rejected or 0,
                tostring(row.lastOrder),
                tostring(row.boost),
                row.goalChanges or 0,
                yesno(row.arrived)
            ))
        end
    end

    if crewList:size() > limit then
        add(string.format(
            "... %d additional crew",
            crewList:size() - limit
        ))
    end

    add("Recent events:")

    for i = 1, math.min(
        #(state.events or {}),
        MAX_EVENT_LINES
    ) do
        add(tostring(state.events[i]))
    end

    return lines
end

script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    function(ship)
        if ship.iShipId ~= 1 then return end

        local ok, lines = pcall(build_snapshot, ship)

        if ok then
            displayLines = lines
        else
            displayLines = {
                "TERRAN BOARDING POD AI DIAGNOSTICS",
                "Snapshot error: "
                    .. tostring(lines):sub(1, 120)
            }
        end
    end
)

local function draw_panel()
    if not Hyperspace.App
        or not Hyperspace.App.world
        or not Hyperspace.App.world.bStartedGame then
        return
    end

    Graphics.CSurface.GL_PushMatrix()

    pcall(function()
        Graphics.CSurface.GL_LoadIdentity()

        for i, line in ipairs(displayLines) do
            Graphics.freetype.easy_print(
                FONT,
                TEXT_X,
                TEXT_Y + (i - 1) * LINE_HEIGHT,
                line
            )
        end
    end)

    Graphics.CSurface.GL_PopMatrix()
end

script.on_render_event(
    Defines.RenderEvents.MOUSE_CONTROL,
    draw_panel,
    function() end
)