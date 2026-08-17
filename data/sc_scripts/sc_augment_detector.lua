--[[
DESCRIPTION: Registers tagged detector augments as a targeting source.
        - Scales detector strength with Sensors effective power.
        - Shared targeting core handles accuracy, radius, cloak, and detection effects.
TAG: <sc-detector/>
DEPENDENCIES: sc_targeting_core.lua
]]

mods.sc = mods.sc or {}
mods.sc.detectorAugments = mods.sc.detectorAugments or {}

local detectorAugments = mods.sc.detectorAugments
local targeting = mods.sc.targeting
local helpers = mods.sc.helpers

mods.sc.tag.register_augment_tag("sc-detector", detectorAugments)

local function get_detector_strength(ship)
    local sensors = ship and ship:GetSystem(7)

    if not sensors
        or not helpers.ship_has_augment(ship, detectorAugments) then

        return nil
    end

    return sensors:GetEffectivePower()
end

targeting.register_source("sc_detector", get_detector_strength)