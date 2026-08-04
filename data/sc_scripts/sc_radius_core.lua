-- Test No. 6

--[[
SC radius core.

This version uses sc_projectile_scaling.lua as the only weapon-radius
calculation and weapon-modifier registry.

Calculation order:
    1. Base radius.
    2. Live C/Q/S for targeting preview, or frozen C/Q/S for a fired shot.
    3. Shared weapon modifiers such as artillery, pilot, and detector.
    4. Flat projectile-only radius deltas, summed and clamped once.

Preview updates:
    - SHIP_LOOP refreshes all ships while unpaused.
    - MOUSE_CONTROL pre-render refreshes the player while paused or unpaused,
      before the targeting cursor is drawn.

Projectile targeting preserves the proven Pre Radius Rebuild method: the
existing FTL projectile target is used as the center and replaced once with a
single randomized Hyperspace.Pointf. ComputeHeading is not called.
]]

mods.sc = mods.sc or {}
mods.sc.radius = mods.sc.radius or {}

local userdata_table = mods.multiverse.userdata_table
local vter = mods.multiverse.vter

local CORE_STORAGE_KEY = "mods.sc.radiusCore"
local CORE_TEST_NUMBER = 6

mods.sc.radius.CORE_STORAGE_KEY = CORE_STORAGE_KEY
mods.sc.radius.CORE_TEST_NUMBER = CORE_TEST_NUMBER

mods.sc.radius.projectileRadiusDeltas =
    mods.sc.radius.projectileRadiusDeltas or {}

local projectileRadiusDeltas =
    mods.sc.radius.projectileRadiusDeltas

local function get_random_point_in_radius(center, radius)
    local distance = radius * math.sqrt(math.random())
    local angle = math.random() * 2 * math.pi

    return Hyperspace.Pointf(
        center.x + distance * math.cos(angle),
        center.y + distance * math.sin(angle)
    )
end

mods.sc.radius.get_random_point_in_radius =
    get_random_point_in_radius

function mods.sc.radius.get_base_radius(weapon)
    return mods.sc.scaling.get_base_radius(weapon)
end

-- Projectile-only radius effects are flat additions or subtractions.
-- A callback returns one numeric delta and is never given an accumulated
-- radius. The core sums every delta and clamps the final result once.
function mods.sc.radius.register_projectile_radius_delta(
    name,
    func
)
    if type(name) ~= "string"
        or type(func) ~= "function" then

        return false
    end

    projectileRadiusDeltas[name] = func
    return true
end

function mods.sc.radius.unregister_projectile_radius_delta(
    name
)
    if projectileRadiusDeltas[name] == nil then
        return false
    end

    projectileRadiusDeltas[name] = nil
    return true
end

function mods.sc.radius.get_projectile_radius(
    ship,
    projectile,
    weapon,
    startingRadius
)
    local baseRadius =
        mods.sc.scaling.get_base_radius(weapon)

    local radius = startingRadius

    if type(radius) ~= "number" then
        radius =
            mods.sc.scaling.get_weapon_preview_radius(
                ship,
                weapon
            )
    end

    radius = math.max(0, radius or baseRadius)

    local totalDelta = 0

    for _, func in pairs(projectileRadiusDeltas) do
        local delta = func(
            ship,
            projectile,
            weapon
        )

        if type(delta) == "number" then
            totalDelta = totalDelta + delta
        end
    end

    return math.max(0, radius + totalDelta)
end

local function get_modifier_delta(calculation, modifierName)
    local modifier = calculation
        and calculation.weaponModifiers
        and calculation.weaponModifiers[modifierName]

    return modifier and modifier.delta or 0
end

local function refresh_dynamic_modifier_state(ship)
    if mods.sc.pilot
        and mods.sc.pilot.refresh_accuracy_bonus then

        mods.sc.pilot.refresh_accuracy_bonus(ship)
    end
end

local function refresh_ship_weapon_radii(ship)
    local weapons = ship
        and ship.weaponSystem
        and ship.weaponSystem.weapons

    if not weapons then
        return
    end

    refresh_dynamic_modifier_state(ship)

    for weapon in vter(weapons) do
        local calculation =
            mods.sc.scaling.get_weapon_preview_calculation(
                ship,
                weapon
            )

        if calculation
            and type(calculation.previewRadius) == "number" then

            weapon.radius = math.max(
                0,
                calculation.previewRadius
            )
        else
            weapon.radius =
                mods.sc.scaling.get_base_radius(weapon)
        end
    end
