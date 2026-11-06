--[[
DESCRIPTION: Shared state and dodge-to-accuracy calculation for the Terran Strafe ability.
        - Converts half of current dodge into accuracy while the Strafe effect is active.
TAG: <sc-strafe/>
DEPENDENCIES: sc_tag.lua, sc_button_ui.lua, sc_helpers.lua
]]

mods.sc.strafe = mods.sc.strafe or {}

local strafe = mods.sc.strafe
local helpers = mods.sc.helpers
local buttonTimer = mods.sc.buttonTimer

local STRAFE_BUTTON = "terran_strafe"
local PILOT_SYSTEM_ID = Hyperspace.ShipSystem.NameToSystemId("pilot")

local strafeAugments = {}
mods.sc.tag.register("augment", "sc-strafe", strafeAugments, "value")

local accuracyBonus = {
    [0] = 0,
    [1] = 0
}

local dodgeRefreshInProgress = {
    [0] = false,
    [1] = false
}

local dodgeEventSerial = {
    [0] = 0,
    [1] = 0
}

strafe.BUTTON_NAME = STRAFE_BUTTON
strafe.SYSTEM_ID = PILOT_SYSTEM_ID

function strafe.get_system_id(ship)
    if not ship then return nil end

    for augmentName, systemName in pairs(strafeAugments) do
        if ship:HasAugmentation(augmentName) > 0 then
            local systemId = helpers.system_id_from_name(systemName)

            if systemId then
                return systemId
            end
        end
    end

    return nil
end

function strafe.has_augment(ship)
    return helpers.ship_has_augment(ship, strafeAugments)
end

function strafe.is_active(ship)
    if not ship then return false end

    local strafeSystem = ship:GetSystem(PILOT_SYSTEM_ID)

    return strafeSystem
        and strafeSystem.bManned
        and strafe.has_augment(ship)
        and buttonTimer.is_active(STRAFE_BUTTON, ship.iShipId)
end

function strafe.clear_accuracy(ship)
    accuracyBonus[ship.iShipId] = 0
end

local function update_accuracy_bonus_from_dodge(ship, dodge)
    local shipId = ship.iShipId

    if not strafe.is_active(ship) then
        accuracyBonus[shipId] = 0
        return 0
    end

    local effectiveDodge = dodge or 0

    if ship.cloakSystem and ship.cloakSystem.bTurnedOn then
        effectiveDodge = effectiveDodge + 60
    end

    local removedAmount = math.floor(effectiveDodge / 2)

    accuracyBonus[shipId] = removedAmount
    return removedAmount
end

function strafe.refresh_accuracy(ship)
    local shipId = ship.iShipId

    if not strafe.is_active(ship) then
        accuracyBonus[shipId] = 0
        return 0
    end

    if dodgeRefreshInProgress[shipId] then
        return accuracyBonus[shipId] or 0
    end

    dodgeRefreshInProgress[shipId] = true

    local serialBefore = dodgeEventSerial[shipId] or 0
    local success, dodge = pcall(function()
        return ship:GetDodgeFactor()
    end)

    dodgeRefreshInProgress[shipId] = false

    if success
        and type(dodge) == "number"
        and (dodgeEventSerial[shipId] or 0) == serialBefore then

        update_accuracy_bonus_from_dodge(ship, dodge)
    end

    return accuracyBonus[shipId] or 0
end

script.on_internal_event(Defines.InternalEvents.GET_DODGE_FACTOR, function(ship, dodge)
    local shipId = ship.iShipId

    dodgeEventSerial[shipId] = (dodgeEventSerial[shipId] or 0) + 1
    update_accuracy_bonus_from_dodge(ship, dodge)

    return Defines.Chain.CONTINUE, dodge
end)

script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, function()
    accuracyBonus[0] = 0
    accuracyBonus[1] = 0
end)