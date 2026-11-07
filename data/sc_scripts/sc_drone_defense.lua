--[[
DESCRIPTION: Core behavior for Terran Defense Matrix drones.
        - Registers drones with the <sc-active-shield> tag.
        - Determines whether tagged drones are deployed, powered, alive, and ready.
        - Creates the configured number of super-shield layers.
        - Uses each drone's native weapon cooldown between activations.
TAG: <sc-active-shield value="#"/>
DEPENDENCIES: sc_tag.lua, Multiverse vter
SOURCE CREDIT: TNE_ACTIVE_DRONE_LUA.lua, Fusion drones.lua
]]

local vter = mods.multiverse.vter

mods.sc.defenseMatrix = mods.sc.defenseMatrix or {}
local defense = mods.sc.defenseMatrix

local activeDrones = {}
local activeShieldCycleSpent = setmetatable({}, {__mode = "k"})

mods.sc.tag.register("drone", "sc-active-shield", activeDrones, "value")

function defense.has_tag(drone)
    return drone
        and drone.blueprint
        and activeDrones[drone.blueprint.name] ~= nil
end

local function get_shield_levels(drone)
    local shieldLevels = tonumber(activeDrones[drone.blueprint.name]) or 1
    return math.max(1, math.floor(shieldLevels))
end

function defense.is_active(drone)
    return defense.has_tag(drone)
        and drone.deployed
        and drone.powered
        and not drone.bDead
end

function defense.get_owner_id(drone)
    if not drone then return nil end
    return drone:GetOwnerId()
end

local function update_cycle_lock(drone)
    if not defense.has_tag(drone) then return end

    if activeShieldCycleSpent[drone] and (drone.weaponCooldown) <= 0 then
        activeShieldCycleSpent[drone] = nil
    end
end

function defense.update_cycle_locks(shipManager)
    for drone in vter(shipManager.spaceDrones) do
        update_cycle_lock(drone)
    end
end

local function drone_can_activate(drone, ignoreCooldown)
    if not defense.is_active(drone) then return false end

    update_cycle_lock(drone)

    if activeShieldCycleSpent[drone] then
        return false
    end

    if not ignoreCooldown and (drone.weaponCooldown or 0) > 0 then
        return false
    end

    return true
end

function defense.has_active_drone(shipManager)
    for drone in vter(shipManager.spaceDrones) do
        if defense.is_active(drone) then
            return true
        end
    end

    return false
end

local function get_ready_drone(shipManager)
    for drone in vter(shipManager.spaceDrones) do
        if drone_can_activate(drone, false) then
            return drone
        end
    end

    return nil
end

local function put_drone_on_cooldown(drone)
    local cooldown = drone:GetWeaponCooldown()

    if cooldown > 0 then
        drone.weaponCooldown = cooldown
    end
end

local function add_super_shield(shipManager)
    local shieldSystem = shipManager.shieldSystem
    if not shieldSystem then return end

    local shieldLocation = shieldSystem.superUpLoc
    shieldSystem:AddSuperShield(Hyperspace.Point(shieldLocation.x, shieldLocation.y))
end

function defense.activate(shipManager, activeShieldDrone, ignoreCooldown)
    activeShieldDrone = activeShieldDrone or get_ready_drone(shipManager)

    if not activeShieldDrone or not drone_can_activate(activeShieldDrone, ignoreCooldown) then
        return false
    end

    local shieldLevels = get_shield_levels(activeShieldDrone)

    for _ = 1, shieldLevels do
        add_super_shield(shipManager)
    end

    activeShieldCycleSpent[activeShieldDrone] = true
    put_drone_on_cooldown(activeShieldDrone)

    return true
end