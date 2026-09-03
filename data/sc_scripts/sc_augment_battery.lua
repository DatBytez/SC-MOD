--[[
DESCRIPTION: Shared battery framework for tag-driven battery augments.
        - Tracks activation state per battery-powered room.
        - Renders battery-powered room visuals.
TAG: <sc-battery/>
SOURCE CREDIT: MsBinaryLily
]]

local vter = mods.multiverse.vter
local helpers = mods.sc.helpers

mods.sc = mods.sc or {}
mods.sc.battery = mods.sc.battery or {}
mods.sc.batteryAugments = mods.sc.batteryAugments or {}

local battery = mods.sc.battery
local batteryAugments = mods.sc.batteryAugments

mods.sc.tag.register("augment", "sc-battery", batteryAugments)

local BATTERY_ID = Hyperspace.ShipSystem.NameToSystemId("battery")
local ACTIVATION_RATE = 0.15

local batteryState = {}
local activeHiddenAugs = {}

local scalingHiddenAugCounts = {
    TERRAN_HIDDEN_FIRE_EXTINGUISHERS = 3,
    TERRAN_HIDDEN_FTL_BOOSTER = 9
}


-- ============================================================================
-- Battery Core API
-- ============================================================================

function battery.get_state(shipManager)
    local shipId = shipManager.iShipId

    batteryState[shipId] = batteryState[shipId] or {
        roomActivationTimers = {}
    }

    return batteryState[shipId]
end

function battery.is_active(shipManager)
    if not helpers.ship_has_augment(shipManager, batteryAugments) then return false end
    if not helpers.ship_has_working_system(shipManager, BATTERY_ID) then return false end

    return shipManager.batterySystem.bTurnedOn
end

function battery.get_system_activation(shipManager, systemName)
    local system = helpers.get_system_by_name(shipManager, systemName)
    if not system then return 0 end

    local state = battery.get_state(shipManager)
    return state.roomActivationTimers[system.roomId] or 0
end

function battery.get_system_power_info(shipManager, systemName)
    local system = helpers.get_system_by_name(shipManager, systemName)
    if not system then return 0, 0, 0 end

    return system.iBatteryPower, system:GetEffectivePower(), system:GetMaxPower()
end

function battery.get_system_battery_power(shipManager, systemName)
    local system = helpers.get_system_by_name(shipManager, systemName)
    if not system then return 0 end

    return system.iBatteryPower
end

function battery.get_system_effective_battery_power(shipManager, systemName)
    local system = helpers.get_system_by_name(shipManager, systemName)
    if not system then return 0 end

    local batteryPow = system.iBatteryPower
    if batteryPow <= 0 then return 0 end

    local activation = battery.get_system_activation(shipManager, systemName)

    return math.floor(batteryPow * activation)
end


-- ============================================================================
-- Shared Hidden Augment Helpers
-- ============================================================================

local function get_ship_hidden_aug_table(shipManager)
    local shipId = shipManager.iShipId
    activeHiddenAugs[shipId] = activeHiddenAugs[shipId] or {}
    return activeHiddenAugs[shipId]
end

function battery.set_hidden_aug(shipManager, augName, shouldEnable)
    local shipAugs = get_ship_hidden_aug_table(shipManager)
    local hiddenAug = "HIDDEN " .. augName
    local currentlyEnabled = shipAugs[augName] == true

    if shouldEnable and not currentlyEnabled then
        shipManager:AddAugmentation(hiddenAug)
        shipAugs[augName] = true
    elseif not shouldEnable and currentlyEnabled then
        shipManager:RemoveAugmentation(hiddenAug)
        shipAugs[augName] = false
    end
end

local function get_scaling_hidden_aug_count(augName)
    local count = scalingHiddenAugCounts[augName]
    if count ~= nil then return count end

    count = 0

    while augmentManager:GetAugmentDefinition(augName .. "_" .. (count + 1)) do
        count = count + 1
    end

    scalingHiddenAugCounts[augName] = count
    return count
end

function battery.clear_scaling_hidden_aug(shipManager, augName)
    local count = get_scaling_hidden_aug_count(augName)

    for power = 1, count do
        battery.set_hidden_aug(shipManager, augName .. "_" .. power, false)
    end
end

function battery.set_scaling_hidden_aug(shipManager, augName, enabled, batteryPow)
    local count = get_scaling_hidden_aug_count(augName)
    local activePower = math.min(batteryPow, count)

    for power = 1, count do
        battery.set_hidden_aug(shipManager, augName .. "_" .. power, enabled and power == activePower)
    end
end


-- ============================================================================
-- Room Activation State
-- ============================================================================

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    local state = battery.get_state(shipManager)

    if not battery.is_active(shipManager) then
        state.roomActivationTimers = {}
        return
    end

    local tick = Hyperspace.FPS.SpeedFactor / 16
    local poweredRooms = {}

    for system in vter(shipManager.vSystemList) do
        if system and system.iBatteryPower > 0 then
            poweredRooms[system.roomId] = true
        end
    end

    for roomId, _ in pairs(poweredRooms) do
        local activationTimer = state.roomActivationTimers[roomId] or 0

        state.roomActivationTimers[roomId] = math.min(
            1,
            activationTimer + ACTIVATION_RATE * tick
        )
    end

    for roomId, _ in pairs(state.roomActivationTimers) do
        if not poweredRooms[roomId] then
            state.roomActivationTimers[roomId] = nil
        end
    end
end)


-- ============================================================================
-- Ship-Floor Visuals
-- ============================================================================

local function render_battery_effects(ship)
    local shipManager = Hyperspace.ships(ship.iShipId)
    if not shipManager then return end
    if not battery.is_active(shipManager) then return end

    local level = shipManager.batterySystem:GetMaxPower()
    if level <= 0 then return end

    local rooms = ship.vRoomList
    local roomActivationTimers =
        battery.get_state(shipManager).roomActivationTimers

    for roomId, alpha in pairs(roomActivationTimers) do
        if alpha > 0 then
            local roomdata = rooms[roomId]

            if roomdata then
                local rect = roomdata.rect
                local baseG = math.min(1, (25 * level + 154) / 255)
                local color1 = Graphics.GL_Color(14 / 255, baseG, 255 / 255, alpha)
                local color2 = Graphics.GL_Color(14 / 255, baseG, 255 / 255, 0.4 * alpha)

                Graphics.CSurface.GL_PushMatrix()
                Graphics.CSurface.GL_DrawRectOutline(rect.x, rect.y, rect.w, rect.h, color2, (level + 5) * alpha)
                Graphics.CSurface.GL_DrawRectOutline(rect.x, rect.y, rect.w, rect.h, color2, (level + 3) * alpha)
                Graphics.CSurface.GL_DrawRectOutline(rect.x, rect.y, rect.w, rect.h, color1, (level + 1) * alpha)
                Graphics.CSurface.GL_PopMatrix()
            end
        end
    end
end

script.on_render_event(
    Defines.RenderEvents.SHIP_FLOOR,
    function() end,
    render_battery_effects
)