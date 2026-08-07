-- Terran Boarding Pod - snapshot/recreate transport debug.
-- This file is diagnostic only and does not alter gameplay behavior.

mods.sc_drone_pod = mods.sc_drone_pod or {}
local pod = mods.sc_drone_pod

local SCREEN_X = 65
local SCREEN_Y = 110
local LINE_HEIGHT = 18
local MAX_LINES = 22

local function active_transport_count()
    local count = 0

    for _, _ in pairs(pod.activeTransports or {}) do
        count = count + 1
    end

    return count
end

script.on_render_event(
    Defines.RenderEvents.MOUSE_CONTROL,

    function()
        return Defines.Chain.CONTINUE
    end,

    function()
        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y,
            "Terran Boarding Pod - Snapshot Transport Debug"
        )

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y + LINE_HEIGHT,
            "Active transports: "
            .. tostring(active_transport_count())
        )

        local lines = pod.debugLines or {}
        local first = math.max(1, #lines - MAX_LINES + 1)

        local displayIndex = 0

        for index = first, #lines do
            displayIndex = displayIndex + 1

            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                SCREEN_Y + LINE_HEIGHT * (1 + displayIndex),
                tostring(index)
                .. ". "
                .. tostring(lines[index])
            )
        end
    end
)