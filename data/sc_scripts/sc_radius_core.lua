--[[
DESCRIPTION: Owns all SC weapon-radius calculation, preview, modifiers, and projectile spread.
        - Calculates base radius and Chain/Charge/Chainstep radius scaling.
        - Applies registered weapon-radius modifiers in priority order.
        - Refreshes the live targeting radius, including while paused.
        - Calculates frozen fired-projectile radius from stored scaling levels.
        - Applies projectile-only radius deltas such as HALO fake-projectile spread.
        - Randomizes the projectile target once without changing its heading.
DEPENDENCIES: sc_projectile_scaling.lua, Multiverse userdata_table, Multiverse vter
]]

local userdata_table = mods.multiverse.userdata_table
local vter = mods.multiverse.vter
local scaling = mods.sc.scaling

mods.sc.radius = mods.sc.radius or {}
local radius = mods.sc.radius

local SOURCE_ORDER = {
    "chain",
    "charge",
    "chainstep"
}

radius.modifiers = radius.modifiers or {}
radius.modifierOrder = radius.modifierOrder or {}
radius.projectileRadiusDeltas =
    radius.projectileRadiusDeltas or {}

local modifiers = radius.modifiers
local modifierOrder = radius.modifierOrder
local projectileRadiusDeltas = radius.projectileRadiusDeltas

local modifierRegistrationSerial = 0

local function get_live_level(weapon, sourceName)
    if sourceName == "chain" then
        return weapon.boostLevel
    elseif sourceName == "charge" then
        return math.max(0, weapon.chargeLevel - 1)
    elseif sourceName == "chainstep" then
        local weaponData = userdata_table(weapon, "mods.sc.chainstep")

        return weaponData.firingLevel or weaponData.level or weapon.boostLevel
    end
end

local function calculate_source_radius(weaponName, baseRadius, getLevel)
    local result = baseRadius

    for _, sourceName in ipairs(SOURCE_ORDER) do
        local entry = scaling.get_source_stat_entry(sourceName, weaponName, "radius")

        if entry then
            result = result + getLevel(sourceName) * entry.value
        end
    end

    return math.max(0, result)
end

local function sort_modifier_order()
    table.sort(
        modifierOrder,
        function(leftName, rightName)
            local left = modifiers[leftName]
            local right = modifiers[rightName]

            if left.priority == right.priority then
                return left.serial < right.serial
            end

            return left.priority < right.priority
        end
    )
end

function radius.register_modifier(name, func, priority)
    local entry = modifiers[name]

    if not entry then
        modifierRegistrationSerial = modifierRegistrationSerial + 1

        entry = {serial = modifierRegistrationSerial}

        modifiers[name] = entry
        table.insert(modifierOrder, name)
    end

    entry.func = func
    entry.priority = priority or 100

    sort_modifier_order()
end

function radius.unregister_modifier(name)
    if not modifiers[name] then
        return false
    end

    modifiers[name] = nil

    for index = #modifierOrder, 1, -1 do
        if modifierOrder[index] == name then
            table.remove(modifierOrder, index)
            break
        end
    end

    return true
end

function radius.apply_modifiers(ship, weapon, startingRadius, baseRadius)
    local result = math.max(0, startingRadius)

    for _, name in ipairs(modifierOrder) do
        result = math.max(0, modifiers[name].func(ship, weapon, result, baseRadius))
    end

    return result
end

function radius.get_weapon_preview_radius(ship, weapon)
    local baseRadius = weapon.blueprint.radius

    local scalingRadius = calculate_source_radius(weapon.blueprint.name, baseRadius, function(sourceName)
                return get_live_level(weapon, sourceName)
            end)

    return radius.apply_modifiers(ship, weapon, scalingRadius, baseRadius)
end

function radius.get_projectile_starting_radius(projectile, weapon)
    local baseRadius = weapon.blueprint.radius

    local scalingRadius = calculate_source_radius(weapon.blueprint.name,baseRadius,function(sourceName)
                return scaling.get_level(projectile, sourceName)
            end)

    local ship = Hyperspace.ships(projectile.ownerId)

    return radius.apply_modifiers(ship, weapon, scalingRadius, baseRadius)
end

function radius.register_projectile_radius_delta(name, func)
    if type(name) ~= "string" or type(func) ~= "function" then
        return false
    end

    projectileRadiusDeltas[name] = func
    return true
end

function radius.unregister_projectile_radius_delta(name)
    if projectileRadiusDeltas[name] == nil then
        return false
    end

    projectileRadiusDeltas[name] = nil
    return true
end

function radius.get_projectile_radius(ship, projectile, weapon, startingRadius)
    local result = startingRadius

    if type(result) ~= "number" then
        result = radius.get_weapon_preview_radius(ship, weapon)
    end

    result = math.max(0, result or weapon.blueprint.radius)

    local totalDelta = 0

    for _, func in pairs(projectileRadiusDeltas) do
        local delta = func(ship, projectile, weapon)

        if type(delta) == "number" then
            totalDelta = totalDelta + delta
        end
    end

    return math.max(0, result + totalDelta)
end

local function get_random_point_in_radius(center, spread)
    local distance = spread * math.sqrt(math.random())

    local angle = math.random() * 2 * math.pi

    return Hyperspace.Pointf(center.x + distance * math.cos(angle), center.y + distance * math.sin(angle))
end

radius.get_random_point_in_radius = get_random_point_in_radius

local function refresh_ship_weapon_radii(ship)
    local weapons = ship and ship.weaponSystem and ship.weaponSystem.weapons

    if not weapons then return end

    for weapon in vter(weapons) do
        local previewRadius = radius.get_weapon_preview_radius(ship, weapon)

        weapon.radius = previewRadius
    end
end

radius.refresh_ship_weapon_radii = refresh_ship_weapon_radii

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, refresh_ship_weapon_radii)

script.on_render_event(Defines.RenderEvents.MOUSE_CONTROL, function()
        local playerShip = Hyperspace.ships.player

        if playerShip then
            refresh_ship_weapon_radii(playerShip)
        end

        return Defines.Chain.CONTINUE
    end,
    function()
    end
)

local function apply_projectile_radius(projectile, weapon)
    if not projectile.target then return end

    local ship = Hyperspace.ships(projectile.ownerId)

    local startingRadius = radius.get_projectile_starting_radius(projectile, weapon)

    local finalRadius = radius.get_projectile_radius(ship, projectile, weapon, startingRadius)

    if finalRadius <= 0 then return end

    local targetCenter = Hyperspace.Pointf(projectile.target.x, projectile.target.y)

    projectile.target = get_random_point_in_radius(targetCenter, finalRadius)
end

local function register_projectile_radius_handler()
    script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, apply_projectile_radius)
end

script.on_load(register_projectile_radius_handler)
