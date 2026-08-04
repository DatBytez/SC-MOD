-- Test No. 7

--[[
Pilot / detector shared-radius integration verification.

Preview line:
    Shared  = live C/Q/S plus pilot and detector
    Display = weapon.radius used by the targeting UI

Shot lines:
    Scale = frozen projectile C/Q/S radius before pilot/detector
    P     = pilot weapon-radius contribution
    D     = detector weapon-radius contribution
    Start = radius passed to projectile-only modifiers
    Final = radius after projectile-only modifiers such as HALO fake spread

This file does not change weapon or projectile behavior.
]]

local userdata_table = mods.multiverse.userdata_table
local vter = mods.multiverse.vter

local TEST_NUMBER = 7
local EXPECTED_CORE_TEST = 3
local MAX_SHOTS = 3
local SCREEN_X = 65
local SCREEN_Y = 110
local LINE_HEIGHT = 18
local MATCH_EPSILON = 0.01

local CORE_STORAGE_KEY = "mods.sc.radiusCore"
local SCALING_STORAGE_KEY = "mods.sc.projectileScaling"

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

local function trim_weapon_name(name)
    name = tostring(name or "unknown")

    if #name <= 30 then
        return name
    end

    return string.sub(name, 1, 27) .. "..."
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
        weaponModifiedRadius = core.weaponModifiedRadius,
        pilotDelta = core.pilotModifierDelta,
        detectorDelta = core.detectorModifierDelta,
        startingRadius = core.startingRadius,
        finalRadius = core.finalRadius,
        projectileDelta = core.projectileModifierDelta
    }

    shot.match =
        shot.coreTest == EXPECTED_CORE_TEST
        and nearly_equal(
            shot.startingRadius,
            shot.weaponModifiedRadius
        )

    table.insert(shots, shot)

    while #shots > MAX_SHOTS do
        table.remove(shots, 1)
    end
end

local function register_debug_handler()
    if mods.sc_debug_radius_integration_registered_test7 then
        return
    end

    mods.sc_debug_radius_integration_registered_test7 = true

    script.on_internal_event(
        Defines.InternalEvents.PROJECTILE_FIRE,
        capture_shot
    )
end

-- Radius Core Test No. 3 also registers its fire handler from on_load.
-- Because this debug file loads last, this handler is registered afterward.
script.on_load(register_debug_handler)

local function get_first_weapon_preview()
    local ship = Hyperspace.ships.player
    local weapons = ship
        and ship.weaponSystem
        and ship.weaponSystem.weapons

    if not weapons then
        return nil
    end

    for weapon in vter(weapons) do
        if mods.sc
            and mods.sc.scaling
            and mods.sc.scaling
                .get_weapon_preview_calculation then

            local calculation =
                mods.sc.scaling
                    .get_weapon_preview_calculation(
                        ship,
                        weapon
                    )

            return {
                weaponName = weapon.blueprint
                    and weapon.blueprint.name
                    or "unknown",
                shared = calculation
                    and calculation.previewRadius,
                display = weapon.radius,
                pilotDelta = modifier_delta(
                    calculation,
                    "pilot_accuracy"
                ),
                detectorDelta = modifier_delta(
                    calculation,
                    "sc_detector"
                )
            }
        end

        return nil
    end

    return nil
end

script.on_render_event(
    Defines.RenderEvents.SHIP_STATUS,

    function()
        return Defines.Chain.CONTINUE
    end,

    function()
        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y,
            "Radius Integration - Debug Test No. "
                .. tostring(TEST_NUMBER)
        )

        local pilotRegistered =
            mods.sc
            and mods.sc.scaling
            and mods.sc.scaling.has_preview_modifier
            and mods.sc.scaling.has_preview_modifier(
                "pilot_accuracy"
            )

        local detectorRegistered =
            mods.sc
            and mods.sc.scaling
            and mods.sc.scaling.has_preview_modifier
            and mods.sc.scaling.has_preview_modifier(
                "sc_detector"
            )

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y + LINE_HEIGHT,
            "Shared modifiers: Pilot="
                .. (pilotRegistered and "YES" or "NO")
                .. " Detector="
                .. (detectorRegistered and "YES" or "NO")
                .. " | Expected Core="
                .. tostring(EXPECTED_CORE_TEST)
        )

        local preview = get_first_weapon_preview()

        if preview then
            local previewStatus = nearly_equal(
                preview.shared,
                preview.display
            ) and "MATCH" or "DIFF"

            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                SCREEN_Y + LINE_HEIGHT * 2,
                "Preview "
                    .. trim_weapon_name(preview.weaponName)
                    .. ": Shared="
                    .. number_text(preview.shared)
                    .. " Display="
                    .. number_text(preview.display)
                    .. " P="
                    .. number_text(preview.pilotDelta)
                    .. " D="
                    .. number_text(preview.detectorDelta)
                    .. " | "
                    .. previewStatus
            )
        else
            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                SCREEN_Y + LINE_HEIGHT * 2,
                "Preview: no player weapon calculation"
            )
        end

        if #shots == 0 then
            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                SCREEN_Y + LINE_HEIGHT * 3,
                "Fire a player weapon to capture pilot/detector radius data."
            )
            return
        end

        for index, shot in ipairs(shots) do
            local y = SCREEN_Y
                + LINE_HEIGHT * (2 + index * 2)

            local status

            if shot.coreTest ~= EXPECTED_CORE_TEST then
                status = "WRONG CORE"
            elseif shot.match then
                status = "MATCH"
            else
                status = "DIFF"
            end

            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                y,
                tostring(index)
                    .. ": "
                    .. trim_weapon_name(shot.weaponName)
                    .. " Src="
                    .. tostring(shot.source)
                    .. " Mode="
                    .. tostring(shot.mode or "-")
                    .. " | "
                    .. status
            )

            Graphics.freetype.easy_print(
                0,
                SCREEN_X + 18,
                y + LINE_HEIGHT,
                "Scale="
                    .. number_text(shot.scalingRadius)
                    .. " P="
                    .. number_text(shot.pilotDelta)
                    .. " D="
                    .. number_text(shot.detectorDelta)
                    .. " Start="
                    .. number_text(shot.startingRadius)
                    .. " Final="
                    .. number_text(shot.finalRadius)
                    .. " Proj="
                    .. number_text(shot.projectileDelta)
            )
        end
    end
)
