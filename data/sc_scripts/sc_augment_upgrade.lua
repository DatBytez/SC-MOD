--[[
DESCRIPTION: Applies augment-driven increases to player system upgrade caps.
        - Maintains base caps for standard and custom systems.
        - Adds bonuses from installed augments with the <sc-upgrade> tag.
        - Clamps purchased levels if an upgrade bonus is removed.
        - Handles multiple artillery system instances.
        - Exposes base-cap lookup through mods.sc.system_caps.get_cap.
TAG: <sc-upgrade system="SYSTEM_NAME" value="#"/>
DEPENDENCIES: sc_tag.lua, Multiverse vter
]]

local vter = mods.multiverse.vter

mods.sc = mods.sc or {}
mods.sc.augmentUpgrades = mods.sc.augmentUpgrades or {}
mods.sc.system_caps = mods.sc.system_caps or {}

local augmentUpgrades = mods.sc.augmentUpgrades
local systemCaps = mods.sc.system_caps

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
local trackedSystems = {}

mods.sc.tag.register("augment", "sc-upgrade", augmentUpgrades, "system")


-- ============================================================================
-- System Cap Data
-- ============================================================================

local function system_id_from_name(systemName)
    local systemId = Hyperspace.ShipSystem.NameToSystemId(systemName)

    if type(systemId) == "number" and systemId >= 0 then
        return systemId
    end

    return nil
end

for systemId, baseCap in pairs(BASE_CAPS_BY_ID) do
    trackedSystems[#trackedSystems + 1] = {
        systemId = systemId,
        baseCap = baseCap
    }
end

for systemName, baseCap in pairs(CUSTOM_BASE_CAPS_BY_NAME) do
    trackedSystems[#trackedSystems + 1] = {
        systemName = systemName,
        baseCap = baseCap
    }
end

function systemCaps.get_cap(system)
    if type(system) == "number" then
        return BASE_CAPS_BY_ID[system] or 0
    end
    if type(system) ~= "string" then return 0 end

    local systemId = system_id_from_name(system)
    return (systemId and BASE_CAPS_BY_ID[systemId]) or CUSTOM_BASE_CAPS_BY_NAME[system] or 0
end


-- ============================================================================
-- Upgrade Bonuses
-- ============================================================================

local function upgrade_matches_system(upgrade, trackedSystem)
    if trackedSystem.systemId ~= nil then
        return system_id_from_name(upgrade.system) == trackedSystem.systemId
    end

    return upgrade.system == trackedSystem.systemName
end

local function get_active_upgrade_bonus(ship, trackedSystem)
    local bonus = 0

    for augName, upgrades in pairs(augmentUpgrades) do
        local count = ship:HasAugmentation(augName)

        if count > 0 then
            for _, upgrade in ipairs(upgrades) do
                if upgrade.value > 0 and upgrade_matches_system(upgrade, trackedSystem) then
                    bonus = bonus + upgrade.value * count
                end
            end
        end
    end

    return bonus
end


-- ============================================================================
-- System Cap Application
-- ============================================================================

local function get_system_instances(ship, trackedSystem)
    local systems = {}

    if trackedSystem.systemId == 11 and ship.artillerySystems then
        for system in vter(ship.artillerySystems) do
            systems[#systems + 1] = system
        end

        if #systems > 0 then
            return systems
        end
    end

    local systemId = trackedSystem.systemId or system_id_from_name(trackedSystem.systemName)

    if systemId and ship:HasSystem(systemId) then
        systems[1] = ship:GetSystem(systemId)
    end

    return systems
end

local function clamp_purchased_levels(system, effectiveMax)
    local excess = system:GetMaxPower() - effectiveMax

    for _ = 1, math.max(excess, 0) do
        system:UpgradeSystem(-1)
    end
end

local function apply_effective_max(ship, trackedSystem)
    local effectiveMax = trackedSystem.baseCap + get_active_upgrade_bonus(ship, trackedSystem)

    for _, system in ipairs(get_system_instances(ship, trackedSystem)) do
        if system.maxLevel ~= effectiveMax or system:GetMaxPower() > effectiveMax then
            system.maxLevel = effectiveMax
            clamp_purchased_levels(system, effectiveMax)
        end
    end
end

local function apply_all_effective_max()
    local ship = Hyperspace.ships.player
    if not ship then return end

    for _, trackedSystem in ipairs(trackedSystems) do
        apply_effective_max(ship, trackedSystem)
    end
end


-- ============================================================================
-- Event Hooks
-- ============================================================================

local function handle_upgrade_tab(currentTab)
    if tostring(currentTab) == "upgrades" then
        apply_all_effective_max()
    end
end

script.on_render_event(
    Defines.RenderEvents.TABBED_WINDOW,
    handle_upgrade_tab,
    handle_upgrade_tab
)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    if ship.iShipId ~= 0 then return end

    externalCheckCounter = externalCheckCounter + 1
    if externalCheckCounter < EXTERNAL_CHECK_INTERVAL then return end

    externalCheckCounter = 0
    apply_all_effective_max()
end)