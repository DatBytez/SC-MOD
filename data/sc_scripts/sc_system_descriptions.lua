mods.sc = mods.sc or {}

local vter = mods.multiverse.vter

-- Sensors Level Descriptions

local SENSORS_ID = Hyperspace.ShipSystem.NameToSystemId("sensors")

local SENSOR_LEVEL_TEXT_IDS = {
    [5] = "tooltip_sc_sensors_level_5",
    [6] = "tooltip_sc_sensors_level_6"
}

local function get_sc_level_description(systemId, level, tooltip)
    if systemId ~= SENSORS_ID then return end

    local textId = SENSOR_LEVEL_TEXT_IDS[level]
    if not textId then return end

    return Hyperspace.Text:GetText(textId)
end

script.on_internal_event(
    Defines.InternalEvents.GET_LEVEL_DESCRIPTION,
    get_sc_level_description
)

-- Yamato Artillery Level Descriptions

local YAMATO_WEAPON = "ARTILLERY_YAMATO_LASER"
local ARTILLERY_ID = Hyperspace.ShipSystem.NameToSystemId("artillery")

local YAMATO_LEVEL_TEXT_IDS = {
    [1] = "tooltip_sc_yamato_artillery_level_1",
    [2] = "tooltip_sc_yamato_artillery_level_2",
    [3] = "tooltip_sc_yamato_artillery_level_3",
    [4] = "tooltip_sc_yamato_artillery_level_4"
}

local function has_yamato_artillery()
    local ship = Hyperspace.ships(0)
    if not ship then return false end

    for artillery in vter(ship.artillerySystems) do
        local weapon = artillery.projectileFactory

        if weapon.blueprint.name == YAMATO_WEAPON then
            return true
        end
    end

    return false
end

local function get_yamato_artillery_description(systemId, level, _tooltip)
    if systemId ~= ARTILLERY_ID then return end
    if not has_yamato_artillery() then return end

    local textId = YAMATO_LEVEL_TEXT_IDS[level]
    if not textId then return end

    return Hyperspace.Text:GetText(textId)
end

script.on_internal_event(
    Defines.InternalEvents.GET_LEVEL_DESCRIPTION,
    get_yamato_artillery_description
)