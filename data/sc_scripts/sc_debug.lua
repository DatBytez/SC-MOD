-- Test No. 9

--[[
Final shared-radius cleanup verification through load-order step 4.

The report confirms:
    - Shared scaling loaded before the radius core.
    - Legacy weapon-radius APIs are absent.
    - Paused pilot/cloak preview matches weapon.radius.
    - Fired projectiles use the shared frozen C/Q/S radius.

This file does not change gameplay behavior.
]]

local userdata_table = mods.multiverse.userdata_table
local vter = mods.multiverse.vter

local TEST_NUMBER = 9
local EXPECTED_SCALING_TEST = 5
local EXPECTED_CORE_TEST = 5
local EXPECTED_PILOT_TEST = 4
local EXPECTED_DETECTOR_TEST = 2

local CORE_STORAGE_KEY = "mods.sc.radiusCore"
local SCALING_STORAGE_KEY = "mods.sc.projectileScaling"

local SCREEN_X = 65
local SCREEN_Y = 110
local LINE_HEIGHT = 18
local MAX_WEAPONS = 3
local MAX_SHOTS = 3
local MATCH_EPSILON = 0.01

local shots = {}

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

local function nearly_equal(left, right)
    return left ~= nil
        and right ~= nil
        and math.abs(left - right) <= MATCH_EPSILON
end

local function game_is_paused()
    local success, paused = pcall(
        function()
            return Hyperspace.App.world.space.gamePaused
        end
    )

    return success and paused or false
end

local function modifier_delta(calculation, name)
    local modifier = calculation
        and calculation.weaponModifiers
        and calculation.weaponModifiers[name]

    return modifier and modifier.delta or 0
end

local function get_source_text(projectile)
    local data = userdata_table(
        projectile,
        SCALING_STORAGE_KEY
    )

    if data.hasChain then
        return "C" .. number_text(data.chainLevel)
    end

    if data.hasCharge then
        return "Q" .. number_text(data.chargeLevel)
    end

    if data.hasChainstep then
        return "S" .. number_text(data.chainstepLevel)
    end

    return "none"
end

local function capture_shot(projectile, weapon)
    if not projectile
        or not weapon
        or projectile.ownerId ~= 0 then

        return
    end

    local core = userdata_table(
        projectile,
        CORE_STORAGE_KEY
    )

    local shot = {
        weaponName = weapon.blueprint
            and weapon.blueprint.name
            or "unknown",
        source = get_source_text(projectile),
        coreTest = core.testNumber,
        mode = core.mode,
        scalingRadius = core.scalingRadius,
        artilleryDelta = core.artilleryModifierDelta,
        pilotDelta = core.pilotModifierDelta,
        detectorDelta = core.detectorModifierDelta,
        startingRadius = core.startingRadius,
        finalRadius = core.finalRadius,
        projectileDelta = core.projectileModifierDelta
    }

    shot.match =
        shot.coreTest == EXPECTED_CORE_TEST
        and shot.mode == "shared_radius"
        and nearly_equal(
            shot.startingRadius,
            core.weaponModifiedRadius
        )

    table.insert(shots, shot)

    while #shots > MAX_SHOTS do
        table.remove(shots, 1)
    end
end

local function register_debug_handler()
    if mods.sc_debug_final_radius_registered_test9 then
        return
    end

    mods.sc_debug_final_radius_registered_test9 = true

    script.on_internal_event(
        Defines.InternalEvents.PROJECTILE_FIRE,
        capture_shot
    )
end

