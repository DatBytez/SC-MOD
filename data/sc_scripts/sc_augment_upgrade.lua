mods.sc = mods.sc or {}
mods.sc.augmentUpgrades = mods.sc.augmentUpgrades or {}

local augmentUpgrades = mods.sc.augmentUpgrades

mods.sc.tag.register_augment_tag("sc-upgrade", augmentUpgrades)

local updating_system_values = false
local tabbed_window_bonus_removed = false

local function get_system_base_key(systemName)
    return "sc_upgrade_base_" .. systemName
end

local function get_system_upgrade_key(systemName)
    return "sc_upgrade_amount_" .. systemName
end

local function get_system_removed_key(systemName)
    return "sc_upgrade_removed_" .. systemName
end

local function set_saved_base_max(systemName, amount)
    Hyperspace.playerVariables[get_system_base_key(systemName)] = amount or 0
end

local function get_saved_base_max(systemName)
    return Hyperspace.playerVariables[get_system_base_key(systemName)] or 0
end

local function get_saved_applied_amount(systemName)
    return Hyperspace.playerVariables[get_system_upgrade_key(systemName)] or 0
end

local function set_saved_applied_amount(systemName, amount)
    Hyperspace.playerVariables[get_system_upgrade_key(systemName)] = amount or 0
end

local function get_saved_removed_amount(systemName)
    return Hyperspace.playerVariables[get_system_removed_key(systemName)] or 0
end

local function set_saved_removed_amount(systemName, amount)
    Hyperspace.playerVariables[get_system_removed_key(systemName)] = amount or 0
end

local function get_all_upgrade_systems()
    local systems = {}

    for _, upgrades in pairs(augmentUpgrades) do
        for _, upgrade in ipairs(upgrades) do
            if upgrade.system then
                systems[upgrade.system] = true
            end
        end
    end

    return systems
end

local function get_desired_system_upgrades(ship)
    local desired = {}
    if not ship then return desired end

    for augName, upgrades in pairs(augmentUpgrades) do
        local count = ship:HasAugmentation(augName) or 0
        if count > 0 then
            for _, upgrade in ipairs(upgrades) do
                if upgrade.system and (upgrade.amount or 0) ~= 0 then
                    desired[upgrade.system] = (desired[upgrade.system] or 0) + (upgrade.amount or 1) * count
                end
            end
        end
    end

    return desired
end

local function update_system_base_values(ship)
    if not ship or ship.iShipId ~= 0 then return end
	--print("update_system_base_values")
    if updating_system_values then
        return
    end

    updating_system_values = true

    local systemsToCheck = get_all_upgrade_systems()

    for systemName, _ in pairs(systemsToCheck) do
        local systemId = Hyperspace.ShipSystem.NameToSystemId(systemName)
        local sys = ship:GetSystem(systemId)

        if sys then
            local currentMax = sys:GetMaxPower() or 0
            set_saved_base_max(systemName, currentMax)
        end
    end

    updating_system_values = false
end

local function apply_system_upgrade_values(ship)
    if not ship or ship.iShipId ~= 0 then return end
	--print("apply_system_upgrade_values")
    if updating_system_values then
        return
    end

    updating_system_values = true

    local desired = get_desired_system_upgrades(ship)
    local systemsToCheck = get_all_upgrade_systems()

    for systemName, _ in pairs(systemsToCheck) do
        local wanted = desired[systemName] or 0
        local current = get_saved_applied_amount(systemName)
        local diff = wanted - current

        local systemId = Hyperspace.ShipSystem.NameToSystemId(systemName)
        local sys = ship:GetSystem(systemId)

        if sys and diff ~= 0 then
            sys:UpgradeSystem(diff)
            set_saved_applied_amount(systemName, wanted)
        end
    end

    updating_system_values = false
end

