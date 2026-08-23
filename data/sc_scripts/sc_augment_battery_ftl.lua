--[[
DESCRIPTION: Battery power supplied to Engines enables a scaling hidden FTL booster.
TAG: <sc-battery-ftl/>
DEPENDENCIES: sc_augment_battery.lua
]]

local helpers = mods.sc.helpers
local battery = mods.sc.battery

mods.sc.batteryFtlAugments = mods.sc.batteryFtlAugments or {}
local ftlAugments = mods.sc.batteryFtlAugments

mods.sc.tag.register("augment", "sc-battery-ftl", ftlAugments)

local FTL_BOOSTER_AUG = "TERRAN_HIDDEN_FTL_BOOSTER"

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if not helpers.ship_has_augment(shipManager, ftlAugments)
        or not battery.is_active(shipManager)
    then
        battery.set_scaling_hidden_aug(shipManager, FTL_BOOSTER_AUG, false, 0)
        return
    end

    local enginesSystem = helpers.get_system_by_name(shipManager, "engines")

    if not (enginesSystem and enginesSystem:Powered()) then
        battery.set_scaling_hidden_aug(shipManager, FTL_BOOSTER_AUG, false, 0)
        return
    end

    local effectiveBatteryPow =
        battery.get_system_effective_battery_power(shipManager, "engines")

    battery.set_scaling_hidden_aug(shipManager, FTL_BOOSTER_AUG, effectiveBatteryPow > 0, effectiveBatteryPow)
end)