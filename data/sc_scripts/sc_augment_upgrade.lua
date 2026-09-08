mods.sc = mods.sc or {}
mods.sc.augmentUpgrades = mods.sc.augmentUpgrades or {}
mods.sc.system_caps = mods.sc.system_caps or {}

local augmentUpgrades = mods.sc.augmentUpgrades
local upgradeBaseCapsByName = {}
local upgradeBaseCapsById = {}

local BASE_CAPS_BY_ID = {
    [0] = 16, -- shields
    [1] = 8,  -- engines
    [2] = 3,  -- oxygen
    [3] = 8,  -- weapons
    [4] = 15, -- drones
    [5] = 3,  -- medbay
    [6] = 3,  -- pilot
    [7] = 3,  -- sensors
    [8] = 3,  -- doors
    [9] = 4,  -- teleporter
    [10] = 3, -- cloaking
    [11] = 5, -- artillery
    [12] = 2, -- battery
    [13] = 3, -- clonebay
    [14] = 3, -- mind
    [15] = 3, -- hacking
    [20] = 3  -- temporal
}

local CUSTOM_BASE_CAPS_BY_NAME = {
    lily_system_bracers = 3
}

local EXTERNAL_CHECK_INTERVAL = 15
local externalCheckCounter = 0
local applyingMaxLevels = false
local lastApplied = {}

local function system_id_from_name(systemName)
    if type(systemName) ~= "string" or systemName == "" then return nil end

    local systemId = Hyperspace.ShipSystem.NameToSystemId(systemName)
    if type(systemId) == "number" and systemId >= 0 then
        return systemId
    end

    return nil
end

local function get_attribute_value(node, attributeName)
    local attribute = node:first_attribute(attributeName)
    return attribute and attribute:value() or nil
end

local function get_number_attribute(node, attributeName)
    local value = get_attribute_value(node, attributeName)
    if value == nil then return nil end

    return tonumber(value)
end

local function remember_tag_base_cap(systemName, baseCap)
    if type(systemName) ~= "string" or systemName == "" or not baseCap or baseCap <= 0 then return end

    local systemId = system_id_from_name(systemName)

    if systemId ~= nil and BASE_CAPS_BY_ID[systemId] then
        if not upgradeBaseCapsById[systemId] or baseCap < upgradeBaseCapsById[systemId] then
            upgradeBaseCapsById[systemId] = baseCap
        end

        return
    end

    if not upgradeBaseCapsByName[systemName] or baseCap < upgradeBaseCapsByName[systemName] then
        upgradeBaseCapsByName[systemName] = baseCap
    end
end

mods.sc.tag.register("augment", "sc-upgrade", augmentUpgrades, function(tagNode, blueprintNode)
    local entries = {}

    while tagNode do
        local systemName = get_attribute_value(tagNode, "system")
        local value = get_number_attribute(tagNode, "value") or 0
        local baseCap = get_number_attribute(tagNode, "base") or get_number_attribute(tagNode, "baseCap") or get_number_attribute(tagNode, "cap")

        if type(systemName) == "string" and systemName ~= "" and value ~= 0 then
            table.insert(entries, {
                system = systemName,
                value = value,
                base = baseCap
            })

            remember_tag_base_cap(systemName, baseCap)
        end

        tagNode = tagNode:next_sibling("sc-upgrade")
    end

    if #entries > 0 then
        return entries
    end

    return nil
end)

function mods.sc.system_caps.get_cap(system)
    if type(system) == "number" then
        return upgradeBaseCapsById[system] or BASE_CAPS_BY_ID[system] or 0
    end

    if type(system) ~= "string" then
        return 0
    end

    local systemId = system_id_from_name(system)

    if systemId ~= nil then
        local idBaseCap = upgradeBaseCapsById[systemId] or BASE_CAPS_BY_ID[systemId]
        if idBaseCap then
            return idBaseCap
        end
    end

    return upgradeBaseCapsByName[system] or CUSTOM_BASE_CAPS_BY_NAME[system] or 0
end

local function get_player_ship()
    return Hyperspace.ships and Hyperspace.ships.player or nil
end

local function add_system_instance(systems, sys)
    if sys then
        table.insert(systems, sys)
    end
end

local function get_system_instances(ship, systemId, systemName)
    local systems = {}
    if not ship then return systems end

    if systemId == 11 and ship.artillerySystems and vter then
        for sys in vter(ship.artillerySystems) do
            add_system_instance(systems, sys)
        end

        if #systems > 0 then
            return systems
        end
    end

    if systemId == nil then
        systemId = system_id_from_name(systemName)
    end

    if systemId ~= nil and ship:HasSystem(systemId) then
        add_system_instance(systems, ship:GetSystem(systemId))
    end

    return systems
end

