--[[
DESCRIPTION: Registers tagged detector augments as a targeting source.
        - Scales detector strength with Sensors effective power.
TAG: <sc-detector/>
DEPENDENCIES: sc_tag.lua, sc_targeting_core.lua
]]

local targeting = mods.sc.targeting
local detectorAugments = {}

mods.sc.tag.register("augment", "sc-detector", detectorAugments)

local SENSORS_SYSTEM_ID = Hyperspace.ShipSystem.NameToSystemId("sensors")

local function ship_has_detector(ship)
    for augName in pairs(detectorAugments) do
        if ship:HasAugmentation(augName) > 0 then
            return true
        end
    end

    return false
end

local function get_detector_strength(ship)
    if not ship_has_detector(ship) then return nil end

    local sensors = ship:GetSystem(SENSORS_SYSTEM_ID)
    if not sensors then return nil end

    return sensors:GetEffectivePower()
end

targeting.register_source("sc_detector", get_detector_strength)