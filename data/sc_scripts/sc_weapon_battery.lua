--[[
DESCRIPTION: Battery weapons using copied projectiles.
    - Weapons use <sc_battery group="..."/> or <sc-battery group="..."/>.
    - A battery weapon only works with the weapon slot immediately to its RIGHT.
    - The right weapon must also have a battery tag, must be in the same group, and must be powered.
    - Battery weapon links are allowed to overlap.
        Example: slots 1, 2, and 3 in the same group allow slot 1 -> 2 and slot 2 -> 3.
    - Only normal shots create battery copies. Copied projectiles do not create additional copies.
    - The copied projectile receives a -50 accuracy penalty.
    - The right weapon still fires normally; it is not cleared, replaced, disabled, or depowered.
DEPENDENCIES: mv_core, sc_weapon_copy.lua
]]

mods.sc_battery_weapons = mods.sc_battery_weapons or {}

mods.multiverse.weaponTagParsers = mods.multiverse.weaponTagParsers or {}
local weaponTagParsers = mods.multiverse.weaponTagParsers

local batteryGroupById = {}
local warnedMissingCopyApi = false
local COPY_ACCURACY_PENALTY = 50

local function get_battery_node(weaponNode)
    local batteryNode = weaponNode:first_node("sc_battery")
    if batteryNode then return batteryNode end

    return weaponNode:first_node("sc-battery")
end

table.insert(weaponTagParsers, function(weaponNode)
    local batteryNode = get_battery_node(weaponNode)
    if not batteryNode then return end

    local nameAttr = weaponNode:first_attribute("name")
    if not nameAttr then return end

    local groupAttr = batteryNode:first_attribute("group")
    local groupId = groupAttr and groupAttr:value() or "default"

    batteryGroupById[nameAttr:value()] = groupId
end)

local function get_weapon_group(weapon)
    if not weapon or not weapon.blueprint then return nil end

    return batteryGroupById[weapon.blueprint.name]
end

local function get_weapon_slot(weapon)
    if not weapon then return nil end

    local ship = Hyperspace.ships(weapon.iShipId)
    if not ship or not ship.weaponSystem then return nil end

    local weapons = ship.weaponSystem.weapons

    for i = 0, weapons:size() - 1 do
        if weapons[i] == weapon then
            return i
        end
    end

    return nil
end

local function get_weapon_for_slot(shipId, weaponSlot)
    if shipId == nil or weaponSlot == nil then return nil end

    local ship = Hyperspace.ships(shipId)
    if not ship or not ship.weaponSystem then return nil end

    local weapons = ship.weaponSystem.weapons
    if weaponSlot < 0 or weaponSlot >= weapons:size() then return nil end

    return weapons[weaponSlot]
end

local function battery_matches_right_weapon(leftWeapon, rightWeapon)
    if not leftWeapon or not rightWeapon then return false end
    if not leftWeapon.blueprint or not rightWeapon.blueprint then return false end

    local leftGroup = get_weapon_group(leftWeapon)
    local rightGroup = get_weapon_group(rightWeapon)

    if not leftGroup or not rightGroup then return false end

    return leftGroup == rightGroup
end

local function weapon_is_powered(weapon)
    if not weapon then return false end
    if not weapon.weaponVisual then return false end

    return weapon.weaponVisual.bPowered == true
end

local function get_matching_right_weapon(weapon)
    if not weapon then return nil end

    local weaponSlot = get_weapon_slot(weapon)
    if weaponSlot == nil then return nil end

    local rightWeapon = get_weapon_for_slot(weapon.iShipId, weaponSlot + 1)
    if not battery_matches_right_weapon(weapon, rightWeapon) then return nil end
    if not weapon_is_powered(rightWeapon) then return nil end

    return rightWeapon
end

local function copy_api_available()
    return mods.sc_projectile_copy
        and mods.sc_projectile_copy.create_projectile_copy
end

local function warn_missing_copy_api_once()
    if warnedMissingCopyApi then return end

    warnedMissingCopyApi = true
    print("SC BATTERY ERROR | sc_weapon_copy.lua must load before sc_weapon_battery.lua and must expose mods.sc_projectile_copy.create_projectile_copy")
end

local function apply_copied_shot_accuracy_penalty(projectile)
    if not projectile then return end
    if not projectile.extend then return end
    if not projectile.extend.customDamage then return end

    local currentAccuracyMod = projectile.extend.customDamage.accuracyMod or 0
    projectile.extend.customDamage.accuracyMod = currentAccuracyMod - COPY_ACCURACY_PENALTY
end

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    if not projectile or not weapon or not weapon.blueprint then return end

    if mods.sc_projectile_copy and mods.sc_projectile_copy.is_copy and mods.sc_projectile_copy.is_copy(projectile) then
        return
    end

    if not get_weapon_group(weapon) then return end

    if mods.sc_projectile_copy and mods.sc_projectile_copy.store_projectile_data then
        mods.sc_projectile_copy.store_projectile_data(projectile, weapon)
    end

    local rightWeapon = get_matching_right_weapon(weapon)
    if not rightWeapon then return end

    if not copy_api_available() then
        warn_missing_copy_api_once()
        return
    end

    local copiedProjectile = mods.sc_projectile_copy.create_projectile_copy(projectile, weapon, {
        useOriginalTarget = true
    })
    apply_copied_shot_accuracy_penalty(copiedProjectile)
end)
