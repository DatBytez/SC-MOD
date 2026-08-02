--[[
SC DEBUG - HALO PROJECTILE REPORT

Purpose:
    Keep the most recent complete/active HALO attack visible on screen.

A HALO attack currently produces 8 projectile events:
    4 real missile projectiles
    4 fake visual projectiles

This script records:
    selected  = weapon.targets[0], the original aim center
    core      = projectile.target when PROJECTILE_FIRE reaches this file
    final     = projectile.target on the projectile's first update
    coreDist  = distance from selected to core
    haloMove  = distance from core to final
    finalDist = distance from selected to final

REQUIRED SCRIPT ORDER:
    sc_radius_core.lua
    sc_weapon_chainstep.lua
    sc_debug.lua
    sc_weapon_halo.lua

With that order:
    "core" shows the result after sc_radius_core.lua.
    "final" shows the result after sc_weapon_halo.lua.

The report remains visible until another HALO attack begins.
]]

mods.sc_debug = mods.sc_debug or {}
mods.sc_debug.halo = mods.sc_debug.halo or {}

local HALO_WEAPON_NAME = "TERRAN_MISSILE_HALO"
local HALO_PROJECTILES_PER_ATTACK = 8
local FAKE_PROJECTILE_SCALE = 0.25

-- Track only player-fired HALO attacks.
-- Change this to nil to accept either player or enemy projectiles.
local TRACK_OWNER_ID = 0

-- A large gap also starts a new report, which prevents an interrupted
-- partial volley from being combined with the next attack.
local NEW_ATTACK_TICK_GAP = 120

local SCREEN_X = 10
local SCREEN_Y = 175
local LINE_HEIGHT = 20

local POSITION_EPSILON = 0.05

local userdata_table =
    mods.multiverse
    and mods.multiverse.userdata_table

local report = mods.sc_debug.halo

report.attackNumber =
    report.attackNumber or 0

report.shots =
    report.shots or {}

report.tick =
    report.tick or 0

report.lastShotTick =
    report.lastShotTick or -100000

-- -----------------
-- GENERAL HELPERS
-- -----------------

local function copy_point(point)
    if not point then
        return nil
    end

    return {
        x = point.x or 0,
        y = point.y or 0
    }
end

local function get_weapon_target(weapon)
    if not weapon
        or not weapon.targets
        or weapon.targets:size() <= 0 then

        return nil
    end

    return copy_point(
        weapon.targets[0]
    )
end

local function distance_between(pointA, pointB)
    if not pointA or not pointB then
        return nil
    end

    local dx =
        pointB.x - pointA.x

    local dy =
        pointB.y - pointA.y

    return math.sqrt(
        dx * dx + dy * dy
    )
end

local function format_number(value)
    if value == nil then
        return "-"
    end

    return string.format(
        "%.1f",
        value
    )
end

local function format_point(point)
    if not point then
        return "(-,-)"
    end

    return string.format(
        "(%.0f,%.0f)",
        point.x,
        point.y
    )
end

local function get_projectile_scale(projectile)
    if projectile
        and projectile.death_animation then

        return projectile
            .death_animation
            .fScale
    end

    return nil
end

local function is_fake_projectile(projectile)
    local scale =
        get_projectile_scale(projectile)

    return scale ~= nil
        and math.abs(
            scale - FAKE_PROJECTILE_SCALE
        ) < 0.0001
end

local function is_tracked_halo_projectile(projectile, weapon)
    if not projectile
        or not weapon
        or not weapon.blueprint
        or weapon.blueprint.name ~= HALO_WEAPON_NAME then

        return false
    end

    if TRACK_OWNER_ID ~= nil
        and projectile.ownerId ~= TRACK_OWNER_ID then

        return false
    end

    return true
end

local function get_projectile_debug_state(projectile)
    if not projectile then
        return nil
    end

    if userdata_table then
        return userdata_table(
            projectile,
            "mods.sc_debug.halo"
        )
    end

    -- This fallback is only for installations where the MV
    -- userdata helper is unavailable.
    projectile.table =
        projectile.table or {}

    projectile.table.sc_debug_halo =
        projectile.table.sc_debug_halo or {}

    return projectile.table.sc_debug_halo
end

-- -----------------
-- REPORT MANAGEMENT
-- -----------------

local function start_new_attack(ownerId)
    report.attackNumber =
        report.attackNumber + 1

    report.ownerId =
        ownerId

    report.shots = {}

    report.startedTick =
        report.tick
end

local function should_start_new_attack()
    if #report.shots == 0 then
        return true
    end

    if #report.shots
        >= HALO_PROJECTILES_PER_ATTACK then

        return true
    end

    return report.tick
        - report.lastShotTick
        > NEW_ATTACK_TICK_GAP
end

