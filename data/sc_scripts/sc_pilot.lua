--[[
DESCRIPTION: Shared state and dodge-to-accuracy calculation for the Terran pilot ability.
        - Converts half of current dodge into accuracy while the pilot effect is active.
DEPENDENCIES: sc_button_ui.lua, sc_helpers.lua
]]

mods.sc.pilot = mods.sc.pilot or {}

local pilot = mods.sc.pilot
local helpers = mods.sc.helpers
local buttonTimer = mods.sc.buttonTimer

local PILOT_BUTTON = "terran_pilot"
local PILOT_AUGMENT = "TERRAN_SHIP_ARMOR_LIGHT"
local PILOT_SYSTEM_ID = 6

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

pilot.BUTTON_NAME = PILOT_BUTTON
pilot.SYSTEM_ID = PILOT_SYSTEM_ID

function pilot.has_augment(ship)
    return helpers.ship_has_augment(ship, PILOT_AUGMENT)
end

function pilot.is_active(ship)
    return buttonTimer.is_active(PILOT_BUTTON, ship.iShipId)
        and pilot.has_augment(ship)
        and ship:GetSystem(PILOT_SYSTEM_ID).bManned
end

function pilot.clear_accuracy(ship)
    accuracyBonus[ship.iShipId] = 0
end

local function update_accuracy_bonus_from_dodge(ship, dodge)
    local shipId = ship.iShipId

    if not pilot.is_active(ship) then
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

function pilot.refresh_accuracy(ship)
    local shipId = ship.iShipId

    if not pilot.is_active(ship) then
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