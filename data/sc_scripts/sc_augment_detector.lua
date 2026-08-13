--[[
SC detector augment source.

The detector tag and activation test remain here. Shared targeting behavior is
owned by sc_targeting_core.lua so other temporary targeting sources can use the
same mechanics without duplicating projectile or cloak-charge callbacks.
]]

mods.sc = mods.sc or {}
mods.sc.detector = mods.sc.detector or {}
mods.sc.detectorAugments = mods.sc.detectorAugments or {}

local detector = mods.sc.detector
local detectorAugments = mods.sc.detectorAugments
local targeting = mods.sc.targeting

mods.sc.tag.register_augment_flag_tag(
    "sc-detector",
    detectorAugments
)

local function ship_has_sc_detector(ship)
    if not ship then return false end

    for augName, _ in pairs(detectorAugments) do
        if ship:HasAugmentation(augName) > 0 then
            return true
        end
    end

    return false
end

local function get_detector_strength(ship)
    local sensors = ship and ship:GetSystem(7)

    if not sensors
        or not ship_has_sc_detector(ship) then

        return nil
    end

    return sensors:GetEffectivePower()
end

local function get_detector_accuracy_bonus(
    ship,
    weapon
)
    return targeting.get_accuracy_bonus_for_strength(
        get_detector_strength(ship),
        weapon
    )
end

local function apply_detector_radius_modifier(
    ship,
    weapon,
    radius,
    baseRadius
)
    local accuracyBonus =
        get_detector_accuracy_bonus(
            ship,
            weapon
        )

    if accuracyBonus == nil then
        return radius
    end

    return math.max(
        0,
        radius - accuracyBonus * 4
    )
end

-- Keep the detector helpers available to other SC scripts while the shared
-- targeting core owns the actual gameplay callbacks.
detector.ship_has_detector =
    ship_has_sc_detector

detector.get_strength =
    get_detector_strength

detector.weapon_is_missile =
    targeting.weapon_is_missile

detector.get_accuracy_bonus =
    get_detector_accuracy_bonus

detector.apply_radius_modifier =
    apply_detector_radius_modifier

-- The detector is now one activation source for the shared targeting core.
targeting.register_source(
    "sc_detector",
    get_detector_strength
)
