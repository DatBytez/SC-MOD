mods.sc = mods.sc or {}

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

local yamatoLevelDescriptions = {
    [1] = "Level 1: 2 shots — 25 sec cooldown",
    [2] = "Level 2: 3 shots — 25 sec cooldown",
    [3] = "Level 3: 4 shots — 22.5 sec cooldown",
    [4] = "Level 4: 5 shots — 17.5 sec cooldown"
}

local function has_yamato_artillery()
    local ship = Hyperspace.ships(0)
    if not ship then return false end

    for artillery in vter(ship.artillerySystems) do
        local weapon = artillery.projectileFactory

        if weapon
            and weapon.blueprint
            and weapon.blueprint.name == YAMATO_WEAPON then
            return true
        end
    end

    return false
end

script.on_internal_event(
    Defines.InternalEvents.GET_LEVEL_DESCRIPTION,
    function(systemId, level, _tooltip)
        if systemId ~= Hyperspace.ShipSystem.NameToSystemId("artillery") then
            return
        end

        if not has_yamato_artillery() then
            return
        end

        return yamatoLevelDescriptions[level]
    end
)