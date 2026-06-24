-- ------------------------
-- TERRAN SHIP REPAIR HULL
-- ------------------------
-- If a ship has TERRAN_SHIP, heal 1 hull when one of its completely
-- destroyed systems is repaired back above destroyed status.
--
-- This version does NOT rely only on healthState.first.
-- It tracks each real ShipSystem object from ship.vSystemList and uses
-- ShipSystem:CompletelyDestroyed(), with healthState/GetDamage fallbacks.

local TERRAN_SHIP_AUG = "TERRAN_SHIP"
local HULL_HEAL_AMOUNT = 1
local HULL_HEAL_FORCE = true
local DEBUG_REPAIR_HULL = true

local function fallback_vter(cvec)
    local i = -1
    local n = cvec:size()
    return function()
        i = i + 1
        if i < n then return cvec[i] end
    end
end
local vter = (mods.multiverse and mods.multiverse.vter) or fallback_vter

-- MV provides this table. The fallback keeps this script usable if vSystemList
-- is not available for some reason.
local systemIds = (mods.multiverse and mods.multiverse.systemIds) or {
    [0] = "shields",
    [1] = "engines",
    [2] = "oxygen",
    [3] = "weapons",
    [4] = "drones",
    [5] = "medbay",
    [6] = "piloting",
    [7] = "sensors",
    [8] = "doors",
    [9] = "teleporter",
    [10] = "cloaking",
    [11] = "artillery",
    [12] = "battery",
    [13] = "clonebay",
    [14] = "mind",
    [15] = "hacking",
    [20] = "temporal"
}

local function debug_print(message)
    if DEBUG_REPAIR_HULL then
        print("[SC TERRAN REPAIR HULL] " .. message)
    end
end

local function ship_has_terran_aug(ship)
    return ship and ship:HasAugmentation(TERRAN_SHIP_AUG) > 0
end

local function get_system_state(system)
    if not system then return nil end

    -- ShipSystem.table exists in Hyperspace 1.4.0+ and stays attached to the
    -- system object. This is safer than a separate ship/sysId table because it
    -- also handles duplicate artillery systems.
    system.table.sc_terran_repair_hull = system.table.sc_terran_repair_hull or {}
    return system.table.sc_terran_repair_hull
end

local function get_system_name(system)
    if not system then return "?" end

    local sysId = system.iSystemType
    if sysId ~= nil and Hyperspace.ShipSystem.SystemIdToName then
        local ok, name = pcall(Hyperspace.ShipSystem.SystemIdToName, sysId)
        if ok and name and name ~= "" then
            return name
        end
    end

    if system.GetName then
        local ok, namePtr = pcall(function() return system:GetName() end)
        if ok and namePtr then
            return tostring(namePtr)
        end
    end

    return tostring(sysId or "?")
end

local function get_hull_text(ship)
    if not (ship and ship.ship and ship.ship.hullIntegrity) then
        return "nil"
    end

    return tostring(ship.ship.hullIntegrity.first or 0) .. "/" .. tostring(ship.ship.hullIntegrity.second or 0)
end

local function get_system_health(system)
    if not (system and system.healthState) then
        return nil, nil
    end

    return system.healthState.first or 0, system.healthState.second or 0
end

local function get_system_damage(system)
    if not system then return nil, nil end

    local damage = nil
    local maxDamage = nil

    if system.GetDamage then
        local ok, value = pcall(function() return system:GetDamage() end)
        if ok then damage = value end
    end
    if damage == nil then
        damage = system.fDamage
    end

    maxDamage = system.fMaxDamage

    return damage, maxDamage
end

local function system_is_completely_destroyed(system)
    if not system then return false end

    -- Preferred method: use the engine's own definition of completely destroyed.
    if system.CompletelyDestroyed then
        local ok, destroyed = pcall(function() return system:CompletelyDestroyed() end)
        if ok and destroyed ~= nil then
            return destroyed
        end
    end

    -- Fallback 1: if damage/maxDamage are available, destroyed means damage has
    -- reached or passed max damage.
    local damage, maxDamage = get_system_damage(system)
    if damage ~= nil and maxDamage ~= nil and maxDamage > 0 then
        return damage >= maxDamage
    end

    -- Fallback 2: old healthState method.
    local currentHealth, maxHealth = get_system_health(system)
    if currentHealth ~= nil and maxHealth ~= nil and maxHealth > 0 then
        return currentHealth <= 0
    end

    return false
