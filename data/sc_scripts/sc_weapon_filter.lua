--[[
DESCRIPTION: Restricts tagged weapon hull and system damage by target ship type.
        - Bio weapons can damage organic ships.
        - Rust weapons can damage automated ships.
        - Adds matching filter information to the weapon stat box.
TAGS: <bio-weapon/>, <rust-weapon/>
DEPENDENCIES: sc_tag.lua
]]

local bioWeapons = {}
local rustWeapons = {}

mods.sc.tag.register("weapon", "bio-weapon", bioWeapons)
mods.sc.tag.register("weapon", "rust-weapon", rustWeapons)

local function target_matches_weapon_filter(shipManager, weaponName)
    return (bioWeapons[weaponName] and shipManager:HasAugmentation("ORGANIC") > 0)
        or (rustWeapons[weaponName] and shipManager.bAutomated)
end

local function remove_filtered_ship_damage(shipManager, projectile, damage)
    if not projectile then return end
    
    local weaponName = projectile.extend.name

    if not bioWeapons[weaponName] and not rustWeapons[weaponName] then return end
    if target_matches_weapon_filter(shipManager, weaponName) then return end

    if damage.iDamage > 0 then
        damage.iDamage = 0
    end

    if damage.iSystemDamage > 0 then
        damage.iSystemDamage = 0
    end
end

script.on_internal_event(Defines.InternalEvents.DAMAGE_AREA, function(shipManager, projectile, _location, damage)
        remove_filtered_ship_damage(shipManager, projectile, damage)
    end
)

script.on_internal_event(Defines.InternalEvents.DAMAGE_BEAM, function(shipManager, projectile, _location, damage, _realNewTile, beamHitType)
        if beamHitType == Defines.BeamHit.NEW_ROOM then
            remove_filtered_ship_damage(shipManager, projectile, damage)
        end
    end
)

script.on_internal_event(Defines.InternalEvents.WEAPON_STATBOX, function(bp, stats)
        local hasBio = bioWeapons[bp.name]
        local hasRust = rustWeapons[bp.name]

        if not hasBio and not hasRust then return end

        local text = stats

        if hasBio then
            text = text .. "\n\n" .. Hyperspace.Text:GetText("stat_bio_weapon")
        end

        if hasRust then
            text = text .. "\n\n" .. Hyperspace.Text:GetText("stat_rust_weapon")
        end

        return Defines.Chain.CONTINUE, text
    end
)