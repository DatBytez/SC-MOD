--[[
DESCRIPTION: Scales projectile visuals based on their firing order within a volley.
        - Each subsequent projectile grows in size.
TAG: <sc-projectile-scale value="#"/>
DEPENDENCIES: sc_tag.lua, Multiverse userdata_table
]]

local userdata_table = mods.multiverse.userdata_table

local projectileScaleWeapons = {}

mods.sc.tag.register("weapon", "sc-projectile-scale", projectileScaleWeapons, "value")

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    local scaleStep = projectileScaleWeapons[weapon.blueprint.name]
    if not scaleStep then return end

    local weaponData = userdata_table(weapon, "mods.sc.projectileScale")

    weaponData.shotIndex = (weaponData.shotIndex or 0) + 1

    if projectile.flight_animation then
        projectile.flight_animation.fScale =
            math.max(0, 1 + (weaponData.shotIndex - 1) * scaleStep)
    end

    if weapon.queuedProjectiles:size() == 0 then
        weaponData.shotIndex = 0
    end
end)