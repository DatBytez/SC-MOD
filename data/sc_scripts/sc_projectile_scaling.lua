-- Test No. 4

--[[
Passive shared reader and radius calculator for projectile scaling metadata.

This file does not register gameplay event handlers and does not change
projectiles, weapons, damage, radius, targeting, cooldowns, shots, or
missile costs.

It reads metadata previously stored by:
    sc_weapon_chain.lua
    sc_weapon_charge.lua
    sc_weapon_chainstep.lua

The radius calculator uses the stored projectile level together with the
already-parsed sc-chain, sc-charge, and sc-chainstep radius entries. It
calculates the radius that those three scaling systems alone would produce.
Projectile calculations remain unchanged. This test also provides one shared weapon-radius modifier pipeline. The same
pipeline is used for live targeting previews and for the frozen radius of a
fired projectile. Chain, charge, and chainstep are calculated first, followed
by registered weapon-radius modifiers such as pilot and detector. The shared
reader itself does not assign weapon.radius or alter projectile targets.
]]

local userdata_table = mods.multiverse.userdata_table

mods.sc = mods.sc or {}
mods.sc.scaling = mods.sc.scaling or {}

local scaling = mods.sc.scaling

local STORAGE_KEY = "mods.sc.projectileScaling"
local READER_VERSION = 4
local SOURCE_ORDER = {
    "chain",
    "charge",
    "chainstep"
}

scaling.READER_VERSION = READER_VERSION
scaling.STORAGE_KEY = STORAGE_KEY

local function copy_table(source)
    if not source then
        return nil
    end

    local result = {}

    for key, value in pairs(source) do
        if type(value) == "table" then
            result[key] = copy_table(value)
        else
            result[key] = value
        end
    end

    return result
end

local function read_storage(projectile)
    if not projectile then
        return nil
    end

    return userdata_table(projectile, STORAGE_KEY)
end

local function number_or_zero(value)
    local number = tonumber(value)

    if number == nil then
        return 0
    end

    return number
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

local function get_stored_base_radius(weapon)
    if not weapon then
        return 0
    end

    local weaponData = userdata_table(
        weapon,
        "mods.sc.weaponStuff"
    )

    if type(weaponData.baseRadius) == "number" then
        return weaponData.baseRadius
    end

    if weapon.blueprint
        and type(weapon.blueprint.radius) == "number" then
        return weapon.blueprint.radius
    end

    if type(weapon.radius) == "number" then
        return weapon.radius
    end

    return 0
end

local function find_radius_entry(entries)
    if not entries then
        return nil
    end

    for _, entry in ipairs(entries) do
        if entry.stat == "radius" then
            return entry.amount or 0
        end
    end

    return nil
end

local function get_radius_amount(sourceName, weaponName)
    if not weaponName then
        return nil
    end

    if sourceName == "chain" then
        local entries = mods.sc.chainers
            and mods.sc.chainers[weaponName]

        return find_radius_entry(entries)
    end

    if sourceName == "charge" then
        local entries = mods.sc.chargers
            and mods.sc.chargers[weaponName]

        return find_radius_entry(entries)
    end

    if sourceName == "chainstep" then
        local definition = mods.sc.chainstep
            and mods.sc.chainstep[weaponName]

        return find_radius_entry(
            definition and definition.statBoosts
        )
    end

    return nil
end

local function get_live_core_radius(projectile, weapon)
    if not projectile
        or not weapon
        or not mods.sc.radius
        or not mods.sc.radius.get_final_radius then
        return nil
    end

    local ship = Hyperspace.ships(projectile.ownerId)

    if not ship then
        return nil
    end

    local success, radius = pcall(
        mods.sc.radius.get_final_radius,
        ship,
        weapon
    )

    if not success or type(radius) ~= "number" then
        return nil
    end

    return radius
end

-- Returns a normalized copy of the scaling metadata on a projectile.
-- The returned table is detached from userdata, so changing it cannot
-- change the metadata stored on the projectile.
function scaling.get_projectile_data(projectile)
    local stored = read_storage(projectile)

    if not stored then
        return nil
    end

    local data = {
        readerVersion = READER_VERSION,
        scalingVersion = stored.scalingVersion,
        weaponName = stored.weaponName,
        chain = nil,
        charge = nil,
        chainstep = nil
    }

    if stored.hasChain == true then
        data.chain = {
            level = stored.chainLevel,
            rawLevel = stored.chainRawLevel
        }
    end

    if stored.hasCharge == true then
        data.charge = {
            level = stored.chargeLevel,
            storedShots = stored.chargeStoredShots,
            weaponLevel = stored.chargeWeaponLevel
        }
    end

    if stored.hasChainstep == true then
        data.chainstep = {
            level = stored.chainstepLevel,
            liveLevel = stored.chainstepLiveLevel,
            firingLevel = stored.chainstepFiringLevel
        }
    end

    return data
