--[[
SC DEBUG - DETECTOR / HALO TEST

Purpose:
    Remove previous debug output and show only the information needed
    to diagnose why the detector augment is not affecting the HALO
    missile launcher.

What this checks:
    1. Did the sc-detector XML tag populate mods.sc.detectorAugments?
    2. Does the firing ship actually have one of those detector augments?
    3. Does the firing ship have sensors, and what is their effective power?
    4. Is the HALO weapon being identified as a missile?
    5. What accuracy bonus should detector apply?
    6. What accuracyMod is present on the fired projectile?
    7. What radius reduction should detector apply?
    8. Which radius projectile modifiers are currently registered?
    9. How far did sc_radius_core move the HALO projectile target?

Suggested load order for this debug file:
    sc_radius_core.lua
    sc_augment_detector.lua
    sc_weapon_halo.lua
    sc_debug.lua

If sc_debug.lua is loaded after the detector script, the displayed
accuracyMod should include the detector result.
]]

mods.sc_debug = mods.sc_debug or {}
mods.sc_debug.detectorHalo = mods.sc_debug.detectorHalo or {}

local REPORT = mods.sc_debug.detectorHalo

local HALO_WEAPON_NAME = "TERRAN_MISSILE_HALO"
local FAKE_PROJECTILE_SCALE = 0.25
local SCREEN_X = 10
local SCREEN_Y = 175
local LINE_HEIGHT = 18
local MAX_SHOTS = 8

-- Set to 0 to only track player HALO shots.
-- Set to nil to track both player and enemy HALO shots.
local TRACK_OWNER_ID = 0

REPORT.shots = REPORT.shots or {}
REPORT.attackNumber = REPORT.attackNumber or 0
REPORT.lastSummary = REPORT.lastSummary or "Waiting for player HALO fire..."

local function bool_text(value)
    return value and "YES" or "NO"
end

local function number_text(value)
    if value == nil then
        return "-"
    end

    return tostring(value)
end

local function format_number(value)
    if value == nil then
        return "-"
    end

    return string.format("%.1f", value)
end

local function copy_point(point)
    if not point then
        return nil
    end

    return {
        x = point.x or 0,
        y = point.y or 0
    }
end

local function distance_between(pointA, pointB)
    if not pointA or not pointB then
        return nil
    end

    local dx = pointB.x - pointA.x
    local dy = pointB.y - pointA.y

    return math.sqrt(dx * dx + dy * dy)
end

local function get_weapon_target(weapon)
    if not weapon
        or not weapon.targets
        or weapon.targets:size() <= 0 then

        return nil
    end

    return copy_point(weapon.targets[0])
end

local function get_projectile_scale(projectile)
    if projectile and projectile.death_animation then
        return projectile.death_animation.fScale
    end

    return nil
end

local function is_fake_halo_projectile(projectile)
    local scale = get_projectile_scale(projectile)

    return scale ~= nil
        and math.abs(scale - FAKE_PROJECTILE_SCALE) < 0.0001
end

local function is_halo_weapon(weapon)
    return weapon
        and weapon.blueprint
        and weapon.blueprint.name == HALO_WEAPON_NAME
end

local function is_tracked_halo(projectile, weapon)
    if not projectile or not is_halo_weapon(weapon) then
        return false
    end

    if TRACK_OWNER_ID ~= nil
        and projectile.ownerId ~= TRACK_OWNER_ID then

        return false
    end

    return true
end

local function count_detector_tags()
    local detectorAugments =
        mods.sc
        and mods.sc.detectorAugments

    local count = 0
    local names = {}

    if detectorAugments then
        for augName, _ in pairs(detectorAugments) do
            count = count + 1
            table.insert(names, augName)
        end
    end

    table.sort(names)

    return count, table.concat(names, ",")
end

local function ship_detector_info(ship)
    if not ship then
        return false, "no ship"
    end

    local detectorAugments =
        mods.sc
        and mods.sc.detectorAugments

    if not detectorAugments then
        return false, "detector table missing"
    end

    local checkedAny = false

    for augName, _ in pairs(detectorAugments) do
        checkedAny = true

        if ship:HasAugmentation(augName) > 0 then
            return true, augName
        end
    end

    if not checkedAny then
        return false, "detector table empty"
    end

    return false, "ship lacks parsed detector aug"
end

local function is_missile_weapon(weapon)
    if not weapon or not weapon.blueprint then
        return false
    end

    return weapon.blueprint.typeName == "MISSILES"
        or weapon.blueprint.type == "MISSILE"
        or weapon.blueprint.type == 2
end

local function get_expected_accuracy_bonus(ship, weapon)
    if not ship then
        return nil
    end

    local sensors = ship:GetSystem(7)

    if not sensors then
        return nil
    end

    local bonus = sensors:GetEffectivePower() * 2.5

    if is_missile_weapon(weapon) then
        bonus = bonus * 2
    end

    return math.ceil(bonus)
end

local function get_base_radius(weapon)
    if not weapon then
        return 0
    end

    if mods.sc
        and mods.sc.radius
        and mods.sc.radius.get_base_radius then

        return mods.sc.radius.get_base_radius(weapon)
    end

    if weapon.blueprint and weapon.blueprint.radius then
        return weapon.blueprint.radius
    end

    return weapon.radius or 0
end

local function list_relevant_radius_modifiers()
    local projectileModifiers =
        mods.sc
        and mods.sc.radius
        and mods.sc.radius.projectileModifiers

    if not projectileModifiers then
        return "missing"
    end

    local names = {}

    for name, _ in pairs(projectileModifiers) do
        if string.find(name, "detector")
            or string.find(name, "halo") then

            table.insert(names, name)
        end
    end

    table.sort(names)

    if #names == 0 then
        return "none"
    end

    return table.concat(names, ",")
