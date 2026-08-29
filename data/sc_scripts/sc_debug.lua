-- Terran Boarding Pod immediate-hidden transport diagnostic.
-- Diagnostic only; gameplay logic does not depend on this file.

mods.sc_drone_pod =
    mods.sc_drone_pod or {}

local pod = mods.sc_drone_pod

local SCREEN_X = 45
local SCREEN_Y = 105
local LINE_HEIGHT = 17
local MAX_LINES = 22

local function count_table(tbl)
    local count = 0

    for _ in pairs(tbl or {}) do
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
            "Boarding Pod - Hidden MC / Continuous Return"
        )

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y + LINE_HEIGHT,
            "In flight="
            .. tostring(
                count_table(
                    pod.activeTransports
                )
            )
            .. "  Boarders="
            .. tostring(
                count_table(
                    pod.returnableBoarders
                )
            )
        )

        local lines =
            pod.debugLines or {}

        local first =
            math.max(
                1,
                #lines - MAX_LINES + 1
            )

        local displayIndex = 0

        for index = first, #lines do
            displayIndex =
                displayIndex + 1

            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                SCREEN_Y
                    + LINE_HEIGHT
                    * (1 + displayIndex),
                tostring(lines[index])
            )
        end
    end
)
