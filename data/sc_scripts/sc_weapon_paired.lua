--[[
DESCRIPTION: Paired weapons using copied projectiles and target-weapon replacement.
    - Weapons use <sc_paired group="..."/>.
    - A paired weapon only works with the weapon slot immediately to its RIGHT.
    - The right weapon must also have <sc_paired> and must be in the same group.
    - The right weapon is replaced with a blueprint of the same name with "_TARGET" appended while paired.
    - The right weapon is restored when the valid primary is no longer immediately to its left.
    - Replacement protects earlier weapon slots by only popping the changed slot and everything after it.
    - Popped weapons are re-added in their original order with only the changed slot swapped.
    - The secondary weapon has autoFiring forced off while paired.
    - Ship-loop pairing logic is disabled unless Hyperspace.App.world.bStartedGame is true.
    - Pairing is built left-to-right as non-overlapping pairs of two.
    - The left weapon fires normally and creates a copied projectile from the right weapon's launch point.
    - The right weapon's own projectiles are killed/cleared so only the left weapon's copied projectiles apply damage.
DEPENDENCIES: mv_core
]]

local vter = mods.multiverse.vter
local userdata_table = mods.multiverse.userdata_table

mods.sc_paired_weapons = mods.sc_paired_weapons or {}

mods.multiverse.weaponTagParsers = mods.multiverse.weaponTagParsers or {}
local weaponTagParsers = mods.multiverse.weaponTagParsers

local pairedGroupById = {}
local targetCoordinatesByShip = {
    [0] = {},
    [1] = {}
}
local destinationSpaceByShip = {
    [0] = {},
    [1] = {}
}

local USE_RIGHT_SLOT_TARGET = true
local TARGET_SUFFIX = "_PAIRED"
local function run_has_started()
    return Hyperspace.App
        and Hyperspace.App.world
        and Hyperspace.App.world.bStartedGame
end

local function should_run_paired_weapon_logic(shipManager)
    if not run_has_started() then return false end
    if not shipManager then return false end
    if shipManager.iShipId ~= 0 then return false end

    return true
end

table.insert(weaponTagParsers, function(weaponNode)
    local pairedNode = weaponNode:first_node("sc_paired")
    if pairedNode then
        local nameAttr = weaponNode:first_attribute("name")
        if not nameAttr then return end

        local weaponName = nameAttr:value()
        local groupAttr = pairedNode:first_attribute("group")
        local groupId = groupAttr and groupAttr:value() or "default"

        pairedGroupById[weaponName] = groupId
        pairedGroupById[weaponName .. TARGET_SUFFIX] = groupId
    end
end)

local function mark_as_paired_copy(projectile)
    if not projectile then return end

    local tableData = userdata_table(projectile, "mods.sc.paired_weapons")
    tableData.isPairedCopy = true
end

local function is_paired_copy(projectile)
    if not projectile then return false end

    local tableData = userdata_table(projectile, "mods.sc.paired_weapons")
    return tableData.isPairedCopy == true
end

local function pointf_from_point(point)
    if not point then return nil end
    return Hyperspace.Pointf(point.x, point.y)
end

local function copy_custom_damage(src, dst)
    if not src or not dst then return end
    if not src.extend or not dst.extend then return end
    if not src.extend.customDamage or not dst.extend.customDamage then return end

    dst.extend.customDamage.def = src.extend.customDamage.def
    dst.extend.customDamage.sourceShipId = src.extend.customDamage.sourceShipId
    dst.extend.customDamage.accuracyMod = src.extend.customDamage.accuracyMod
    dst.extend.customDamage.droneAccuracyMod = src.extend.customDamage.droneAccuracyMod
end

local function string_ends_with(value, suffix)
    if not value or not suffix then return false end

    return string.sub(value, -string.len(suffix)) == suffix
end

local function get_original_name_from_target_name(weaponName)
    if not string_ends_with(weaponName, TARGET_SUFFIX) then return nil end

    return string.sub(weaponName, 1, string.len(weaponName) - string.len(TARGET_SUFFIX))
