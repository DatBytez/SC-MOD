--[[
DESCRIPTION: Battery-powered systems recover from ion damage more quickly.
TAG: <sc-battery-ion/>
DEPENDENCIES: sc_augment_battery.lua
SOURCE CREDIT: MsBinaryLily
]]

local vter = mods.multiverse.vter
local helpers = mods.sc.helpers or require("mods.sc.helpers")
local battery = mods.sc.battery

mods.sc.batteryIonAugments = mods.sc.batteryIonAugments or {}
local ionAugments = mods.sc.batteryIonAugments

mods.sc.tag.register_augment_flag_tag("sc-battery-ion", ionAugments)

local CLOAKING_ID = Hyperspace.ShipSystem.NameToSystemId("cloaking")
local DEIONIZATION_RATE = 0.15
local CLOAKING_MULTIPLIER = 0.5

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if not helpers.ship_has_augment(shipManager, ionAugments) then return end
    if not battery.is_active(shipManager) then return end

    local activationTimer = battery.get_activation(shipManager)
    if activationTimer <= 0 then return end

    local tick = Hyperspace.FPS.SpeedFactor / 16

    for system in vter(shipManager.vSystemList) do
        if system then
            local batteryPow = system.iBatteryPower

            if batteryPow > 0 and system.iLockCount > 0 then
                local systemLvl = system:GetMaxPower()
                local scale = batteryPow * systemLvl
                local deionizationBoost =
                    activationTimer * DEIONIZATION_RATE * scale

                if system:GetId() == CLOAKING_ID then
                    deionizationBoost =
                        deionizationBoost * CLOAKING_MULTIPLIER
                end

                system.lockTimer.currTime =
                    system.lockTimer.currTime + tick * deionizationBoost
            end
        end
    end
end)
