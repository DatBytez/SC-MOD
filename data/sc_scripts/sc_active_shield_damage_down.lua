--[[
DESCRIPTION: Active shield layers reduce incoming projectile damage instead of only blocking it.
        - Based on the TNE SHIELD_COLLISION damage-down method.
        - Intended to load after sc_drone_defense.lua.
        - Only affects ships with a deployed, powered, living <sc-active-shield/> drone.
        - Uses current super shield layers as the active shield capacity.
        - Reduces hull, system, crew, and ion damage fields.
        - If all reduced damage fields reach 0, the projectile is killed.
]]

local vter = mods.multiverse.vter

mods.sc = mods.sc or {}
mods.sc.activeShieldDamageDown = mods.sc.activeShieldDamageDown or {
    hits = 0,
    killed = 0,
    passed = 0,
    last = nil
}

local activeShieldState = mods.sc.activeShieldDamageDown
local shieldCollisionData = setmetatable({}, {__mode = "k"})

local DAMAGE_FIELDS = {
    "iDamage",
    "iSystemDamage",
    "iPersDamage",
    "iIonDamage"
}

local function ship_has_active_shield_drone(shipManager)
    if not shipManager or not mods.sc.activeShield then return false end

    for drone in vter(shipManager.spaceDrones) do
        if drone and drone.blueprint
            and mods.sc.activeShield[drone.blueprint.name]
            and drone.deployed
            and drone.powered
            and not drone.bDead then
            return true
        end
    end

    return false
end

local function get_super_shields(shipManager)
    local shieldSystem = shipManager and shipManager.shieldSystem
    if not shieldSystem then return 0 end

    return shieldSystem.shields.power.super.first or 0
end

local function get_projectile_name(projectile)
    if projectile and projectile.extend and projectile.extend.name then
        return projectile.extend.name
    end

    local success, name = pcall(function()
        return Hyperspace.Get_Projectile_Extend(projectile).name
    end)

    if success then
        return name
    end

    return nil
end

local function get_damage_amount(damage)
    local amount = 0

    if not damage then return amount end

    for _, field in ipairs(DAMAGE_FIELDS) do
        local value = damage[field] or 0

        if value > amount then
            amount = value
        end
    end

    return amount
end

local function copy_damage_fields(damage)
    local values = {}

    if not damage then return values end

    for _, field in ipairs(DAMAGE_FIELDS) do
        values[field] = damage[field] or 0
    end

    return values
end

local function reduce_damage_fields(damage, reduction)
    if not damage or reduction <= 0 then return end

    for _, field in ipairs(DAMAGE_FIELDS) do
        local value = damage[field]

        if value and value > 0 then
            damage[field] = math.max(0, value - reduction)
        end
    end
end

local function damage_fields_are_zero(damage)
    if not damage then return true end

    for _, field in ipairs(DAMAGE_FIELDS) do
        if (damage[field] or 0) > 0 then
            return false
        end
    end

    return true
end

local function consume_active_shield_layers(shipManager, preCollisionLayers, consumedLayers)
    local shieldSystem = shipManager and shipManager.shieldSystem
    if not shieldSystem then return end

    local superPower = shieldSystem.shields.power.super
    local desiredLayers = math.max(0, preCollisionLayers - consumedLayers)

    if superPower.first > desiredLayers then
        superPower.first = desiredLayers
    end
end

script.on_internal_event(Defines.InternalEvents.SHIELD_COLLISION_PRE, function(shipManager, projectile, damage, response)
    if not shipManager or not projectile or not damage then
        return Defines.Chain.CONTINUE
    end

    if projectile.ownerId == shipManager.iShipId then
        return Defines.Chain.CONTINUE
    end

    if not ship_has_active_shield_drone(shipManager) then
        return Defines.Chain.CONTINUE
    end

    local superLayers = get_super_shields(shipManager)
    if superLayers <= 0 then
        return Defines.Chain.CONTINUE
    end

    local projectileDamage = projectile.damage or damage
    local damageAmount = get_damage_amount(projectileDamage)
    if damageAmount <= 0 then
        return Defines.Chain.CONTINUE
    end

    shieldCollisionData[projectile] = {
        shipId = shipManager.iShipId,
        projectileName = get_projectile_name(projectile),
        preCollisionLayers = superLayers,
        consumedLayers = math.min(superLayers, damageAmount),
        before = copy_damage_fields(projectileDamage)
    }

    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.SHIELD_COLLISION, function(shipManager, projectile, damage, response)
    if not shipManager or not projectile then
        return Defines.Chain.CONTINUE
    end

    local collisionData = shieldCollisionData[projectile]
    if not collisionData or collisionData.shipId ~= shipManager.iShipId then
        return Defines.Chain.CONTINUE
    end

    local reduction = collisionData.consumedLayers or 0
    if reduction <= 0 then
        shieldCollisionData[projectile] = nil
        return Defines.Chain.CONTINUE
    end

    reduce_damage_fields(projectile.damage, reduction)
    reduce_damage_fields(damage, reduction)
    consume_active_shield_layers(shipManager, collisionData.preCollisionLayers, reduction)

    local after = copy_damage_fields(projectile.damage or damage)
    local killed = damage_fields_are_zero(projectile.damage or damage)

    if killed then
        projectile:Kill()
        activeShieldState.killed = activeShieldState.killed + 1
    else
        activeShieldState.passed = activeShieldState.passed + 1
    end

    activeShieldState.hits = activeShieldState.hits + 1
    activeShieldState.last = {
        shipId = shipManager.iShipId,
        projectileName = collisionData.projectileName,
        preCollisionLayers = collisionData.preCollisionLayers,
        consumedLayers = reduction,
        before = collisionData.before,
        after = after,
        killed = killed
    }

    shieldCollisionData[projectile] = nil

    return Defines.Chain.CONTINUE
end)
