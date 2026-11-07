--[[
DESCRIPTION: Manages the secondary/right weapon while an <sc_paired> pair is active.
        - Swaps the secondary to the generic GEMINI_PAIRED blueprint.
        - Removes its power and missile cost while paired.
        - Synchronizes its cooldown with the primary weapon and suppresses native firing.
        - Restores the original weapon state when the pair breaks or a management screen opens.
DEPENDENCIES: sc_weapon_paired_core.lua
]]

local paired = mods.sc.paired

local SECONDARY_FULL_CHARGE_BUFFER = 0.10

local function reset_weapon_cooldown(weapon)
    if not weapon or not weapon.cooldown then return end

    weapon.cooldown.first = 0
    if weapon.chargeLevel ~= nil then weapon.chargeLevel = 0 end
    paired.clear_weapon_projectiles(weapon)
end

local function get_pair_signature(pairData)
    return tostring(pairData.primarySlot)
        .. "|" .. tostring(pairData.secondarySlot)
        .. "|" .. (paired.get_original_or_current_weapon_name(pairData.primaryWeapon) or "")
        .. "|" .. (paired.get_original_or_current_weapon_name(pairData.secondaryWeapon) or "")
end

local function reset_stored_pair_cooldowns(data, fallbackSecondaryWeapon)
    if not data or not data.isPaired then return end

    reset_weapon_cooldown(data.pairedPrimaryWeapon)
    reset_weapon_cooldown(data.pairedSecondaryWeapon or fallbackSecondaryWeapon)
end

local function reset_pair_cooldowns_on_initial_pair(pairData)
    local data = paired.get_state(pairData.secondaryWeapon)
    local pairSignature = get_pair_signature(pairData)

    if data.isPaired and data.pairSignature == pairSignature then return end

    reset_stored_pair_cooldowns(data, pairData.secondaryWeapon)

    data.isPaired = true
    data.pairSignature = pairSignature
    data.pairedPrimaryWeapon = pairData.primaryWeapon
    data.pairedSecondaryWeapon = pairData.secondaryWeapon

    reset_weapon_cooldown(pairData.primaryWeapon)
    reset_weapon_cooldown(pairData.secondaryWeapon)
end

local function set_secondary_power_requirement_zero(secondaryWeapon)
    local data = paired.get_state(secondaryWeapon)

    if data.originalRequiredPower == nil then data.originalRequiredPower = secondaryWeapon.requiredPower end
    if data.originalPowered == nil then data.originalPowered = secondaryWeapon.powered end

    secondaryWeapon.requiredPower = 0
end

local function set_secondary_missile_spend_zero(secondaryWeapon)
    local data = paired.get_state(secondaryWeapon)

    if data.originalMissileSpend == nil then data.originalMissileSpend = secondaryWeapon.iSpendMissile end
    secondaryWeapon.iSpendMissile = 0
end

local function set_secondary_to_paired_blueprint(secondaryWeapon)
    if not secondaryWeapon or not secondaryWeapon.blueprint then return end

    local data = paired.get_state(secondaryWeapon)

    if data.originalBlueprint == nil then
        data.originalBlueprint = secondaryWeapon.blueprint
        data.originalBlueprintName = secondaryWeapon.blueprint.name
    end

    local pairedBlueprint = Hyperspace.Blueprints:GetWeaponBlueprint(paired.GENERIC_SECONDARY_BLUEPRINT)

    if not pairedBlueprint then return end

    secondaryWeapon.blueprint = pairedBlueprint
end

local function restore_secondary_blueprint(weapon, data)
    if data.originalBlueprint ~= nil then weapon.blueprint = data.originalBlueprint end

    data.originalBlueprint = nil
    data.originalBlueprintName = nil
end

local function weapon_has_active_pair_restore_state(data)
    return data.isPaired == true
        or data.originalBlueprint ~= nil
        or data.originalRequiredPower ~= nil
        or data.originalPowered ~= nil
        or data.originalMissileSpend ~= nil
        or data.pairSignature ~= nil
end

local function restore_secondary_state(weapon)
    if not weapon then return end

    local data = paired.get_state(weapon)
    if not weapon_has_active_pair_restore_state(data) then return end

    if data.originalRequiredPower ~= nil then weapon.requiredPower = data.originalRequiredPower end
    if data.originalMissileSpend ~= nil then weapon.iSpendMissile = data.originalMissileSpend end

    restore_secondary_blueprint(weapon, data)

    if data.originalPowered ~= nil then weapon.powered = data.originalPowered end

    reset_stored_pair_cooldowns(data, weapon)

    data.originalRequiredPower = nil
    data.originalPowered = nil
    data.originalMissileSpend = nil
    data.isPaired = false
    data.pairSignature = nil
    data.pairedPrimaryWeapon = nil
    data.pairedSecondaryWeapon = nil