end

-- Returns the applied zero-based scaling level for one source.
-- sourceName must be "chain", "charge", or "chainstep".
function scaling.get_level(projectile, sourceName)
    local data = scaling.get_projectile_data(projectile)
    local source = data and data[sourceName]

    if not source then
        return nil
    end

    return source.level
end

-- Returns true when the named source was stored on the projectile.
function scaling.has_source(projectile, sourceName)
    local data = scaling.get_projectile_data(projectile)

    return data ~= nil and data[sourceName] ~= nil
end

-- Returns active source names in a stable order.
function scaling.get_active_sources(projectile)
    local data = scaling.get_projectile_data(projectile)
    local sources = {}

    if not data then
        return sources
    end

    for _, sourceName in ipairs(SOURCE_ORDER) do
        if data[sourceName] then
            table.insert(sources, sourceName)
        end
    end

    return sources
end

-- Returns a detached copy of one normalized source table.
function scaling.get_source_data(projectile, sourceName)
    local data = scaling.get_projectile_data(projectile)

    return data and copy_table(data[sourceName]) or nil
end

-- Calculates the radius produced by sc-chain, sc-charge, and
-- sc-chainstep using the exact levels stored on this projectile.
--
-- This is diagnostic only. No value is applied to the weapon or projectile.
function scaling.get_radius_calculation(projectile, weapon)
    if not projectile or not weapon then
        return nil
    end

    local projectileData = scaling.get_projectile_data(projectile)
    local weaponName = get_weapon_name(projectileData, weapon)
    local baseRadius = get_stored_base_radius(weapon)
    local totalContribution = 0
    local activeSourceCount = 0
    local activeRadiusSourceCount = 0
    local contributions = {}

    for _, sourceName in ipairs(SOURCE_ORDER) do
        local sourceData = projectileData
            and projectileData[sourceName]
            or nil

        local active = sourceData ~= nil
        local level = active
            and math.max(0, number_or_zero(sourceData.level))
            or nil

        local amount = get_radius_amount(
            sourceName,
            weaponName
        )

        local hasRadiusTag = amount ~= nil
        local delta = 0

        if active then
            activeSourceCount = activeSourceCount + 1
        end

        if active and hasRadiusTag then
            delta = level * amount
            totalContribution = totalContribution + delta
            activeRadiusSourceCount = activeRadiusSourceCount + 1
        end

        contributions[sourceName] = {
            active = active,
            level = level,
            amount = amount,
            delta = delta,
            hasRadiusTag = hasRadiusTag
        }
    end

    local unclampedRadius = baseRadius + totalContribution
    local expectedRadius = math.max(0, unclampedRadius)
    local liveCoreRadius = get_live_core_radius(
        projectile,
        weapon
    )

    return {
        calculatorVersion = READER_VERSION,
        scalingVersion = projectileData
            and projectileData.scalingVersion
            or nil,
        weaponName = weaponName,
        baseRadius = baseRadius,
        totalContribution = totalContribution,
        unclampedRadius = unclampedRadius,
        expectedRadius = expectedRadius,
        clampAdjustment = expectedRadius - unclampedRadius,
        weaponRadius = type(weapon.radius) == "number"
            and weapon.radius
            or nil,
        liveCoreRadius = liveCoreRadius,
        liveCoreDifference = liveCoreRadius ~= nil
            and liveCoreRadius - expectedRadius
            or nil,
        activeSourceCount = activeSourceCount,
        activeRadiusSourceCount = activeRadiusSourceCount,
        hasStoredScaling = activeSourceCount > 0,
        hasScalingRadius = activeRadiusSourceCount > 0,
        contributions = contributions
    }
end

-- Convenience function. Returns expectedRadius first and the full
-- detached calculation table second.
function scaling.get_expected_radius(projectile, weapon)
    local calculation = scaling.get_radius_calculation(
        projectile,
        weapon
    )

    if not calculation then
        return nil, nil
    end

    return calculation.expectedRadius, calculation
end

-- Returns one source's detached radius-contribution record.
function scaling.get_radius_contribution(
    projectile,
    weapon,
    sourceName
)
    local calculation = scaling.get_radius_calculation(
        projectile,
        weapon
    )

    if not calculation then
        return nil
    end

    return copy_table(
        calculation.contributions[sourceName]
    )
