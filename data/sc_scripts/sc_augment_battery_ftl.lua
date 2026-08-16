--[[
DESCRIPTION: Battery power supplied to Engines enables a scaling hidden FTL booster.
TAG: <sc-battery-ftl/>
DEPENDENCIES: sc_augment_battery.lua
]]

local helpers = mods.sc.helpers or require("mods.sc.helpers")
local battery = mods.sc.battery

mods.sc.batteryFtlAugments = mods.sc.batteryFtlAugments or {}
local ftlAugments = mods.sc.batteryFtlAugments

mods.sc.tag.register_augment_flag_tag("sc-battery-ftl", ftlAugments)

local FTL_BOOSTER_AUG = "TERRAN_HIDDEN_FTL_BOOSTER"

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if not helpers.ship_has_augment(shipManager, ftlAugments)
        or not battery.is_active(shipManager)
    then
        battery.set_scaling_hidden_aug(
            shipManager,
            FTL_BOOSTER_AUG,
            false,
            0
        )
        return
    end

    local enginesSystem = helpers.get_system_by_name(shipManager, "engines")
    local enginesBatteryPow = 0

    if enginesSystem and enginesSystem:Powered() then
        enginesBatteryPow = enginesSystem.iBatteryPower
    end

    battery.set_scaling_hidden_aug(
        shipManager,
        FTL_BOOSTER_AUG,
        enginesBatteryPow > 0,
        enginesBatteryPow
    )
end)