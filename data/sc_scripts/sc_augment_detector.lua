--[[
DESCRIPTION: Provides shared detector targeting functionality for tagged augments.
        - Scales detector strength with Sensors effective power.
        - Improves weapon accuracy through the shared targeting core.
        - Reduces projectile targeting radius based on detector accuracy.
        - Registers the detector as an activation source for shared targeting effects.
TAG: <sc-detector/>
DEPENDENCIES: sc_targeting_core.lua
]]

mods.sc = mods.sc or {}
mods.sc.detector = mods.sc.detector or {}
mods.sc.detectorAugments = mods.sc.detectorAugments or {}

local detector = mods.sc.detector
local detectorAugments = mods.sc.detectorAugments
local targeting = mods.sc.targeting
local helpers = mods.sc.helpers

mods.sc.tag.register_augment_tag("sc-detector", detectorAugments)

local function get_detector_strength(ship)
    local sensors = ship and ship:GetSystem(7)

    if not sensors or not helpers.ship_has_augment(ship, detectorAugments) then
        return nil
    end

    return sensors:GetEffectivePower()
end

local function get_detector_accuracy_bonus(ship, weapon)
    return targeting.get_accuracy_bonus_for_strength(get_detector_strength(ship), weapon)
end

local function apply_detector_radius_modifier(ship, weapon, radius, baseRadius)
    local accuracyBonus = get_detector_accuracy_bonus(ship, weapon)

    if accuracyBonus == nil then
        return radius
    end

    return math.max(0, radius - accuracyBonus * 4)
end

detector.ship_has_detector = function(ship) return helpers.ship_has_augment(ship, detectorAugments) end

detector.get_strength = get_detector_strength

detector.weapon_is_missile = targeting.weapon_is_missile

detector.get_accuracy_bonus = get_detector_accuracy_bonus

detector.apply_radius_modifier = apply_detector_radius_modifier

targeting.register_source("sc_detector", get_detector_strength)
