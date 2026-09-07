--[[
DESCRIPTION: Pairs adjacent tagged weapons so the left weapon performs the attack for both slots.
        - Builds non-overlapping pairs from left to right using matching <sc_paired> groups.
        - Requires the primary/left weapon to be powered.
        - The secondary/right weapon remains in place; no weapon blueprint swapping is performed.
        - When a pair is first formed, both weapons' cooldowns are reset to 0.
        - The secondary/right weapon's cooldown is matched to the primary/left weapon.
        - The primary/left weapon fires normally and creates a copied projectile from the secondary/right weapon's launch point.
        - The copied projectile chooses its target in this order:
            1. The secondary/right weapon's currently selected target, if exposed.
            2. The most recently killed/removed secondary projectile target this combat.
            3. The primary/left weapon's projectile target.
        - Kills the secondary/right weapon's own projectiles so damage is only applied by the primary and its copy.
        - Forces secondary autofire off while paired.
        - Keeps the secondary/right weapon below full charge and clears queued projectiles to prevent secondary firing.
        - The secondary/right weapon's missile spend is forced to 0 while paired.
        - Can temporarily point the secondary/right weapon at NAME_PAIRED to use a zero-missile secondary blueprint.
        - Restores the secondary/right weapon's original powered state when the pair is no longer valid.
TAG: <sc_paired group="GROUP"/>
DEPENDENCIES: sc_tag.lua, Multiverse userdata_table, Multiverse vter
]]

local vter = mods.multiverse.vter
local userdata_table = mods.multiverse.userdata_table

local pairedGroupById = {}
local removedProjectileTargetsByShip = {}
local removedProjectileDestinationsByShip = {}

-- Optional alternate blueprint for paired secondary weapons.
-- Create NAME_PAIRED as a clone of NAME with <missiles>0</missiles> and ideally <power>0</power>.
local SECONDARY_BLUEPRINT_SUFFIX = "_PAIRED"

-- Keep the secondary just below full charge so target data can remain assigned
-- without letting the secondary weapon enter its actual fire/sound path.
local SECONDARY_FULL_CHARGE_BUFFER = 0.10

local function parse_paired_group(tagNode, weaponNode)
    local groupAttr = tagNode:first_attribute("group")
    local groupId = groupAttr and groupAttr:value() or "default"
    local weaponName = weaponNode:first_attribute("name"):value()

    pairedGroupById[weaponName .. SECONDARY_BLUEPRINT_SUFFIX] = groupId

    return groupId
end

mods.sc.tag.register("weapon", "sc_paired", pairedGroupById, parse_paired_group)

local function run_has_started()
    return Hyperspace.App
        and Hyperspace.App.world
        and Hyperspace.App.world.bStartedGame
end

local function reset_combat_target_cache()
    removedProjectileTargetsByShip = {}
    removedProjectileDestinationsByShip = {}
end

script.on_game_event("START_BEACON", false, function()
    reset_combat_target_cache()
end)

script.on_game_event("START_BEACON_EXPLAIN", false, function()
    reset_combat_target_cache()
end)

script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, function(shipManager)
    if shipManager and shipManager.iShipId == 0 then
        reset_combat_target_cache()
    end
end)

local function pointf_from_point(point)
    if not point then return nil end
    if point.x == nil or point.y == nil then return nil end

    return Hyperspace.Pointf(point.x, point.y)
end

local function copy_custom_damage(src, dst)
    local srcDamage = src.extend and src.extend.customDamage
    local dstDamage = dst.extend and dst.extend.customDamage

    if not srcDamage or not dstDamage then return end

    dstDamage.def = srcDamage.def
    dstDamage.sourceShipId = srcDamage.sourceShipId
    dstDamage.accuracyMod = srcDamage.accuracyMod
    dstDamage.droneAccuracyMod = srcDamage.droneAccuracyMod
end

local function get_weapon_group(weapon)
    if not weapon or not weapon.blueprint then return nil end

    return pairedGroupById[weapon.blueprint.name]
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