end

local function is_target_weapon_name(weaponName)
    return get_original_name_from_target_name(weaponName) ~= nil
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

local function get_weapon_for_slot(shipId, weaponSlot)
    if shipId == nil or weaponSlot == nil then return nil end

    local ship = Hyperspace.ships(shipId)
    if not ship or not ship.weaponSystem then return nil end

    local weapons = ship.weaponSystem.weapons
    if weaponSlot < 0 or weaponSlot >= weapons:size() then return nil end

    return weapons[weaponSlot]
end

local function get_right_slot(weapon)
    local weaponSlot = get_weapon_slot(weapon)
    if weaponSlot == nil then return nil end

    return weaponSlot + 1
end

local function get_left_slot(weapon)
    local weaponSlot = get_weapon_slot(weapon)
    if weaponSlot == nil then return nil end
    if weaponSlot <= 0 then return nil end

    return weaponSlot - 1
end

local function primary_matches_secondary(primaryWeapon, secondaryWeapon)
    if not primaryWeapon or not secondaryWeapon then return false end
    if not primaryWeapon.blueprint or not secondaryWeapon.blueprint then return false end

    local primaryGroup = get_weapon_group(primaryWeapon)
    local secondaryGroup = get_weapon_group(secondaryWeapon)

    if not primaryGroup or not secondaryGroup then return false end

    return primaryGroup == secondaryGroup
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

local function get_matching_right_weapon(weapon)
    if not weapon then return nil end

    local ship = Hyperspace.ships(weapon.iShipId)
    local weaponSlot = get_weapon_slot(weapon)

    if not ship or weaponSlot == nil then return nil end

    local pairSlots = build_valid_pair_slots(ship)
    local pairData = pairSlots[weaponSlot]

    if not pairData or pairData.primarySlot ~= weaponSlot then return nil end

    return pairData.secondaryWeapon
end

local function get_matching_left_weapon(weapon)
    if not weapon then return nil end

    local ship = Hyperspace.ships(weapon.iShipId)
    local weaponSlot = get_weapon_slot(weapon)

    if not ship or weaponSlot == nil then return nil end

    local pairSlots = build_valid_pair_slots(ship)
    local pairData = pairSlots[weaponSlot]

    if not pairData or pairData.secondarySlot ~= weaponSlot then return nil end

    return pairData.primaryWeapon
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

    local emitPointX = 0
    local emitPointY = 0
    local vertMod = 1

    if weapon.mount.mirror then
        vertMod = -1
    end

    emitPointX = emitPointX + ship.shipImage.x + shipGraph.shipBox.x + weaponAnim.renderPoint.x + slideOffset.x
    emitPointY = emitPointY + ship.shipImage.y + shipGraph.shipBox.y + weaponAnim.renderPoint.y + slideOffset.y

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

local function store_projectile_data(projectile, weapon)
    if not projectile or not weapon then return end

    local shipId = weapon.iShipId
    local weaponSlot = get_weapon_slot(weapon)

    if shipId == nil or weaponSlot == nil then return end

    if not targetCoordinatesByShip[shipId] then
        targetCoordinatesByShip[shipId] = {}
    end

    if not destinationSpaceByShip[shipId] then
        destinationSpaceByShip[shipId] = {}
    end

    targetCoordinatesByShip[shipId][weaponSlot] = pointf_from_point(projectile.target)
    destinationSpaceByShip[shipId][weaponSlot] = projectile.destinationSpace
end

local function get_cached_target_point_for_slot(shipId, weaponSlot)
    if shipId == nil or weaponSlot == nil then return nil end

    local shipTargetCoordinates = targetCoordinatesByShip[shipId]
    if not shipTargetCoordinates then return nil end

    return shipTargetCoordinates[weaponSlot]
end

