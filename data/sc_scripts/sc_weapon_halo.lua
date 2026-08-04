-- Test No. 1

--[[
HALO weapon-specific projectile behavior.

The HALO weapon creates one real mini-projectile and one fake
mini-projectile for each shot.

The shared radius system first calculates the normal frozen chainstep radius.
This script then adds a flat projectile-only radius delta to fake projectiles:

    Real HALO projectile:
        +0 additional radius

    Fake HALO projectile:
        +10 radius per stored chainstep level

The radius core sums projectile deltas and clamps once after the sum.
Load this script after sc_radius_core.lua.
]]

local HALO_WEAPON =
    "TERRAN_MISSILE_HALO"

local FAKE_PROJECTILE_SCALE =
    0.25

local FAKE_RADIUS_PER_CHAINSTEP =
    10

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

local function get_stored_chainstep_level(projectile)
    if not mods.sc
        or not mods.sc.scaling
        or not mods.sc.scaling.get_level then

        return 0
    end

    local level =
        mods.sc.scaling.get_level(
            projectile,
            "chainstep"
        )

    return math.max(
        0,
        math.floor(tonumber(level) or 0)
    )
end

mods.sc.radius.register_projectile_radius_delta(
    "halo_fake_spread",
    function(ship, projectile, weapon)
        if not is_halo_weapon(weapon)
            or not is_fake_projectile(projectile) then

            return 0
        end

        return get_stored_chainstep_level(projectile)
            * FAKE_RADIUS_PER_CHAINSTEP
    end
)

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