end

mods.sc.radius.refresh_ship_weapon_radii =
    refresh_ship_weapon_radii

local function store_applied_radius(
    projectile,
    calculation,
    startingRadius,
    finalRadius,
    targetBefore,
    targetAfter
)
    local data = userdata_table(
        projectile,
        CORE_STORAGE_KEY
    )

    data.testNumber = CORE_TEST_NUMBER
    data.mode = "shared_radius"
    data.baseRadius = calculation
        and calculation.baseRadius
        or nil
    data.scalingRadius = calculation
        and calculation.scalingRadius
        or nil
    data.weaponModifiedRadius = calculation
        and calculation.startingRadius
        or nil
    data.pilotModifierDelta = get_modifier_delta(
        calculation,
        "pilot_accuracy"
    )
    data.detectorModifierDelta = get_modifier_delta(
        calculation,
        "sc_detector"
    )
    data.artilleryModifierDelta = get_modifier_delta(
        calculation,
        "chain_artillery"
    )
    data.hasStoredScaling = calculation
        and calculation.hasStoredScaling
        or false
    data.hasScalingRadius = calculation
        and calculation.hasScalingRadius
        or false
    data.startingRadius = startingRadius
    data.finalRadius = finalRadius
    data.projectileModifierDelta =
        finalRadius - startingRadius

    data.targetBeforeX = targetBefore
        and targetBefore.x
        or nil
    data.targetBeforeY = targetBefore
        and targetBefore.y
        or nil
    data.targetAfterX = targetAfter
        and targetAfter.x
        or nil
    data.targetAfterY = targetAfter
        and targetAfter.y
        or nil

    local dx = targetBefore
        and targetAfter
        and targetAfter.x - targetBefore.x
        or 0
    local dy = targetBefore
        and targetAfter
        and targetAfter.y - targetBefore.y
        or 0

    data.targetMovedDistance = math.sqrt(
        dx * dx + dy * dy
    )
end

script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    refresh_ship_weapon_radii
)

-- Render callbacks continue while paused. Refresh before the mouse/targeting
-- layer is drawn so pilot activation and cloak changes are visible at once.
script.on_render_event(
    Defines.RenderEvents.MOUSE_CONTROL,

    function()
        local playerShip = Hyperspace.ships.player

        if playerShip then
            refresh_ship_weapon_radii(playerShip)
        end

        return Defines.Chain.CONTINUE
    end,

    function()
    end
)

local function apply_projectile_radius(projectile, weapon)
    if not projectile
        or not weapon
        or not projectile.target then

        return
    end

    local ship = Hyperspace.ships(projectile.ownerId)

    if not ship then
        return
    end

    refresh_dynamic_modifier_state(ship)

    local calculation =
        mods.sc.scaling
            .get_projectile_starting_radius_calculation(
                projectile,
                weapon
            )

    local startingRadius = calculation
        and calculation.startingRadius
        or mods.sc.scaling.get_base_radius(weapon)

    startingRadius = math.max(0, startingRadius)

    local finalRadius =
        mods.sc.radius.get_projectile_radius(
            ship,
            projectile,
            weapon,
            startingRadius
        )

    local targetBefore = Hyperspace.Pointf(
        projectile.target.x,
        projectile.target.y
    )

    if finalRadius <= 0 then
        store_applied_radius(
            projectile,
            calculation,
            startingRadius,
            finalRadius,
            targetBefore,
            targetBefore
        )

        return
    end

    projectile.target = get_random_point_in_radius(
        targetBefore,
        finalRadius
    )

    store_applied_radius(
        projectile,
        calculation,
        startingRadius,
        finalRadius,
        targetBefore,
        projectile.target
    )
end

mods.sc.radius.apply_projectile_radius =
    apply_projectile_radius

local function register_projectile_radius_handler()
    if mods.sc.radius._projectileApplyRegisteredTest6 then
        return
    end

    mods.sc.radius._projectileApplyRegisteredTest6 = true

    script.on_internal_event(
        Defines.InternalEvents.PROJECTILE_FIRE,
        apply_projectile_radius
    )
end

-- Chain, charge, and chainstep register their metadata handlers while their
-- files load. Registering this callback from on_load places it afterward.
script.on_load(register_projectile_radius_handler)