end

-- --------------------------------------------------------------------------
-- PASSIVE LIVE WEAPON PREVIEW RADIUS
-- --------------------------------------------------------------------------

scaling.previewModifiers = scaling.previewModifiers or {}
scaling.previewModifierOrder = scaling.previewModifierOrder or {}

local previewModifiers = scaling.previewModifiers
local previewModifierOrder = scaling.previewModifierOrder

-- Registers a read-only live preview modifier. The callback signature matches
-- the legacy radius-core weapon modifier signature:
--
--     function(ship, weapon, radius, baseRadius) -> newRadius
--
-- Registering a name again replaces its callback without changing its order.
function scaling.register_preview_modifier(name, func)
    if type(name) ~= "string" or type(func) ~= "function" then
        return false
    end

    if previewModifiers[name] == nil then
        table.insert(previewModifierOrder, name)
    end

    previewModifiers[name] = func
    return true
end

function scaling.unregister_preview_modifier(name)
    if previewModifiers[name] == nil then
        return false
    end

    previewModifiers[name] = nil

    for index = #previewModifierOrder, 1, -1 do
        if previewModifierOrder[index] == name then
            table.remove(previewModifierOrder, index)
        end
    end

    return true
end

function scaling.has_preview_modifier(name)
    return previewModifiers[name] ~= nil
end

function scaling.get_preview_modifier_names()
    local names = {}

    for _, name in ipairs(previewModifierOrder) do
        if previewModifiers[name] ~= nil then
            table.insert(names, name)
        end
    end

    return names
end

-- Generic names for the same registry. The older preview names remain valid
-- so existing Test No. files continue to work.
scaling.register_weapon_radius_modifier =
    scaling.register_preview_modifier

scaling.unregister_weapon_radius_modifier =
    scaling.unregister_preview_modifier

scaling.has_weapon_radius_modifier =
    scaling.has_preview_modifier

scaling.get_weapon_radius_modifier_names =
    scaling.get_preview_modifier_names

local function apply_registered_weapon_modifiers(
    ship,
    weapon,
    startingRadius,
    baseRadius
)
    local radius = math.max(0, number_or_zero(startingRadius))
    local results = {}
    local errors = {}

    for _, name in ipairs(previewModifierOrder) do
        local func = previewModifiers[name]

        if func then
            local beforeRadius = radius
            local success, modifiedRadius = pcall(
                func,
                ship,
                weapon,
                radius,
                baseRadius
            )

            if success then
                if modifiedRadius ~= nil then
                    if type(modifiedRadius) == "number" then
                        radius = modifiedRadius
                    else
                        table.insert(
                            errors,
                            name .. ": non-number result"
                        )
                    end
                end
            else
                table.insert(
                    errors,
                    name .. ": " .. tostring(modifiedRadius)
                )
            end

            radius = math.max(0, radius)

            results[name] = {
                beforeRadius = beforeRadius,
                afterRadius = radius,
                delta = radius - beforeRadius,
                success = success
            }
        end
    end

    return radius, results, errors
end

scaling.apply_registered_weapon_radius_modifiers =
    apply_registered_weapon_modifiers

local function get_preview_source_definition(sourceName, weaponName)
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

local function get_weapon_preview_level(weapon, sourceName)
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

function scaling.get_weapon_preview_level(weapon, sourceName)
    if not weapon
        or not weapon.blueprint
        or not get_preview_source_definition(
            sourceName,
            weapon.blueprint.name
        ) then

        return nil
    end

    return get_weapon_preview_level(
        weapon,
        sourceName
    )
end

local function get_legacy_weapon_preview_radius(ship, weapon)
    if not ship
        or not weapon
        or not mods.sc.radius
        or not mods.sc.radius.get_final_radius then

        return nil
    end

    local success, radius = pcall(
        mods.sc.radius.get_final_radius,
        ship,
        weapon
    )

    if not success or type(radius) ~= "number" then
        return nil
    end

    return radius
end

