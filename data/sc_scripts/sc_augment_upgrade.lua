--[[
DESCRIPTION: Increases systems maximum based on augment upgrades.
        - Requires system max to be increased in blueprints.
        - Adds bonuses from installed augments with the <sc-upgrade> tag.
        - Handles multiple artillery system instances? Untested.
TAG: <sc-upgrade system="SYSTEM_NAME" value="#"/>
DEPENDENCIES: sc_tag.lua, Multiverse vter
]]

local vter = mods.multiverse.vter

mods.sc = mods.sc or {}
mods.sc.augmentUpgrades = mods.sc.augmentUpgrades or {}

local augmentUpgrades = mods.sc.augmentUpgrades

local ARTILLERY_ID = 11
local CAP_CHECK_INTERVAL = 15

local SYSTEMS = {
    shields = {systemId = 0, baseCap = 16},
    engines = {systemId = 1, baseCap = 8},
    oxygen = {systemId = 2, baseCap = 3},
    weapons = {systemId = 3, baseCap = 8},
    drones = {systemId = 4, baseCap = 15},
    medbay = {systemId = 5, baseCap = 3},
    pilot = {systemId = 6, baseCap = 3},
    sensors = {systemId = 7, baseCap = 3},
    doors = {systemId = 8, baseCap = 3},
    teleporter = {systemId = 9, baseCap = 4},
    cloaking = {systemId = 10, baseCap = 3},
    artillery = {systemId = ARTILLERY_ID, baseCap = 5},
    battery = {systemId = 12, baseCap = 2},
    clonebay = {systemId = 13, baseCap = 3},
    mind = {systemId = 14, baseCap = 3},
    hacking = {systemId = 15, baseCap = 3},
    temporal = {systemId = 20, baseCap = 3},
    lily_system_bracers = {baseCap = 3}
}

local capCheckCounter = 0

mods.sc.tag.register("augment", "sc-upgrade", augmentUpgrades, "system")

local function system_id_from_name(systemName)
    local systemId = Hyperspace.ShipSystem.NameToSystemId(systemName)
    return systemId >= 0 and systemId or nil
end

local function get_active_upgrade_bonus(ship, systemName)
    local bonus = 0

    for augName, upgrades in pairs(augmentUpgrades) do
        local count = ship:HasAugmentation(augName)

        if count > 0 then
            for _, upgrade in ipairs(upgrades) do
                if upgrade.system == systemName then
                    bonus = bonus + upgrade.value * count
                end
            end
        end
    end

    return bonus
end

local function apply_max_to_system(system, effectiveMax)
    if system.maxLevel ~= effectiveMax then
        system.maxLevel = effectiveMax
    end

    local excess = system:GetMaxPower() - effectiveMax
    for _ = 1, math.max(excess, 0) do
        system:UpgradeSystem(-1)
    end
end

local function apply_effective_max(ship, systemName, systemData)
    local effectiveMax = systemData.baseCap + get_active_upgrade_bonus(ship, systemName)

    if systemData.systemId == ARTILLERY_ID and ship.artillerySystems then
        local foundArtillery = false

        for system in vter(ship.artillerySystems) do
            foundArtillery = true
            apply_max_to_system(system, effectiveMax)
        end

        if foundArtillery then return end
    end

    local systemId = systemData.systemId or system_id_from_name(systemName)

    if systemId and ship:HasSystem(systemId) then
        apply_max_to_system(ship:GetSystem(systemId), effectiveMax)
    end
end

local function apply_all_effective_max(ship)
    for systemName, systemData in pairs(SYSTEMS) do
        apply_effective_max(ship, systemName, systemData)
    end
end

local function handle_upgrade_tab(currentTab)
    if tostring(currentTab) ~= "upgrades" then return end

    local ship = Hyperspace.ships.player
    if ship then
        apply_all_effective_max(ship)
    end
end

script.on_render_event(Defines.RenderEvents.TABBED_WINDOW, handle_upgrade_tab, handle_upgrade_tab)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    if ship.iShipId ~= 0 then return end

    apply_all_effective_max(ship)
end)
