--[[
DESCRIPTION: Weapon targeting effects for the Terran pilot ability.
        - Reduces targeting radius from the current dodge-derived accuracy bonus.
        - Adds that accuracy bonus to fired projectiles.
        - Increases projectile speed by 1% per point of converted accuracy.
DEPENDENCIES: sc_pilot.lua, sc_radius_core.lua
]]

local pilot = mods.sc.pilot

local RADIUS_PER_ACCURACY = 1.5
local MIN_RADIUS = 1

-- Refresh the dodge-derived accuracy inside the modifier itself so Radius Core
-- remains generic and the targeting preview updates immediately while paused.
local function apply_pilot_radius_modifier(ship, weapon, radius, baseRadius)
    if not pilot.is_active(ship) then
        return radius
    end

    local accuracyBonus = pilot.refresh_accuracy(ship)

    if accuracyBonus <= 0 then
        return radius
    end

    return math.max(
        MIN_RADIUS,
        radius - accuracyBonus * RADIUS_PER_ACCURACY
    )
end

mods.sc.radius.register_modifier(
    "pilot_accuracy",
    apply_pilot_radius_modifier,
    100
)

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile)
    local ship = Hyperspace.ships(projectile.ownerId)

    if not pilot.is_active(ship) then
        pilot.clear_accuracy(ship)
        return
    end

    local accuracyBonus = pilot.refresh_accuracy(ship)

    projectile.extend.customDamage.accuracyMod =
        projectile.extend.customDamage.accuracyMod + accuracyBonus

    local speedMultiplier = 1 + accuracyBonus * 0.01

    projectile.speed = Hyperspace.Pointf(
        projectile.speed.x * speedMultiplier,
        projectile.speed.y * speedMultiplier
    )

    projectile.speed_magnitude =
        projectile.speed_magnitude * speedMultiplier
end)