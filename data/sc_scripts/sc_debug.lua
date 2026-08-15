-- Comsat lifetime diagnostic only.
-- Gameplay must not depend on this file.
--
-- This intentionally replaces all previous sc_debug.lua diagnostics.

local SCREEN_X = 65
local SCREEN_Y = 110
local LINE_HEIGHT = 18
local MAX_DRONES_PER_SHIP = 4

local vter =
    mods.multiverse.vter

local function bool_text(value)
    if value == true then
        return "true"
    elseif value == false then
        return "false"
    end

    return tostring(value)
end

local function number_text(value)
    if type(value) ~= "number" then
        return tostring(value)
    end

    return string.format("%.2f", value)
end

local function safe_call(
    object,
    methodName
)
    if not object then
        return nil
    end

    local method =
        object[methodName]

    if type(method) ~= "function" then
        return nil
    end

    local ok, result =
        pcall(
            method,
            object
        )

    if not ok then
        return "ERROR"
    end

    return result
end

local function get_registry()
    return mods.sc
        and mods.sc.comsatDrones
        or {}
end

local function get_registered_lifetime(
    drone
)
    if not drone
        or not drone.blueprint
        or not drone.blueprint.name then

        return nil
    end

    return get_registry()[
        drone.blueprint.name
    ]
end

local function get_timer_state(
    shipId,
    drone
)
    if not mods.sc
        or not mods.sc.comsat
        or not mods.sc.comsat.get_timer_state
        or not drone
        or drone.selfId == nil then

        return nil
    end

    return mods.sc.comsat.get_timer_state(
        shipId,
        drone.selfId
    )
end

local function count_table_entries(tbl)
    local count = 0

    for _, _ in pairs(tbl or {}) do
        count = count + 1
    end

    return count
end

local function append(
    lines,
    text
)
    lines[#lines + 1] =
        text
end

local function append_ship_debug(
    lines,
    shipId
)
    local ship =
        Hyperspace.ships(shipId)

    if not ship then
        append(
            lines,
            "Ship " .. tostring(shipId) .. ": unavailable"
        )
        return
    end

    local drones =
        ship.droneSystem
        and ship.droneSystem.drones

    local spaceDrones =
        ship.spaceDrones

    append(
        lines,
        string.format(
            "Ship %d: droneSystem.drones=%d spaceDrones=%d",
            shipId,
            drones and drones:size() or 0,
            spaceDrones and spaceDrones:size() or 0
        )
    )

    if not drones then
        append(
            lines,
            "   no droneSystem.drones vector"
        )
        return
    end

    local found = 0

    for drone in vter(drones) do
        local lifetime =
            get_registered_lifetime(drone)

        if lifetime ~= nil then
            found = found + 1

            if found <= MAX_DRONES_PER_SHIP then
                local destroyed =
                    safe_call(
                        drone,
                        "Destroyed"
                    )

                append(
                    lines,
                    string.format(
                        "D%d %s id:%s life:%s dep:%s pow:%s dead:%s destroyed:%s",
                        found,
                        drone.blueprint.name,
                        tostring(drone.selfId),
                        number_text(lifetime),
                        bool_text(drone.deployed),
                        bool_text(drone.powered),
                        bool_text(drone.bDead),
                        bool_text(destroyed)
                    )
                )

                local state =
                    get_timer_state(
                        shipId,
                        drone
                    )

                if state then
                    append(
                        lines,
                        string.format(
                            "   timer started:%s remaining:%s expired:%s",
                            bool_text(state.started),
                            number_text(state.remaining),
                            bool_text(state.expired)
                        )
                    )
                else
                    append(
                        lines,
                        "   timer state: MISSING"
                    )
                end
            end
        end
    end

    if found == 0 then
        append(
            lines,
            "   no registered Comsat found"
        )
    end
end

local function build_debug_lines()
    local lines = {}

    append(
        lines,
        "COMSAT TIMER DEBUG - PILOT STYLE"
    )

    append(
        lines,
        string.format(
            "registry:%d TERRAN_COMSAT:%s SpeedFactor:%s step:%s",
            count_table_entries(
                get_registry()
            ),
            number_text(
                get_registry().TERRAN_COMSAT
            ),
            number_text(
                Hyperspace.FPS.SpeedFactor
            ),
            number_text(
                Hyperspace.FPS.SpeedFactor
                    / 16
            )
        )
    )

    append_ship_debug(
        lines,
        0
    )

    append_ship_debug(
        lines,
        1
    )

    return lines
end

script.on_render_event(
    Defines.RenderEvents.MOUSE_CONTROL,

    function()
        return Defines.Chain.CONTINUE
    end,

    function()
        local lines =
            build_debug_lines()

        for index, line in ipairs(lines) do
            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                SCREEN_Y
                    + LINE_HEIGHT
                    * (index - 1),
                line
            )
        end
    end
)