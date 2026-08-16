--[[
DESCRIPTION: Battery power supplied to Engines increases ship dodge.
TAG: <sc-battery-dodge/>
DEPENDENCIES: sc_augment_battery.lua
]]

local helpers = mods.sc.helpers or require("mods.sc.helpers")
local battery = mods.sc.battery

mods.sc.batteryDodgeAugments = mods.sc.batteryDodgeAugments or {}
local dodgeAugments = mods.sc.batteryDodgeAugments

mods.sc.tag.register_augment_flag_tag("sc-battery-dodge", dodgeAugments)

local PILOT_SYSTEM_ID = 6

local function piloting_allows_positive_dodge(shipManager)
    local piloting = shipManager:GetSystem(PILOT_SYSTEM_ID)
    if not piloting or piloting:CompletelyDestroyed() then return false end
    if not piloting.bManned then return false end

    return piloting:GetEffectivePower() > 0
end

script.on_internal_event(
    Defines.InternalEvents.GET_DODGE_FACTOR,
    function(shipManager, dodge)
        if not helpers.ship_has_augment(shipManager, dodgeAugments) then return end
        if not battery.is_active(shipManager) then return end

        local batteryPow, systemPow, systemLvl =
            battery.get_system_power_info(shipManager, "engines")
        local activationTimer =
            battery.get_system_activation(shipManager, "engines")

        if batteryPow < 1 or activationTimer <= 0 then return end

        local bonus =
            activationTimer
            * (2.0 + (0.4 * systemLvl) - (0.47 * systemPow))

        bonus = math.floor(bonus * batteryPow)

        if bonus > 0 and not piloting_allows_positive_dodge(shipManager) then
            bonus = 0
        end

        if bonus == 0 then return end

        return 0, dodge + bonus
    end
)