local function remove_system_upgrade_values_for_tabbed_window(ship)
    if not ship or ship.iShipId ~= 0 then return end

    if updating_system_values then
        return
    end

    if tabbed_window_bonus_removed then
        return
    end

    updating_system_values = true

    local systemsToCheck = get_all_upgrade_systems()

    for systemName, _ in pairs(systemsToCheck) do
        local applied = get_saved_applied_amount(systemName)
        local systemId = Hyperspace.ShipSystem.NameToSystemId(systemName)
        local sys = ship:GetSystem(systemId)

        if sys then
            if applied ~= 0 then
                sys:UpgradeSystem(-applied)
                set_saved_removed_amount(systemName, applied)
                set_saved_applied_amount(systemName, 0)
            else
                set_saved_removed_amount(systemName, 0)
            end
        end
    end

    tabbed_window_bonus_removed = true
    updating_system_values = false
end

local function restore_system_upgrade_values_after_tabbed_window(ship)
    if not ship or ship.iShipId ~= 0 then return end

    if not tabbed_window_bonus_removed then
        return
    end

    update_system_base_values(ship)
    apply_system_upgrade_values(ship)

    local systemsToCheck = get_all_upgrade_systems()
    for systemName, _ in pairs(systemsToCheck) do
        set_saved_removed_amount(systemName, 0)
    end

    tabbed_window_bonus_removed = false
end

local function get_visual_removed_upgrade_entries()
    local entries = {}
    local systemsToCheck = get_all_upgrade_systems()

    for systemName, _ in pairs(systemsToCheck) do
        local removed = get_saved_removed_amount(systemName)
        if removed > 0 then
            entries[systemName] = removed
        end
    end

    return entries
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

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if not Hyperspace.App.world.bStartedGame then
	--print("NOT IN A RUN")
    else
    	update_system_base_values(shipManager)
    	apply_system_upgrade_values(shipManager)
    end
end)

script.on_render_event(
    Defines.RenderEvents.TABBED_WINDOW,
    function(currentTab)
        local ship = Hyperspace.ships.player
        if not ship then return end
        remove_system_upgrade_values_for_tabbed_window(ship)
    end,
    function(currentTab)
    end
)

script.on_internal_event(Defines.InternalEvents.TABBED_WINDOW_CONFIRM, function(currentTabName)
    local ship = Hyperspace.ships.player
    if not ship then return end
    restore_system_upgrade_values_after_tabbed_window(ship)
end)

script.on_internal_event(Defines.InternalEvents.TABBED_WINDOW_UNDO, function(currentTabName)
    local ship = Hyperspace.ships.player
    if not ship then return end
    restore_system_upgrade_values_after_tabbed_window(ship)
end)

script.on_render_event(
    Defines.RenderEvents.TABBED_WINDOW,
    function(currentTab)
    end,
    function(currentTab)
        if tostring(currentTab) ~= "upgrades" then return end

        local ship = Hyperspace.ships.player
        if not ship then return end

        local entries = get_visual_removed_upgrade_entries()

        local START_X = 375
        local START_Y = 453
        local SLOT_W = 66

        local BOX_W = 15
        local BOX_H = 7
        local BOX_GAP = 1
        local STEP = BOX_H + BOX_GAP

        local green = Graphics.GL_Color(0.3, 1.0, 0.3, 0.9)

        for systemName, removedBonus in pairs(entries) do
            local slot = get_manual_subsystem_slot(ship, systemName)
            if slot ~= nil then
                local systemId = Hyperspace.ShipSystem.NameToSystemId(systemName)
                local sys = ship:GetSystem(systemId)

                if sys then
                    local baseLevel = sys:GetMaxPower() or 0
                    local BOX_X = START_X + slot * SLOT_W

                    for i = 0, removedBonus - 1 do
                        local BOX_Y = START_Y - ((baseLevel + i) * STEP)
                        Graphics.CSurface.GL_DrawRectOutline(BOX_X, BOX_Y, BOX_W, BOX_H, green, 2)
                    end
                end
            end
        end
    end
)