--[[
DESCRIPTION: Pairs adjacent tagged weapons so the left weapon performs the attack for both slots.
        - Builds non-overlapping pairs from left to right using matching <sc_paired> groups.
        - Requires the primary/left weapon to be powered.
        - The secondary/right weapon temporarily uses a paired secondary blueprint while paired.
        - When a pair is first formed, both weapons' cooldowns are reset to 0.
        - The secondary/right weapon's cooldown is matched to the primary/left weapon.
        - The primary/left weapon fires normally and creates a copied projectile from the secondary/right weapon's launch point.
        - The copied projectile chooses its target in this order:
            1. The secondary/right weapon's currently selected target, if exposed.
            2. The most recently killed/removed secondary projectile target this combat.
            3. The primary/left weapon's projectile target.
        - Kills the secondary/right weapon's own projectiles so damage is only applied by the primary and its copy.
        - Restores the secondary/right weapon's original blueprint and powered state when the pair is no longer valid.
TAG: <sc_paired group="GROUP"/>
DEPENDENCIES: sc_tag.lua, Multiverse userdata_table
]]

local userdata_table = mods.multiverse.userdata_table

local pairedGroupById = {}
local removedProjectileTargetsByShip = {}
local removedProjectileDestinationsByShip = {}

-- One generic harmless targeting shell for every paired secondary weapon.
-- This blueprint must exist. It should have <power>0</power>, <missiles>0</missiles>,
-- and harmless/no damage.
local GENERIC_SECONDARY_BLUEPRINT = "GEMINI_PAIRED"

local function parse_paired_group(tagNode, weaponNode)
    local groupAttr = tagNode:first_attribute("group")
    local groupId = groupAttr and groupAttr:value() or "default"

    pairedGroupById[GENERIC_SECONDARY_BLUEPRINT] = groupId

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
    return vector_point(weapon.lastTargets, 0)
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
    weapon.queuedProjectiles:clear()
end

local function get_pair_state_data(weapon)
    if not weapon then return nil end
    return userdata_table(weapon, "mods.sc.paired_weapon_state")
end

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

    local data = get_pair_state_data(pairData.secondaryWeapon)
    if not data then return end
    if data.isPaired then return end

    data.isPaired = true

    reset_weapon_cooldown(pairData.primaryWeapon)
    reset_weapon_cooldown(pairData.secondaryWeapon)
end

local function get_paired_secondary_blueprint()
    return Hyperspace.Blueprints:GetWeaponBlueprint(GENERIC_SECONDARY_BLUEPRINT)
end

local function set_secondary_to_paired_blueprint(secondaryWeapon)
    if not secondaryWeapon or not secondaryWeapon.blueprint then return end

    local data = get_pair_state_data(secondaryWeapon)
    if not data then return end

    if data.originalBlueprint == nil then
        data.originalBlueprint = secondaryWeapon.blueprint
    end

    if data.originalPowered == nil then
        data.originalPowered = secondaryWeapon.powered
    end

    local pairedBlueprint = get_paired_secondary_blueprint()
    if not pairedBlueprint then
        print("SC PAIRED ERROR | Missing generic paired secondary blueprint: " .. tostring(GENERIC_SECONDARY_BLUEPRINT))
        return
    end

    secondaryWeapon.blueprint = pairedBlueprint
end

local function restore_secondary_state(weapon)
    if not weapon then return end

    local data = get_pair_state_data(weapon)
    if not data then return end

    if data.originalBlueprint ~= nil then
        weapon.blueprint = data.originalBlueprint
    end

    if data.originalPowered ~= nil then
        weapon.powered = data.originalPowered
    end

    data.originalBlueprint = nil
    data.originalPowered = nil
    data.isPaired = false
end

local function restore_unpaired_secondary_states(shipManager, pairSlots)
    if not shipManager or not shipManager.weaponSystem then return end

    local weapons = shipManager.weaponSystem.weapons
    if not weapons then return end

    for i = 0, weapons:size() - 1 do
        local weapon = weapons[i]
        local pairData = pairSlots and pairSlots[i]

        if weapon and (not pairData or pairData.secondarySlot ~= i) then
            restore_secondary_state(weapon)
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

    restore_unpaired_secondary_states(shipManager, pairSlots)

    local i = 0

    while i <= weapons:size() - 2 do
        local pairData = pairSlots[i]

        if pairData and pairData.primarySlot == i then
            reset_pair_cooldowns_on_initial_pair(pairData)
            set_secondary_to_paired_blueprint(pairData.secondaryWeapon)
            sync_secondary_cooldown_to_primary(pairData.primaryWeapon, pairData.secondaryWeapon)
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
            projectile:Kill()
            clear_weapon_projectiles(weapon)
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
