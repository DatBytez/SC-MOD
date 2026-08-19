--[[
DESCRIPTION: Enemy AI for Terran SCV hull repair.
        - At 5 hull or less, activates enemy terran_scv LAUNCH_REPAIR power.
DEPENDENCIES: Multiverse vter; sc_drone_scv.lua
]]

local vter = mods.multiverse.vter

local SCV_RACE = "terran_scv"
local SCV_REPAIR_POWER = "LAUNCH_REPAIR"
local ENEMY_HULL_THRESHOLD = 5

local repairUsedBelowThreshold = false

local function is_available_enemy_scv(crew)
    return crew.iShipId == 1
        and crew:GetSpecies() == SCV_RACE
        and not crew:IsDead()
        and not crew:OutOfGame()
end

local function try_activate_enemy_scv_repair(enemyShip)
    for crew in vter(enemyShip.vCrewList) do
        if is_available_enemy_scv(crew) then
            for power in vter(crew.extend.crewPowers) do
                if power.def.name == SCV_REPAIR_POWER
                    and power.enabled
                    and power:PowerReady() == 1 then
                    power:PreparePower()
                    return true
                end
            end
        end
    end

    return false
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if shipManager.iShipId ~= 0 then return end

    local enemyShip = Hyperspace.Global.GetInstance():GetShipManager(1)
    if not enemyShip then
        repairUsedBelowThreshold = false
        return
    end

    local hull = enemyShip.ship.hullIntegrity
    local currentHull = hull.first

    if currentHull <= 0 or currentHull > ENEMY_HULL_THRESHOLD then
        repairUsedBelowThreshold = false
        return
    end

    if repairUsedBelowThreshold or currentHull >= hull.second then return end

    if try_activate_enemy_scv_repair(enemyShip) then
        repairUsedBelowThreshold = true
    end
end)