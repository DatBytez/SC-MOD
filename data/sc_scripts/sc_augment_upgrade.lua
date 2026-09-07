mods.sc = mods.sc or {}
mods.sc.augmentUpgrades = mods.sc.augmentUpgrades or {}
mods.sc.system_caps = mods.sc.system_caps or {}

local augmentUpgrades = mods.sc.augmentUpgrades

mods.sc.tag.register("augment", "sc-upgrade", augmentUpgrades, "system")

local TEST_SYSTEM = "lily_system_bracers"
local TEST_SYSTEM_BASE_CAP = 3

local lastAppliedMaxLevel = nil
local applyingMaxLevel = false

function mods.sc.system_caps.get_cap(system)
    if system == TEST_SYSTEM then
        return TEST_SYSTEM_BASE_CAP
    end

    return 0
end

local function get_player_ship()
    return Hyperspace.ships and Hyperspace.ships.player or nil
end

local function get_test_system(ship)
    if not ship then return nil end

    local systemId = Hyperspace.ShipSystem.NameToSystemId(TEST_SYSTEM)
    if not ship:HasSystem(systemId) then return nil end

    return ship:GetSystem(systemId)
end

local function get_active_upgrade_bonus(ship)
    local bonus = 0
    if not ship then return bonus end

    for augName, upgrades in pairs(augmentUpgrades) do
        local count = ship:HasAugmentation(augName) or 0

        if count > 0 then
            for _, upgrade in ipairs(upgrades) do
                if upgrade.system == TEST_SYSTEM then
                    local value = upgrade.value or upgrade.amount or 0
                    if value > 0 then
                        bonus = bonus + value * count
                    end
                end
            end
        end
    end

    return bonus
end

local function get_effective_max_level(ship)
    return TEST_SYSTEM_BASE_CAP + get_active_upgrade_bonus(ship)
end

local function set_max_level_if_needed(sys, effectiveMax)
    if not sys or effectiveMax <= 0 then return end

    if lastAppliedMaxLevel ~= effectiveMax or sys.maxLevel ~= effectiveMax then
        sys.maxLevel = effectiveMax
        lastAppliedMaxLevel = effectiveMax
    end
end

local function clamp_purchased_levels(sys, effectiveMax)
    if not sys or effectiveMax <= 0 then return end

    local currentMax = sys:GetMaxPower() or 0
    local excess = currentMax - effectiveMax

    if excess <= 0 then return end

    for i = 1, excess do
        sys:UpgradeSystem(-1)
    end
end

local function apply_current_effective_max()
    if applyingMaxLevel then return end

    local ship = get_player_ship()
    if not ship or ship.iShipId ~= 0 then return end

    local sys = get_test_system(ship)
    if not sys then return end

    applyingMaxLevel = true

    local effectiveMax = get_effective_max_level(ship)

    set_max_level_if_needed(sys, effectiveMax)
    clamp_purchased_levels(sys, effectiveMax)
    set_max_level_if_needed(sys, effectiveMax)

    applyingMaxLevel = false
end

local function handle_tabbed_window(currentTab)
    if tostring(currentTab) ~= "upgrades" then return end

    apply_current_effective_max()
end

script.on_render_event(
    Defines.RenderEvents.TABBED_WINDOW,
    handle_tabbed_window,
    handle_tabbed_window
)

script.on_internal_event(Defines.InternalEvents.TABBED_WINDOW_CONFIRM, function(currentTabName)
    apply_current_effective_max()
end)

script.on_internal_event(Defines.InternalEvents.TABBED_WINDOW_UNDO, function(currentTabName)
    apply_current_effective_max()
end)
