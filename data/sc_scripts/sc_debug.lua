-- Test No. 5

--[[
Projectile radius application verification.

Shows the four most recent player-fired projectiles and compares:
    Expected = passive C/Q/S radius from sc_projectile_scaling.lua Test No. 2
    Start    = radius selected by sc_radius_core.lua Test No. 2 before
               projectile-only modifiers
    Final    = radius after detector, HALO, and other projectile modifiers

This debug script does not change projectile or weapon behavior.
]]

mods.sc_debug = mods.sc_debug or {}
mods.sc_debug.projectileRadiusApply =
    mods.sc_debug.projectileRadiusApply or {}

local REPORT =
    mods.sc_debug.projectileRadiusApply

local userdata_table =
    mods.multiverse.userdata_table

local TEST_NUMBER = 5
local REQUIRED_CORE_TEST = 2
local TRACK_OWNER_ID = 0
local MAX_SHOTS = 4
local SCREEN_X = 70
local SCREEN_Y = 115
local LINE_HEIGHT = 18
local MATCH_EPSILON = 0.01

local CORE_STORAGE_KEY =
    mods.sc
    and mods.sc.radius
    and mods.sc.radius.CORE_STORAGE_KEY
    or "mods.sc.radiusCore"

REPORT.shots = REPORT.shots or {}

local function number_text(value)
    if value == nil then
        return "-"
    end

    if value == math.floor(value) then
        return tostring(math.floor(value))
    end

    return string.format("%.2f", value)
end

local function trim_weapon_name(name)
    name = tostring(name or "unknown")

    if #name <= 38 then
        return name
    end

    return string.sub(name, 1, 35) .. "..."
end

local function copy_contribution(contribution)
    if not contribution then
        return nil
    end

    return {
        active = contribution.active,
        level = contribution.level,
        amount = contribution.amount,
        delta = contribution.delta,
        hasRadiusTag = contribution.hasRadiusTag
    }
end

local function contribution_text(label, contribution)
    if not contribution or not contribution.active then
        return label .. "=-"
    end

    if not contribution.hasRadiusTag then
        return label
            .. "="
            .. number_text(contribution.level)
            .. "(no radius)"
    end

    return label
        .. "="
        .. number_text(contribution.level)
        .. "x"
        .. number_text(contribution.amount)
        .. "="
        .. number_text(contribution.delta)
end

local function source_list(calculation)
    if not calculation
        or not calculation.contributions then

        return "none"
    end

    local sources = {}

    if calculation.contributions.chain
        and calculation.contributions.chain.active then
        table.insert(sources, "C")
    end

    if calculation.contributions.charge
        and calculation.contributions.charge.active then
        table.insert(sources, "Q")
    end

    if calculation.contributions.chainstep
        and calculation.contributions.chainstep.active then
        table.insert(sources, "S")
    end

    if #sources == 0 then
        return "none"
    end

    return table.concat(sources, "+")
end

local function get_status(calculation, coreData)
    if not coreData then
        return "NO CORE RECORD"
    end

    if coreData.testNumber ~= REQUIRED_CORE_TEST then
        return "WRONG CORE TEST"
    end

    if not calculation then
        return "NO CALCULATION"
    end

    if not calculation.hasStoredScaling then
        return "UNTAGGED"
    end

    if not calculation.hasScalingRadius then
        return "NO RADIUS STAT"
    end

    if coreData.startingRadius == nil then
        return "NO START VALUE"
    end

    if math.abs(
        coreData.startingRadius
            - calculation.expectedRadius
    ) <= MATCH_EPSILON then
        return "MATCH"
    end

    return "DIFF"
end

local function snapshot_calculation(calculation)
    if not calculation then
        return nil
    end

    local contributions =
        calculation.contributions or {}

    return {
        baseRadius = calculation.baseRadius,
        totalContribution = calculation.totalContribution,
        expectedRadius = calculation.expectedRadius,
        liveCoreRadius = calculation.liveCoreRadius,
        hasStoredScaling = calculation.hasStoredScaling,
        hasScalingRadius = calculation.hasScalingRadius,
        contributions = {
            chain = copy_contribution(
                contributions.chain
            ),
            charge = copy_contribution(
                contributions.charge
            ),
            chainstep = copy_contribution(
                contributions.chainstep
            )
        }
    }
end

local function snapshot_core_data(projectile)
    local stored =
        userdata_table(
            projectile,
            CORE_STORAGE_KEY
        )

    if not stored then
        return nil
    end

    return {
        testNumber = stored.testNumber,
        mode = stored.mode,
        baseRadius = stored.baseRadius,
        sharedExpectedRadius = stored.sharedExpectedRadius,
        legacyCoreRadius = stored.legacyCoreRadius,
        overrideRadius = stored.overrideRadius,
        startingRadius = stored.startingRadius,
        finalRadius = stored.finalRadius,
        projectileModifierDelta = stored.projectileModifierDelta,
        targetMovedDistance = stored.targetMovedDistance
    }
end

