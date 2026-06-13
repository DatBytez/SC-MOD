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

local rustWeapons = {}
table.insert(weaponTagParsers, function(weaponNode)
    local nameAttr = weaponNode:first_attribute("name")
    if not nameAttr then return end

    if weaponNode:first_node("rust-weapon") then
        rustWeapons[nameAttr:value()] = true
    end
end)

--[[
////////////////////
LOGIC
////////////////////
]]--

local function is_rust_weapon(projectile)
    return rustWeapons[projectile and projectile.extend and projectile.extend.name] == true
end

local function target_is_automated(shipManager)
    return shipManager and shipManager.bAutomated == true
end

local function remove_non_automated_ship_damage(shipManager, projectile, location, damage)
    if not is_rust_weapon(projectile) then return end
    if target_is_automated(shipManager) then return end
    if not damage then return end

    if damage.iDamage and damage.iDamage > 0 then
        damage.iDamage = 0
    end

    if damage.iSystemDamage and damage.iSystemDamage > 0 then
        damage.iSystemDamage = 0
    end

end

script.on_internal_event(Defines.InternalEvents.DAMAGE_AREA, function(shipManager, projectile, location, damage, forceHit, shipFriendlyFire)
    remove_non_automated_ship_damage(shipManager, projectile, location, damage)
end)

script.on_internal_event(Defines.InternalEvents.DAMAGE_BEAM, function(shipManager, projectile, location, damage, realNewTile, beamHitType)
    if beamHitType == Defines.BeamHit.NEW_ROOM then
        remove_non_automated_ship_damage(shipManager, projectile, location, damage)
    end
end)

-- Add info to stats
script.on_internal_event(Defines.InternalEvents.WEAPON_STATBOX, function(bp, stats)
    if rustWeapons[bp.name] then
        return Defines.Chain.CONTINUE, stats.."\n\n"..Hyperspace.Text:GetText("stat_rust_weapon")
    end
end)