local function primary_matches_secondary(primaryWeapon, secondaryWeapon)
    if not primaryWeapon or not secondaryWeapon then return false end
    if not primaryWeapon.blueprint or not secondaryWeapon.blueprint then return false end
    if not primaryWeapon.powered then return false end

    local primaryGroup = get_weapon_group(primaryWeapon)
    if not primaryGroup then return false end

    return primaryGroup == get_weapon_group(secondaryWeapon)
end

local function build_valid_pair_slots(shipManager)
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

local function get_weapon_sprite_point(weapon, offsetX, offsetY)
    if not weapon or not weapon.weaponVisual or not weapon.mount then return nil end

    local shipManager = Hyperspace.ships(weapon.iShipId)
    if not shipManager or not shipManager.ship then return nil end

    local shipGraph = Hyperspace.ShipGraph.GetShipInfo(weapon.iShipId)
    if not shipGraph then return nil end

    local weaponAnim = weapon.weaponVisual
    local ship = shipManager.ship
    local slideOffset = weaponAnim:GetSlide()
    local vertMod = weapon.mount.mirror and -1 or 1

    local emitPointX = ship.shipImage.x + shipGraph.shipBox.x + weaponAnim.renderPoint.x + slideOffset.x
    local emitPointY = ship.shipImage.y + shipGraph.shipBox.y + weaponAnim.renderPoint.y + slideOffset.y

    if weapon.mount.rotate then
        emitPointX = emitPointX - offsetY + weaponAnim.mountPoint.y
        emitPointY = emitPointY + (offsetX - weaponAnim.mountPoint.x) * vertMod
    else
        emitPointX = emitPointX + (offsetX - weaponAnim.mountPoint.x) * vertMod
        emitPointY = emitPointY + offsetY - weaponAnim.mountPoint.y
    end

    return Hyperspace.Pointf(emitPointX, emitPointY)
end

local function get_predicted_weapon_launch_point(weapon)
    if not weapon or not weapon.weaponVisual then return nil end

    local weaponAnim = weapon.weaponVisual

    if weaponAnim.fireLocation then
        return get_weapon_sprite_point(weapon, weaponAnim.fireLocation.x, weaponAnim.fireLocation.y)
    end

    if weaponAnim.mountPoint then
        return get_weapon_sprite_point(weapon, weaponAnim.mountPoint.x, weaponAnim.mountPoint.y)
    end

    return nil
end

local function vector_size(vector)
    if not vector then return 0 end

    local ok, size = pcall(function()
        return vector:size()
    end)

    if not ok or not size then return 0 end

    return size
end

local function vector_point(vector, index)
    if not vector then return nil end
    if vector_size(vector) <= index then return nil end

    local ok, point = pcall(function()
        return vector[index]
    end)

    if not ok then return nil end

    return pointf_from_point(point)
end

local function weapon_has_selected_target(weapon)
    if not weapon then return false end

    if weapon.fireWhenReady then return true end
    if weapon.targetId and weapon.targetId >= 0 then return true end

    return false
end

local function get_selected_weapon_target_point(weapon)
    if not weapon_has_selected_target(weapon) then return nil end

    local lastTargets = weapon.lastTargets
    if not lastTargets then return nil end

    -- For normal weapons, the first stored point appears to be the selected target.
    return vector_point(lastTargets, 0)
end

local function store_removed_secondary_projectile_target(projectile, weaponSlot, shipId)
    if not projectile or weaponSlot == nil or shipId == nil then return end

    removedProjectileTargetsByShip[shipId] = removedProjectileTargetsByShip[shipId] or {}
    removedProjectileDestinationsByShip[shipId] = removedProjectileDestinationsByShip[shipId] or {}

    removedProjectileTargetsByShip[shipId][weaponSlot] = pointf_from_point(projectile.target)
    removedProjectileDestinationsByShip[shipId][weaponSlot] = projectile.destinationSpace
