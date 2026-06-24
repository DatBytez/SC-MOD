-- ------------------------
-- TERRAN SHIP REPAIR HULL
-- ------------------------
-- If a ship has TERRAN_SHIP, heal 1 hull when one of its completely
-- destroyed systems is repaired back above destroyed status.

local TERRAN_SHIP_AUG = "TERRAN_SHIP"
local HULL_HEAL_AMOUNT = 1
local HULL_HEAL_FORCE = true
local LILY_SYSTEM_BRACERS_ID = Hyperspace.ShipSystem.NameToSystemId("lily_system_bracers")

local function fallback_vter(cvec)
    local i = -1
    local n = cvec:size()
    return function()
        i = i + 1
        if i < n then return cvec[i] end
    end
end
local vter = (mods.multiverse and mods.multiverse.vter) or fallback_vter

local function ship_has_terran_aug(ship)
    return ship and ship:HasAugmentation(TERRAN_SHIP_AUG) > 0
end

local function get_system_state(system)
    if not system then return nil end

    -- Attach the state to the actual system object so duplicate artillery/custom
    -- systems do not collide with each other.
    system.table.sc_terran_repair_hull = system.table.sc_terran_repair_hull or {}
    return system.table.sc_terran_repair_hull
end

local function ship_hull_missing(ship)
    if not (ship and ship.ship and ship.ship.hullIntegrity) then
        return false
    end

    local hull = ship.ship.hullIntegrity
    return (hull.first or 0) < (hull.second or 0)
end

local function system_is_completely_destroyed(system)
    return system
        and system.CompletelyDestroyed
        and system:CompletelyDestroyed()
end

local function heal_hull(ship)
    if ship_hull_missing(ship) and ship.DamageHull then
        ship:DamageHull(-HULL_HEAL_AMOUNT, HULL_HEAL_FORCE)
    end
end

local function update_system_state(ship, system)
    if not (ship and system) then return end

    local state = get_system_state(system)
    if not state then return end

    local currentlyDestroyed = system_is_completely_destroyed(system)

    if state.wasCompletelyDestroyed and not currentlyDestroyed then
        if ship_has_terran_aug(ship) then
            heal_hull(ship)
        end

        -- Do not heal again until this system becomes completely destroyed again.
        state.wasCompletelyDestroyed = false
    elseif currentlyDestroyed then
        state.wasCompletelyDestroyed = true
    end
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    if not (ship and ship.vSystemList) then return end

    -- If the ship is already destroyed, clear per-system flags so stale repair
    -- states do not survive weird edge cases.
    if ship.bDestroyed then
        for system in vter(ship.vSystemList) do
            if system and system.table then
                system.table.sc_terran_repair_hull = nil
            end
        end
        return
    end

    for system in vter(ship.vSystemList) do
        update_system_state(ship, system)
    end

    if LILY_SYSTEM_BRACERS_ID then
        update_system_state(ship, ship:GetSystem(LILY_SYSTEM_BRACERS_ID))
    end
end)
