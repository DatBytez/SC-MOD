mods.sc = mods.sc or {}
mods.sc.augmentUpgrades = mods.sc.augmentUpgrades or {}
mods.sc.system_caps = mods.sc.system_caps or {}

local augmentUpgrades = mods.sc.augmentUpgrades

mods.sc.tag.register_augment_tag("sc-upgrade", augmentUpgrades)

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

local SYSTEM_CAP_FALLBACKS = {
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

local temporarilyRemovedLevels = {}
local tabbedWindowLevelRemoved = false
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
        local fallback = SYSTEM_CAP_FALLBACKS.reactor

        if playerShip and playerShip.myBlueprint and playerShip.myBlueprint.blueprintName then
            local definition = Hyperspace.CustomShipSelect.GetInstance():GetDefinition(playerShip.myBlueprint.blueprintName)
            if definition and definition.maxReactorLevel and definition.maxReactorLevel > 0 then
                return definition.maxReactorLevel
            end
        end

        return fallback
    end

    local fallback = SYSTEM_CAP_FALLBACKS[systemName] or 0
    local rawCap = Hyperspace.playerVariables[systemName .. "_cap"]

    if rawCap == nil or rawCap < 0 or (rawCap == 0 and fallback > 0) then
        return fallback
    end

    return rawCap
end

local function get_desired_system_upgrades(ship)
    local desired = {}
    if not ship then return desired end

    for augName, upgrades in pairs(augmentUpgrades) do
        local count = ship:HasAugmentation(augName) or 0
        if count > 0 then
            for _, upgrade in ipairs(upgrades) do
                if upgrade.system and (upgrade.amount or 0) > 0 then
                    desired[upgrade.system] = (desired[upgrade.system] or 0) + (upgrade.amount or 1) * count
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

local function get_actual_system_max(ship, systemName)
    local sys = get_system(ship, systemName)
    if not sys then return 0 end

    return sys:GetMaxPower() or 0
end

local function get_true_system_max_for_ui(ship, systemName)
    return get_actual_system_max(ship, systemName) + (temporarilyRemovedLevels[systemName] or 0)
end

local function get_augmented_limit(systemName, bonus)
    local naturalCap = mods.sc.system_caps.get_cap(systemName)
    if naturalCap <= 0 or bonus <= 0 then
        return naturalCap, naturalCap
    end

    return naturalCap + bonus, naturalCap
end

local function system_is_at_augmented_limit(ship, systemName, bonus)
    local allowedMax = get_augmented_limit(systemName, bonus)
    if allowedMax <= 0 then return true end

    return get_true_system_max_for_ui(ship, systemName) >= allowedMax
end

local function get_temp_levels_to_remove(currentMax, naturalCap, bonus)
    if naturalCap <= 0 or bonus <= 0 then return 0 end

    local allowedMax = naturalCap + bonus

    if currentMax >= allowedMax then return 0 end
    if currentMax < naturalCap then return 0 end

    return currentMax - naturalCap + 1
end

local function get_remaining_bonus_boxes(ship, systemName, bonus)
    local allowedMax, naturalCap = get_augmented_limit(systemName, bonus)
    if naturalCap <= 0 or bonus <= 0 then
        return 0, naturalCap
    end

    local trueMax = get_true_system_max_for_ui(ship, systemName)
    if trueMax >= allowedMax then
        return 0, allowedMax
    end

    local startLevel = math.max(naturalCap, trueMax)
    local remaining = allowedMax - startLevel

    if remaining < 0 then
        remaining = 0
    end

    return remaining, startLevel
end

local function get_green_purchased_boxes(ship, systemName)
    local naturalCap = mods.sc.system_caps.get_cap(systemName)
    if naturalCap <= 0 then
        return 0, 0
    end

    local visibleGameBars = get_actual_system_max(ship, systemName)
    if visibleGameBars > naturalCap then
        visibleGameBars = naturalCap
    end

    local trueMax = get_true_system_max_for_ui(ship, systemName)
    local greenBoxes = trueMax - visibleGameBars

    if greenBoxes < 0 then
        greenBoxes = 0
    end

    return greenBoxes, visibleGameBars
end

local function temporarily_remove_level_for_upgrade_screen(ship)
    if not ship or ship.iShipId ~= 0 then return end
    if updatingSystemLevels then return end
    if tabbedWindowLevelRemoved then return end

    updatingSystemLevels = true

    local desired = get_desired_system_upgrades(ship)

    for systemName, bonus in pairs(desired) do
        if bonus > 0 and not system_is_at_augmented_limit(ship, systemName, bonus) then
            local sys = get_system(ship, systemName)
            local naturalCap = mods.sc.system_caps.get_cap(systemName)

            if sys and naturalCap > 0 then
                local currentMax = sys:GetMaxPower() or 0
                local levelsToRemove = get_temp_levels_to_remove(currentMax, naturalCap, bonus)

                if levelsToRemove > 0 then
                    for i = 1, levelsToRemove do
                        sys:UpgradeSystem(-1)
                    end
                    temporarilyRemovedLevels[systemName] = (temporarilyRemovedLevels[systemName] or 0) + levelsToRemove
                end
            end
        end
    end

    tabbedWindowLevelRemoved = true
    updatingSystemLevels = false
end

local function restore_level_after_upgrade_screen(ship)
    if not ship or ship.iShipId ~= 0 then return end
    if updatingSystemLevels then return end
    if not tabbedWindowLevelRemoved then return end

    updatingSystemLevels = true

    for systemName, removed in pairs(temporarilyRemovedLevels) do
        local sys = get_system(ship, systemName)

        if sys and removed > 0 then
            for i = 1, removed do
                sys:UpgradeSystem(1)
            end
        end

        temporarilyRemovedLevels[systemName] = nil
    end

    tabbedWindowLevelRemoved = false
    updatingSystemLevels = false
end

local function get_manual_subsystem_slot(ship, systemName)
    if not ship or not systemName then return nil end

    local subsystemOrder = {
        "pilot",
        "sensors",
        "doors",
        "battery",
        "lily_system_bracers"
    }

    local slot = 0

    for _, name in ipairs(subsystemOrder) do
        local systemId = Hyperspace.ShipSystem.NameToSystemId(name)

        if ship:HasSystem(systemId) then
            if name == systemName then
                return slot
            end
            slot = slot + 1
        end
    end

    return nil
end

script.on_render_event(
    Defines.RenderEvents.TABBED_WINDOW,
    function(currentTab)
        local ship = Hyperspace.ships.player
        if not ship then return end

        if tostring(currentTab) == "upgrades" then
            temporarily_remove_level_for_upgrade_screen(ship)
        else
            restore_level_after_upgrade_screen(ship)
        end
    end,
    function(currentTab)
        if tostring(currentTab) ~= "upgrades" then return end

        local ship = Hyperspace.ships.player
        if not ship then return end

        local entries = get_desired_system_upgrades(ship)

        local START_X = 365
        local START_Y = 453
        local SLOT_W = 66

        local BOX_W = 15
        local BOX_H = 7
        local BOX_GAP = 1
        local STEP = BOX_H + BOX_GAP

        local green = Graphics.GL_Color(0.25, 1.0, 0.25, 0.85)
        local grey = Graphics.GL_Color(0.45, 0.45, 0.45, 0.8)

        for systemName, bonus in pairs(entries) do
            if bonus > 0 then
                local slot = get_manual_subsystem_slot(ship, systemName)
                if slot ~= nil then
                    local BOX_X = START_X + slot * SLOT_W

                    local greenBoxes, greenStartLevel = get_green_purchased_boxes(ship, systemName)
                    for i = 0, greenBoxes - 1 do
                        local BOX_Y = START_Y - ((greenStartLevel + i) * STEP)
                        Graphics.CSurface.GL_DrawRect(BOX_X, BOX_Y, BOX_W, BOX_H, green)
                    end

                    local boxesToDraw, startLevel = get_remaining_bonus_boxes(ship, systemName, bonus)
                    for i = 0, boxesToDraw - 1 do
                        local BOX_Y = START_Y - ((startLevel + i) * STEP)
                        Graphics.CSurface.GL_DrawRectOutline(BOX_X, BOX_Y, BOX_W, BOX_H, grey, 2)
                    end
                end
            end
        end
    end
)

script.on_internal_event(Defines.InternalEvents.TABBED_WINDOW_CONFIRM, function(currentTabName)
    local ship = Hyperspace.ships.player
    if not ship then return end

    restore_level_after_upgrade_screen(ship)
end)

script.on_internal_event(Defines.InternalEvents.TABBED_WINDOW_UNDO, function(currentTabName)
    local ship = Hyperspace.ships.player
    if not ship then return end

    restore_level_after_upgrade_screen(ship)
end)
