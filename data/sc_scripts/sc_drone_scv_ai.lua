-- ------------------------
-- SCV AUTO HULL REPAIR - ENEMY AI
-- ------------------------
-- Automatically uses one enemy terran_scv hull repair ability when the enemy ship
-- is alive, missing hull, and reaches ENEMY_HULL_THRESHOLD hull or lower.
--
-- This intentionally calls the existing LAUNCH_REPAIR power, so the existing
-- sc_drone_scv.lua ACTIVATE_POWER handler still performs the actual hull-repair
-- drone spawn.

local SCV_RACE = "terran_scv"
local SCV_REPAIR_POWER = "LAUNCH_REPAIR"
local ENEMY_SHIP_ID = 1
local ENEMY_HULL_THRESHOLD = 5
local POWER_READY = 1 -- From Hyperspace PowerReadyState: POWER_READY

-- If true, only one enemy SCV repair is automatically launched per threshold event.
-- Set this to false if you want additional enemy SCVs to keep launching while the enemy
-- remains at 5 hull or less and the enemy ship is still missing hull.
local ONE_REPAIR_PER_THRESHOLD_EVENT = true

local usedRepairForCurrentThresholdEvent = false

local function vter(cvec)
    if not cvec then
        return function() return nil end
    end

    local i = -1
    local n = cvec:size()
    return function()
        i = i + 1
        if i < n then
            return cvec[i]
        end
    end
end

local function get_ship_manager(shipId)
    local global = Hyperspace.Global.GetInstance()
    if not global then return nil end
    return global:GetShipManager(shipId)
end

local function get_current_hull(shipManager)
    if not shipManager or not shipManager.ship or not shipManager.ship.hullIntegrity then
        return nil
    end

    return shipManager.ship.hullIntegrity.first or 0
end

local function ship_missing_hull(shipManager)
    if not shipManager or not shipManager.ship or not shipManager.ship.hullIntegrity then
        return false
    end

    local hull = shipManager.ship.hullIntegrity
    return (hull.first or 0) < (hull.second or 0)
end

local function is_valid_enemy_scv(crew)
    if not crew then return false end
    if crew:IsDead() then return false end
    if crew:OutOfGame() then return false end
    if crew.iShipId ~= ENEMY_SHIP_ID then return false end
    return crew:GetSpecies() == SCV_RACE
end

local function try_activate_enemy_scv_repair(enemyShip)
    if not enemyShip or not enemyShip.vCrewList then return false end

    for crew in vter(enemyShip.vCrewList) do
        if is_valid_enemy_scv(crew) and crew.extend and crew.extend.crewPowers then
            for power in vter(crew.extend.crewPowers) do
                if power and power.def and power.def.name == SCV_REPAIR_POWER then
                    if power.enabled and power:PowerReady() == POWER_READY then
                        -- Use PreparePower instead of ActivatePower directly so Hyperspace
                        -- sets the cooldown, charge count, powerRoom, powerShip, and animation
                        -- exactly like a normal button press.
                        power:PreparePower()
                        return true
                    end
                end
            end
        end
    end

    return false
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    -- Run this logic only once per frame from the player ship loop,
    -- but only inspect the enemy ship and enemy-owned SCVs.
    if not shipManager or shipManager.iShipId ~= 0 then return end

    local enemyShip = get_ship_manager(ENEMY_SHIP_ID)
    local enemyHull = get_current_hull(enemyShip)

    -- Reset between combats / after the enemy is gone or destroyed.
    if not enemyShip or not enemyHull or enemyHull <= 0 then
        usedRepairForCurrentThresholdEvent = false
        return
    end

    -- If the enemy is above the threshold again, allow a future threshold crossing
    -- to trigger another automatic repair.
    if enemyHull > ENEMY_HULL_THRESHOLD then
        usedRepairForCurrentThresholdEvent = false
        return
    end

    if ONE_REPAIR_PER_THRESHOLD_EVENT and usedRepairForCurrentThresholdEvent then return end
    if not ship_missing_hull(enemyShip) then return end

    if try_activate_enemy_scv_repair(enemyShip) then
        usedRepairForCurrentThresholdEvent = true
    end
end)
