mods.sc = mods.sc or {}
mods.sc.augmentUpgrades = mods.sc.augmentUpgrades or {}
mods.sc.system_caps = mods.sc.system_caps or {}

local augmentUpgrades = mods.sc.augmentUpgrades

mods.sc.tag.register("augment", "sc-upgrade", augmentUpgrades, "system")

local SYSTEM_NAMES_BY_ID = mods.multiverse and mods.multiverse.systemIds or {
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

local SYSTEM_BASE_CAP_FALLBACKS = {
    weapons = 8,
    shields = 16,
    engines = 8,
    oxygen = 3,
    teleporter = 4,
    medbay = 3,
    clonebay = 3,
    drones = 15,
    cloaking = 3,
    hacking = 3,
    mind = 3,
    artillery = 5,
    temporal = 3,
    piloting = 3,
    sensors = 3,
    doors = 3,
    battery = 2,
    lily_system_bracers = 3,
    reactor = 25
}

local TEST_SYSTEMS = {
    lily_system_bracers = true
}

local nativeMaxLevels = {}
local applyingSystemLimits = false

local function normalize_system_name(system)
    if type(system) == "number" then
        return SYSTEM_NAMES_BY_ID[system]
    end

    if type(system) == "string" then
        return system
    end

    return nil
end

function mods.sc.system_caps.get_cap(system)
    local systemName = normalize_system_name(system)

    if not systemName then
        return 0
    end

    local fallback = SYSTEM_BASE_CAP_FALLBACKS[systemName] or 0

    if systemName == "reactor" then
        local playerShip = Hyperspace.ships and Hyperspace.ships.player

        if playerShip and playerShip.myBlueprint and playerShip.myBlueprint.blueprintName then
            local definition = Hyperspace.CustomShipSelect.GetInstance():GetDefinition(playerShip.myBlueprint.blueprintName)
            if definition and definition.maxReactorLevel and definition.maxReactorLevel > 0 then
                return math.min(definition.maxReactorLevel, fallback)
            end
        end

        return fallback
    end

    local rawCap = Hyperspace.playerVariables[systemName .. "_cap"]

    if rawCap == nil or rawCap < 0 or (rawCap == 0 and fallback > 0) then
        return fallback
    end

    if fallback > 0 then
        return math.min(rawCap, fallback)
    end

    return rawCap
end

local function get_system_id(systemName)
    if not systemName then return -1 end
    return Hyperspace.ShipSystem.NameToSystemId(systemName)
end

local function get_system(ship, systemName)
    if not ship or not systemName then return nil end

    local systemId = get_system_id(systemName)
    if systemId < 0 then return nil end
    if not ship:HasSystem(systemId) then return nil end

    return ship:GetSystem(systemId)
end

local function get_blueprint_max_power(ship, systemName)
    if not ship or not systemName then return 0 end

    local systemId = get_system_id(systemName)
    if systemId < 0 then return 0 end

    local maxPower = 0

    pcall(function()
        if ship.myBlueprint and ship.myBlueprint.systemInfo then
            local systemInfo = ship.myBlueprint.systemInfo[systemId]
            if systemInfo and systemInfo.maxPower and systemInfo.maxPower > maxPower then
                maxPower = systemInfo.maxPower
            end
        end
    end)

    pcall(function()
        if ship.myBlueprint and ship.myBlueprint.blueprintName then
            local definition = Hyperspace.CustomShipSelect.GetInstance():GetDefinition(ship.myBlueprint.blueprintName)
            if definition and definition.systemInfo then
                local systemInfo = definition.systemInfo[systemId]
                if systemInfo and systemInfo.maxPower and systemInfo.maxPower > maxPower then
                    maxPower = systemInfo.maxPower
                end
            end
        end
    end)

    return maxPower
end

local function remember_native_max_level(ship, systemName, sys)
    if not ship or not systemName or not sys then return end

    local shipId = ship.iShipId or 0
    nativeMaxLevels[shipId] = nativeMaxLevels[shipId] or {}

    local nativeMax = 0
    local currentMax = sys:GetMaxPower() or 0
    local rawCap = Hyperspace.playerVariables[systemName .. "_cap"]
    local fallback = SYSTEM_BASE_CAP_FALLBACKS[systemName] or 0
    local blueprintMax = get_blueprint_max_power(ship, systemName)

    if sys.maxLevel and sys.maxLevel > nativeMax then nativeMax = sys.maxLevel end
    if currentMax > nativeMax then nativeMax = currentMax end
    if rawCap and rawCap > nativeMax then nativeMax = rawCap end
    if fallback > nativeMax then nativeMax = fallback end
    if blueprintMax > nativeMax then nativeMax = blueprintMax end

    local storedMax = nativeMaxLevels[shipId][systemName] or 0
    if nativeMax > storedMax then
        nativeMaxLevels[shipId][systemName] = nativeMax
    end
end

local function get_native_max_level(ship, systemName, sys)
    remember_native_max_level(ship, systemName, sys)

    local shipId = ship and ship.iShipId or 0
    if nativeMaxLevels[shipId] then
        return nativeMaxLevels[shipId][systemName] or 0
    end

    return 0
end

local function get_augment_upgrade_bonuses(ship)
    local bonuses = {}
    if not ship then return bonuses end

    for augName, upgrades in pairs(augmentUpgrades) do
        local count = ship:HasAugmentation(augName) or 0
        if count > 0 then
            for _, upgrade in ipairs(upgrades) do
                local amount = upgrade.value or upgrade.amount or 0
                if upgrade.system and amount > 0 then
                    bonuses[upgrade.system] = (bonuses[upgrade.system] or 0) + amount * count
                end
            end
        end
    end

    return bonuses
end

local function get_effective_max_level(systemName, bonus)
    local baseCap = mods.sc.system_caps.get_cap(systemName)
    if baseCap <= 0 then return 0 end

    return baseCap + (bonus or 0)
end

local function set_max_level(sys, maxLevel)
    if not sys or not maxLevel or maxLevel <= 0 then return end
    sys.maxLevel = maxLevel
end

local function clamp_purchased_level(ship, systemName, bonus)
    local sys = get_system(ship, systemName)
    if not sys then return end

    local effectiveMax = get_effective_max_level(systemName, bonus)
    if effectiveMax <= 0 then return end

    local currentMax = sys:GetMaxPower() or 0
    local excess = currentMax - effectiveMax

    if excess <= 0 then return end

    for i = 1, excess do
        sys:UpgradeSystem(-1)
    end
end

local function apply_upgrade_screen_limits(ship)
    if not ship or ship.iShipId ~= 0 then return end
    if applyingSystemLimits then return end

    applyingSystemLimits = true

    local bonuses = get_augment_upgrade_bonuses(ship)

    for systemName in pairs(TEST_SYSTEMS) do
        local sys = get_system(ship, systemName)
        if sys then
            local effectiveMax = get_effective_max_level(systemName, bonuses[systemName] or 0)
            if effectiveMax > 0 then
                remember_native_max_level(ship, systemName, sys)
                set_max_level(sys, effectiveMax)
                clamp_purchased_level(ship, systemName, bonuses[systemName] or 0)
            end
        end
    end

    applyingSystemLimits = false
end

local function restore_native_limits(ship)
    if not ship or ship.iShipId ~= 0 then return end
    if applyingSystemLimits then return end

    applyingSystemLimits = true

    local bonuses = get_augment_upgrade_bonuses(ship)

    for systemName in pairs(TEST_SYSTEMS) do
        local sys = get_system(ship, systemName)
        if sys then
            remember_native_max_level(ship, systemName, sys)
            clamp_purchased_level(ship, systemName, bonuses[systemName] or 0)

            local nativeMax = get_native_max_level(ship, systemName, sys)
            if nativeMax > 0 then
                set_max_level(sys, nativeMax)
            end
        end
    end

    applyingSystemLimits = false
end

local function handle_tabbed_window(currentTab)
    local ship = Hyperspace.ships.player
    if not ship then return end

    if tostring(currentTab) == "upgrades" then
        apply_upgrade_screen_limits(ship)
    else
        restore_native_limits(ship)
    end
end

script.on_render_event(
    Defines.RenderEvents.TABBED_WINDOW,
    handle_tabbed_window,
    handle_tabbed_window
)

local function restore_player_native_limits()
    local ship = Hyperspace.ships.player
    if not ship then return end

    restore_native_limits(ship)
end

script.on_internal_event(Defines.InternalEvents.TABBED_WINDOW_CONFIRM, restore_player_native_limits)
script.on_internal_event(Defines.InternalEvents.TABBED_WINDOW_UNDO, restore_player_native_limits)
