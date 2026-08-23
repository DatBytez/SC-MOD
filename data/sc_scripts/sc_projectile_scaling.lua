--[[
DESCRIPTION: Shared projectile stat, missile-cost, and weapon-radius scaling.
        - Reads frozen Chain, Charge, and Chainstep levels from fired projectiles.
        - Applies tagged projectile stat values through one shared path.
        - Calculates and pays Lua-controlled missile costs.
        - Calculates live targeting-preview radius and frozen fired-projectile radius.
        - Applies registered weapon-radius modifiers in priority order.
DEPENDENCIES: sc_tag.lua, Multiverse userdata_table
]]

local userdata_table = mods.multiverse.userdata_table

mods.sc.scaling = mods.sc.scaling or {}
local scaling = mods.sc.scaling

local STORAGE_KEY = "mods.sc.projectileScaling"
local WEAPON_DATA_KEY = "mods.sc.weaponStuff"

local SOURCE_ORDER = {
    "chain",
    "charge",
    "chainstep"
}

local SOURCE_LEVEL_FIELDS = {
    chain = {
        active = "hasChain",
        level = "chainLevel"
    },
    charge = {
        active = "hasCharge",
        level = "chargeLevel"
    },
    chainstep = {
        active = "hasChainstep",
        level = "chainstepLevel"
    }
}

local SPECIAL_SCALING_STATS = {
    radius = true,
    shots = true,
    cooldown = true,
    missileCost = true
}

local function number_or_zero(value)
    return tonumber(value) or 0
end

local function clamp_radius(radius)
    return math.max(0, number_or_zero(radius))
end

function scaling.get_base_radius(weapon)
    if not weapon then return 0 end

    local weaponData = userdata_table(weapon, WEAPON_DATA_KEY)

    if type(weaponData.baseRadius) ~= "number" then
        weaponData.baseRadius =
            (weapon.blueprint and weapon.blueprint.radius)
            or weapon.radius
            or 0
    end

    return weaponData.baseRadius
end

local function get_source_definition(sourceName, weaponName)
    if sourceName == "chain" then
        return mods.sc.chainers and mods.sc.chainers[weaponName]
    elseif sourceName == "charge" then
        return mods.sc.chargers and mods.sc.chargers[weaponName]
    elseif sourceName == "chainstep" then
        return mods.sc.chainstep and mods.sc.chainstep[weaponName]
    end
end

local function get_source_stat_entries(sourceName, weaponName)
    local definition = get_source_definition(sourceName, weaponName)
    if not definition then return nil end

    if sourceName == "chainstep" then
        return definition.statBoosts
    end

    return definition
end

function scaling.get_source_stat_entries(sourceName, weaponName)
    return get_source_stat_entries(sourceName, weaponName)
end

function scaling.get_source_stat_entry(sourceName, weaponName, statName)
    local entries = get_source_stat_entries(sourceName, weaponName)
    if not entries then return nil end

    for _, entry in ipairs(entries) do
        if entry.stat == statName then
            return entry
        end
    end
end

local function get_source_radius_value(sourceName, weaponName)
    local entry = scaling.get_source_stat_entry(
        sourceName,
        weaponName,
        "radius"
    )

    return entry and entry.value or nil
end

local function get_projectile_storage(projectile)
    if not projectile then return nil end
    return userdata_table(projectile, STORAGE_KEY)
end

local function get_stored_level(storage, sourceName)
    local fields = SOURCE_LEVEL_FIELDS[sourceName]

    if not fields or storage[fields.active] ~= true then
        return nil
    end

    return math.max(0, number_or_zero(storage[fields.level]))
end

function scaling.get_level(projectile, sourceName)
    local storage = get_projectile_storage(projectile)
    if not storage then return nil end

    return get_stored_level(storage, sourceName)
end

function scaling.apply_projectile_stats(
    projectile,
    weapon,
    sourceName,
    level,
    specialHandlers
)
    if not projectile or not weapon or not weapon.blueprint then return end

    local statBoosts = get_source_stat_entries(
        sourceName,
        weapon.blueprint.name
    )

    if not statBoosts then return end

    level = math.max(0, number_or_zero(level))

    for _, statBoost in ipairs(statBoosts) do
        local stat = statBoost.stat
        local value = number_or_zero(statBoost.value)
        local specialHandler =
            type(specialHandlers) == "table"
            and specialHandlers[stat]

        if specialHandler then
            specialHandler(
                projectile,
                weapon,
                statBoost,
                level,
                sourceName
            )
        elseif SPECIAL_SCALING_STATS[stat] then
            -- Radius and weapon/volley mechanics are handled elsewhere.
        elseif stat == "accuracyMod" then
            if projectile.extend and projectile.extend.customDamage then
                local customDamage = projectile.extend.customDamage

                customDamage.accuracyMod =
                    number_or_zero(customDamage.accuracyMod)
                    + level * value
            end
        elseif projectile.damage then
            projectile.damage[stat] =
                number_or_zero(projectile.damage[stat])
                + level * value
        end
    end
