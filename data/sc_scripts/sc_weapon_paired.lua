--[[
DESCRIPTION: Pairs adjacent tagged weapons so the left weapon performs the attack for both slots.
        - Builds non-overlapping pairs from left to right using matching <sc_paired> groups.
        - Requires the primary/left weapon to be powered.
        - Replaces the secondary/right weapon with its "_PAIRED" target blueprint while the pair is valid.
        - Restores the original secondary weapon when the pair is no longer valid.
        - Uses the secondary weapon's target and launch point for a copied projectile fired by the primary weapon.
        - Kills the secondary weapon's own projectiles so damage is only applied by the primary and its copy.
        - Forces secondary autofire off while paired.
TAG: <sc_paired group="GROUP"/>
DEPENDENCIES: sc_tag.lua, Multiverse userdata_table, Multiverse vter
]]

local vter = mods.multiverse.vter
local userdata_table = mods.multiverse.userdata_table

local pairedGroupById = {}
local targetCoordinatesByShip = {}
local destinationSpaceByShip = {}

local TARGET_SUFFIX = "_PAIRED"

local function parse_paired_group(tagNode, weaponNode)
    local groupAttr = tagNode:first_attribute("group")
    local groupId = groupAttr and groupAttr:value() or "default"
    local weaponName = weaponNode:first_attribute("name"):value()

    pairedGroupById[weaponName .. TARGET_SUFFIX] = groupId

    return groupId
end

mods.sc.tag.register("weapon", "sc_paired", pairedGroupById, parse_paired_group)

local function pointf_from_point(point)
    return Hyperspace.Pointf(point.x, point.y)
end

local function copy_custom_damage(src, dst)
    local srcDamage = src.extend and src.extend.customDamage
    local dstDamage = dst.extend and dst.extend.customDamage

    if not srcDamage or not dstDamage then return end

    dstDamage.def = srcDamage.def
    dstDamage.accuracyMod = srcDamage.accuracyMod
    dstDamage.droneAccuracyMod = srcDamage.droneAccuracyMod
end