local function get_cached_destination_space_for_slot(shipId, weaponSlot)
    if shipId == nil or weaponSlot == nil then return nil end

    local shipDestinationSpaces = destinationSpaceByShip[shipId]
    if not shipDestinationSpaces then return nil end

    return shipDestinationSpaces[weaponSlot]
end

local function get_copy_launch_point(projectile, leftWeapon, rightWeapon)
    if not projectile then return nil end

    local predictedRightLaunchPoint = get_predicted_weapon_launch_point(rightWeapon)
    if predictedRightLaunchPoint then
        return Hyperspace.Pointf(predictedRightLaunchPoint.x, predictedRightLaunchPoint.y)
    end

    return pointf_from_point(projectile.position)
end

local function get_copy_target_point(projectile, leftWeapon)
    if not projectile or not leftWeapon then return nil end

    if not USE_RIGHT_SLOT_TARGET then
        return pointf_from_point(projectile.target)
    end

    local rightSlot = get_right_slot(leftWeapon)
    if rightSlot == nil then
        return pointf_from_point(projectile.target)
    end

    local rightSlotTargetPoint = get_cached_target_point_for_slot(leftWeapon.iShipId, rightSlot)
    if rightSlotTargetPoint then
        return Hyperspace.Pointf(rightSlotTargetPoint.x, rightSlotTargetPoint.y)
    end

    return pointf_from_point(projectile.target)
end

local function get_copy_destination_space(projectile, leftWeapon)
    if not projectile or not leftWeapon then return nil end

    if not USE_RIGHT_SLOT_TARGET then
        return projectile.destinationSpace
    end

    local rightSlot = get_right_slot(leftWeapon)
    if rightSlot == nil then
        return projectile.destinationSpace
    end

    local rightSlotDestinationSpace = get_cached_destination_space_for_slot(leftWeapon.iShipId, rightSlot)
    if rightSlotDestinationSpace ~= nil then
        return rightSlotDestinationSpace
    end

    return projectile.destinationSpace
end

local function copy_common_projectile_state(src, dst, copyLaunchPoint, copyTargetPoint, copyDestinationSpace)
    if not src or not dst then return end

    local launchPoint = copyLaunchPoint
    if not launchPoint then
        launchPoint = pointf_from_point(src.position)
    end

    local targetPoint = copyTargetPoint
    if not targetPoint then
        targetPoint = pointf_from_point(src.target)
    end

    local destinationSpace = copyDestinationSpace
    if destinationSpace == nil then
        destinationSpace = src.destinationSpace
    end

    dst.position = Hyperspace.Pointf(launchPoint.x, launchPoint.y)
    dst.last_position = Hyperspace.Pointf(launchPoint.x, launchPoint.y)
    dst.target = Hyperspace.Pointf(targetPoint.x, targetPoint.y)
    dst.destinationSpace = destinationSpace
    dst.heading = src.heading
    dst.lifespan = src.lifespan
    dst.speed = Hyperspace.Pointf(src.speed.x, src.speed.y)
    dst.speed_magnitude = src.speed_magnitude
    dst.entryAngle = src.entryAngle
    dst.bBroadcastTarget = src.bBroadcastTarget

    dst:SetDamage(src.damage)
    copy_custom_damage(src, dst)
    mark_as_paired_copy(dst)
end

local function copy_beam_state(src, dst, copyLaunchPoint, copyTargetPoint, copyDestinationSpace)
    copy_common_projectile_state(src, dst, copyLaunchPoint, copyTargetPoint, copyDestinationSpace)

    if not src or not dst then return end

    local launchPoint = copyLaunchPoint
    if not launchPoint then
        launchPoint = pointf_from_point(src.position)
    end

    dst.target1 = Hyperspace.Pointf(src.target1.x, src.target1.y)
    dst.target2 = Hyperspace.Pointf(src.target2.x, src.target2.y)
    dst.sub_start = Hyperspace.Pointf(launchPoint.x, launchPoint.y)
    dst.sub_end = Hyperspace.Pointf(src.sub_end.x, src.sub_end.y)
    dst.shield_end = Hyperspace.Pointf(src.shield_end.x, src.shield_end.y)
    dst.final_end = Hyperspace.Pointf(src.final_end.x, src.final_end.y)

    dst.length = src.length
    dst.timer = src.timer
    dst.start_heading = src.start_heading