end

local function restore_unpaired_secondary_states(shipManager, pairSlots)
    local weapons = shipManager.weaponSystem.weapons

    for i = 0, weapons:size() - 1 do
        local pairData = pairSlots[i]

        if not pairData or pairData.secondarySlot ~= i then
            restore_secondary_state(weapons[i])
        end
    end
end

local function sync_secondary_cooldown_to_primary(primaryWeapon, secondaryWeapon)
    if not primaryWeapon.cooldown or not secondaryWeapon.cooldown then return end

    secondaryWeapon.cooldown.first = primaryWeapon.cooldown.first
    secondaryWeapon.cooldown.second = primaryWeapon.cooldown.second

    if primaryWeapon.chargeLevel ~= nil and secondaryWeapon.chargeLevel ~= nil then
        secondaryWeapon.chargeLevel = primaryWeapon.chargeLevel
    end
end

local function hold_secondary_below_full_charge(secondaryWeapon)
    if not secondaryWeapon.cooldown then return end

    local maxCharge = secondaryWeapon.cooldown.second
    if not maxCharge then return end

    local cappedCharge = math.max(0, maxCharge - SECONDARY_FULL_CHARGE_BUFFER)
    if secondaryWeapon.cooldown.first > cappedCharge then secondaryWeapon.cooldown.first = cappedCharge end
end

local function suppress_secondary_fire_request(secondaryWeapon)
    secondaryWeapon.autoFiring = false

    hold_secondary_below_full_charge(secondaryWeapon)
    paired.clear_weapon_projectiles(secondaryWeapon)
end

function paired.maintain_secondary_pair(pairData)
    reset_pair_cooldowns_on_initial_pair(pairData)
    set_secondary_power_requirement_zero(pairData.secondaryWeapon)
    set_secondary_to_paired_blueprint(pairData.secondaryWeapon)
    set_secondary_power_requirement_zero(pairData.secondaryWeapon)
    set_secondary_missile_spend_zero(pairData.secondaryWeapon)
    sync_secondary_cooldown_to_primary(pairData.primaryWeapon, pairData.secondaryWeapon)
    suppress_secondary_fire_request(pairData.secondaryWeapon)
end

function paired.sync_after_primary_fire(pairData)
    paired.clear_weapon_projectiles(pairData.secondaryWeapon)
    sync_secondary_cooldown_to_primary(pairData.primaryWeapon, pairData.secondaryWeapon)
end

local function restore_all_paired_secondary_states(shipManager)
    if not shipManager or not shipManager.weaponSystem then return end

    local weapons = shipManager.weaponSystem.weapons
    for i = 0, weapons:size() - 1 do restore_secondary_state(weapons[i]) end
end

local tabbedWindowRendered = false
local tabbedWindowOpen = false

script.on_render_event(
    Defines.RenderEvents.TABBED_WINDOW,
    function()
        tabbedWindowRendered = true

        local shipManager = Hyperspace.ships(0)
        if shipManager then
            restore_all_paired_secondary_states(shipManager)
        end
    end,
    function() end
)

script.on_render_event(
    Defines.RenderEvents.MOUSE_CONTROL,
    function() end,
    function()
        tabbedWindowOpen = tabbedWindowRendered
        tabbedWindowRendered = false
    end
)

local function maintain_paired_secondary_weapons(shipManager)
    local weapons = shipManager.weaponSystem.weapons
    local pairSlots = paired.build_valid_pair_slots(shipManager)

    restore_unpaired_secondary_states(shipManager, pairSlots)

    local i = 0

    while i <= weapons:size() - 2 do
        local pairData = pairSlots[i]

        if pairData and pairData.primarySlot == i then
            paired.maintain_secondary_pair(pairData)
            i = i + 2
        else
            i = i + 1
        end
    end
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if not paired.run_has_started() then return end
    if not shipManager or shipManager.iShipId ~= 0 or not shipManager.weaponSystem then return end

    if tabbedWindowOpen then
        restore_all_paired_secondary_states(shipManager)
        return
    end

    maintain_paired_secondary_weapons(shipManager)
end)