-- Radius core registers its handler from on_load. This file loads last, so its
-- on_load callback registers the diagnostic handler afterward.
script.on_load(register_debug_handler)

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
        local ship, active, cloaked, accuracy =
            get_live_state()

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y,
            "Final Radius Cleanup - Debug Test No. "
                .. tostring(TEST_NUMBER)
        )

        local scalingTest = mods.sc
            and mods.sc.scaling
            and mods.sc.scaling.READER_VERSION
            or nil

        local coreTest = mods.sc
            and mods.sc.radius
            and mods.sc.radius.CORE_TEST_NUMBER
            or nil

        local pilotTest = mods.sc
            and mods.sc.pilot
            and mods.sc.pilot.TEST_NUMBER
            or nil

        local detectorTest = mods.sc
            and mods.sc.detector
            and mods.sc.detector.TEST_NUMBER
            or nil

        local versionsCorrect =
            scalingTest == EXPECTED_SCALING_TEST
            and coreTest == EXPECTED_CORE_TEST
            and pilotTest == EXPECTED_PILOT_TEST
            and detectorTest == EXPECTED_DETECTOR_TEST

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y + LINE_HEIGHT,
            "Scaling=" .. number_text(scalingTest)
                .. " Core=" .. number_text(coreTest)
                .. " Pilot=" .. number_text(pilotTest)
                .. " Detector=" .. number_text(detectorTest)
                .. " | "
                .. (versionsCorrect and "VERSIONS OK" or "WRONG FILE")
        )

        local legacyRemoved = mods.sc
            and mods.sc.radius
            and mods.sc.radius.register_modifier == nil
            and mods.sc.radius.get_final_radius == nil
            and mods.sc.scaling.register_preview_modifier == nil
            and mods.sc.scaling.get_legacy_weapon_preview_radius == nil

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y + LINE_HEIGHT * 2,
            "Legacy APIs removed=" .. bool_text(legacyRemoved)
                .. " | Paused=" .. bool_text(game_is_paused())
                .. " Active=" .. bool_text(active)
                .. " Cloak=" .. bool_text(cloaked)
                .. " Accuracy=" .. number_text(accuracy)
        )

        local weapons = ship
            and ship.weaponSystem
            and ship.weaponSystem.weapons

        local weaponIndex = 0

        if weapons then
            for weapon in vter(weapons) do
                weaponIndex = weaponIndex + 1

                if weaponIndex > MAX_WEAPONS then
                    break
                end

                local calculation =
                    mods.sc.scaling
                        .get_weapon_preview_calculation(
                            ship,
                            weapon
                        )

                local shared = calculation
                    and calculation.previewRadius
                    or nil

                local display = weapon.radius
                local match = nearly_equal(shared, display)

                Graphics.freetype.easy_print(
                    0,
                    SCREEN_X,
                    SCREEN_Y + LINE_HEIGHT * (2 + weaponIndex),
                    tostring(weaponIndex)
                        .. ": "
                        .. trim_weapon_name(
                            weapon.blueprint
                            and weapon.blueprint.name
                        )
                        .. " Shared=" .. number_text(shared)
                        .. " Display=" .. number_text(display)
                        .. " A=" .. number_text(
                            modifier_delta(
                                calculation,
                                "chain_artillery"
                            )
                        )
                        .. " P=" .. number_text(
                            modifier_delta(
                                calculation,
                                "pilot_accuracy"
                            )
                        )
                        .. " D=" .. number_text(
                            modifier_delta(
                                calculation,
                                "sc_detector"
                            )
                        )
                        .. " | "
                        .. (match and "MATCH" or "DIFF")
                )
            end
        end

        local shotStartY = SCREEN_Y
            + LINE_HEIGHT * (3 + MAX_WEAPONS)

        if #shots == 0 then
            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                shotStartY,
                "Fire a player weapon to verify shared projectile radius."
            )
            return
        end

        for index, shot in ipairs(shots) do
            local y = shotStartY
                + LINE_HEIGHT * ((index - 1) * 2)

            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                y,
                "Shot " .. tostring(index)
                    .. ": "
                    .. trim_weapon_name(shot.weaponName)
                    .. " Src=" .. tostring(shot.source)
                    .. " Mode=" .. tostring(shot.mode or "-")
                    .. " | "
                    .. (shot.match and "MATCH" or "DIFF")
            )

            Graphics.freetype.easy_print(
                0,
                SCREEN_X + 18,
                y + LINE_HEIGHT,
                "Scale=" .. number_text(shot.scalingRadius)
                    .. " A=" .. number_text(shot.artilleryDelta)
                    .. " P=" .. number_text(shot.pilotDelta)
                    .. " D=" .. number_text(shot.detectorDelta)
                    .. " Start=" .. number_text(shot.startingRadius)
                    .. " Final=" .. number_text(shot.finalRadius)
                    .. " Proj=" .. number_text(shot.projectileDelta)
            )
        end
    end
)
