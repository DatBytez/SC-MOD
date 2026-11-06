--[[
DESCRIPTION: Shared utility functions used by multiple SC scripts.
        - Checks ships for tagged augments.
        - Totals numeric values from tagged augments.
        - Converts blueprint lists into lookup sets.
        - Converts system names into valid system IDs
DEPENDENCIES: Multiverse vter
]]

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

function helpers.blueprint_list_to_set(listName)
    local entries = {}

    for entry in vter(Hyperspace.Blueprints:GetBlueprintList(listName)) do
        entries[entry] = true
    end

    return entries
end

function helpers.system_id_from_name(systemName)
    if not systemName then return nil end

    local systemId = Hyperspace.ShipSystem.NameToSystemId(systemName)
    return systemId >= 0 and systemId or nil
end