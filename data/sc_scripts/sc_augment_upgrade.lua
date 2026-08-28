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

local SUBSYSTEM_ORDER = {
    "pilot",
    "sensors",
    "doors",
    "battery",
    "lily_system_bracers"
}

local temporarilyRemovedLevels = {}
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

    for augName, upgrades in pairs(augmentUpgrades) do
        local count = ship:HasAugmentation(augName)
        if count > 0 then
            for _, upgrade in ipairs(upgrades) do
                if upgrade.value > 0 then
                    desired[upgrade.system] = (desired[upgrade.system] or 0) + upgrade.value * count
                end
            end
        end
    end

    return desired
end

local function get_system(ship, systemName)
    local systemId = Hyperspace.ShipSystem.NameToSystemId(systemName)
    if not ship:HasSystem(systemId) then return nil end

    return ship:GetSystem(systemId)
end

local function get_actual_system_max(ship, systemName)
    local sys = get_system(ship, systemName)
    return sys and sys:GetMaxPower() or 0
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

local function get_target_temp_levels_to_remove(trueMax, naturalCap, bonus)
    if naturalCap <= 0 or bonus <= 0 then return 0 end

    local allowedMax = naturalCap + bonus
    if trueMax >= allowedMax or trueMax < naturalCap then return 0 end

    return trueMax - naturalCap + 1
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
    return allowedMax - startLevel, startLevel
end

local function get_green_purchased_boxes(ship, systemName)
    local naturalCap = mods.sc.system_caps.get_cap(systemName)
    if naturalCap <= 0 then
        return 0, 0
    end

    local visibleGameBars = math.min(get_actual_system_max(ship, systemName), naturalCap)
    local trueMax = get_true_system_max_for_ui(ship, systemName)

    return trueMax - visibleGameBars, visibleGameBars
end

local function restore_removed_levels_for_system(ship, systemName)
    local removed = temporarilyRemovedLevels[systemName] or 0
    if removed <= 0 then return end

    local sys = get_system(ship, systemName)
    if sys then
        for _ = 1, removed do
            sys:UpgradeSystem(1)
        end
    end

    temporarilyRemovedLevels[systemName] = nil
end

local function clamp_system_to_augmented_limit(ship, systemName, bonus)
    local sys = get_system(ship, systemName)
    if not sys then return end

    local allowedMax = get_augmented_limit(systemName, bonus)
    if allowedMax <= 0 then return end

    local actualMax = sys:GetMaxPower()
    local removed = temporarilyRemovedLevels[systemName] or 0
    local trueMax = actualMax + removed
    local excess = trueMax - allowedMax

    if excess <= 0 then return end

    if removed > 0 then
        local removeFromStored = math.min(excess, removed)
        removed = removed - removeFromStored
        excess = excess - removeFromStored
        temporarilyRemovedLevels[systemName] = removed > 0 and removed or nil
    end

    if excess > 0 then
        for _ = 1, excess do
            sys:UpgradeSystem(-1)
        end
    end
end

local function enforce_augmented_limits(ship, desired)
    desired = desired or get_desired_system_upgrades(ship)

    local checkedSystems = {}

    for systemName in pairs(SYSTEM_CAP_FALLBACKS) do
        if systemName ~= "reactor" then
            checkedSystems[systemName] = true
            clamp_system_to_augmented_limit(ship, systemName, desired[systemName] or 0)
        end
    end

    for systemName, bonus in pairs(desired) do
        if not checkedSystems[systemName] then
            checkedSystems[systemName] = true
            clamp_system_to_augmented_limit(ship, systemName, bonus)
        end
    end

    for systemName in pairs(temporarilyRemovedLevels) do
        if not checkedSystems[systemName] then
            clamp_system_to_augmented_limit(ship, systemName, desired[systemName] or 0)
        end
    end
end

local function update_temporary_levels_for_upgrade_screen(ship)
    if ship.iShipId ~= 0 or updatingSystemLevels then return end

    updatingSystemLevels = true

    local desired = get_desired_system_upgrades(ship)
    enforce_augmented_limits(ship, desired)

    local handledSystems = {}

    for systemName, bonus in pairs(desired) do
        handledSystems[systemName] = true

        local sys = get_system(ship, systemName)
        local naturalCap = mods.sc.system_caps.get_cap(systemName)

        if sys and naturalCap > 0 then
            local trueMax = get_true_system_max_for_ui(ship, systemName)
            local targetRemoved = get_target_temp_levels_to_remove(trueMax, naturalCap, bonus)
            local currentRemoved = temporarilyRemovedLevels[systemName] or 0
            local difference = targetRemoved - currentRemoved

            if difference > 0 then
                for _ = 1, difference do
                    sys:UpgradeSystem(-1)
                end
            elseif difference < 0 then
                for _ = 1, -difference do
                    sys:UpgradeSystem(1)
                end
            end

            if difference ~= 0 then
                temporarilyRemovedLevels[systemName] = targetRemoved > 0 and targetRemoved or nil
            end
        else
            restore_removed_levels_for_system(ship, systemName)
        end
    end

    for systemName in pairs(temporarilyRemovedLevels) do
        if not handledSystems[systemName] then
            restore_removed_levels_for_system(ship, systemName)
        end
    end

    enforce_augmented_limits(ship, desired)

    upgradeTabActive = true
    updatingSystemLevels = false
end

local function restore_all_removed_levels(ship)
    if ship.iShipId ~= 0 or updatingSystemLevels then return end

    updatingSystemLevels = true

    for systemName in pairs(temporarilyRemovedLevels) do
        restore_removed_levels_for_system(ship, systemName)
    end

    upgradeTabActive = false
    enforce_augmented_limits(ship)

    updatingSystemLevels = false
end

local function get_manual_subsystem_slot(ship, systemName)
    local slot = 0

    for _, name in ipairs(SUBSYSTEM_ORDER) do
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

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    if ship.iShipId ~= 0 or updatingSystemLevels then return end

    if upgradeTabActive then
        update_temporary_levels_for_upgrade_screen(ship)
    else
        updatingSystemLevels = true
        enforce_augmented_limits(ship)
        updatingSystemLevels = false
    end
end)

script.on_render_event(
    Defines.RenderEvents.TABBED_WINDOW,
    function(currentTab)
        local ship = Hyperspace.ships.player
        if not ship then return end

        if tostring(currentTab) == "upgrades" then
            update_temporary_levels_for_upgrade_screen(ship)
        else
            restore_all_removed_levels(ship)
        end
    end,
    function(currentTab)
        if tostring(currentTab) ~= "upgrades" then return end

        local ship = Hyperspace.ships.player
        if not ship then return end

        update_temporary_levels_for_upgrade_screen(ship)

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
)

local function restore_player_upgrade_levels()
    local ship = Hyperspace.ships.player
    if not ship then return end

    restore_all_removed_levels(ship)
end

script.on_internal_event(Defines.InternalEvents.TABBED_WINDOW_CONFIRM, restore_player_upgrade_levels)
script.on_internal_event(Defines.InternalEvents.TABBED_WINDOW_UNDO, restore_player_upgrade_levels)