end

function scaling.calculate_missile_cost(missileData, level)
    if not missileData then return nil end

    local baseCost = tonumber(missileData.base) or 1
    local value = number_or_zero(missileData.value)

    return math.max(
        1,
        math.floor(
            baseCost
            + math.max(0, number_or_zero(level)) * value
        )
    )
end

function scaling.get_missile_cost(weapon, sourceName, level)
    if not weapon or not weapon.blueprint then return nil end

    local missileData = scaling.get_source_stat_entry(
        sourceName,
        weapon.blueprint.name,
        "missileCost"
    )

    return scaling.calculate_missile_cost(missileData, level)
end

function scaling.can_pay_missile_cost(ship, weapon, sourceName, level)
    local missileCost = scaling.get_missile_cost(
        weapon,
        sourceName,
        level
    )

    if missileCost == nil then
        return true, nil
    end

    return ship ~= nil
        and ship:GetMissileCount() >= missileCost,
        missileCost
end

function scaling.pay_missile_cost_once(
    ship,
    weapon,
    sourceName,
    level,
    volleyState,
    paidKey
)
    if not ship or not weapon or type(volleyState) ~= "table" then
        return nil, false
    end

    paidKey = paidKey or "missilePaid"

    if volleyState[paidKey] then
        return 0, false
    end

    local missileCost = scaling.get_missile_cost(
        weapon,
        sourceName,
        level
    )

    if missileCost == nil then
        return nil, false
    end

    ship:ModifyMissileCount(-missileCost)
    volleyState[paidKey] = true

    return missileCost, true
end

local function calculate_source_radius(
    weaponName,
    baseRadius,
    getLevel
)
    local radius = baseRadius

    for _, sourceName in ipairs(SOURCE_ORDER) do
        local level = getLevel(sourceName)
        local value = get_source_radius_value(
            sourceName,
            weaponName
        )

        if level ~= nil and value ~= nil then
            radius =
                radius
                + math.max(0, number_or_zero(level))
                * number_or_zero(value)
        end
    end

    return clamp_radius(radius)
end

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

            if left.priority == right.priority then
                return left.serial < right.serial
            end

            return left.priority < right.priority
        end
    )
end

function scaling.register_weapon_radius_modifier(
    name,
    func,
    priority
)
    if type(name) ~= "string"
        or type(func) ~= "function" then

        return false
    end

    local entry = weaponRadiusModifiers[name]

    if not entry then
        modifierRegistrationSerial =
            modifierRegistrationSerial + 1

        entry = {
            serial = modifierRegistrationSerial
        }

        weaponRadiusModifiers[name] = entry
        table.insert(weaponRadiusModifierOrder, name)
    end

    entry.func = func
    entry.priority = tonumber(priority) or 100

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
            break
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
        local modifiedRadius =
            weaponRadiusModifiers[name].func(
                ship,
                weapon,
                radius,
                baseRadius
            )

        if type(modifiedRadius) == "number" then
            radius = clamp_radius(modifiedRadius)
        end
    end

    return radius
end

local function get_live_level(weapon, sourceName)
    if sourceName == "chain" then
        return math.max(0, number_or_zero(weapon.boostLevel))
    elseif sourceName == "charge" then
        return math.max(
            0,
            number_or_zero(weapon.chargeLevel) - 1
        )
    elseif sourceName == "chainstep" then
        local weaponData =
            userdata_table(weapon, "mods.sc.chainstep")

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
    if not weapon or not weapon.blueprint then return nil end

    local weaponName = weapon.blueprint.name
    local baseRadius = scaling.get_base_radius(weapon)

    local scalingRadius = calculate_source_radius(
        weaponName,
        baseRadius,
        function(sourceName)
            if not get_source_definition(sourceName, weaponName) then
                return nil
            end

            return get_live_level(weapon, sourceName)
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
    local calculation =
        scaling.get_weapon_preview_calculation(ship, weapon)

    return calculation and calculation.previewRadius or nil
end

function scaling.get_projectile_starting_radius_calculation(
    projectile,
    weapon
)
    if not projectile or not weapon or not weapon.blueprint then return nil end

    local storage = get_projectile_storage(projectile)
    local weaponName =
        (storage and storage.weaponName)
        or weapon.blueprint.name

    local baseRadius = scaling.get_base_radius(weapon)

    local scalingRadius = calculate_source_radius(
        weaponName,
        baseRadius,
        function(sourceName)
            return storage
                and get_stored_level(storage, sourceName)
                or nil
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