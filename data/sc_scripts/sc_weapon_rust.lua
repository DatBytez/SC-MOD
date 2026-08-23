--[[
DESCRIPTION: Restricts tagged weapon hull and system damage to automated ships.
        - Non-automated ships take no positive hull or system damage from the weapon.
        - Applies to area-hit projectiles and beams entering a new room.
        - Adds rust-weapon information to the weapon stat box.
TAG: <rust-weapon/>
DEPENDENCIES: Multiverse weaponTagParsers
]]

local rustWeapons = {}

table.insert(mods.multiverse.weaponTagParsers, function(weaponNode)
    if weaponNode:first_node("rust-weapon") then
        rustWeapons[weaponNode:first_attribute("name"):value()] = true
    end
end)

local function remove_non_automated_ship_damage(shipManager, projectile, damage)
    if not rustWeapons[projectile.extend.name] or shipManager.bAutomated then
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
        remove_non_automated_ship_damage(shipManager, projectile, damage)
    end
)

script.on_internal_event(Defines.InternalEvents.DAMAGE_BEAM, function(shipManager, projectile, _location, damage, _realNewTile, beamHitType)
        if beamHitType == Defines.BeamHit.NEW_ROOM then
            remove_non_automated_ship_damage(shipManager, projectile, damage)
        end
    end
)

script.on_internal_event(Defines.InternalEvents.WEAPON_STATBOX, function(bp, stats)
        if rustWeapons[bp.name] then
            return Defines.Chain.CONTINUE,
                stats .. "\n\n" .. Hyperspace.Text:GetText("stat_rust_weapon")
        end
    end
)