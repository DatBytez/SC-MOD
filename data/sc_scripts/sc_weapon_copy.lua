local userdata_table = mods.multiverse.userdata_table

mods.sc_projectile_copy = mods.sc_projectile_copy or {}

mods.multiverse.weaponTagParsers = mods.multiverse.weaponTagParsers or {}
local weaponTagParsers = mods.multiverse.weaponTagParsers

local copyShotWeapons = {}
local targetCoordinatesByShip = {
    [0] = {},
    [1] = {}
}
local destinationSpaceByShip = {
    [0] = {},
    [1] = {}
}

local USE_RIGHT_SLOT_TARGET = true

table.insert(weaponTagParsers, function(weaponNode)
    local copyNode = weaponNode:first_node("sc-copy-shot")
    if not copyNode then return end

    local nameAttr = weaponNode:first_attribute("name")
    if not nameAttr then return end

    local copyCount = 1
    local amountAttr = copyNode:first_attribute("amount")
    if amountAttr then
        local parsedAmount = tonumber(amountAttr:value())
        if parsedAmount and parsedAmount > 0 then
            copyCount = math.floor(parsedAmount)
        end
    end

    copyShotWeapons[nameAttr:value()] = copyCount
end)

local function mark_as_copy(projectile)
    if not projectile then return end

    local tableData = userdata_table(projectile, "mods.sc.projectile_copy")
    tableData.isCopy = true
end

local function is_copy(projectile)
    if not projectile then return false end

    local tableData = userdata_table(projectile, "mods.sc.projectile_copy")
    return tableData.isCopy == true
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

local function get_copy_launch_point(projectile, weapon)
    if not projectile or not weapon then return nil end

    local rightSlot = get_right_slot(weapon)
    if rightSlot == nil then
        return pointf_from_point(projectile.position)
    end

    local rightWeapon = get_weapon_for_slot(weapon.iShipId, rightSlot)
    local predictedRightLaunchPoint = get_predicted_weapon_launch_point(rightWeapon)

    if predictedRightLaunchPoint then
        return Hyperspace.Pointf(predictedRightLaunchPoint.x, predictedRightLaunchPoint.y)
    end

    return pointf_from_point(projectile.position)
end

local function get_copy_target_point(projectile, weapon, options)
    if not projectile or not weapon then return nil end

    if options and options.useOriginalTarget then
        return pointf_from_point(projectile.target)
    end

    if not USE_RIGHT_SLOT_TARGET then
        return pointf_from_point(projectile.target)
    end

    local rightSlot = get_right_slot(weapon)
    if rightSlot == nil then
        return pointf_from_point(projectile.target)
    end

    local rightSlotTargetPoint = get_cached_target_point_for_slot(weapon.iShipId, rightSlot)

    if rightSlotTargetPoint then
        return Hyperspace.Pointf(rightSlotTargetPoint.x, rightSlotTargetPoint.y)
    end

    return pointf_from_point(projectile.target)
end

local function get_copy_destination_space(projectile, weapon, options)
    if not projectile or not weapon then return nil end

    if options and options.useOriginalTarget then
        return projectile.destinationSpace
    end

    if not USE_RIGHT_SLOT_TARGET then
        return projectile.destinationSpace
    end

    local rightSlot = get_right_slot(weapon)
    if rightSlot == nil then
        return projectile.destinationSpace
    end

    local rightSlotDestinationSpace = get_cached_destination_space_for_slot(weapon.iShipId, rightSlot)

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
    mark_as_copy(dst)
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

local function create_projectile_copy(projectile, weapon, options)
    if not projectile or not weapon or not weapon.blueprint then return nil end

    local spaceManager = Hyperspace.App.world.space
    local blueprint = weapon.blueprint
    local typeName = blueprint.typeName
    local copyLaunchPoint = get_copy_launch_point(projectile, weapon)
    local copyTargetPoint = get_copy_target_point(projectile, weapon, options)
    local copyDestinationSpace = get_copy_destination_space(projectile, weapon, options)

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

function mods.sc_projectile_copy.create_projectile_copy(projectile, weapon, options)
    return create_projectile_copy(projectile, weapon, options)
end

function mods.sc_projectile_copy.store_projectile_data(projectile, weapon)
    return store_projectile_data(projectile, weapon)
end

function mods.sc_projectile_copy.is_copy(projectile)
    return is_copy(projectile)
end

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    if not projectile or not weapon or not weapon.blueprint then return end

    if not is_copy(projectile) then
        store_projectile_data(projectile, weapon)
    end

    if is_copy(projectile) then return end

    local copyCount = copyShotWeapons[weapon.blueprint.name]
    if not copyCount then return end

    for i = 1, copyCount do
        create_projectile_copy(projectile, weapon)
    end
end)
