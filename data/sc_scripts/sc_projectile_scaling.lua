-- Test No. 6

--[[
Shared projectile-scaling and weapon-radius calculations.

Load this file after sc_tag.lua and before sc_radius_core.lua.

The chain, charge, and chainstep weapon scripts store the exact zero-based
level used by each fired projectile in:

    userdata_table(projectile, "mods.sc.projectileScaling")

This file reads that frozen data for fired projectiles and reads the live
weapon state for the targeting preview. Radius is calculated in this order:

    1. Blueprint/base radius.
    2. Chain, charge, and chainstep radius contributions.
    3. Registered weapon-radius modifiers in priority order.

Projectile-only flat radius deltas are applied afterward by
sc_radius_core.lua.
]]

local userdata_table = mods.multiverse.userdata_table

mods.sc = mods.sc or {}
mods.sc.scaling = mods.sc.scaling or {}

local scaling = mods.sc.scaling

local STORAGE_KEY = "mods.sc.projectileScaling"
local WEAPON_DATA_KEY = "mods.sc.weaponStuff"

local SOURCE_ORDER = {
    "chain",
    "charge",
    "chainstep"
}

local function number_or_zero(value)
    return tonumber(value) or 0
end

local function clamp_radius(radius)
    return math.max(0, number_or_zero(radius))
end

function scaling.get_base_radius(weapon)
    if not weapon then
        return 0
    end

    local weaponData = userdata_table(
        weapon,
        WEAPON_DATA_KEY
    )

    if type(weaponData.baseRadius) ~= "number" then
        weaponData.baseRadius =
            (
                weapon.blueprint
                and weapon.blueprint.radius
            )
            or weapon.radius
            or 0
    end

    return weaponData.baseRadius
end

local function read_storage(projectile)
    if not projectile then
        return nil
    end

    return userdata_table(projectile, STORAGE_KEY)
end

local function get_weapon_name(projectileData, weapon)
    if projectileData and projectileData.weaponName then
        return projectileData.weaponName
    end

    return weapon
        and weapon.blueprint
        and weapon.blueprint.name
        or nil
end

local function find_radius_entry(entries)
    if type(entries) ~= "table" then
        return nil
    end

    for _, entry in ipairs(entries) do
        if entry.stat == "radius" then
            return entry.amount or 0
        end
    end

    return nil
end

local function get_source_definition(sourceName, weaponName)
    if not weaponName then
        return nil
    end

    if sourceName == "chain" then
        return mods.sc.chainers
            and mods.sc.chainers[weaponName]
            or nil
    end

    if sourceName == "charge" then
        return mods.sc.chargers
            and mods.sc.chargers[weaponName]
            or nil
    end

    if sourceName == "chainstep" then
        return mods.sc.chainstep
            and mods.sc.chainstep[weaponName]
            or nil
    end

    return nil
end

local function get_radius_amount(sourceName, weaponName)
    local definition = get_source_definition(
        sourceName,
        weaponName
    )

    if sourceName == "chainstep" then
        return find_radius_entry(
            definition and definition.statBoosts
        )
    end

    return find_radius_entry(definition)
end

local function get_projectile_data(projectile)
    local stored = read_storage(projectile)

    if not stored then
        return nil
    end

    local data = {
        weaponName = stored.weaponName
    }

    if stored.hasChain == true then
        data.chain = {
            level = math.max(
                0,
                number_or_zero(stored.chainLevel)
            )
        }
    end

    if stored.hasCharge == true then
        data.charge = {
            level = math.max(
                0,
                number_or_zero(stored.chargeLevel)
            )
        }
    end

    if stored.hasChainstep == true then
        data.chainstep = {
            level = math.max(
                0,
                number_or_zero(stored.chainstepLevel)
            )
        }
    end

    return data
end

function scaling.get_level(projectile, sourceName)
    local data = get_projectile_data(projectile)
    local source = data and data[sourceName]

    return source and source.level or nil
end

local function calculate_source_radius(
    weaponName,
    baseRadius,
    getLevel
)
    local radius = baseRadius

    for _, sourceName in ipairs(SOURCE_ORDER) do
        local definition = get_source_definition(
            sourceName,
            weaponName
        )

        local active, level = getLevel(
            sourceName,
            definition
        )

        local amount = get_radius_amount(
            sourceName,
            weaponName
        )

        if active and amount ~= nil then
            radius = radius
                + math.max(0, number_or_zero(level))
                * amount
        end
    end

    return clamp_radius(radius)
end

-- --------------------------------------------------------------------------
-- WEAPON-RADIUS MODIFIERS
-- --------------------------------------------------------------------------

scaling.weaponRadiusModifiers =
    scaling.weaponRadiusModifiers or {}

scaling.weaponRadiusModifierOrder =
    scaling.weaponRadiusModifierOrder or {}

local weaponRadiusModifiers = scaling.weaponRadiusModifiers
local weaponRadiusModifierOrder = scaling.weaponRadiusModifierOrder
local modifierRegistrationSerial = 0