end

local function get_removed_projectile_target(shipId, weaponSlot)
    local shipTargets = removedProjectileTargetsByShip[shipId]
    if not shipTargets then return nil end

    return shipTargets[weaponSlot]
end

local function get_removed_projectile_destination(shipId, weaponSlot)
    local shipDestinations = removedProjectileDestinationsByShip[shipId]
    if not shipDestinations then return nil end

    return shipDestinations[weaponSlot]
end

local function get_copy_launch_point(projectile, secondaryWeapon)
    local predictedSecondaryLaunchPoint = get_predicted_weapon_launch_point(secondaryWeapon)

    if predictedSecondaryLaunchPoint then
        return pointf_from_point(predictedSecondaryLaunchPoint)
    end

    return pointf_from_point(projectile.position)
end

local function get_copy_target_point(projectile, primaryWeapon, secondaryWeapon, secondarySlot)
    local selectedSecondaryTarget = get_selected_weapon_target_point(secondaryWeapon)

    if selectedSecondaryTarget then
        return selectedSecondaryTarget
    end

    local removedSecondaryTarget = get_removed_projectile_target(primaryWeapon.iShipId, secondarySlot)

    if removedSecondaryTarget then
        return pointf_from_point(removedSecondaryTarget)
    end

    return pointf_from_point(projectile.target)
end

local function get_copy_destination_space(projectile, primaryWeapon, secondaryWeapon, secondarySlot)
    if get_selected_weapon_target_point(secondaryWeapon) then
        return projectile.destinationSpace
    end

    local removedSecondaryDestination = get_removed_projectile_destination(primaryWeapon.iShipId, secondarySlot)

    if removedSecondaryDestination ~= nil then
        return removedSecondaryDestination
    end

    return projectile.destinationSpace
end

local function copy_common_projectile_state(src, dst, copyLaunchPoint, copyTargetPoint, copyDestinationSpace)
    dst.position = pointf_from_point(copyLaunchPoint)
    dst.last_position = pointf_from_point(copyLaunchPoint)
    dst.target = pointf_from_point(copyTargetPoint)
    dst.destinationSpace = copyDestinationSpace
    dst.heading = src.heading
    dst.lifespan = src.lifespan
    dst.speed = pointf_from_point(src.speed)
    dst.speed_magnitude = src.speed_magnitude
    dst.entryAngle = src.entryAngle
    dst.bBroadcastTarget = src.bBroadcastTarget

    dst:SetDamage(src.damage)
    copy_custom_damage(src, dst)
    userdata_table(dst, "mods.sc.paired_weapons").isPairedCopy = true
end

local function copy_beam_state(src, dst, copyLaunchPoint, copyTargetPoint, copyDestinationSpace)
    copy_common_projectile_state(src, dst, copyLaunchPoint, copyTargetPoint, copyDestinationSpace)

    dst.target1 = pointf_from_point(src.target1)
    dst.target2 = pointf_from_point(src.target2)
    dst.sub_start = pointf_from_point(copyLaunchPoint)
    dst.sub_end = pointf_from_point(src.sub_end)
    dst.shield_end = pointf_from_point(src.shield_end)
    dst.final_end = pointf_from_point(src.final_end)

    dst.length = src.length
    dst.timer = src.timer
    dst.start_heading = src.start_heading
end