end

local function create_paired_projectile_copy(projectile, leftWeapon, rightWeapon)
    if not projectile or not leftWeapon or not leftWeapon.blueprint or not rightWeapon then return nil end

    local spaceManager = Hyperspace.App.world.space
    local blueprint = leftWeapon.blueprint
    local typeName = blueprint.typeName
    local copyLaunchPoint = get_copy_launch_point(projectile, leftWeapon, rightWeapon)
    local copyTargetPoint = get_copy_target_point(projectile, leftWeapon)
    local copyDestinationSpace = get_copy_destination_space(projectile, leftWeapon)

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
        return beam
    end

    if typeName == "BOMB" then
        local bomb = spaceManager:CreateBomb(
            blueprint,
            projectile.ownerId,
            copyTargetPoint,
            copyDestinationSpace
        )

        copy_common_projectile_state(projectile, bomb, copyLaunchPoint, copyTargetPoint, copyDestinationSpace)
        return bomb
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
        return missile
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
    return laser
end

local function clear_weapon_projectiles(weapon)
    if not weapon or not weapon.queuedProjectiles then return end

    for queuedProjectile in vter(weapon.queuedProjectiles) do
        queuedProjectile:Kill()
    end

    weapon.queuedProjectiles:clear()
end

local function get_weapon_names(shipManager)
    local weaponNames = {}

    if not shipManager or not shipManager.weaponSystem then return weaponNames end

    for weapon in vter(shipManager.weaponSystem.weapons) do
        table.insert(weaponNames, weapon.blueprint.name)
    end

    return weaponNames
end

local function remove_all_weapons(shipManager)
    if not shipManager or not shipManager.weaponSystem then return end

    while shipManager.weaponSystem.weapons:size() > 0 do
        shipManager.weaponSystem:RemoveWeapon(0)
    end
end

local function add_weapon_by_name(weaponName)
    local blueprint = Hyperspace.Blueprints:GetWeaponBlueprint(weaponName)
    if not blueprint then
        print("SC PAIRED ERROR | Missing weapon blueprint: " .. tostring(weaponName))
        return false
    end

    local commandGui = Hyperspace.App.gui
    local equipment = commandGui.equipScreen

    equipment:AddWeapon(blueprint, true, false)
    return true
end

local function get_weapon_names_from_slot(shipManager, startSlot)
    local weaponNames = {}

    if not shipManager or not shipManager.weaponSystem then return weaponNames end
    if startSlot == nil then return weaponNames end

    local weapons = shipManager.weaponSystem.weapons

    for i = startSlot, weapons:size() - 1 do
        local weapon = weapons[i]

        if weapon and weapon.blueprint then
            table.insert(weaponNames, weapon.blueprint.name)
        end
    end

    return weaponNames
end

local function remove_weapons_from_slot_to_end(shipManager, startSlot)
    if not shipManager or not shipManager.weaponSystem then return end
    if startSlot == nil then return end

    local weapons = shipManager.weaponSystem.weapons

    while weapons:size() > startSlot do
        shipManager.weaponSystem:RemoveWeapon(startSlot)
    end
end

local function replace_weapon_in_slot(shipManager, weaponSlot, newWeaponName)
    if not shipManager or not shipManager.weaponSystem then return false end
    if weaponSlot == nil or not newWeaponName then return false end

    local weapons = shipManager.weaponSystem.weapons
    if weaponSlot < 0 or weaponSlot >= weapons:size() then return false end

    if not Hyperspace.Blueprints:GetWeaponBlueprint(newWeaponName) then
        print("SC PAIRED ERROR | Cannot replace weapon with missing blueprint: " .. tostring(newWeaponName))
        return false
    end

    local tailWeaponNames = get_weapon_names_from_slot(shipManager, weaponSlot)

    if #tailWeaponNames <= 0 then return false end

    tailWeaponNames[1] = newWeaponName

    remove_weapons_from_slot_to_end(shipManager, weaponSlot)

    for _, weaponName in ipairs(tailWeaponNames) do
        add_weapon_by_name(weaponName)
    end

    return true