local function sort_modifier_order()
    table.sort(
        weaponRadiusModifierOrder,
        function(leftName, rightName)
            local left = weaponRadiusModifiers[leftName]
            local right = weaponRadiusModifiers[rightName]

            if not left then return false end
            if not right then return true end

            if left.priority == right.priority then
                return left.serial < right.serial
            end

            return left.priority < right.priority
        end
    )
end

-- Lower priority values run first. Re-registering an existing name replaces
-- its function and priority while retaining its original serial tie-breaker.
function scaling.register_weapon_radius_modifier(
    name,
    func,
    priority
)
    if type(name) ~= "string"
        or type(func) ~= "function" then

        return false
    end

    local existing = weaponRadiusModifiers[name]

    if not existing then
        modifierRegistrationSerial =
            modifierRegistrationSerial + 1

        existing = {
            serial = modifierRegistrationSerial
        }

        weaponRadiusModifiers[name] = existing
        table.insert(weaponRadiusModifierOrder, name)
    end

    existing.func = func
    existing.priority = tonumber(priority) or 100

    sort_modifier_order()
    return true
end

function scaling.unregister_weapon_radius_modifier(name)
    if not weaponRadiusModifiers[name] then
        return false
    end

    weaponRadiusModifiers[name] = nil

    for index = #weaponRadiusModifierOrder, 1, -1 do
        if weaponRadiusModifierOrder[index] == name then
            table.remove(weaponRadiusModifierOrder, index)
        end
    end

    return true
end

function scaling.has_weapon_radius_modifier(name)
    return weaponRadiusModifiers[name] ~= nil
end

function scaling.apply_weapon_radius_modifiers(
    ship,
    weapon,
    startingRadius,
    baseRadius
)
    local radius = clamp_radius(startingRadius)

    for _, name in ipairs(weaponRadiusModifierOrder) do
        local entry = weaponRadiusModifiers[name]

        if entry and entry.func then
            local success, modifiedRadius = pcall(
                entry.func,
                ship,
                weapon,
                radius,
                baseRadius
            )

            if success
                and type(modifiedRadius) == "number" then

                radius = clamp_radius(modifiedRadius)
            end
        end
    end

    return radius
end

-- --------------------------------------------------------------------------
-- LIVE PREVIEW LEVELS
-- --------------------------------------------------------------------------

local function get_live_level(weapon, sourceName)
    if not weapon then
        return 0
    end

    if sourceName == "chain" then
        return math.max(
            0,
            number_or_zero(weapon.boostLevel)
        )
    end

    if sourceName == "charge" then
        return math.max(
            0,
            number_or_zero(weapon.chargeLevel) - 1
        )
    end

    if sourceName == "chainstep" then
        local weaponData = userdata_table(
            weapon,
            "mods.sc.chainstep"
        )

        return math.max(
            0,
            math.floor(
                number_or_zero(
                    weaponData.firingLevel
                        or weaponData.level
                        or weapon.boostLevel
                )
            )
        )
    end

    return 0
end

function scaling.get_weapon_preview_calculation(ship, weapon)
    if not weapon or not weapon.blueprint then
        return nil
    end

    local weaponName = weapon.blueprint.name
    local baseRadius = scaling.get_base_radius(weapon)

    local scalingRadius = calculate_source_radius(
        weaponName,
        baseRadius,
        function(sourceName, definition)
            return definition ~= nil,
                definition and get_live_level(
                    weapon,
                    sourceName
                ) or nil
        end
    )

    local previewRadius =
        scaling.apply_weapon_radius_modifiers(
            ship,
            weapon,
            scalingRadius,
            baseRadius
        )

    return {
        baseRadius = baseRadius,
        scalingRadius = scalingRadius,
        previewRadius = previewRadius
    }
end

function scaling.get_weapon_preview_radius(ship, weapon)
    local calculation = scaling.get_weapon_preview_calculation(
        ship,
        weapon
    )

    if not calculation then
        return nil
    end

    return calculation.previewRadius
end

-- Calculates the frozen starting radius for one fired projectile. C/Q/S use
-- metadata already stored on the projectile. Weapon modifiers use the firing
-- ship's current state when the radius core handles the shot.
function scaling.get_projectile_starting_radius_calculation(
    projectile,
    weapon
)
    if not projectile or not weapon then
        return nil
    end

    local projectileData = get_projectile_data(projectile)
    local weaponName = get_weapon_name(
        projectileData,
        weapon
    )
    local baseRadius = scaling.get_base_radius(weapon)

    local scalingRadius = calculate_source_radius(
        weaponName,
        baseRadius,
        function(sourceName)
            local sourceData = projectileData
                and projectileData[sourceName]
                or nil

            return sourceData ~= nil,
                sourceData and sourceData.level or nil
        end
    )

    local ship = Hyperspace.ships(projectile.ownerId)

    local startingRadius =
        scaling.apply_weapon_radius_modifiers(
            ship,
            weapon,
            scalingRadius,
            baseRadius
        )

    return {
        baseRadius = baseRadius,
        scalingRadius = scalingRadius,
        startingRadius = startingRadius
    }
end

function scaling.get_projectile_starting_radius(
    projectile,
    weapon
)
    local calculation =
        scaling.get_projectile_starting_radius_calculation(
            projectile,
            weapon
        )

    return calculation and calculation.startingRadius or nil
end
