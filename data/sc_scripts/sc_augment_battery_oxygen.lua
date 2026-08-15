--[[
DESCRIPTION: Battery power supplied to Oxygen increases oxygen refill speed.
TAG: <sc-battery-oxygen/>
DEPENDENCIES: sc_augment_battery.lua
]]

local helpers = mods.sc.helpers or require("mods.sc.helpers")
local battery = mods.sc.battery

mods.sc.batteryOxygenAugments = mods.sc.batteryOxygenAugments or {}
local oxygenAugments = mods.sc.batteryOxygenAugments

mods.sc.tag.register_augment_flag_tag("sc-battery-oxygen", oxygenAugments)

local O2_REFILL_FACTOR_PER_SCALE = 5.00

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if not helpers.ship_has_augment(shipManager, oxygenAugments) then return end
    if not battery.is_active(shipManager) then return end

    local oxygenSystem = helpers.get_system_by_name(shipManager, "oxygen")
    local oxygen = shipManager.oxygenSystem

    if not (oxygenSystem and oxygen and oxygenSystem:Powered()) then return end

    local oxygenBatteryPow = oxygenSystem.iBatteryPower
    if oxygenBatteryPow <= 0 then return end

    local activationTimer = battery.get_activation(shipManager)
    if activationTimer <= 0 then return end

    local oxygenSystemPow = oxygenSystem:GetEffectivePower()
    if oxygenSystemPow <= 0 then return end

    local tick = Hyperspace.FPS.SpeedFactor / 16
    local refill = oxygen:GetRefillSpeed()
    local scale = oxygenBatteryPow * oxygenSystemPow
    local extraFactor =
        activationTimer * O2_REFILL_FACTOR_PER_SCALE * scale
    local delta = refill * tick * extraFactor

    if delta == 0 then return end

    local levels = oxygen.oxygenLevels

    for i = 0, levels:size() - 1 do
        levels[i] = math.min(
            math.max(levels[i] + delta, 0),
            100
        )
    end
end)