local function create_paired_projectile_copy(projectile, primaryWeapon, secondaryWeapon, secondarySlot)
    local spaceManager = Hyperspace.App.world.space
    local blueprint = primaryWeapon.blueprint
    local typeName = blueprint.typeName
    local copyLaunchPoint = get_copy_launch_point(projectile, secondaryWeapon)
    local copyTargetPoint = get_copy_target_point(projectile, primaryWeapon, secondaryWeapon, secondarySlot)
    local copyDestinationSpace = get_copy_destination_space(projectile, primaryWeapon, secondaryWeapon, secondarySlot)

    if typeName == "BEAM" then
        local beam = spaceManager:CreateBeam(
            blueprint,
            copyLaunchPoint,
            projectile.currentSpace,
            projectile.ownerId,
            projectile.target1,
            projectile.target2,
            copyDestinationSpace,
            projectile.length,
            projectile.heading
        )

        copy_beam_state(projectile, beam, copyLaunchPoint, copyTargetPoint, copyDestinationSpace)
        return
    end

    if typeName == "BOMB" then
        local bomb = spaceManager:CreateBomb(
            blueprint,
            projectile.ownerId,
            copyTargetPoint,
            copyDestinationSpace
        )

        copy_common_projectile_state(projectile, bomb, copyLaunchPoint, copyTargetPoint, copyDestinationSpace)
        return
    end

    if typeName == "MISSILES" then
        local missile = spaceManager:CreateMissile(
            blueprint,
            copyLaunchPoint,
            projectile.currentSpace,
            projectile.ownerId,
            copyTargetPoint,
            copyDestinationSpace,
            projectile.heading
        )

        copy_common_projectile_state(projectile, missile, copyLaunchPoint, copyTargetPoint, copyDestinationSpace)
        return
    end

    local laser = spaceManager:CreateLaserBlast(
        blueprint,
        copyLaunchPoint,
        projectile.currentSpace,
        projectile.ownerId,
        copyTargetPoint,
        copyDestinationSpace,
        projectile.heading
    )

    copy_common_projectile_state(projectile, laser, copyLaunchPoint, copyTargetPoint, copyDestinationSpace)
end

local function clear_weapon_projectiles(weapon)
    if not weapon or not weapon.queuedProjectiles then return end

    for queuedProjectile in vter(weapon.queuedProjectiles) do
        queuedProjectile:Kill()
    end

    weapon.queuedProjectiles:clear()
end

local function hold_secondary_below_full_charge(secondaryWeapon)
    if not secondaryWeapon or not secondaryWeapon.cooldown then return end

    local maxCharge = secondaryWeapon.cooldown.second
    if not maxCharge then return end

    local cappedCharge = maxCharge - SECONDARY_FULL_CHARGE_BUFFER
    if cappedCharge < 0 then
        cappedCharge = 0
    end

    if secondaryWeapon.cooldown.first > cappedCharge then
        secondaryWeapon.cooldown.first = cappedCharge
    end
end

local function suppress_secondary_fire_request(secondaryWeapon)
    if not secondaryWeapon then return end

    secondaryWeapon.autoFiring = false

    -- Leave fireWhenReady/targetId/lastTargets intact when possible, because
    -- those fields provide the selected target for the copied projectile.
    -- Prevent actual firing by keeping the secondary just below full charge
    -- and clearing queued projectiles as a fallback.
    hold_secondary_below_full_charge(secondaryWeapon)
    clear_weapon_projectiles(secondaryWeapon)
end

local function get_power_override_data(weapon)
    if not weapon then return nil end

    return userdata_table(weapon, "mods.sc.paired_weapon_power_override")
end

local function try_get_field(object, fieldName)
    local ok, value = pcall(function()
        return object[fieldName]
    end)

    if not ok then return nil end

    return value
end

local function try_set_field(object, fieldName, value)
    local ok = pcall(function()
        object[fieldName] = value
    end)

    return ok
end

local SECONDARY_POWER_FIELD_CANDIDATES = {
    "powerRequired",
    "requiredPower",
    "iRequiredPower",
    "powerRequirement",
    "iPowerRequired"
}

local function reset_weapon_cooldown(weapon)
    if not weapon or not weapon.cooldown then return end

    weapon.cooldown.first = 0

    if weapon.chargeLevel ~= nil then
        weapon.chargeLevel = 0
    end

    clear_weapon_projectiles(weapon)
end

