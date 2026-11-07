--[[
DESCRIPTION: Displays enemy Boarding Pod AI assembly diagnostics.
        - Shows the selected crew's room, destination, task, and active NO_AI stat.
        - Shows accepted/rejected movement commands and destination changes.
        - Shows recent AI and movement transitions useful for troubleshooting.
DEPENDENCIES: sc_drone_pod_ai.lua
]]

local TEXT_X = 20
local TEXT_Y = 165
local LINE_HEIGHT = 16
local FONT = 10
local MAX_EVENTS = 10

local function draw_panel()
    if not Hyperspace.App or not Hyperspace.App.world
        or not Hyperspace.App.world.bStartedGame then
        return
    end

    local debug = mods.sc and mods.sc.dronePodAI

    Graphics.CSurface.GL_PushMatrix()
    Graphics.CSurface.GL_LoadIdentity()
    Graphics.CSurface.GL_SetColor(Graphics.GL_Color(1, 1, 1, 1))

    local line = 0
    local function add(message)
        Graphics.freetype.easy_print(FONT, TEXT_X, TEXT_Y + line * LINE_HEIGHT, message)
        line = line + 1
    end

    add("TERRAN BOARDING POD AI TEST")

    if not debug then
        add("sc_drone_pod_ai.lua is not loaded")
        Graphics.CSurface.GL_PopMatrix()
        return
    end

    add(string.format("State: %s", debug.state or "Unknown"))
    add(string.format("Tick=%d  Drone room=%s  Slots=%s  Selected=%d",
        debug.tick or 0,
        tostring(debug.roomId or "-"),
        tostring(debug.capacity or "-"),
        #(debug.rows or {})
    ))
    add("NO_AI duration=30s (once)    Orders every 6 ship loops")
    add("room=current  goal=destination  task=AI task  orders=OK/FAIL")

    for _, record in ipairs(debug.rows or {}) do
        add(string.format("%s [%s] room=%s goal=%s task=%s NO_AI=%s",
            tostring(record.name), tostring(record.id),
            tostring(record.room or "-"), tostring(record.goal or "-"),
            tostring(record.task or "-"), tostring(record.noAi or "-")
        ))
        add(string.format("  arrived=%s  boost=%s  orders=%d/%d  last=%s  goal changes=%d",
            record.arrived and "YES" or "NO",
            tostring(record.boost),
            record.accepted or 0, record.rejected or 0,
            tostring(record.lastOrder), record.goalChanges or 0
        ))
    end

    add("")
    add("Recent events (newest first):")
    local events = debug.events or {}
    for i = 1, math.min(#events, MAX_EVENTS) do
        add(events[i])
    end

    Graphics.CSurface.GL_PopMatrix()
end

script.on_render_event(Defines.RenderEvents.MOUSE_CONTROL, draw_panel, function() end)
