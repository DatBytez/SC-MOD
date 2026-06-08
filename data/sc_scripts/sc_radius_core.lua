mods.sc = mods.sc or {}
mods.sc.radius = mods.sc.radius or {}

local userdata_table = mods.multiverse.userdata_table
local vter = mods.multiverse.vter

mods.sc.radius.modifiers = mods.sc.radius.modifiers or {}

local function get_random_point_in_radius(center, radius)
    local r = radius * math.sqrt(math.random())
    local theta = math.random() * 2 * math.pi
    return Hyperspace.Pointf(center.x + r * math.cos(theta), center.y + r * math.sin(theta))
end

mods.sc.radius.get_random_point_in_radius = get_random_point_in_radius

function mods.sc.radius.get_base_radius(weapon)
    local wdata = userdata_table(weapon, "mods.sc.weaponStuff")
    if wdata.baseRadius == nil then
        wdata.baseRadius = (weapon.blueprint and weapon.blueprint.radius) or weapon.radius or 0
    end
    return wdata.baseRadius
end

function mods.sc.radius.register_modifier(name, func)
    mods.sc.radius.modifiers[name] = func
end

function mods.sc.radius.unregister_modifier(name)
    mods.sc.radius.modifiers[name] = nil
end

function mods.sc.radius.get_final_radius(ship, weapon)
    local baseRadius = mods.sc.radius.get_base_radius(weapon)
    local radius = baseRadius

    for _, func in pairs(mods.sc.radius.modifiers) do
        radius = func(ship, weapon, radius, baseRadius)
    end

    return math.max(0, radius)
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    local weapons = ship and ship.weaponSystem and ship.weaponSystem.weapons
    if not weapons then return end

    for weapon in vter(weapons) do
        weapon.radius = mods.sc.radius.get_final_radius(ship, weapon)
    end
end)

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    if not projectile or not weapon then return end

    local ship = Hyperspace.ships(projectile.ownerId)
    if not ship then return end

    local wdata = userdata_table(weapon, "mods.sc.weaponStuff")

    if wdata.fireRadiusOverrideActive then
        local radius = math.max(0, wdata.fireRadiusOverride or 0)

        wdata.fireRadiusOverrideActive = false
        wdata.fireRadiusOverride = nil

        if radius > 0 then
            projectile.target = get_random_point_in_radius(projectile.target, radius)
        end
        return
    end

    local radius = mods.sc.radius.get_final_radius(ship, weapon)
    if radius > 0 then
        projectile.target = get_random_point_in_radius(projectile.target, radius)
    end
end)