local function reset_pair_cooldowns_on_initial_pair(pairData)
    if not pairData or not pairData.secondaryWeapon then return end

    local data = get_power_override_data(pairData.secondaryWeapon)
    if not data then return end

    if data.isPaired then return end

    data.isPaired = true

    reset_weapon_cooldown(pairData.primaryWeapon)
    reset_weapon_cooldown(pairData.secondaryWeapon)
end

local function set_secondary_power_requirement_zero(secondaryWeapon)
    if not secondaryWeapon then return end

    local data = get_power_override_data(secondaryWeapon)
    if not data then return end

    if data.originalPowered == nil then
        data.originalPowered = secondaryWeapon.powered
    end

    data.modifiedFields = data.modifiedFields or {}

    for _, fieldName in ipairs(SECONDARY_POWER_FIELD_CANDIDATES) do
        local currentValue = try_get_field(secondaryWeapon, fieldName)

        if type(currentValue) == "number" then
            if data.modifiedFields[fieldName] == nil then
                data.modifiedFields[fieldName] = currentValue
            end

            try_set_field(secondaryWeapon, fieldName, 0)
        end
    end
end

local function set_secondary_missile_spend_zero(secondaryWeapon)
    if not secondaryWeapon then return end

    local data = get_power_override_data(secondaryWeapon)
    if not data then return end

    local currentSpend = try_get_field(secondaryWeapon, "iSpendMissile")

    if type(currentSpend) == "number" then
        if data.originalMissileSpend == nil then
            data.originalMissileSpend = currentSpend
        end

        try_set_field(secondaryWeapon, "iSpendMissile", 0)
    end
end

