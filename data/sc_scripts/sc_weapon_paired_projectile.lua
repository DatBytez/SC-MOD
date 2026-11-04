--[[
DESCRIPTION: Handles projectile targeting and copying for active <sc_paired> weapon pairs.
        - Removes the secondary weapon's native projectile while preserving its selected target.
        - Fires a copied primary projectile from the secondary weapon's launch point.
        - Uses the secondary selected target, its most recently removed projectile target, or the primary target in that order.
DEPENDENCIES: sc_weapon_paired_core.lua, sc_weapon_paired_secondary.lua, Multiverse userdata_table
]]

local userdata_table = mods.multiverse.userdata_table
local paired = mods.sc.paired

local removedProjectileTargetsByShip = {}
local removedProjectileDestinationsByShip = {}

local function reset_combat_target_cache()
    removedProjectileTargetsByShip = {}
    removedProjectileDestinationsByShip = {}
end

script.on_game_event("START_BEACON", false, reset_combat_target_cache)
script.on_game_event("START_BEACON_EXPLAIN", false, reset_combat_target_cache)

script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, function(shipManager)
    if shipManager and shipManager.iShipId == 0 then reset_combat_target_cache() end
end)

local function pointf_from_point(point)
    if not point or point.x == nil or point.y == nil then return nil end
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

local function weapon_has_selected_target(weapon)
    return weapon and (weapon.fireWhenReady or (weapon.targetId and weapon.targetId >= 0))
end

local function get_selected_weapon_target_point(weapon)
    if not weapon_has_selected_target(weapon) then return nil end
    if not weapon.lastTargets or weapon.lastTargets:size() == 0 then return nil end

    return pointf_from_point(weapon.lastTargets[0])
end

local function store_removed_secondary_projectile_target(projectile, weaponSlot, shipId)
    removedProjectileTargetsByShip[shipId] = removedProjectileTargetsByShip[shipId] or {}
    removedProjectileDestinationsByShip[shipId] = removedProjectileDestinationsByShip[shipId] or {}

    removedProjectileTargetsByShip[shipId][weaponSlot] = pointf_from_point(projectile.target)
    removedProjectileDestinationsByShip[shipId][weaponSlot] = projectile.destinationSpace
end

local function get_copy_launch_point(projectile, secondaryWeapon)
    return pointf_from_point(get_predicted_weapon_launch_point(secondaryWeapon)) or pointf_from_point(projectile.position)
end

local function get_copy_target(projectile, primaryWeapon, secondaryWeapon, secondarySlot)
    local selectedTarget = get_selected_weapon_target_point(secondaryWeapon)
    if selectedTarget then return selectedTarget, projectile.destinationSpace end

    local shipTargets = removedProjectileTargetsByShip[primaryWeapon.iShipId]
    local shipDestinations = removedProjectileDestinationsByShip[primaryWeapon.iShipId]
    local cachedTarget = shipTargets and shipTargets[secondarySlot]
    local cachedDestination = shipDestinations and shipDestinations[secondarySlot]

    local copyTarget = pointf_from_point(cachedTarget) or pointf_from_point(projectile.target)
    local copyDestination = cachedDestination ~= nil and cachedDestination or projectile.destinationSpace
    return copyTarget, copyDestination
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
    local copyLaunchPoint = get_copy_launch_point(projectile, secondaryWeapon)
    local copyTargetPoint, copyDestinationSpace = get_copy_target(projectile, primaryWeapon, secondaryWeapon, secondarySlot)

    if blueprint.typeName == "BEAM" then
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

    if blueprint.typeName == "BOMB" then
        local bomb = spaceManager:CreateBomb(blueprint, projectile.ownerId, copyTargetPoint, copyDestinationSpace)
        copy_common_projectile_state(projectile, bomb, copyLaunchPoint, copyTargetPoint, copyDestinationSpace)
        return
    end

    if blueprint.typeName == "MISSILES" then
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

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    if not paired.run_has_started() or not projectile or not weapon then return end
    if userdata_table(projectile, "mods.sc.paired_weapons").isPairedCopy then return end
    if not paired.get_weapon_group(weapon) then return end

    local weaponSlot = paired.get_weapon_slot(weapon)
    if weaponSlot == nil then return end

    local ship = Hyperspace.ships(weapon.iShipId)
    if not ship then return end

    local pairData = paired.build_valid_pair_slots(ship)[weaponSlot]
    if not pairData then return end

    if pairData.secondarySlot == weaponSlot then
        store_removed_secondary_projectile_target(projectile, weaponSlot, weapon.iShipId)
        paired.maintain_secondary_pair(pairData)
        projectile:Kill()
        return
    end

    create_paired_projectile_copy(projectile, pairData.primaryWeapon, pairData.secondaryWeapon, pairData.secondarySlot)
    paired.sync_after_primary_fire(pairData)
end)
