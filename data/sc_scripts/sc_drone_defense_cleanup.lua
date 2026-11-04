--[[
DESCRIPTION: Removes Defense Matrix super shields after incoming threats have ended.
        - Tracks projectiles currently traveling toward each ship.
        - Keeps temporary shields while projectile or beam danger remains.
        - Clears all super shields once no threats remain.
DEPENDENCIES: sc_drone_defense.lua, sc_drone_defense_threats.lua, Multiverse vter
]]

local vter = mods.multiverse.vter
local defense = mods.sc.defenseMatrix

local function count_incoming_enemy_projectiles(shipId)
    local count = 0

    for projectile in vter(Hyperspace.App.world.space.projectiles) do
        local projectileIsActive = projectile._targetable ~= false and not projectile.passedTarget
        local projectileIsEnemy = projectile.ownerId ~= shipId
        local projectileIsAtShip = projectile.currentSpace == shipId or projectile.destinationSpace == shipId

        if projectileIsActive and projectileIsEnemy and projectileIsAtShip then
            count = count + 1
        end
    end

    return count
end

local function pop_all_super_shields(shipManager)
    local shieldSystem = shipManager.shieldSystem
    if not shieldSystem then return end

    local superPower = shieldSystem.shields.power.super
    local currentSuper = superPower.first
    if currentSuper <= 0 then return end

    local popLocation = shieldSystem.superUpLoc

    for _ = 1, currentSuper do
        shieldSystem:CollisionReal(popLocation.x, popLocation.y, Hyperspace.Damage(), true)
    end

    superPower.first = 0
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    local shipId = shipManager.iShipId
    local frameTime = Hyperspace.FPS.SpeedFactor / 16

    defense.update_cycle_locks(shipManager)
    defense.update_threat_timers(shipId, frameTime)

    if not defense.has_active_drone(shipManager) then return end

    local hasActiveThreat = count_incoming_enemy_projectiles(shipId) > 0
        or defense.has_recent_threat(shipId)

    if hasActiveThreat then return end

    pop_all_super_shields(shipManager)
end)