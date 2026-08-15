
mods.sc = mods.sc or {}
mods.sc.helpers = mods.sc.helpers or {}

local helpers = mods.sc.helpers
local vter = mods.multiverse.vter

-- ============================================================================
-- Augment Check
-- ============================================================================

function helpers.ship_has_augment(ship, augment)
    if not ship then return false end

    if type(augment) == "table" then
        for augName, _ in pairs(augment) do
            if ship:HasAugmentation(augName) > 0 then
                return true
            end
        end
        return false
    end

    return ship:HasAugmentation(augment) > 0
end

-- ============================================================================
-- Drone Check
-- ============================================================================

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
-- System Check
-- ============================================================================

function helpers.ship_has_working_system(ship, systemId)
    if not ship then return false end

    local system = ship:HasSystem(systemId) and ship:GetSystem(systemId)
    return system and not system:CompletelyDestroyed()
end

function helpers.get_system_by_name(shipManager, systemName)
    local systemId = Hyperspace.ShipSystem.NameToSystemId(systemName)
    if not shipManager or not shipManager.vSystemList then return nil end
    for system in vter(shipManager.vSystemList) do
        if system and system.GetId and system:GetId() == systemId then
            return system
        end
    end
    return nil
end

function helpers.get_system_by_id(shipManager, systemId)
    if not shipManager or not shipManager.vSystemList then return nil end
    for system in vter(shipManager.vSystemList) do
        if system and system.GetId and system:GetId() == systemId then
            return system
        end
    end
    return nil
end
