--[[
Shared helper functions for common patterns across SC mod scripts.
Reduces code duplication and improves maintainability.
]]

mods.sc = mods.sc or {}
mods.sc.helpers = mods.sc.helpers or {}

local helpers = mods.sc.helpers

-- Fallback for vter if multiverse is not available
local function fallback_vter(cvec)
    local i = -1
    local n = cvec:size()
    return function()
        i = i + 1
        if i < n then return cvec[i] end
    end
end
local vter = (mods.multiverse and mods.multiverse.vter) or fallback_vter

-- ============================================================================
-- Augment Checkers
-- ============================================================================

---Check if a ship has a specific augmentation.
---@param ship table The ship object
---@param augmentName string The augmentation name to check
---@return boolean True if ship has the augmentation, false otherwise
function helpers.ship_has_augment(ship, augmentName)
    return ship and ship:HasAugmentation(augmentName) > 0
end

---Check if a ship has any augmentation from a set.
---Useful for systems with multiple possible augment variants.
---@param ship table The ship object
---@param augmentSet table A table of augmentation names (keys don't matter)
---@return boolean True if ship has any augment from the set, false otherwise
function helpers.ship_has_augment_in_set(ship, augmentSet)
    if not ship or not augmentSet then return false end

    for augName, _ in pairs(augmentSet) do
        if ship:HasAugmentation(augName) > 0 then
            return true
        end
    end

    return false
end

-- ============================================================================
-- Drone Checkers
-- ============================================================================

---Check if a ship has any drone matching a predicate function.
---The predicate receives a single drone object and should return true/false.
---@param ship table The ship object
---@param predicate function Function that returns true if drone matches criteria
---@return boolean True if any drone matches the predicate, false otherwise
function helpers.ship_has_drone_matching(ship, predicate)
    if not ship or not ship.droneSystem or not ship.droneSystem.drones then
        return false
    end

    for drone in vter(ship.droneSystem.drones) do
        if predicate(drone) then
            return true
        end
    end

    return false
end

-- ============================================================================
-- System Checkers
-- ============================================================================

---Check if a ship has a system with remaining health (not destroyed).
---@param ship table The ship object
---@param systemId number The system ID
---@return boolean True if system exists and has health, false otherwise
function helpers.ship_has_powered_system(ship, systemId)
    if not ship then return false end

    local system = ship:HasSystem(systemId) and ship:GetSystem(systemId)
    return system and not system:CompletelyDestroyed()
end