end

local function reset_report(ownerId)
    REPORT.attackNumber = REPORT.attackNumber + 1
    REPORT.ownerId = ownerId
    REPORT.shots = {}
end

script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_FIRE,
    function(projectile, weapon)
        if not is_tracked_halo(projectile, weapon) then
            return
        end

        if #REPORT.shots == 0 or #REPORT.shots >= MAX_SHOTS then
            reset_report(projectile.ownerId)
        end

        local ship = Hyperspace.ships(projectile.ownerId)
        local sensors = ship and ship:GetSystem(7)
        local sensorPower = sensors and sensors:GetEffectivePower() or nil
        local hasDetector, detectorReason = ship_detector_info(ship)
        local tagCount, tagNames = count_detector_tags()
        local expectedAccuracy = get_expected_accuracy_bonus(ship, weapon)
        local baseRadius = get_base_radius(weapon)
        local expectedReduction = expectedAccuracy and expectedAccuracy * 2 or nil
        local expectedDetectorRadius = nil
        local expectedFakeAfterDetector = nil
        local expectedFakeBeforeDetector = nil

        if expectedReduction then
            expectedDetectorRadius = math.max(0, baseRadius - expectedReduction)
            expectedFakeAfterDetector = expectedDetectorRadius * 5
            expectedFakeBeforeDetector = math.max(0, baseRadius * 5 - expectedReduction)
        end

        local selectedTarget = get_weapon_target(weapon)
        local firedTarget = copy_point(projectile.target)
        local movedDistance = distance_between(selectedTarget, firedTarget)
        local projectileAccuracy =
            projectile
            and projectile.extend
            and projectile.extend.customDamage
            and projectile.extend.customDamage.accuracyMod
            or nil

        local shot = {
            index = #REPORT.shots + 1,
            fake = is_fake_halo_projectile(projectile),
            scale = get_projectile_scale(projectile),
            ownerId = projectile.ownerId,
            weaponName = weapon and weapon.blueprint and weapon.blueprint.name or "-",
            weaponType = weapon and weapon.blueprint and tostring(weapon.blueprint.type) or "-",
            weaponTypeName = weapon and weapon.blueprint and tostring(weapon.blueprint.typeName) or "-",
            missile = is_missile_weapon(weapon),
            tagCount = tagCount,
            tagNames = tagNames,
            hasDetector = hasDetector,
            detectorReason = detectorReason,
            sensorPower = sensorPower,
            expectedAccuracy = expectedAccuracy,
            projectileAccuracy = projectileAccuracy,
            baseRadius = baseRadius,
            expectedReduction = expectedReduction,
            expectedDetectorRadius = expectedDetectorRadius,
            expectedFakeAfterDetector = expectedFakeAfterDetector,
            expectedFakeBeforeDetector = expectedFakeBeforeDetector,
            movedDistance = movedDistance,
            radiusModifiers = list_relevant_radius_modifiers()
        }

        table.insert(REPORT.shots, shot)

        REPORT.lastSummary =
            "HALO detector debug captured shot "
            .. tostring(shot.index)
            .. "/"
            .. tostring(MAX_SHOTS)
    end
)

script.on_render_event(
    Defines.RenderEvents.SHIP_STATUS,

    function()
        return Defines.Chain.CONTINUE
    end,

    function()
        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y,
            "SC DETECTOR/HALO DEBUG: " .. REPORT.lastSummary
        )

        if #REPORT.shots == 0 then
            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                SCREEN_Y + LINE_HEIGHT,
                "Fire TERRAN_MISSILE_HALO from the player ship. No other debug output is active."
            )
            return
        end

        local latest = REPORT.shots[#REPORT.shots]

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y + LINE_HEIGHT,
            "Attack #" .. tostring(REPORT.attackNumber)
                .. " shot " .. tostring(latest.index)
                .. " | fake=" .. bool_text(latest.fake)
                .. " scale=" .. format_number(latest.scale)
        )

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y + LINE_HEIGHT * 2,
            "weapon=" .. tostring(latest.weaponName)
                .. " type=" .. tostring(latest.weaponType)
                .. " typeName=" .. tostring(latest.weaponTypeName)
                .. " missile=" .. bool_text(latest.missile)
        )

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y + LINE_HEIGHT * 3,
            "detectorTags=" .. tostring(latest.tagCount)
                .. " [" .. tostring(latest.tagNames) .. "]"
                .. " shipHasDetector=" .. bool_text(latest.hasDetector)
                .. " reason=" .. tostring(latest.detectorReason)
        )

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y + LINE_HEIGHT * 4,
            "sensors=" .. number_text(latest.sensorPower)
                .. " expectedAcc=" .. number_text(latest.expectedAccuracy)
                .. " projectileAccMod=" .. number_text(latest.projectileAccuracy)
        )

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y + LINE_HEIGHT * 5,
            "baseRadius=" .. format_number(latest.baseRadius)
                .. " expectedReduce=" .. number_text(latest.expectedReduction)
                .. " detectorRadius=" .. format_number(latest.expectedDetectorRadius)
                .. " moved=" .. format_number(latest.movedDistance)
        )

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y + LINE_HEIGHT * 6,
            "registered radius modifiers=" .. tostring(latest.radiusModifiers)
        )

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y + LINE_HEIGHT * 7,
            "Fake HALO expected radius if detector before halo="
                .. format_number(latest.expectedFakeAfterDetector)
                .. " | if halo before detector="
                .. format_number(latest.expectedFakeBeforeDetector)
        )

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            SCREEN_Y + LINE_HEIGHT * 8,
            "Failure clues: tags=0 means XML/load-order issue; missile=NO means weapon type check issue; no sc_detector modifier means detector radius code not loaded."
        )
    end
)