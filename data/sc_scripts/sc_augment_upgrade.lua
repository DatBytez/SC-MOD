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

local MAX_LEVEL_TEST_SYSTEMS = {
    lily_system_bracers = true
}

local originalMaxLevels = {}
local upgradeTabActive = false
local updatingSystemLevels = false

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

    if systemName == "reactor" then
        local playerShip = Hyperspace.ships and Hyperspace.ships.player
        local fallback = SYSTEM_BASE_CAP_FALLBACKS.reactor

        if playerShip and playerShip.myBlueprint and playerShip.myBlueprint.blueprintName then
            local definition = Hyperspace.CustomShipSelect.GetInstance():GetDefinition(playerShip.myBlueprint.blueprintName)
            if definition and definition.maxReactorLevel and definition.maxReactorLevel > 0 then
                return math.min(definition.maxReactorLevel, fallback)
            end
        end

        return fallback
    end

    local fallback = SYSTEM_BASE_CAP_FALLBACKS[systemName] or 0
    local rawCap = Hyperspace.playerVariables[systemName .. "_cap"]

    if rawCap == nil or rawCap < 0 or (rawCap == 0 and fallback > 0) then
        return fallback
    end

    if fallback > 0 then
        return math.min(rawCap, fallback)
    end

    return rawCap
end

local function get_native_max_level(ship, systemName, sys)
    local nativeMax = 0

    if sys and sys.maxLevel and sys.maxLevel > nativeMax then
        nativeMax = sys.maxLevel
    end

    if sys then
        local currentMax = sys:GetMaxPower() or 0
        if currentMax > nativeMax then
            nativeMax = currentMax
        end
    end

    local rawCap = Hyperspace.playerVariables[systemName .. "_cap"]
    if rawCap and rawCap > nativeMax then
        nativeMax = rawCap
    end

    local fallback = SYSTEM_BASE_CAP_FALLBACKS[systemName] or 0
    if fallback > nativeMax then
        nativeMax = fallback
    end

    return nativeMax
end

local function remember_original_max_level(ship, systemName, sys)
    if not ship or not systemName or not sys then return end

    local shipId = ship.iShipId or 0
    originalMaxLevels[shipId] = originalMaxLevels[shipId] or {}

    local nativeMax = get_native_max_level(ship, systemName, sys)
    local storedMax = originalMaxLevels[shipId][systemName] or 0

    if nativeMax > storedMax then
        originalMaxLevels[shipId][systemName] = nativeMax
    end
end

local function get_original_max_level(ship, systemName, sys)
    remember_original_max_level(ship, systemName, sys)

    local shipId = ship and ship.iShipId or 0
    return originalMaxLevels[shipId] and originalMaxLevels[shipId][systemName] or nil
end

local function get_desired_system_upgrades(ship)
    local desired = {}
    if not ship then return desired end

    for augName, upgrades in pairs(augmentUpgrades) do
        local count = ship:HasAugmentation(augName) or 0
        if count > 0 then
            for _, upgrade in ipairs(upgrades) do
                if upgrade.system and (upgrade.value or 0) > 0 then
                    desired[upgrade.system] = (desired[upgrade.system] or 0) + upgrade.value * count
                end
            end
        end
    end

    return desired
end

local function get_system(ship, systemName)
    if not ship or not systemName then return nil end

    local systemId = Hyperspace.ShipSystem.NameToSystemId(systemName)
    if not ship:HasSystem(systemId) then return nil end

    return ship:GetSystem(systemId)
end

local function get_effective_max_level(systemName, bonus)
    local baseCap = mods.sc.system_caps.get_cap(systemName)
    if baseCap <= 0 then return 0 end

    return baseCap + (bonus or 0)
end

local function safe_call(func)
    pcall(func)
end

local function clear_temp_power_cap(sys)
    safe_call(function()
        sys.iTempPowerCap = -1
    end)
end

local function check_max_power(sys)
    safe_call(function()
        sys:CheckMaxPower()
    end)
end

local function set_system_max_level(sys, maxLevel)
    if not sys or not maxLevel or maxLevel <= 0 then return end

    safe_call(function()
        sys.maxLevel = maxLevel
    end)
end

local function restore_system_max_level(ship, systemName)
    local sys = get_system(ship, systemName)
    if not sys then return end

    local originalMax = get_original_max_level(ship, systemName, sys)
    if not originalMax or originalMax <= 0 then return end

    clear_temp_power_cap(sys)
    set_system_max_level(sys, originalMax)
    check_max_power(sys)
end

local function clamp_purchased_levels(ship, systemName, bonus)
    local sys = get_system(ship, systemName)
    if not sys then return end

    local effectiveMax = get_effective_max_level(systemName, bonus)
    if effectiveMax <= 0 then return end

    remember_original_max_level(ship, systemName, sys)

    local currentMax = sys:GetMaxPower() or 0
    local excess = currentMax - effectiveMax

    if excess <= 0 then return end

    set_system_max_level(sys, effectiveMax)
    check_max_power(sys)

    for i = 1, excess do
        sys:UpgradeSystem(-1)
    end

    check_max_power(sys)
end

local function apply_upgrade_screen_max_level(ship, systemName, bonus)
    local sys = get_system(ship, systemName)
    if not sys then return end

    local effectiveMax = get_effective_max_level(systemName, bonus)
    if effectiveMax <= 0 then return end

    remember_original_max_level(ship, systemName, sys)
    clear_temp_power_cap(sys)
    set_system_max_level(sys, effectiveMax)
    check_max_power(sys)
    clamp_purchased_levels(ship, systemName, bonus)
end

local function enforce_upgrade_screen_max_levels(ship)
    if not ship or ship.iShipId ~= 0 then return end
    if updatingSystemLevels then return end

    updatingSystemLevels = true

    local desired = get_desired_system_upgrades(ship)

    for systemName in pairs(MAX_LEVEL_TEST_SYSTEMS) do
        apply_upgrade_screen_max_level(ship, systemName, desired[systemName] or 0)
    end

    upgradeTabActive = true
    updatingSystemLevels = false
end

local function enforce_normal_screen_limits(ship)
    if not ship or ship.iShipId ~= 0 then return end
    if updatingSystemLevels then return end

    updatingSystemLevels = true

    local desired = get_desired_system_upgrades(ship)

    for systemName in pairs(MAX_LEVEL_TEST_SYSTEMS) do
        clamp_purchased_levels(ship, systemName, desired[systemName] or 0)
        restore_system_max_level(ship, systemName)
    end

    upgradeTabActive = false
    updatingSystemLevels = false
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    if upgradeTabActive then
        enforce_upgrade_screen_max_levels(ship)
    else
        enforce_normal_screen_limits(ship)
    end
end)

script.on_render_event(
    Defines.RenderEvents.TABBED_WINDOW,
    function(currentTab)
        local ship = Hyperspace.ships.player
        if not ship then return end

        if tostring(currentTab) == "upgrades" then
            enforce_upgrade_screen_max_levels(ship)
        else
            enforce_normal_screen_limits(ship)
        end
    end,
    function(currentTab)
        local ship = Hyperspace.ships.player
        if not ship then return end

        if tostring(currentTab) == "upgrades" then
            enforce_upgrade_screen_max_levels(ship)
        else
            enforce_normal_screen_limits(ship)
        end
    end
)
