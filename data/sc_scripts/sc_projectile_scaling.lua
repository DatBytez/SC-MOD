-- Test No. 2

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
Other radius modifiers, such as pilot or augment effects, are not included
in expectedRadius; liveCoreRadius is reported separately for comparison.
]]

local userdata_table = mods.multiverse.userdata_table

mods.sc = mods.sc or {}
mods.sc.scaling = mods.sc.scaling or {}

local scaling = mods.sc.scaling

local STORAGE_KEY = "mods.sc.projectileScaling"
local READER_VERSION = 2
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
