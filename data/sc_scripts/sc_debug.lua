
--[[
DESCRIPTION: Forces all generated enemy ships to use Terran weapons.
        - Replaces all ship weapon list references with TERRAN_STANDARD_WEAPONS.
        - Prints the original and replacement lists for testing.
DEPENDENCIES: Hyperspace
]]

local REPLACEMENT_LIST = "TERRAN_STANDARD_WEAPONS"

script.on_internal_event(Defines.InternalEvents.GENERATOR_CREATE_SHIP, function(name, sector, event, blueprint, ship)
    if blueprint then
        local originalList = blueprint.loadWeapons
        blueprint.loadWeapons = REPLACEMENT_LIST

        print("[SC Weapon Swap] " .. tostring(name) .. ": " .. tostring(originalList) .. " -> " .. blueprint.loadWeapons)
    end

    return Defines.Chain.CONTINUE, sector, event, blueprint, ship
end)
