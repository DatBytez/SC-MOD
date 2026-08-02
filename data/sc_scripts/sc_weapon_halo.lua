--[[
HALO weapon-specific projectile behavior.

The HALO weapon uses one real mini-projectile and one fake
mini-projectile for each shot. This script increases only the
fake projectile's spread.

IMPORTANT:
Load this script after both sc_radius_core.lua and
sc_weapon_chainstep.lua so it can replace the fake projectile's
normal target after the standard radius calculation has run.
]]

local HALO_WEAPON = "TERRAN_MISSILE_HALO"
local FAKE_PROJECTILE_SCALE = 0.25
local FAKE_RADIUS_MULTIPLIER = 2

local function is_halo_weapon(weapon)
    return weapon
        and weapon.blueprint
        and weapon.blueprint.name == HALO_WEAPON
end

local function is_fake_projectile(projectile)
    return projectile
        and projectile.death_animation
        and projectile.death_animation.fScale == FAKE_PROJECTILE_SCALE
end

local function get_original_target(projectile, weapon)
    -- The weapon target is the center selected by the player or AI.
    -- Use it instead of the projectile's current target because
    -- sc_radius_core.lua has already randomized projectile.target.
    if weapon
        and weapon.targets
        and weapon.targets:size() > 0 then

        local target = weapon.targets[0]

        if target then
            return Hyperspace.Pointf(
                target.x,
                target.y
            )
        end
    end

    -- Fallback for unusual cases where the weapon's target list
    -- is unavailable. This will add the larger spread around the
    -- projectile's current target instead.
    if projectile and projectile.target then
        return Hyperspace.Pointf(
            projectile.target.x,
            projectile.target.y
        )
    end

    return nil
end

script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_FIRE,
    function(projectile, weapon)

        if not is_halo_weapon(weapon)
            or not is_fake_projectile(projectile) then
            return
        end

        local ship =
            Hyperspace.ships(projectile.ownerId)

        if not ship
            or not mods.sc
            or not mods.sc.radius
            or not mods.sc.radius.get_final_radius
            or not mods.sc.radius.get_random_point_in_radius then
            return
        end

        local radius =
            mods.sc.radius.get_final_radius(
                ship,
                weapon
            )

        if not radius or radius <= 0 then
            return
        end

        local center =
            get_original_target(
                projectile,
                weapon
            )

        if not center then
            return
        end

        projectile.target =
            mods.sc.radius.get_random_point_in_radius(
                center,
                radius * FAKE_RADIUS_MULTIPLIER
            )
    end
)
