--[[
DESCRIPTION: Battery power supplied to Oxygen enables scaling fire suppression.
TAG: <sc-battery-fire/>
DEPENDENCIES: sc_augment_battery.lua
]]

local helpers = mods.sc.helpers or require("mods.sc.helpers")
local battery = mods.sc.battery

mods.sc.batteryFireAugments = mods.sc.batteryFireAugments or {}
local fireAugments = mods.sc.batteryFireAugments

mods.sc.tag.register_augment_flag_tag("sc-battery-fire", fireAugments)

local FIRE_EXTINGUISHER_AUG = "TERRAN_HIDDEN_FIRE_EXTINGUISHERS"

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if not helpers.ship_has_augment(shipManager, fireAugments)
        or not battery.is_active(shipManager)
    then
        battery.set_scaling_hidden_aug(
            shipManager,
            FIRE_EXTINGUISHER_AUG,
            false,
            0
        )
        return
    end

    local oxygenSystem = helpers.get_system_by_name(shipManager, "oxygen")
    local oxygen = shipManager.oxygenSystem

    if not (oxygenSystem and oxygen and oxygenSystem:Powered()) then
        battery.set_scaling_hidden_aug(
            shipManager,
            FIRE_EXTINGUISHER_AUG,
            false,
            0
        )
        return
    end

    local oxygenBatteryPow = oxygenSystem.iBatteryPower
    local oxygenBatteryActive = oxygenBatteryPow > 0

    battery.set_scaling_hidden_aug(
        shipManager,
        FIRE_EXTINGUISHER_AUG,
        oxygenBatteryActive,
        oxygenBatteryPow
    )
end)
