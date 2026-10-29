mods.sc = mods.sc or {}
mods.sc.helpers = mods.sc.helpers or {}

local helpers = mods.sc.helpers
local vter = mods.multiverse.vter

function helpers.ship_has_augment(ship, augment)
    if not ship then return false end

    if type(augment) == "table" then
        for augName in pairs(augment) do
            if ship:HasAugmentation(augName) > 0 then
                return true
            end
        end

        return false
    end

    return ship:HasAugmentation(augment) > 0
end

function helpers.get_augment_value_total(ship, augments)
    if not ship then return 0 end

    local total = 0

    for augName, value in pairs(augments) do
        total = total + value * ship:HasAugmentation(augName)
    end

    return total
end

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

function helpers.blueprint_list_to_set(listName)
    local entries = {}

    for entry in vter(Hyperspace.Blueprints:GetBlueprintList(listName)) do
        entries[entry] = true
    end

    return entries
end