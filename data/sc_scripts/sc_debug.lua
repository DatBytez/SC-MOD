-- Test No. 8

--[[
Paused pilot-radius preview verification.

This report is drawn after MOUSE_CONTROL. Radius Core Test No. 4 refreshes the
player weapon radii in the pre-render callback for the same render event, so
Shared and Display should already match even while the game is paused.

Test while paused:
    1. Activate the pilot ability.
    2. Activate cloak while pilot remains active.
    3. Confirm Active, Cloak, Accuracy, P, Shared, and Display update.

This file does not change gameplay behavior.
]]

local vter = mods.multiverse.vter

local TEST_NUMBER = 8
local EXPECTED_CORE_TEST = 4
local EXPECTED_PILOT_TEST = 3
local SCREEN_X = 65
local SCREEN_Y = 110
local LINE_HEIGHT = 18
local MAX_WEAPONS = 3
local MATCH_EPSILON = 0.01

local function number_text(value)
    if value == nil then
        return "-"
    end

    if math.abs(value - math.floor(value)) < 0.0001 then
        return tostring(math.floor(value))
    end

    return string.format("%.2f", value)
end

local function bool_text(value)
    return value and "YES" or "NO"
end

local function trim_weapon_name(name)
    name = tostring(name or "unknown")

    if #name <= 28 then
        return name
    end

    return string.sub(name, 1, 25) .. "..."
end

local function nearly_equal(a, b)
    return a ~= nil
        and b ~= nil
        and math.abs(a - b) <= MATCH_EPSILON
end

local function modifier_delta(calculation, name)
    local modifiers = calculation
        and (calculation.weaponModifiers
            or calculation.previewModifiers)

    local modifier = modifiers and modifiers[name]

    return modifier and modifier.delta or 0
end

local function game_is_paused()
    local success, paused = pcall(
        function()
            return Hyperspace.App.world.space.gamePaused
        end
    )

    return success and paused or false
end

local function get_live_state()
    local ship = Hyperspace.ships.player
    local shipId = ship and ship.iShipId or 0

    local active = ship
        and mods.sc_pilot_button
        and mods.sc_pilot_button.activated
        and mods.sc_pilot_button.activated[shipId]
        or false

    local cloaked = ship
        and ship.cloakSystem
        and ship.cloakSystem.bTurnedOn
        or false

    local accuracy = mods.sc_accuracy
        and mods.sc_accuracy.dodgeToAccuracy
        and mods.sc_accuracy.dodgeToAccuracy[shipId]
        or 0

    return ship, active, cloaked, accuracy
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
            "Paused Radius Refresh - Debug Test No. "
                .. tostring(TEST_NUMBER)
        )

        local ship, active, cloaked, accuracy =
            get_live_state()

        local coreTest = mods.sc
            and mods.sc.radius
            and mods.sc.radius.CORE_TEST_NUMBER
            or nil

        local pilotRefresh = mods.sc
            and mods.sc.pilot
            and mods.sc.pilot.refresh_accuracy_bonus
            ~= nil

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y + LINE_HEIGHT,
            "Paused=" .. bool_text(game_is_paused())
                .. " Active=" .. bool_text(active)
                .. " Cloak=" .. bool_text(cloaked)
                .. " Accuracy=" .. number_text(accuracy)
                .. " | Core=" .. number_text(coreTest)
                .. " PilotRefresh=" .. bool_text(pilotRefresh)
        )

        if coreTest ~= EXPECTED_CORE_TEST
            or not pilotRefresh then

            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                SCREEN_Y + LINE_HEIGHT * 2,
                "Expected Radius Core Test No. "
                    .. tostring(EXPECTED_CORE_TEST)
                    .. " and Pilot Test No. "
                    .. tostring(EXPECTED_PILOT_TEST)
            )
        end

        local weapons = ship
            and ship.weaponSystem
            and ship.weaponSystem.weapons

        if not weapons then
            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                SCREEN_Y + LINE_HEIGHT * 3,
                "No player weapons available."
            )
            return
        end

        local index = 0

        for weapon in vter(weapons) do
            index = index + 1

            if index > MAX_WEAPONS then
                break
            end

            local calculation = nil

            if mods.sc
                and mods.sc.scaling
                and mods.sc.scaling
                    .get_weapon_preview_calculation then

                calculation =
                    mods.sc.scaling
                        .get_weapon_preview_calculation(
                            ship,
                            weapon
                        )
            end

            local shared = calculation
                and calculation.previewRadius
                or nil

            local display = weapon.radius

            local status = nearly_equal(
                shared,
                display
            ) and "MATCH" or "DIFF"

            local y = SCREEN_Y
                + LINE_HEIGHT * (2 + index)

            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                y,
                tostring(index)
                    .. ": "
                    .. trim_weapon_name(
                        weapon.blueprint
                        and weapon.blueprint.name
                    )
                    .. " Shared="
                    .. number_text(shared)
                    .. " Display="
                    .. number_text(display)
                    .. " P="
                    .. number_text(
                        modifier_delta(
                            calculation,
                            "pilot_accuracy"
                        )
                    )
                    .. " | "
                    .. status
            )
        end
    end
)
