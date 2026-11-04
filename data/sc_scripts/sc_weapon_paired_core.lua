--[[
DESCRIPTION: Shared pairing state and pair discovery for tagged weapons.
        - Registers <sc_paired> groups.
        - Builds non-overlapping adjacent pairs from left to right.
        - Preserves a secondary weapon's original identity while its blueprint is swapped.
TAG: <sc_paired group="GROUP"/>
DEPENDENCIES: sc_tag.lua, Multiverse userdata_table, Multiverse vter
]]

local vter = mods.multiverse.vter
local userdata_table = mods.multiverse.userdata_table

mods.sc = mods.sc or {}
mods.sc.paired = mods.sc.paired or {}

local paired = mods.sc.paired

paired.GENERIC_SECONDARY_BLUEPRINT = "GEMINI_PAIRED"
paired.STATE_KEY = "mods.sc.paired_weapon_power_override"
paired.groups = paired.groups or {}

local function parse_paired_group(tagNode)
    local groupAttr = tagNode:first_attribute("group")
    return groupAttr and groupAttr:value() or "default"
end

mods.sc.tag.register("weapon", "sc_paired", paired.groups, parse_paired_group)

function paired.run_has_started()
    return Hyperspace.App and Hyperspace.App.world and Hyperspace.App.world.bStartedGame
end

function paired.get_state(weapon)
    if not weapon then return nil end
    return userdata_table(weapon, paired.STATE_KEY)
end

function paired.get_original_or_current_weapon_name(weapon)
    if not weapon or not weapon.blueprint then return nil end

    local data = paired.get_state(weapon)
    return data.originalBlueprintName or weapon.blueprint.name
end

function paired.get_weapon_group(weapon)
    local weaponName = paired.get_original_or_current_weapon_name(weapon)
    return weaponName and paired.groups[weaponName] or nil
end

function paired.get_weapon_slot(weapon)
    if not weapon then return nil end

    local ship = Hyperspace.ships(weapon.iShipId)
    if not ship or not ship.weaponSystem then return nil end

    local weapons = ship.weaponSystem.weapons

    for i = 0, weapons:size() - 1 do
        if weapons[i] == weapon then return i end
    end

    return nil
end

local function secondary_can_become_paired(secondaryWeapon)
    local data = paired.get_state(secondaryWeapon)
    if data.isPaired then return true end
    return not secondaryWeapon.powered
end

local function primary_matches_secondary(primaryWeapon, secondaryWeapon)
    if not primaryWeapon or not secondaryWeapon then return false end
    if not primaryWeapon.blueprint or not secondaryWeapon.blueprint then return false end
    if not primaryWeapon.powered or not secondary_can_become_paired(secondaryWeapon) then return false end

    local primaryGroup = paired.get_weapon_group(primaryWeapon)
    return primaryGroup and primaryGroup == paired.get_weapon_group(secondaryWeapon)
end

function paired.build_valid_pair_slots(shipManager)
    local pairSlots = {}
    if not shipManager or not shipManager.weaponSystem then return pairSlots end

    local weapons = shipManager.weaponSystem.weapons
    if not weapons then return pairSlots end

    local i = 0

    while i <= weapons:size() - 2 do
        local primaryWeapon = weapons[i]
        local secondaryWeapon = weapons[i + 1]

        if primary_matches_secondary(primaryWeapon, secondaryWeapon) then
            local pairData = {
                primarySlot = i,
                secondarySlot = i + 1,
                primaryWeapon = primaryWeapon,
                secondaryWeapon = secondaryWeapon
            }

            pairSlots[i] = pairData
            pairSlots[i + 1] = pairData
            i = i + 2
        else
            i = i + 1
        end
    end

    return pairSlots
end

function paired.clear_weapon_projectiles(weapon)
    if not weapon or not weapon.queuedProjectiles then return end

    for projectile in vter(weapon.queuedProjectiles) do
        projectile:Kill()
    end

    weapon.queuedProjectiles:clear()
end
