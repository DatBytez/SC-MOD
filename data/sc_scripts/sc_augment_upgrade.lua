--[[
DESCRIPTION: Increases systems maximum based on augment upgrades.
        - Allows temporary Comsat Sensors levels without enforcing the normal Sensors cap.
        - Applies upgrades to all artillery system instances.
TAG: <sc-upgrade system="SYSTEM_NAME" value="#"/>
DEPENDENCIES: sc_tag.lua, sc_helpers.lua, Multiverse vter
]]

local vter = mods.multiverse.vter
local helpers = mods.sc.helpers
local augmentUpgrades = {}

local SYSTEMS = {
    shields = {baseCap = 16},
    engines = {baseCap = 8},
    oxygen = {baseCap = 3},
    weapons = {baseCap = 8},
    drones = {baseCap = 15},
    medbay = {baseCap = 3},
    pilot = {baseCap = 3},
    sensors = {baseCap = 3},
    doors = {baseCap = 3},
    teleporter = {baseCap = 4},
    cloaking = {baseCap = 2},
    artillery = {baseCap = 5},
    battery = {baseCap = 2},
    clonebay = {baseCap = 3},
    mind = {baseCap = 3},
    hacking = {baseCap = 3},
    temporal = {baseCap = 3},
    lily_system_bracers = {baseCap = 3}
}

mods.sc.tag.register("augment", "sc-upgrade", augmentUpgrades, "system")

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

    if systemName == "sensors"
        and mods.sc.comsat
        and mods.sc.comsat.get_temporary_sensor_cap_bonus then

        effectiveMax = effectiveMax + mods.sc.comsat.get_temporary_sensor_cap_bonus(ship)
    end

    if systemName == "artillery" and ship.artillerySystems then
        local foundArtillery = false

        for system in vter(ship.artillerySystems) do
            foundArtillery = true
            apply_max_to_system(system, effectiveMax)
        end

        if foundArtillery then return end
    end

    local systemId = helpers.system_id_from_name(systemName)

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