local function add_tracked_system(trackedSystems, systemId, systemName, baseCap)
    if not baseCap or baseCap <= 0 then return end

    local key = systemId ~= nil and ("id:" .. tostring(systemId)) or ("name:" .. tostring(systemName))
    trackedSystems[key] = {
        systemId = systemId,
        systemName = systemName,
        baseCap = baseCap
    }
end

local function get_tracked_systems()
    local trackedSystems = {}

    for systemId, baseCap in pairs(BASE_CAPS_BY_ID) do
        add_tracked_system(trackedSystems, systemId, nil, baseCap)
    end

    for systemName, baseCap in pairs(CUSTOM_BASE_CAPS_BY_NAME) do
        add_tracked_system(trackedSystems, nil, systemName, baseCap)
    end

    for systemId, baseCap in pairs(upgradeBaseCapsById) do
        add_tracked_system(trackedSystems, systemId, nil, baseCap)
    end

    for systemName, baseCap in pairs(upgradeBaseCapsByName) do
        add_tracked_system(trackedSystems, nil, systemName, baseCap)
    end

    return trackedSystems
end

local function upgrade_matches_system(upgrade, systemId, systemName)
    if not upgrade or type(upgrade.system) ~= "string" then return false end

    if systemId ~= nil then
        return system_id_from_name(upgrade.system) == systemId
    end

    return system_id_from_name(upgrade.system) == nil and upgrade.system == systemName
end

local function get_active_upgrade_bonus(ship, systemId, systemName)
    if not ship then return 0 end

    local bonus = 0

    for augName, upgrades in pairs(augmentUpgrades) do
        local count = ship:HasAugmentation(augName) or 0

        if count > 0 then
            for _, upgrade in ipairs(upgrades) do
                if upgrade_matches_system(upgrade, systemId, systemName) then
                    local value = upgrade.value or 0

                    if value > 0 then
                        bonus = bonus + value * count
                    end
                end
            end
        end
    end

    return bonus
end

local function clamp_purchased_levels(sys, effectiveMax)
    if not sys or effectiveMax <= 0 then return end

    local currentMax = sys:GetMaxPower() or 0
    local excess = currentMax - effectiveMax

    if excess <= 0 then return end

    for _ = 1, excess do
        sys:UpgradeSystem(-1)
    end
end

local function apply_effective_max_to_system_instance(ship, trackedSystem, sys, instanceIndex, force)
    if not ship or ship.iShipId ~= 0 or not trackedSystem or not sys then return end

    local baseCap = trackedSystem.baseCap or 0
    if baseCap <= 0 then return end

    local bonus = get_active_upgrade_bonus(ship, trackedSystem.systemId, trackedSystem.systemName)
    local effectiveMax = baseCap + bonus
    local purchasedMax = sys:GetMaxPower() or 0
    local stateKey = trackedSystem.systemId ~= nil
        and ("id:" .. tostring(trackedSystem.systemId) .. "#" .. tostring(instanceIndex or 1))
        or ("name:" .. tostring(trackedSystem.systemName) .. "#" .. tostring(instanceIndex or 1))
    local state = lastApplied[stateKey] or {}

    local needsUpdate =
        force or
        state.bonus ~= bonus or
        state.maxLevel ~= effectiveMax or
        state.purchasedMax ~= purchasedMax or
        sys.maxLevel ~= effectiveMax or
        purchasedMax > effectiveMax

    if not needsUpdate then return end

    sys.maxLevel = effectiveMax
    clamp_purchased_levels(sys, effectiveMax)

    lastApplied[stateKey] = {
        bonus = bonus,
        maxLevel = effectiveMax,
        purchasedMax = sys:GetMaxPower() or 0
    }
end

local function apply_effective_max_for_tracked_system(ship, trackedSystem, force)
    local systems = get_system_instances(ship, trackedSystem.systemId, trackedSystem.systemName)

    for index, sys in ipairs(systems) do
        apply_effective_max_to_system_instance(ship, trackedSystem, sys, index, force)
    end
end

local function apply_all_effective_max(force)
    if applyingMaxLevels then return end

    local ship = get_player_ship()
    if not ship or ship.iShipId ~= 0 then return end

    applyingMaxLevels = true

    local trackedSystems = get_tracked_systems()

    for _, trackedSystem in pairs(trackedSystems) do
        apply_effective_max_for_tracked_system(ship, trackedSystem, force)
    end

    applyingMaxLevels = false
end

local function handle_upgrade_tab(currentTab)
    if tostring(currentTab) ~= "upgrades" then return end

    apply_all_effective_max(true)
end

script.on_render_event(
    Defines.RenderEvents.TABBED_WINDOW,
    handle_upgrade_tab,
    handle_upgrade_tab
)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    if not ship or ship.iShipId ~= 0 then return end

    externalCheckCounter = externalCheckCounter + 1
    if externalCheckCounter < EXTERNAL_CHECK_INTERVAL then return end

    externalCheckCounter = 0
    apply_all_effective_max(false)
end)
