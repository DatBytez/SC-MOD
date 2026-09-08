mods.sc = mods.sc or {}
mods.sc.augmentUpgrades = mods.sc.augmentUpgrades or {}
mods.sc.system_caps = mods.sc.system_caps or {}

local augmentUpgrades = mods.sc.augmentUpgrades
local upgradeBaseCaps = {}

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

local SYSTEM_NAME_ALIASES = {
    shield = "shields",
    engine = "engines",
    weapon = "weapons",
    drone = "drones",
    pilot = "piloting",
    clone = "clonebay",
    mind_control = "mind",
    mindcontrol = "mind"
}

local SYSTEM_BASE_CAPS = {
    shields = 16,
    engines = 8,
    oxygen = 3,
    weapons = 8,
    drones = 15,
    medbay = 3,
    piloting = 3,
    sensors = 3,
    doors = 3,
    teleporter = 4,
    cloaking = 3,
    artillery = 5,
    battery = 2,
    clonebay = 3,
    mind = 3,
    hacking = 3,
    temporal = 3,
    lily_system_bracers = 3
}

local EXTERNAL_CHECK_INTERVAL = 15
local externalCheckCounter = 0
local applyingMaxLevels = false
local lastApplied = {}

local function normalize_system_name(system)
    if type(system) == "number" then
        system = SYSTEM_NAMES_BY_ID[system]
    end

    if type(system) ~= "string" then
        return nil
    end

    system = string.lower(system)

    return SYSTEM_NAME_ALIASES[system] or system
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
    local normalized = normalize_system_name(systemName)
    if not normalized or not baseCap or baseCap <= 0 then return end

    if not upgradeBaseCaps[normalized] or baseCap < upgradeBaseCaps[normalized] then
        upgradeBaseCaps[normalized] = baseCap
    end
end

mods.sc.tag.register("augment", "sc-upgrade", augmentUpgrades, function(tagNode, blueprintNode)
    local entries = {}

    while tagNode do
        local systemName = normalize_system_name(get_attribute_value(tagNode, "system"))
        local value = get_number_attribute(tagNode, "value") or 0
        local baseCap = get_number_attribute(tagNode, "base") or get_number_attribute(tagNode, "baseCap") or get_number_attribute(tagNode, "cap")

        if systemName and value ~= 0 then
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
    local systemName = normalize_system_name(system)
    if not systemName then return 0 end

    local scriptedBaseCap = upgradeBaseCaps[systemName] or SYSTEM_BASE_CAPS[systemName] or 0
    local rawCap = Hyperspace.playerVariables[systemName .. "_cap"]

    if rawCap and rawCap > 0 then
        if scriptedBaseCap > 0 then
            return math.min(rawCap, scriptedBaseCap)
        end

        return rawCap
    end

    return scriptedBaseCap
end

local function get_player_ship()
    return Hyperspace.ships and Hyperspace.ships.player or nil
end

local function append_system_if_present(systems, sys)
    if sys then
        table.insert(systems, sys)
    end
end

local function get_systems(ship, systemName)
    local systems = {}
    if not ship or not systemName then return systems end

    local normalized = normalize_system_name(systemName)
    if not normalized then return systems end

    local systemId = Hyperspace.ShipSystem.NameToSystemId(normalized)
    if not systemId or systemId < 0 then return systems end

    if normalized == "artillery" and ship.artillerySystems and vter then
        for sys in vter(ship.artillerySystems) do
            append_system_if_present(systems, sys)
        end

        if #systems > 0 then
            return systems
        end
    end

    if ship:HasSystem(systemId) then
        append_system_if_present(systems, ship:GetSystem(systemId))
    end

    return systems
end

local function get_tracked_systems()
    local trackedSystems = {}

    for systemName in pairs(SYSTEM_BASE_CAPS) do
        trackedSystems[systemName] = true
    end

    for systemName in pairs(upgradeBaseCaps) do
        trackedSystems[systemName] = true
    end

    for _, upgrades in pairs(augmentUpgrades) do
        for _, upgrade in ipairs(upgrades) do
            local systemName = normalize_system_name(upgrade.system)

            if systemName and mods.sc.system_caps.get_cap(systemName) > 0 then
                trackedSystems[systemName] = true
            end
        end
    end

    return trackedSystems
end

local function get_active_upgrade_bonus(ship, systemName)
    local normalized = normalize_system_name(systemName)
    if not ship or not normalized then return 0 end

    local bonus = 0

    for augName, upgrades in pairs(augmentUpgrades) do
        local count = ship:HasAugmentation(augName) or 0

        if count > 0 then
            for _, upgrade in ipairs(upgrades) do
                if normalize_system_name(upgrade.system) == normalized then
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

local function apply_effective_max_to_system_instance(ship, systemName, sys, instanceIndex, force)
    local normalized = normalize_system_name(systemName)
    if not ship or ship.iShipId ~= 0 or not normalized or not sys then return end

    local baseCap = mods.sc.system_caps.get_cap(normalized)
    if baseCap <= 0 then return end

    local bonus = get_active_upgrade_bonus(ship, normalized)
    local effectiveMax = baseCap + bonus
    local purchasedMax = sys:GetMaxPower() or 0
    local stateKey = normalized .. "#" .. tostring(instanceIndex or 1)
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

local function apply_effective_max_for_system(ship, systemName, force)
    local systems = get_systems(ship, systemName)

    for index, sys in ipairs(systems) do
        apply_effective_max_to_system_instance(ship, systemName, sys, index, force)
    end
end

local function apply_all_effective_max(force)
    if applyingMaxLevels then return end

    local ship = get_player_ship()
    if not ship or ship.iShipId ~= 0 then return end

    applyingMaxLevels = true

    local trackedSystems = get_tracked_systems()

    for systemName in pairs(trackedSystems) do
        apply_effective_max_for_system(ship, systemName, force)
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
