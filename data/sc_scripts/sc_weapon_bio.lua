--[[
DESCRIPTION: Restricts tagged weapon hull and system damage to organic ships.
        - Non-organic ships take no positive hull or system damage from the weapon.
        - Applies to area-hit projectiles and beams entering a new room.
        - Adds bio-weapon information to the weapon stat box.
TAG: <bio-weapon/>
DEPENDENCIES: Multiverse weaponTagParsers
]]

local bioWeapons = {}

table.insert(mods.multiverse.weaponTagParsers, function(weaponNode)
    if weaponNode:first_node("bio-weapon") then
        bioWeapons[weaponNode:first_attribute("name"):value()] = true
    end
end)

local function remove_non_organic_ship_damage(shipManager, projectile, damage)
    if not bioWeapons[projectile.extend.name] or shipManager:HasAugmentation("ORGANIC") > 0 then
        return
    end

    if damage.iDamage > 0 then
        damage.iDamage = 0
    end

    if damage.iSystemDamage > 0 then
        damage.iSystemDamage = 0
    end
end

script.on_internal_event(Defines.InternalEvents.DAMAGE_AREA, function(shipManager, projectile, _location, damage)
        remove_non_organic_ship_damage(shipManager, projectile, damage)
    end
)

script.on_internal_event(Defines.InternalEvents.DAMAGE_BEAM, function(shipManager, projectile, _location, damage, _realNewTile, beamHitType)
        if beamHitType == Defines.BeamHit.NEW_ROOM then
            remove_non_organic_ship_damage(shipManager, projectile, damage)
        end
    end
)

script.on_internal_event(Defines.InternalEvents.WEAPON_STATBOX, function(bp, stats)
        if bioWeapons[bp.name] then
            return Defines.Chain.CONTINUE,
                stats .. "\n\n" .. Hyperspace.Text:GetText("stat_bio_weapon")
        end
    end
)