end

local function restore_unpaired_target_weapons(shipManager)
    if not shipManager or not shipManager.weaponSystem then return false end

    local weapons = shipManager.weaponSystem.weapons
    if not weapons then return false end

    local pairSlots = build_valid_pair_slots(shipManager)

    for i = 0, weapons:size() - 1 do
        local weapon = weapons[i]

        if weapon and weapon.blueprint and is_target_weapon_name(weapon.blueprint.name) then
            local pairData = pairSlots[i]

            if not pairData or pairData.secondarySlot ~= i then
                local originalWeaponName = get_original_name_from_target_name(weapon.blueprint.name)

                if originalWeaponName and Hyperspace.Blueprints:GetWeaponBlueprint(originalWeaponName) then
                    return replace_weapon_in_slot(shipManager, i, originalWeaponName)
                end
            end
        end
    end

    return false
end

local function replace_paired_secondary_weapons(shipManager)
    if not shipManager or not shipManager.weaponSystem then return false end

    local weapons = shipManager.weaponSystem.weapons
    if not weapons then return false end

    local pairSlots = build_valid_pair_slots(shipManager)

    local i = 0
    while i <= weapons:size() - 2 do
        local pairData = pairSlots[i]

        if pairData and pairData.primarySlot == i then
            local rightWeapon = pairData.secondaryWeapon

            if rightWeapon and rightWeapon.blueprint then
                local rightWeaponName = rightWeapon.blueprint.name

                if not string_ends_with(rightWeaponName, TARGET_SUFFIX) then
                    local targetWeaponName = rightWeaponName .. TARGET_SUFFIX

                    if Hyperspace.Blueprints:GetWeaponBlueprint(targetWeaponName) then
                        return replace_weapon_in_slot(shipManager, pairData.secondarySlot, targetWeaponName)
                    end
                end
            end

            i = i + 2
        else
            i = i + 1
        end
    end

    return false
end

local function disable_secondary_autofire(secondaryWeapon)
    if not secondaryWeapon then return end

    if secondaryWeapon.autoFiring then
        secondaryWeapon.autoFiring = false
    end
end

local function disable_all_paired_secondary_autofire(shipManager)
    if not shipManager or not shipManager.weaponSystem then return end

    local weapons = shipManager.weaponSystem.weapons
    if not weapons then return end

    local pairSlots = build_valid_pair_slots(shipManager)

    local i = 0
    while i <= weapons:size() - 2 do
        local pairData = pairSlots[i]

        if pairData and pairData.primarySlot == i then
            disable_secondary_autofire(pairData.secondaryWeapon)
            i = i + 2
        else
            i = i + 1
        end
    end
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if not should_run_paired_weapon_logic(shipManager) then return end

    if restore_unpaired_target_weapons(shipManager) then return end

    if replace_paired_secondary_weapons(shipManager) then return end

    disable_all_paired_secondary_autofire(shipManager)
end)

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    if not projectile or not weapon or not weapon.blueprint then return end
    if not run_has_started() then return end

    if is_paired_copy(projectile) then return end

    local weaponGroup = get_weapon_group(weapon)
    if not weaponGroup then return end

    store_projectile_data(projectile, weapon)

    local leftWeapon = get_matching_left_weapon(weapon)
    if leftWeapon then
        projectile:Kill()
        clear_weapon_projectiles(weapon)
        return
    end

    local rightWeapon = get_matching_right_weapon(weapon)
    if not rightWeapon then return end

    create_paired_projectile_copy(projectile, weapon, rightWeapon)
    clear_weapon_projectiles(rightWeapon)
end)
