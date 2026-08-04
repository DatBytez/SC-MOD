-- Test No. 7

--[[
Shared projectile-scaling, projectile-stat, missile-cost, and weapon-radius
calculations.

Load this file after sc_tag.lua and before sc_radius_core.lua.

The chain, charge, and chainstep weapon scripts store the exact zero-based
level used by each fired projectile in:

    userdata_table(projectile, "mods.sc.projectileScaling")

This file:
    1. Reads frozen projectile levels.
    2. Applies ordinary projectile scaling attributes in one place.
    3. Calculates and pays Lua-controlled missile costs.
    4. Calculates live preview and frozen fired-projectile radius.
    5. Applies registered weapon-radius modifiers in priority order.

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

    return userdata_table(
        projectile,
        STORAGE_KEY
    )
end

local function get_weapon_name(
    projectileData,
    weapon
)
    if projectileData
        and projectileData.weaponName then

        return projectileData.weaponName
    end

    return weapon
        and weapon.blueprint
        and weapon.blueprint.name
        or nil
end

local function get_source_definition(
    sourceName,
    weaponName
)
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

local function get_source_stat_entries(
    sourceName,
    weaponName
)
    local definition = get_source_definition(
        sourceName,
        weaponName
    )

    if not definition then
        return nil
    end

    if sourceName == "chainstep" then
        return definition.statBoosts
    end

    return definition
end

function scaling.get_source_stat_entries(
    sourceName,
    weaponName
)
    return get_source_stat_entries(
        sourceName,
        weaponName
    )
end

function scaling.get_source_stat_entry(
    sourceName,
    weaponName,
    statName
)
    local entries = get_source_stat_entries(
        sourceName,
        weaponName
    )

    if type(entries) ~= "table" then
        return nil
    end

    for _, entry in ipairs(entries) do
        if entry.stat == statName then
            return entry
        end
    end

    return nil
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

local function get_radius_amount(
    sourceName,
    weaponName
)
    return find_radius_entry(
        get_source_stat_entries(
            sourceName,
            weaponName
        )
    )
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
                number_or_zero(
                    stored.chainLevel
                )
            )
        }
    end

    if stored.hasCharge == true then
        data.charge = {
            level = math.max(
                0,
                number_or_zero(
                    stored.chargeLevel
                )
            )
        }
    end

    if stored.hasChainstep == true then
        data.chainstep = {
            level = math.max(
                0,
                number_or_zero(
                    stored.chainstepLevel
                )
            )
        }
    end

    return data
end

function scaling.get_level(
    projectile,
    sourceName
)
    local data =
        get_projectile_data(projectile)

    local source =
        data and data[sourceName]

    return source and source.level or nil
end

-- --------------------------------------------------------------------------
-- SHARED PROJECTILE STAT SCALING
-- --------------------------------------------------------------------------

function scaling.apply_projectile_stats(
    projectile,
    weapon,
    sourceName,
    level,
    specialHandlers
)
    if not projectile
        or not weapon
        or not weapon.blueprint then

        return
    end

    local statBoosts =
        get_source_stat_entries(
            sourceName,
            weapon.blueprint.name
        )

    if type(statBoosts) ~= "table" then
        return
    end

    level = math.max(
        0,
        number_or_zero(level)
    )

    for _, statBoost in ipairs(statBoosts) do
        local stat = statBoost.stat
        local amount = statBoost.amount

        if amount == nil then
            amount = 1
        end

        amount = number_or_zero(amount)

        local specialHandler =
            type(specialHandlers) == "table"
            and specialHandlers[stat]
            or nil

        if type(specialHandler) == "function" then
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
            if projectile.extend
                and projectile.extend.customDamage then

                local customDamage =
                    projectile.extend.customDamage

                customDamage.accuracyMod =
                    number_or_zero(
                        customDamage.accuracyMod
                    )
                    + level * amount
            end

        elseif type(stat) == "string"
            and projectile.damage then

            projectile.damage[stat] =
                number_or_zero(
                    projectile.damage[stat]
                )
                + level * amount
        end
    end
end

-- --------------------------------------------------------------------------
-- SHARED MISSILE COST
-- --------------------------------------------------------------------------

function scaling.calculate_missile_cost(
    missileData,
    level
)
    if not missileData then
        return nil
    end

    local baseCost =
        missileData.base or 1

    local amount =
        missileData.amount or 0

    return math.max(
        1,
        math.floor(
            baseCost
                + math.max(
                    0,
                    number_or_zero(level)
                )
                * amount
        )
    )
end

function scaling.get_missile_cost(
    weapon,
    sourceName,
    level
)
    if not weapon or not weapon.blueprint then
        return nil
    end

    local missileData =
        scaling.get_source_stat_entry(
            sourceName,
            weapon.blueprint.name,
            "missileCost"
        )

    return scaling.calculate_missile_cost(
        missileData,
        level
    )
end