end

local function system_repaired_from_destroyed(system, state)
    if not (system and state and state.wasCompletelyDestroyed) then
        return false
    end

    -- Primary repair transition: engine says this system is no longer completely destroyed.
    if not system_is_completely_destroyed(system) then
        return true, "CompletelyDestroyed false"
    end

    -- Fallback transition: health crossed from 0 to above 0.
    local currentHealth, maxHealth = get_system_health(system)
    if state.lastHealth ~= nil and currentHealth ~= nil and maxHealth ~= nil and maxHealth > 0 then
        if state.lastHealth <= 0 and currentHealth > 0 then
            return true, "healthState crossed above 0"
        end
    end

    -- Fallback transition: damage dropped below its prior max-damage value.
    local damage, maxDamage = get_system_damage(system)
    local priorMaxDamage = state.lastMaxDamage or maxDamage
    if state.lastDamage ~= nil and damage ~= nil and priorMaxDamage ~= nil and priorMaxDamage > 0 then
        if state.lastDamage >= priorMaxDamage and damage < priorMaxDamage then
            return true, "damage dropped below max"
        end
    end

    return false, nil
end

local function heal_hull(ship, systemName, system, reason)
    if not (ship and ship.DamageHull) then
        return
    end

    -- This is intentionally the only active print line.
    debug_print("Healing ship: " .. tostring(HULL_HEAL_AMOUNT)
        .. " | ship=" .. tostring(ship.iShipId or "?")
        .. " | system=" .. tostring(systemName or "?")
        .. " | reason=" .. tostring(reason or "?")
        .. " | hullBefore=" .. get_hull_text(ship))

    ship:DamageHull(-HULL_HEAL_AMOUNT, HULL_HEAL_FORCE)
end

local function update_system_state(ship, system)
    if not (ship and system) then return end

    local state = get_system_state(system)
    if not state then return end

    local systemName = get_system_name(system)
    local currentHealth, maxHealth = get_system_health(system)
    local damage, maxDamage = get_system_damage(system)
    local currentlyDestroyed = system_is_completely_destroyed(system)

    local repaired, reason = system_repaired_from_destroyed(system, state)
    if repaired then
        if ship_has_terran_aug(ship) then
            heal_hull(ship, systemName, system, reason)
        end

        -- Do not heal again until the system becomes completely destroyed again.
        state.wasCompletelyDestroyed = false
    elseif currentlyDestroyed then
        state.wasCompletelyDestroyed = true
    end

    state.lastDestroyed = currentlyDestroyed
    state.lastHealth = currentHealth
    state.lastMaxHealth = maxHealth
    state.lastDamage = damage
    state.lastMaxDamage = maxDamage
end

local function update_ship_systems_from_vsystemlist(ship)
    if not (ship and ship.vSystemList) then
        return false
    end

    for system in vter(ship.vSystemList) do
        update_system_state(ship, system)
    end

    return true
end

local function update_ship_systems_fallback(ship)
    if not ship then return end

    for sysId, _ in pairs(systemIds) do
        local system = ship:GetSystem(sysId)
        if system then
            update_system_state(ship, system)
        end
    end
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    if not (ship and ship.ship and ship.ship.hullIntegrity) then return end

    -- If the ship is already destroyed, clear per-system flags so stale repair
    -- states do not survive weird edge cases.
    if ship.bDestroyed then
        if ship.vSystemList then
            for system in vter(ship.vSystemList) do
                if system and system.table then
                    system.table.sc_terran_repair_hull = nil
                end
            end
        end
        return
    end

    -- Preferred method: iterate the actual system objects installed on this ship.
    -- This avoids HasSystem/GetSystem quirks and duplicate artillery key issues.
    if not update_ship_systems_from_vsystemlist(ship) then
        update_ship_systems_fallback(ship)
    end
end)
