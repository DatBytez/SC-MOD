--[[
////////////////////
IMPORTS AND UTIL
////////////////////
]]--

-- Make tag tables local
local weaponTagParsers = mods.multiverse.weaponTagParsers

--[[
////////////////////
DATA & PARSER
////////////////////
]]--

local targetFilteredWeapons = {}

local function get_weapon_filter_data(weaponName)
    if not targetFilteredWeapons[weaponName] then
        targetFilteredWeapons[weaponName] = {
            bio = false,
            rust = false
        }
    end

    return targetFilteredWeapons[weaponName]
end

table.insert(weaponTagParsers, function(weaponNode)
    local nameAttr = weaponNode:first_attribute("name")
    if not nameAttr then return end

    local weaponName = nameAttr:value()
    local filterData = nil

    if weaponNode:first_node("bio-weapon") then
        filterData = get_weapon_filter_data(weaponName)
        filterData.bio = true
    end

    if weaponNode:first_node("rust-weapon") then
        filterData = get_weapon_filter_data(weaponName)
        filterData.rust = true
    end
end)

--[[
////////////////////
LOGIC
////////////////////
]]--

local function get_projectile_filter_data(projectile)
    if not projectile or not projectile.extend then return nil end
    return targetFilteredWeapons[projectile.extend.name]
end

local function target_is_organic(shipManager)
    return shipManager and shipManager:HasAugmentation("ORGANIC") > 0
end

local function target_is_automated(shipManager)
    return shipManager and shipManager.bAutomated == true
end

local function target_matches_any_weapon_filter(shipManager, filterData)
    if not filterData then return true end

    if filterData.bio and target_is_organic(shipManager) then
        return true
    end

    if filterData.rust and target_is_automated(shipManager) then
        return true
    end

    return false
end

local function remove_filtered_ship_damage(shipManager, projectile, location, damage)
    local filterData = get_projectile_filter_data(projectile)
    if not filterData then return end
    if target_matches_any_weapon_filter(shipManager, filterData) then return end
    if not damage then return end

    if damage.iDamage and damage.iDamage > 0 then
        damage.iDamage = 0
    end

    if damage.iSystemDamage and damage.iSystemDamage > 0 then
        damage.iSystemDamage = 0
    end
end

script.on_internal_event(Defines.InternalEvents.DAMAGE_AREA, function(shipManager, projectile, location, damage, forceHit, shipFriendlyFire)
    remove_filtered_ship_damage(shipManager, projectile, location, damage)
end)

script.on_internal_event(Defines.InternalEvents.DAMAGE_BEAM, function(shipManager, projectile, location, damage, realNewTile, beamHitType)
    if beamHitType == Defines.BeamHit.NEW_ROOM then
        remove_filtered_ship_damage(shipManager, projectile, location, damage)
    end
end)

-- Add info to stats
script.on_internal_event(Defines.InternalEvents.WEAPON_STATBOX, function(bp, stats)
    local filterData = targetFilteredWeapons[bp.name]
    if not filterData then return end

    local text = stats

    if filterData.bio then
        text = text.."\n\n"..Hyperspace.Text:GetText("stat_bio_weapon")
    end

    if filterData.rust then
        text = text.."\n\n"..Hyperspace.Text:GetText("stat_rust_weapon")
    end

    return Defines.Chain.CONTINUE, text
end)
