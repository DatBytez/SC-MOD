--[[
DESCRIPTION: Registers tagged detector augments as a targeting source.
        - Scales detector strength with Sensors effective power.
TAG: <sc-detector/>
DEPENDENCIES: sc_tag.lua, sc_helpers.lua, sc_targeting_core.lua
]]

local targeting = mods.sc.targeting
local helpers = mods.sc.helpers
local detectorAugments = {}

mods.sc.tag.register("augment", "sc-detector", detectorAugments)

local SENSORS_SYSTEM_ID = Hyperspace.ShipSystem.NameToSystemId("sensors")

local function get_detector_strength(ship)
    if not helpers.ship_has_augment(ship, detectorAugments) then return nil end

    local sensors = ship:GetSystem(SENSORS_SYSTEM_ID)
    if not sensors then return nil end

    return sensors:GetEffectivePower()
end

targeting.register_source("sc_detector", get_detector_strength)