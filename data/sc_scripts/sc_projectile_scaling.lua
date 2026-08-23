--[[
DESCRIPTION: Shared projectile stat scaling for Chain, Charge, and Chainstep weapons.
        - Provides shared access to each weapon's tagged stat entries.
        - Applies ordinary projectile stat values.
DEPENDENCIES: sc_tag.lua, Multiverse userdata_table
]]

local userdata_table = mods.multiverse.userdata_table

mods.sc.scaling = mods.sc.scaling or {}
local scaling = mods.sc.scaling

local SOURCE_LEVEL_FIELDS = {
    chain = "chainLevel",
    charge = "chargeLevel",
    chainstep = "chainstepLevel"
}

local SPECIAL_SCALING_STATS = {
    radius = true,
    shots = true,
    cooldown = true,
    fireThreshold = true,
    chainStep = true,
    missileBase = true,
    missileCost = true
}

function scaling.get_source_stat_entries(sourceName, weaponName)
    if sourceName == "chain" then
        return mods.sc.chainers[weaponName]
    elseif sourceName == "charge" then
        return mods.sc.chargers[weaponName]
    elseif sourceName == "chainstep" then
        return mods.sc.chainstep[weaponName]
    end
end

function scaling.get_source_stat_entry(sourceName, weaponName, statName)
    local entries = scaling.get_source_stat_entries(sourceName, weaponName)
    if not entries then return nil end

    for _, entry in ipairs(entries) do
        if entry.stat == statName then
            return entry
        end
    end
end

function scaling.get_level(projectile, sourceName)
    local field = SOURCE_LEVEL_FIELDS[sourceName]
    if not field then return nil end

    local storage = userdata_table(projectile, "mods.sc.projectileScaling")
    return storage[field]
end

function scaling.apply_projectile_stats(projectile, weapon, sourceName, level, specialHandlers)
    local statBoosts = scaling.get_source_stat_entries(sourceName, weapon.blueprint.name)

    for _, statBoost in ipairs(statBoosts) do
        local stat = statBoost.stat
        local value = statBoost.value
        local specialHandler = type(specialHandlers) == "table" and specialHandlers[stat]

        if specialHandler then
            specialHandler(projectile, weapon, statBoost, level, sourceName)
        elseif SPECIAL_SCALING_STATS[stat] then
            -- Handled by the owning weapon/radius system.
        elseif stat == "accuracyMod" then
            projectile.extend.customDamage.accuracyMod = projectile.extend.customDamage.accuracyMod + level * value
        else
            projectile.damage[stat] = projectile.damage[stat] + level * value
        end
    end
end