function scaling.can_pay_missile_cost(
    ship,
    weapon,
    sourceName,
    level
)
    local missileCost =
        scaling.get_missile_cost(
            weapon,
            sourceName,
            level
        )

    if missileCost == nil then
        return true, nil
    end

    return ship ~= nil
        and ship:GetMissileCount()
            >= missileCost,
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
    if not ship
        or not weapon
        or type(volleyState) ~= "table" then

        return nil, false
    end

    paidKey = paidKey or "missilePaid"

    if volleyState[paidKey] then
        return 0, false
    end

    local missileCost =
        scaling.get_missile_cost(
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

-- --------------------------------------------------------------------------
-- SOURCE RADIUS
-- --------------------------------------------------------------------------

local function calculate_source_radius(
    weaponName,
    baseRadius,
    getLevel
)
    local radius = baseRadius

    for _, sourceName in ipairs(
        SOURCE_ORDER
    ) do
        local definition =
            get_source_definition(
                sourceName,
                weaponName
            )

        local active, level =
            getLevel(
                sourceName,
                definition
            )

        local amount =
            get_radius_amount(
                sourceName,
                weaponName
            )

        if active and amount ~= nil then
            radius =
                radius
                + math.max(
                    0,
                    number_or_zero(level)
                )
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

local weaponRadiusModifiers =
    scaling.weaponRadiusModifiers

local weaponRadiusModifierOrder =
    scaling.weaponRadiusModifierOrder

local modifierRegistrationSerial = 0

local function sort_modifier_order()
    table.sort(
        weaponRadiusModifierOrder,
        function(leftName, rightName)
            local left =
                weaponRadiusModifiers[leftName]

            local right =
                weaponRadiusModifiers[rightName]

            if not left then return false end
            if not right then return true end

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

    local existing =
        weaponRadiusModifiers[name]

    if not existing then
        modifierRegistrationSerial =
            modifierRegistrationSerial + 1

        existing = {
            serial =
                modifierRegistrationSerial
        }

        weaponRadiusModifiers[name] =
            existing

        table.insert(
            weaponRadiusModifierOrder,
            name
        )
    end

    existing.func = func
    existing.priority =
        tonumber(priority) or 100

    sort_modifier_order()
    return true
end

function scaling.unregister_weapon_radius_modifier(
    name
)
    if not weaponRadiusModifiers[name] then
        return false
    end

    weaponRadiusModifiers[name] = nil

    for index =
        #weaponRadiusModifierOrder,
        1,
        -1 do

        if weaponRadiusModifierOrder[index]
            == name then

            table.remove(
                weaponRadiusModifierOrder,
                index
            )
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
    local radius =
        clamp_radius(startingRadius)

    for _, name in ipairs(
        weaponRadiusModifierOrder
    ) do
        local entry =
            weaponRadiusModifiers[name]

        if entry and entry.func then
            local success, modifiedRadius =
                pcall(
                    entry.func,
                    ship,
                    weapon,
                    radius,
                    baseRadius
                )

            if success
                and type(modifiedRadius)
                    == "number" then

                radius =
                    clamp_radius(
                        modifiedRadius
                    )
            end
        end
    end

    return radius
end

-- --------------------------------------------------------------------------
-- LIVE PREVIEW LEVELS
-- --------------------------------------------------------------------------

local function get_live_level(
    weapon,
    sourceName
)
    if not weapon then
        return 0
    end

    if sourceName == "chain" then
        return math.max(
            0,
            number_or_zero(
                weapon.boostLevel
            )
        )
    end

    if sourceName == "charge" then
        return math.max(
            0,
            number_or_zero(
                weapon.chargeLevel
            ) - 1
        )
    end

    if sourceName == "chainstep" then
        local weaponData =
            userdata_table(
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

function scaling.get_weapon_preview_calculation(
    ship,
    weapon
)
    if not weapon or not weapon.blueprint then
        return nil
    end

    local weaponName =
        weapon.blueprint.name

    local baseRadius =
        scaling.get_base_radius(weapon)

    local scalingRadius =
        calculate_source_radius(
            weaponName,
            baseRadius,
            function(sourceName, definition)
                return definition ~= nil,
                    definition
                    and get_live_level(
                        weapon,
                        sourceName
                    )
                    or nil
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

function scaling.get_weapon_preview_radius(
    ship,
    weapon
)
    local calculation =
        scaling.get_weapon_preview_calculation(
            ship,
            weapon
        )

    if not calculation then
        return nil
    end

    return calculation.previewRadius
end

function scaling.get_projectile_starting_radius_calculation(
    projectile,
    weapon
)
    if not projectile or not weapon then
        return nil
    end

    local projectileData =
        get_projectile_data(projectile)

    local weaponName =
        get_weapon_name(
            projectileData,
            weapon
        )

    local baseRadius =
        scaling.get_base_radius(weapon)

    local scalingRadius =
        calculate_source_radius(
            weaponName,
            baseRadius,
            function(sourceName)
                local sourceData =
                    projectileData
                    and projectileData[sourceName]
                    or nil

                return sourceData ~= nil,
                    sourceData
                    and sourceData.level
                    or nil
            end
        )

    local ship =
        Hyperspace.ships(
            projectile.ownerId
        )

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

    return calculation
        and calculation.startingRadius
        or nil
end