-- Calculates the live targeting-preview radius without assigning weapon.radius.
-- C/Q/S are evaluated from the live weapon state. Shared preview modifiers are
-- then applied in stable registration order. The legacy core result and the
-- currently displayed weapon.radius are included only for comparison.
function scaling.get_weapon_preview_calculation(ship, weapon)
    if not weapon or not weapon.blueprint then
        return nil
    end

    local weaponName = weapon.blueprint.name
    local baseRadius = get_stored_base_radius(weapon)
    local totalContribution = 0
    local contributions = {}

    for _, sourceName in ipairs(SOURCE_ORDER) do
        local definition = get_preview_source_definition(
            sourceName,
            weaponName
        )

        local active = definition ~= nil
        local level = active
            and get_weapon_preview_level(
                weapon,
                sourceName
            )
            or nil

        local amount = active
            and get_radius_amount(
                sourceName,
                weaponName
            )
            or nil

        local hasRadiusTag = amount ~= nil
        local delta = active and hasRadiusTag
            and level * amount
            or 0

        totalContribution =
            totalContribution + delta

        contributions[sourceName] = {
            active = active,
            level = level,
            amount = amount,
            delta = delta,
            hasRadiusTag = hasRadiusTag
        }
    end

    local scalingUnclampedRadius =
        baseRadius + totalContribution

    local scalingRadius = math.max(
        0,
        scalingUnclampedRadius
    )

    local previewRadius, modifierResults, modifierErrors =
        apply_registered_weapon_modifiers(
            ship,
            weapon,
            scalingRadius,
            baseRadius
        )

    local legacyCoreRadius =
        get_legacy_weapon_preview_radius(
            ship,
            weapon
        )

    local weaponRadius =
        type(weapon.radius) == "number"
        and weapon.radius
        or nil

    return {
        previewVersion = READER_VERSION,
        weaponName = weaponName,
        baseRadius = baseRadius,
        totalScalingContribution = totalContribution,
        scalingUnclampedRadius = scalingUnclampedRadius,
        scalingRadius = scalingRadius,
        previewRadius = previewRadius,
        contributions = contributions,
        previewModifiers = modifierResults,
        previewModifierOrder = scaling.get_preview_modifier_names(),
        modifierErrors = modifierErrors,
        legacyCoreRadius = legacyCoreRadius,
        weaponRadius = weaponRadius,
        legacyDifference = legacyCoreRadius ~= nil
            and legacyCoreRadius - previewRadius
            or nil,
        displayDifference = weaponRadius ~= nil
            and weaponRadius - previewRadius
            or nil
    }
end

-- Calculates the frozen starting radius for one fired projectile.
-- The C/Q/S portion uses metadata already stored on that projectile, while
-- pilot, detector, and other registered weapon modifiers use the firing ship's
-- current state. Projectile-only modifiers such as HALO fake spread are not
-- included here; the radius core applies those afterward.
function scaling.get_projectile_starting_radius_calculation(
    projectile,
    weapon
)
    if not projectile or not weapon then
        return nil
    end

    local baseCalculation =
        scaling.get_radius_calculation(
            projectile,
            weapon
        )

    if not baseCalculation then
        return nil
    end

    local ship = Hyperspace.ships(projectile.ownerId)
    local startingRadius, modifierResults, modifierErrors =
        apply_registered_weapon_modifiers(
            ship,
            weapon,
            baseCalculation.expectedRadius,
            baseCalculation.baseRadius
        )

    return {
        calculatorVersion = READER_VERSION,
        weaponName = baseCalculation.weaponName,
        baseRadius = baseCalculation.baseRadius,
        scalingRadius = baseCalculation.expectedRadius,
        scalingUnclampedRadius =
            baseCalculation.unclampedRadius,
        totalScalingContribution =
            baseCalculation.totalContribution,
        contributions =
            copy_table(baseCalculation.contributions),
        hasStoredScaling =
            baseCalculation.hasStoredScaling,
        hasScalingRadius =
            baseCalculation.hasScalingRadius,
        activeSourceCount =
            baseCalculation.activeSourceCount,
        activeRadiusSourceCount =
            baseCalculation.activeRadiusSourceCount,
        startingRadius = startingRadius,
        weaponModifiedRadius = startingRadius,
        weaponModifiers = modifierResults,
        previewModifiers = modifierResults,
        weaponModifierOrder =
            scaling.get_preview_modifier_names(),
        modifierErrors = modifierErrors,
        legacyCoreRadius =
            baseCalculation.liveCoreRadius
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

    if not calculation then
        return nil, nil
    end

    return calculation.startingRadius, calculation
end

function scaling.get_weapon_preview_radius(ship, weapon)
    local calculation =
        scaling.get_weapon_preview_calculation(
            ship,
            weapon
        )

    if not calculation then
        return nil, nil
    end

    return calculation.previewRadius,
        calculation
end

function scaling.get_preview_modifier_contribution(
    ship,
    weapon,
    modifierName
)
    local calculation =
        scaling.get_weapon_preview_calculation(
            ship,
            weapon
        )

    if not calculation then
        return nil
    end

    return copy_table(
        calculation.previewModifiers[
            modifierName
        ]
    )
end