local function string_ends_with(value, suffix)
    return string.sub(value, -#suffix) == suffix
end

local function get_original_name_from_target_name(weaponName)
    if not string_ends_with(weaponName, TARGET_SUFFIX) then return nil end

    return string.sub(weaponName, 1, #weaponName - #TARGET_SUFFIX)
end

local function get_weapon_group(weapon)
    return pairedGroupById[weapon.blueprint.name]
end

local function get_weapon_slot(weapon)
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
    if not shipManager.weaponSystem then return pairSlots end

    local weapons = shipManager.weaponSystem.weapons
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
    if not weapon.weaponVisual or not weapon.mount then return nil end

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
    if not weapon.weaponVisual then return nil end

    local weaponAnim = weapon.weaponVisual

    if weaponAnim.fireLocation then
        return get_weapon_sprite_point(weapon, weaponAnim.fireLocation.x, weaponAnim.fireLocation.y)
    end

    if weaponAnim.mountPoint then
        return get_weapon_sprite_point(weapon, weaponAnim.mountPoint.x, weaponAnim.mountPoint.y)
    end

    return nil
end

local function store_projectile_data(projectile, weapon, weaponSlot)
    local shipId = weapon.iShipId

    targetCoordinatesByShip[shipId] = targetCoordinatesByShip[shipId] or {}
    destinationSpaceByShip[shipId] = destinationSpaceByShip[shipId] or {}

    targetCoordinatesByShip[shipId][weaponSlot] = pointf_from_point(projectile.target)
    destinationSpaceByShip[shipId][weaponSlot] = projectile.destinationSpace
end

local function get_copy_launch_point(projectile, rightWeapon)
    local predictedRightLaunchPoint = get_predicted_weapon_launch_point(rightWeapon)

    if predictedRightLaunchPoint then
        return pointf_from_point(predictedRightLaunchPoint)
    end

    return pointf_from_point(projectile.position)
end

local function get_copy_target_point(projectile, leftWeapon, rightSlot)
    local shipTargets = targetCoordinatesByShip[leftWeapon.iShipId]
    local rightSlotTarget = shipTargets and shipTargets[rightSlot]

    if rightSlotTarget then
        return pointf_from_point(rightSlotTarget)
    end

    return pointf_from_point(projectile.target)
end

local function get_copy_destination_space(projectile, leftWeapon, rightSlot)
    local shipDestinations = destinationSpaceByShip[leftWeapon.iShipId]
    local rightSlotDestination = shipDestinations and shipDestinations[rightSlot]

    if rightSlotDestination ~= nil then
        return rightSlotDestination
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

local function create_paired_projectile_copy(projectile, leftWeapon, rightWeapon, rightSlot)
    local spaceManager = Hyperspace.App.world.space
    local blueprint = leftWeapon.blueprint
    local typeName = blueprint.typeName
    local copyLaunchPoint = get_copy_launch_point(projectile, rightWeapon)
    local copyTargetPoint = get_copy_target_point(projectile, leftWeapon, rightSlot)
    local copyDestinationSpace = get_copy_destination_space(projectile, leftWeapon, rightSlot)

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
    for queuedProjectile in vter(weapon.queuedProjectiles) do
        queuedProjectile:Kill()
    end

    weapon.queuedProjectiles:clear()
end

local function add_weapon_by_name(weaponName)
    local blueprint = Hyperspace.Blueprints:GetWeaponBlueprint(weaponName)

    if not blueprint then
        print("SC PAIRED ERROR | Missing weapon blueprint: " .. tostring(weaponName))
        return false
    end

    Hyperspace.App.gui.equipScreen:AddWeapon(blueprint, true, false)
    return true
end

local function get_weapon_names_from_slot(shipManager, startSlot)
    local weaponNames = {}
    local weapons = shipManager.weaponSystem.weapons

    for i = startSlot, weapons:size() - 1 do
        table.insert(weaponNames, weapons[i].blueprint.name)
    end

    return weaponNames
end

local function remove_weapons_from_slot_to_end(shipManager, startSlot)
    local weapons = shipManager.weaponSystem.weapons

    while weapons:size() > startSlot do
        shipManager.weaponSystem:RemoveWeapon(startSlot)
    end
end

local function replace_weapon_in_slot(shipManager, weaponSlot, newWeaponName)
    local weapons = shipManager.weaponSystem.weapons

    if weaponSlot < 0 or weaponSlot >= weapons:size() then return false end

    if not Hyperspace.Blueprints:GetWeaponBlueprint(newWeaponName) then
        print("SC PAIRED ERROR | Cannot replace weapon with missing blueprint: " .. tostring(newWeaponName))
        return false
    end

    local tailWeaponNames = get_weapon_names_from_slot(shipManager, weaponSlot)
    tailWeaponNames[1] = newWeaponName

    remove_weapons_from_slot_to_end(shipManager, weaponSlot)

    for _, weaponName in ipairs(tailWeaponNames) do
        add_weapon_by_name(weaponName)
    end

    return true
end

local function restore_unpaired_target_weapons(shipManager)
    local weapons = shipManager.weaponSystem.weapons
    local pairSlots = build_valid_pair_slots(shipManager)

    for i = 0, weapons:size() - 1 do
        local weapon = weapons[i]
        local originalWeaponName =
            get_original_name_from_target_name(weapon.blueprint.name)

        if originalWeaponName then
            local pairData = pairSlots[i]

            if not pairData or pairData.secondarySlot ~= i then
                if Hyperspace.Blueprints:GetWeaponBlueprint(originalWeaponName) then
                    return replace_weapon_in_slot(shipManager, i, originalWeaponName)
                end
            end
        end
    end

    return false
end

local function replace_paired_secondary_weapons(shipManager)
    local weapons = shipManager.weaponSystem.weapons
    local pairSlots = build_valid_pair_slots(shipManager)
    local i = 0

    while i <= weapons:size() - 2 do
        local pairData = pairSlots[i]

        if pairData and pairData.primarySlot == i then
            local rightWeaponName = pairData.secondaryWeapon.blueprint.name

            if not string_ends_with(rightWeaponName, TARGET_SUFFIX) then
                local targetWeaponName = rightWeaponName .. TARGET_SUFFIX

                if Hyperspace.Blueprints:GetWeaponBlueprint(targetWeaponName) then
                    return replace_weapon_in_slot(shipManager, pairData.secondarySlot, targetWeaponName)
                end
            end

            i = i + 2
        else
            i = i + 1
        end
    end

    return false
end

local function disable_all_paired_secondary_autofire(shipManager)
    local weapons = shipManager.weaponSystem.weapons
    local pairSlots = build_valid_pair_slots(shipManager)
    local i = 0

    while i <= weapons:size() - 2 do
        local pairData = pairSlots[i]

        if pairData and pairData.primarySlot == i then
            pairData.secondaryWeapon.autoFiring = false
            i = i + 2
        else
            i = i + 1
        end
    end
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if not Hyperspace.App or not Hyperspace.App.world or not Hyperspace.App.world.bStartedGame then return end
    if shipManager.iShipId ~= 0 or not shipManager.weaponSystem then return end

    if restore_unpaired_target_weapons(shipManager) then return end
    if replace_paired_secondary_weapons(shipManager) then return end

    disable_all_paired_secondary_autofire(shipManager)
end)

script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_FIRE,
    function(projectile, weapon)
        if not Hyperspace.App or not Hyperspace.App.world or not Hyperspace.App.world.bStartedGame then return end
        if userdata_table(projectile, "mods.sc.paired_weapons").isPairedCopy then return end
        if not get_weapon_group(weapon) then return end

        local weaponSlot = get_weapon_slot(weapon)
        if weaponSlot == nil then return end

        store_projectile_data(projectile, weapon, weaponSlot)

        local ship = Hyperspace.ships(weapon.iShipId)
        if not ship then return end

        local pairData = build_valid_pair_slots(ship)[weaponSlot]
        if not pairData then return end

        if pairData.secondarySlot == weaponSlot then
            projectile:Kill()
            clear_weapon_projectiles(weapon)
            return
        end

        create_paired_projectile_copy(projectile, weapon, pairData.secondaryWeapon, pairData.secondarySlot)

        clear_weapon_projectiles(pairData.secondaryWeapon)
    end
)