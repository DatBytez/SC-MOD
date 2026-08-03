--[[
HALO weapon-specific projectile behavior.

The HALO weapon creates one real mini-projectile and one fake
mini-projectile for each shot.

This script does not randomize projectile.target itself. Instead,
it registers a projectile-specific radius modifier with
sc_radius_core.lua. The radius core then performs one randomization:

    Real HALO projectile:
        normal final radius

    Fake HALO projectile:
        normal final radius * FAKE_RADIUS_MULTIPLIER

Load this script after sc_radius_core.lua.
]]

local HALO_WEAPON =
    "TERRAN_MISSILE_HALO"

local FAKE_PROJECTILE_SCALE =
    0.25

-- Preserved from the current repository version.
local FAKE_RADIUS_MULTIPLIER =
    5

local function is_halo_weapon(weapon)
    return weapon
        and weapon.blueprint
        and weapon.blueprint.name
            == HALO_WEAPON
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
        get_projectile_scale(
            projectile
        )

    return scale
        == FAKE_PROJECTILE_SCALE
end

-- sc_radius_core.lua must load first so this registration
-- function is available.
if mods.sc
    and mods.sc.radius
    and mods.sc.radius
        .register_projectile_modifier then

    mods.sc.radius.register_projectile_modifier(
        "halo_fake_spread",
        function(
            ship,
            projectile,
            weapon,
            radius,
            baseRadius
        )
            if not is_halo_weapon(weapon)
                or not is_fake_projectile(
                    projectile
                ) then

                return radius
            end

            return radius
                * FAKE_RADIUS_MULTIPLIER
        end
    )
end

-- Give fake HALO projectiles the same shield piercing
-- as the parent HALO weapon while leaving all damage at zero.
script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_FIRE,
    function(projectile, weapon)

        if not is_halo_weapon(weapon)
            or not is_fake_projectile(projectile) then

            return
        end

        local blueprintDamage =
            weapon.blueprint
            and weapon.blueprint.damage

        projectile.damage.iShieldPiercing =
            blueprintDamage
            and blueprintDamage.iShieldPiercing
            or 5
    end
)