--[[
DESCRIPTION: Replaces selected enemy ship weapon and drone lists during enemy ship generation.
]]

local WEAPON_LIST_PAIRS = {
    {"TERRAN_STANDARD_WEAPONS", "WEAPONS_FED"},
    {"TERRAN_STANDARD_WEAPONS", "WEAPONS_REBEL"},
--  { REPLACEMENT_LIST, ORIGINAL_LIST },
}

local DRONE_LIST_PAIRS = {
    {"TERRAN_DRONES_DEFENSE", "DRONES_COMBAT"},
    {"TERRAN_DRONES_STANDARD", "DRONES_STANDARD"},
--  { REPLACEMENT_LIST, ORIGINAL_LIST },
}

script.on_internal_event(Defines.InternalEvents.GENERATOR_CREATE_SHIP, function(name, sector, event, blueprint, ship)
    local originalWeaponList = blueprint.loadWeapons
    local originalDroneList = blueprint.loadDrones

    for _, pair in ipairs(WEAPON_LIST_PAIRS) do
        if originalWeaponList == pair[2] then
            blueprint.loadWeapons = pair[1]
            break
        end
    end

    for _, pair in ipairs(DRONE_LIST_PAIRS) do
        if originalDroneList == pair[2] then
            blueprint.loadDrones = pair[1]
            break
        end
    end

    return Defines.Chain.CONTINUE, sector, event, blueprint, ship
end)