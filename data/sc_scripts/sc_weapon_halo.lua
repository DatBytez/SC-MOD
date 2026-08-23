--[[
DESCRIPTION: Applies special behavior to tagged HALO weapons.
        - Adds +10 radius per stored chainstep level to fake projectiles.
        - Gives fake projectiles the parent weapon's shield piercing.
TAG: <sc-halo/>
DEPENDENCIES: sc_tag.lua, sc_projectile_scaling.lua, sc_radius_core.lua
]]

local haloWeapons = {}

mods.sc.tag.register("weapon", "sc-halo", haloWeapons)

local FAKE_RADIUS_PER_CHAINSTEP = 10

local function is_fake_projectile(projectile)
    return projectile.death_animation and projectile.death_animation.fScale == 0.25 -- This is the only way I can find to detect fake projectiles.
end

local function get_stored_chainstep_level(projectile)
    local level = mods.sc.scaling.get_level(projectile, "chainstep")

    return math.max(0, math.floor(tonumber(level) or 0))
end

mods.sc.radius.register_projectile_radius_delta("halo_fake_spread", function(_ship, projectile, weapon)
        if not haloWeapons[weapon.blueprint.name] or not is_fake_projectile(projectile) then
            return 0
        end

        return get_stored_chainstep_level(projectile) * FAKE_RADIUS_PER_CHAINSTEP
    end
)

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
        if not haloWeapons[weapon.blueprint.name] or not is_fake_projectile(projectile) then
            return
        end

        projectile.damage.iShieldPiercing = weapon.blueprint.damage.iShieldPiercing
    end
)