local function classify_randomizer(shot)
    local coreMoved =
        shot.coreDistance ~= nil
        and shot.coreDistance
            > POSITION_EPSILON

    local haloMoved =
        shot.haloMove ~= nil
        and shot.haloMove
            > POSITION_EPSILON

    if coreMoved and haloMoved then
        return "CORE+HALO"
    elseif haloMoved then
        return "HALO"
    elseif coreMoved then
        return "CORE"
    end

    if shot.finalTarget == nil then
        return "WAIT"
    end

    return "NONE"
end

-- -----------------
-- TICK COUNTER
-- -----------------

script.on_internal_event(
    Defines.InternalEvents.ON_TICK,
    function()
        report.tick =
            report.tick + 1
    end
)

-- -----------------
-- CAPTURE AFTER RADIUS CORE
-- -----------------

script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_FIRE,
    function(projectile, weapon)

        if not is_tracked_halo_projectile(
            projectile,
            weapon
        ) then
            return
        end

        if should_start_new_attack() then
            start_new_attack(
                projectile.ownerId
            )
        end

        local selectedTarget =
            get_weapon_target(weapon)

        local coreTarget =
            copy_point(
                projectile.target
            )

        local shot = {
            index =
                #report.shots + 1,

            fake =
                is_fake_projectile(
                    projectile
                ),

            scale =
                get_projectile_scale(
                    projectile
                ),

            selectedTarget =
                selectedTarget,

            coreTarget =
                coreTarget,

            coreDistance =
                distance_between(
                    selectedTarget,
                    coreTarget
                ),

            finalTarget =
                nil,

            finalDistance =
                nil,

            haloMove =
                nil
        }

        table.insert(
            report.shots,
            shot
        )

        report.lastShotTick =
            report.tick

        local projectileState =
            get_projectile_debug_state(
                projectile
            )

        if projectileState then
            projectileState.shot =
                shot

            projectileState.finalCaptured =
                false
        end
    end
)

-- -----------------
-- CAPTURE AFTER HALO SCRIPT
-- -----------------

script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_UPDATE_PRE,
    function(projectile)

        local projectileState =
            get_projectile_debug_state(
                projectile
            )

        if not projectileState
            or projectileState.finalCaptured
            or not projectileState.shot then

            return Defines.Chain.CONTINUE
        end

        local shot =
            projectileState.shot

        shot.finalTarget =
            copy_point(
                projectile.target
            )

        shot.finalDistance =
            distance_between(
                shot.selectedTarget,
                shot.finalTarget
            )

        shot.haloMove =
            distance_between(
                shot.coreTarget,
                shot.finalTarget
            )

        projectileState.finalCaptured =
            true

        return Defines.Chain.CONTINUE
    end
)

-- -----------------
-- SCREEN REPORT
-- -----------------

script.on_render_event(
    Defines.RenderEvents.SHIP_STATUS,

    function()
        return Defines.Chain.CONTINUE
    end,

    function()
        if #report.shots == 0 then
            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                SCREEN_Y,
                "HALO DEBUG: waiting for a player HALO attack..."
            )
            return
        end

        local ownerText =
            report.ownerId == 0
            and "PLAYER"
            or "ENEMY"

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y,
            "HALO ATTACK #"
                .. tostring(
                    report.attackNumber
                )
                .. " | owner="
                .. ownerText
                .. " | projectiles="
                .. tostring(
                    #report.shots
                )
                .. "/"
                .. tostring(
                    HALO_PROJECTILES_PER_ATTACK
                )
        )

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y + LINE_HEIGHT,
            "ID T scale | selected | core d | final d | haloMove | source"
        )

        for index = 1,
            HALO_PROJECTILES_PER_ATTACK do

            local shot =
                report.shots[index]

            local rowY =
                SCREEN_Y
                + LINE_HEIGHT
                * (index + 1)

            if shot then
                local typeText =
                    shot.fake
                    and "F"
                    or "R"

                local rowText =
                    string.format(
                        "%d  %s %s | %s | %s %s | %s %s | %s | %s",
                        index,
                        typeText,
                        format_number(
                            shot.scale
                        ),
                        format_point(
                            shot.selectedTarget
                        ),
                        format_point(
                            shot.coreTarget
                        ),
                        format_number(
                            shot.coreDistance
                        ),
                        format_point(
                            shot.finalTarget
                        ),
                        format_number(
                            shot.finalDistance
                        ),
                        format_number(
                            shot.haloMove
                        ),
                        classify_randomizer(
                            shot
                        )
                    )

                Graphics.freetype.easy_print(
                    0,
                    SCREEN_X,
                    rowY,
                    rowText
                )
            else
                Graphics.freetype.easy_print(
                    0,
                    SCREEN_X,
                    rowY,
                    tostring(index)
                        .. "  -- waiting --"
                )
            end
        end

        local footerY =
            SCREEN_Y
            + LINE_HEIGHT
            * (
                HALO_PROJECTILES_PER_ATTACK
                + 2
            )

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            footerY,
            "R=real F=fake | core=sc_radius_core result | haloMove=change after sc_weapon_halo"
        )
    end
)