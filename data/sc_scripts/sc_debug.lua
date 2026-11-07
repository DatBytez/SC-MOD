--[[
DESCRIPTION: Displays enemy Boarding Pod AI selection and movement diagnostics.
        - Shows why each enemy crew member is or is not eligible.
        - Shows selected crew's NO_AI value, room, movement goal, and current task.
        - Shows accepted/rejected movement orders to troubleshoot assembly.
DEPENDENCIES: sc_drone_pod_ai.lua
]]

local TEXT_X = 20
local TEXT_Y = 175
local LINE_HEIGHT = 15
local FONT = 10
local MAX_CREW_LINES = 12

local function yesno(value)
    return value and "Y" or "N"
end

local function safe_name(crew)
    local ok, name = pcall(function() return crew:GetName() end)
    return ok and tostring(name) or "?"
end

local function get_no_ai(crew)
    local ok, _, value = pcall(function()
        return crew.extend:CalculateStat(Hyperspace.CrewStat.NO_AI)
    end)
    if not ok then return "ERR" end
    return yesno(value)
end

local function draw_panel()
    if not Hyperspace.App or not Hyperspace.App.world
        or not Hyperspace.App.world.bStartedGame then return end

    Graphics.CSurface.GL_PushMatrix()
    Graphics.CSurface.GL_LoadIdentity()
    Graphics.CSurface.GL_SetColor(Graphics.GL_Color(1, 1, 1, 1))

    local line = 0
    local function add(message)
        Graphics.freetype.easy_print(FONT, TEXT_X, TEXT_Y + line * LINE_HEIGHT, message)
        line = line + 1
    end

    add("TERRAN BOARDING AI DIAGNOSTICS (NO LAUNCH)")

    local state = mods.sc and mods.sc.dronePodAI
    local ship = Hyperspace.Global.GetInstance():GetShipManager(1)
    if not state then
        add("ERROR: sc_drone_pod_ai.lua did not register diagnostics")
    elseif not ship then
        add("No enemy ship")
    else
        local selected = state.selected or {}
        add(string.format("Room=%s Slots=%s Selected=%d  Status=%s",
            tostring(state.room), tostring(state.capacity), #selected, tostring(state.status)))
        add(string.format("NO_AI boosts=%d  Move accepted=%d rejected=%d",
            state.boostsAttempted or 0, state.ordersAccepted or 0, state.ordersRejected or 0))
        add("Crew: name  owner/current  room/goal  task  fight/drone/dead/out  NO_AI")

        local crewList = ship.vCrewList
        local limit = math.min(crewList:size(), MAX_CREW_LINES)
        for i = 0, limit - 1 do
            local crew = crewList[i]
            local marked = " "
            for _, member in ipairs(selected) do
                if member == crew then marked = "*"; break end
            end
            local goal = crew.finalGoal and crew.finalGoal.roomId or -1
            local task = crew.task and crew.task.taskId or -1
            add(string.format("%s%s %d/%d %d/%d t=%s F%s D%s X%s O%s AI=%s",
                marked, safe_name(crew), crew.iShipId, crew.currentShipId,
                crew.iRoomId, goal, tostring(task), yesno(crew:CanFight()),
                yesno(crew:IsDrone()), yesno(crew.bDead), yesno(crew.bOutOfGame),
                get_no_ai(crew)))
        end
        if crewList:size() > limit then
            add(string.format("... %d more crew omitted", crewList:size() - limit))
        end
        add("* = selected for boarding; F=fights D=drone X=dead O=out")
    end

    Graphics.CSurface.GL_PopMatrix()
end

script.on_render_event(Defines.RenderEvents.MOUSE_CONTROL, draw_panel, function() end)