local function get_base_secondary_weapon_name(secondaryWeapon)
    if not secondaryWeapon or not secondaryWeapon.blueprint then return nil end

    local weaponName = secondaryWeapon.blueprint.name
    if not weaponName then return nil end

    if string.sub(weaponName, -#SECONDARY_BLUEPRINT_SUFFIX) == SECONDARY_BLUEPRINT_SUFFIX then
        return string.sub(weaponName, 1, #weaponName - #SECONDARY_BLUEPRINT_SUFFIX)
    end

    return weaponName
end

local function set_secondary_to_paired_blueprint(secondaryWeapon)
    if not secondaryWeapon or not secondaryWeapon.blueprint then return end

    local data = get_power_override_data(secondaryWeapon)
    if not data then return end

    if data.originalBlueprint == nil then
        data.originalBlueprint = secondaryWeapon.blueprint
        data.originalBlueprintName = secondaryWeapon.blueprint.name
    end

    local baseWeaponName = data.originalBlueprintName or get_base_secondary_weapon_name(secondaryWeapon)
    if not baseWeaponName then return end

    local pairedBlueprintName = baseWeaponName .. SECONDARY_BLUEPRINT_SUFFIX
    local pairedBlueprint = Hyperspace.Blueprints:GetWeaponBlueprint(pairedBlueprintName)

    if not pairedBlueprint then
        if not data.missingPairedBlueprintPrinted then
            print("SC PAIRED WARNING | Missing paired secondary blueprint: " .. tostring(pairedBlueprintName))
            data.missingPairedBlueprintPrinted = true
        end

        return
    end

    -- This swaps only the ProjectileFactory's blueprint pointer. It does not
    -- remove/re-add weapons or globally mutate the original blueprint's missiles.
    secondaryWeapon.blueprint = pairedBlueprint
end

local function restore_secondary_blueprint(weapon)
    if not weapon then return end

    local data = get_power_override_data(weapon)
    if not data then return end

    if data.originalBlueprint ~= nil then
        weapon.blueprint = data.originalBlueprint
    end

    data.originalBlueprint = nil
    data.originalBlueprintName = nil
    data.missingPairedBlueprintPrinted = nil
end

local function restore_secondary_power_requirement(weapon)
    if not weapon then return end

    local data = get_power_override_data(weapon)
    if not data then return end

    if data.modifiedFields then
        for fieldName, originalValue in pairs(data.modifiedFields) do
            try_set_field(weapon, fieldName, originalValue)
        end
    end

    if data.originalMissileSpend ~= nil then
        try_set_field(weapon, "iSpendMissile", data.originalMissileSpend)
    end

    restore_secondary_blueprint(weapon)

    if data.originalPowered ~= nil then
        weapon.powered = data.originalPowered
    end

    data.modifiedFields = {}
    data.originalPowered = nil
    data.originalMissileSpend = nil
    data.isPaired = false
end

local function restore_unpaired_power_overrides(shipManager, pairSlots)
    if not shipManager or not shipManager.weaponSystem then return end

    local weapons = shipManager.weaponSystem.weapons
    if not weapons then return end

    for i = 0, weapons:size() - 1 do
        local weapon = weapons[i]
        local pairData = pairSlots and pairSlots[i]

        if weapon and (not pairData or pairData.secondarySlot ~= i) then
            restore_secondary_power_requirement(weapon)
        end
    end
end

local function sync_secondary_cooldown_to_primary(primaryWeapon, secondaryWeapon)
    if not primaryWeapon or not secondaryWeapon then return end
    if not primaryWeapon.cooldown or not secondaryWeapon.cooldown then return end

    secondaryWeapon.cooldown.first = primaryWeapon.cooldown.first
    secondaryWeapon.cooldown.second = primaryWeapon.cooldown.second

    if primaryWeapon.chargeLevel ~= nil and secondaryWeapon.chargeLevel ~= nil then
        secondaryWeapon.chargeLevel = primaryWeapon.chargeLevel
    end
end

local function maintain_paired_secondary_weapons(shipManager)
    local weapons = shipManager.weaponSystem.weapons
    local pairSlots = build_valid_pair_slots(shipManager)

    restore_unpaired_power_overrides(shipManager, pairSlots)

    local i = 0

    while i <= weapons:size() - 2 do
        local pairData = pairSlots[i]

        if pairData and pairData.primarySlot == i then
            reset_pair_cooldowns_on_initial_pair(pairData)
            set_secondary_power_requirement_zero(pairData.secondaryWeapon)
            set_secondary_to_paired_blueprint(pairData.secondaryWeapon)
            set_secondary_missile_spend_zero(pairData.secondaryWeapon)
            sync_secondary_cooldown_to_primary(pairData.primaryWeapon, pairData.secondaryWeapon)
            suppress_secondary_fire_request(pairData.secondaryWeapon)
            i = i + 2
        else
            i = i + 1
        end
    end
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if not run_has_started() then return end
    if not shipManager or shipManager.iShipId ~= 0 or not shipManager.weaponSystem then return end

    maintain_paired_secondary_weapons(shipManager)
end)

script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_FIRE,
    function(projectile, weapon)
        if not run_has_started() then return end
        if not projectile or not weapon then return end
        if userdata_table(projectile, "mods.sc.paired_weapons").isPairedCopy then return end
        if not get_weapon_group(weapon) then return end

        local weaponSlot = get_weapon_slot(weapon)
        if weaponSlot == nil then return end

        local ship = Hyperspace.ships(weapon.iShipId)
        if not ship then return end

        local pairData = build_valid_pair_slots(ship)[weaponSlot]
        if not pairData then return end

        if pairData.secondarySlot == weaponSlot then
            store_removed_secondary_projectile_target(projectile, weaponSlot, weapon.iShipId)
            set_secondary_to_paired_blueprint(weapon)
            set_secondary_missile_spend_zero(weapon)
            projectile:Kill()
            clear_weapon_projectiles(weapon)
            suppress_secondary_fire_request(weapon)
            return
        end

        create_paired_projectile_copy(
            projectile,
            pairData.primaryWeapon,
            pairData.secondaryWeapon,
            pairData.secondarySlot
        )

        clear_weapon_projectiles(pairData.secondaryWeapon)
        sync_secondary_cooldown_to_primary(pairData.primaryWeapon, pairData.secondaryWeapon)
    end
)