local function capture_projectile_radius(projectile, weapon)
        if not projectile
            or not weapon
            or not weapon.blueprint then

            return
        end

        if TRACK_OWNER_ID ~= nil
            and projectile.ownerId
                ~= TRACK_OWNER_ID then

            return
        end

        local calculation = nil

        if mods.sc
            and mods.sc.scaling
            and mods.sc.scaling
                .get_radius_calculation then

            calculation =
                mods.sc.scaling
                    .get_radius_calculation(
                        projectile,
                        weapon
                    )
        end

        local coreData =
            snapshot_core_data(
                projectile
            )

        table.insert(REPORT.shots, {
            weaponName =
                weapon.blueprint.name
                or "unknown",
            calculation =
                snapshot_calculation(
                    calculation
                ),
            coreData = coreData,
            status =
                get_status(
                    calculation,
                    coreData
                )
        })

        while #REPORT.shots > MAX_SHOTS do
            table.remove(REPORT.shots, 1)
        end
    end

local function register_debug_projectile_handler()
    if mods.sc_debug._projectileRadiusApplyRegisteredTest5 then
        return
    end

    mods.sc_debug._projectileRadiusApplyRegisteredTest5 = true

    script.on_internal_event(
        Defines.InternalEvents.PROJECTILE_FIRE,
        capture_projectile_radius
    )
end

-- This on_load callback was registered after the radius core's on_load
-- callback because sc_debug.lua is loaded last. The core therefore
-- registers its PROJECTILE_FIRE handler first, and this diagnostic
-- registers immediately afterward.
script.on_load(register_debug_projectile_handler)


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
            "Projectile Radius Apply - Debug Test No. "
                .. tostring(TEST_NUMBER)
        )

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y + LINE_HEIGHT,
            "Expected=C/Q/S | Start=core before projectile modifiers | Final=applied spread"
        )

        if not mods.sc
            or not mods.sc.scaling
            or not mods.sc.scaling
                .get_radius_calculation then

            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                SCREEN_Y + LINE_HEIGHT * 2,
                "ERROR: sc_projectile_scaling.lua Test No. 2 is not loaded"
            )

            return
        end

        if not mods.sc.radius
            or mods.sc.radius.CORE_TEST_NUMBER
                ~= REQUIRED_CORE_TEST then

            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                SCREEN_Y + LINE_HEIGHT * 2,
                "ERROR: sc_radius_core.lua Test No. 2 is not loaded"
            )

            return
        end

        if #REPORT.shots == 0 then
            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                SCREEN_Y + LINE_HEIGHT * 2,
                "Fire player chain, charge, chainstep, and untagged weapons."
            )

            return
        end

        for index, shot in ipairs(REPORT.shots) do
            local calculation =
                shot.calculation

            local coreData =
                shot.coreData

            local firstLineY =
                SCREEN_Y
                + LINE_HEIGHT * (index * 3 - 1)

            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                firstLineY,
                "Shot "
                    .. tostring(index)
                    .. ": "
                    .. trim_weapon_name(
                        shot.weaponName
                    )
                    .. " | Src="
                    .. source_list(calculation)
                    .. " | Mode="
                    .. tostring(
                        coreData
                        and coreData.mode
                        or "-"
                    )
                    .. " | "
                    .. tostring(shot.status)
            )

            if calculation and coreData then
                Graphics.freetype.easy_print(
                    0,
                    SCREEN_X,
                    firstLineY + LINE_HEIGHT,
                    "  Base="
                        .. number_text(
                            calculation.baseRadius
                        )
                        .. " Delta="
                        .. number_text(
                            calculation.totalContribution
                        )
                        .. " Expected="
                        .. number_text(
                            calculation.expectedRadius
                        )
                        .. " LegacyCore="
                        .. number_text(
                            coreData.legacyCoreRadius
                        )
                        .. " Start="
                        .. number_text(
                            coreData.startingRadius
                        )
                        .. " Final="
                        .. number_text(
                            coreData.finalRadius
                        )
                        .. " PMod="
                        .. number_text(
                            coreData.projectileModifierDelta
                        )
                )

                Graphics.freetype.easy_print(
                    0,
                    SCREEN_X,
                    firstLineY + LINE_HEIGHT * 2,
                    "  "
                        .. contribution_text(
                            "C",
                            calculation.contributions.chain
                        )
                        .. " | "
                        .. contribution_text(
                            "Q",
                            calculation.contributions.charge
                        )
                        .. " | "
                        .. contribution_text(
                            "S",
                            calculation.contributions.chainstep
                        )
                        .. " | Override="
                        .. number_text(
                            coreData.overrideRadius
                        )
                        .. " Move="
                        .. number_text(
                            coreData.targetMovedDistance
                        )
                )

            elseif coreData then
                Graphics.freetype.easy_print(
                    0,
                    SCREEN_X,
                    firstLineY + LINE_HEIGHT,
                    "  Core Test="
                        .. tostring(coreData.testNumber)
                        .. " Start="
                        .. number_text(coreData.startingRadius)
                        .. " Final="
                        .. number_text(coreData.finalRadius)
                )

            else
                Graphics.freetype.easy_print(
                    0,
                    SCREEN_X,
                    firstLineY + LINE_HEIGHT,
                    "  No Test No. 2 radius-core record was found."
                )
            end
        end
    end
)
