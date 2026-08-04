-- Test No. 4

--[[
SC radius core.

Test No. 4 keeps the functioning Test No. 3 projectile path and proven
Pre Radius Rebuild target-randomization method.

It adds one paused-preview update path:
    - SHIP_LOOP continues refreshing all ships while unpaused.
    - MOUSE_CONTROL pre-render refreshes the player weapon radii every frame,
      including while paused and before the targeting cursor is drawn.

Before either preview refresh, the core asks sc_pilot.lua to refresh its live
accuracy value. This lets pilot activation and cloak changes affect the visual
radius immediately while paused.

Order of calculation:
    1. Base radius.
    2. Frozen C/Q/S radius for a fired projectile, or live C/Q/S for preview.
    3. Shared weapon modifiers such as pilot and detector.
    4. Projectile-only modifiers such as HALO fake spread.

No ComputeHeading or alternate coordinate method is used.
]]

mods.sc = mods.sc or {}
mods.sc.radius = mods.sc.radius or {}

local userdata_table = mods.multiverse.userdata_table
local vter = mods.multiverse.vter

local CORE_STORAGE_KEY = "mods.sc.radiusCore"
local CORE_TEST_NUMBER = 4

mods.sc.radius.CORE_STORAGE_KEY =
    CORE_STORAGE_KEY

mods.sc.radius.CORE_TEST_NUMBER =
    CORE_TEST_NUMBER

mods.sc.radius.modifiers =
    mods.sc.radius.modifiers or {}

mods.sc.radius.projectileModifiers =
    mods.sc.radius.projectileModifiers or {}

local function get_random_point_in_radius(center, radius)
    local r =
        radius * math.sqrt(math.random())

    local theta =
        math.random() * 2 * math.pi

    return Hyperspace.Pointf(
        center.x + r * math.cos(theta),
        center.y + r * math.sin(theta)
    )
end

mods.sc.radius.get_random_point_in_radius =
    get_random_point_in_radius

function mods.sc.radius.get_base_radius(weapon)
    local wdata =
        userdata_table(
            weapon,
            "mods.sc.weaponStuff"
        )

    if wdata.baseRadius == nil then
        wdata.baseRadius =
            (
                weapon.blueprint
                and weapon.blueprint.radius
            )
            or weapon.radius
            or 0
    end

    return wdata.baseRadius
end

-- Weapon-level modifiers affect the radius displayed by the
-- targeting UI and the normal radius shared by all projectiles.
function mods.sc.radius.register_modifier(name, func)
    mods.sc.radius.modifiers[name] =
        func
end

function mods.sc.radius.unregister_modifier(name)
    mods.sc.radius.modifiers[name] =
        nil
end

-- Projectile-level modifiers affect only the projectile currently
-- being fired. They do not change weapon.radius or the targeting UI.
function mods.sc.radius.register_projectile_modifier(
    name,
    func
)
    mods.sc.radius.projectileModifiers[name] =
        func
end

function mods.sc.radius.unregister_projectile_modifier(
    name
)
    mods.sc.radius.projectileModifiers[name] =
        nil
end

function mods.sc.radius.get_final_radius(
    ship,
    weapon
)
    local baseRadius =
        mods.sc.radius.get_base_radius(
            weapon
        )

    local radius =
        baseRadius

    for _, func in pairs(
        mods.sc.radius.modifiers
    ) do
        local modifiedRadius =
            func(
                ship,
                weapon,
                radius,
                baseRadius
            )

        if modifiedRadius ~= nil then
            radius =
                modifiedRadius
        end
    end

    return math.max(
        0,
        radius
    )
end

-- Returns the radius that should be used for one specific projectile.
--
-- startingRadius is optional. It is used by fireRadiusOverride and by the
-- shared projectile-scaling radius before projectile-specific modifiers
-- are applied.
function mods.sc.radius.get_projectile_radius(
    ship,
    projectile,
    weapon,
    startingRadius
)
    local baseRadius =
        mods.sc.radius.get_base_radius(
            weapon
        )

    local radius =
        startingRadius

    if radius == nil then
        radius =
            mods.sc.radius.get_final_radius(
                ship,
                weapon
            )
    end

    for _, func in pairs(
        mods.sc.radius.projectileModifiers
    ) do
        local modifiedRadius =
            func(
                ship,
                projectile,
                weapon,
                radius,
                baseRadius
            )

        if modifiedRadius ~= nil then
            radius =
                modifiedRadius
        end
    end

    return math.max(
        0,
        radius
    )
end

local function get_shared_projectile_calculation(
    projectile,
    weapon
)
    if not mods.sc
        or not mods.sc.scaling
        or not mods.sc.scaling
            .get_projectile_starting_radius_calculation then

        return nil
    end

    local success, calculation =
        pcall(
            mods.sc.scaling
                .get_projectile_starting_radius_calculation,
            projectile,
            weapon
        )

    if not success
        or type(calculation) ~= "table" then

        return nil
    end

    return calculation
end

local function get_shared_preview_calculation(
    ship,
    weapon
)
    if not mods.sc
        or not mods.sc.scaling
        or not mods.sc.scaling
            .get_weapon_preview_calculation then

        return nil
    end

    local success, calculation =
        pcall(
            mods.sc.scaling
                .get_weapon_preview_calculation,
            ship,
            weapon
        )

    if not success
        or type(calculation) ~= "table" then

        return nil
    end

    return calculation
end

local function consume_fire_radius_override(weapon)
    local wdata =
        userdata_table(
            weapon,
            "mods.sc.weaponStuff"
        )

    if not wdata.fireRadiusOverrideActive then
        return nil
    end

    local radius =
        math.max(
            0,
            wdata.fireRadiusOverride or 0
        )

    wdata.fireRadiusOverrideActive =
        false

    wdata.fireRadiusOverride =
        nil

    return radius
end

local function get_weapon_modifier_delta(
    calculation,
    modifierName
)
    local modifiers = calculation
        and (calculation.weaponModifiers
            or calculation.previewModifiers)

    local modifier = modifiers
        and modifiers[modifierName]

    return modifier and modifier.delta or 0
end

local function refresh_dynamic_modifier_state(ship)
    if not ship
        or not mods.sc
        or not mods.sc.pilot
        or not mods.sc.pilot.refresh_accuracy_bonus then

        return
    end

    pcall(
        mods.sc.pilot.refresh_accuracy_bonus,
        ship
    )
end

local function refresh_ship_weapon_radii(ship)
    local weapons =
        ship
        and ship.weaponSystem
        and ship.weaponSystem.weapons

    if not weapons then
        return
    end

    refresh_dynamic_modifier_state(ship)

    for weapon in vter(weapons) do
        local calculation =
            get_shared_preview_calculation(
                ship,
                weapon
            )

        if calculation
            and type(calculation.previewRadius)
                == "number" then

            weapon.radius =
                math.max(
                    0,
                    calculation.previewRadius
                )
        else
            weapon.radius =
                mods.sc.radius.get_final_radius(
                    ship,
                    weapon
                )
        end
    end
end

mods.sc.radius.refresh_ship_weapon_radii =
    refresh_ship_weapon_radii

local function store_applied_radius(
    projectile,
    calculation,
    mode,
    overrideRadius,
    startingRadius,
    finalRadius,
    targetBefore,
    targetAfter
)
    local pdata =
        userdata_table(
            projectile,
            CORE_STORAGE_KEY
        )

    pdata.testNumber =
        CORE_TEST_NUMBER

    pdata.mode =
        mode

    pdata.baseRadius =
        calculation
        and calculation.baseRadius
        or nil

    pdata.sharedExpectedRadius =
        calculation
        and (calculation.startingRadius
            or calculation.weaponModifiedRadius
            or calculation.scalingRadius)
        or nil

    pdata.legacyCoreRadius =
        calculation
        and calculation.legacyCoreRadius
        or nil

    pdata.scalingRadius =
        calculation
        and calculation.scalingRadius
        or nil

    pdata.weaponModifiedRadius =
        calculation
        and (calculation.weaponModifiedRadius
            or calculation.startingRadius)
        or nil

    pdata.pilotModifierDelta =
        get_weapon_modifier_delta(
            calculation,
            "pilot_accuracy"
        )

    pdata.detectorModifierDelta =
        get_weapon_modifier_delta(
            calculation,
            "sc_detector"
        )

    pdata.hasStoredScaling =
        calculation
        and calculation.hasStoredScaling
        or false

    pdata.hasScalingRadius =
        calculation
        and calculation.hasScalingRadius
        or false

    pdata.overrideRadius =
        overrideRadius

    pdata.startingRadius =
        startingRadius

    pdata.finalRadius =
        finalRadius

    pdata.projectileModifierDelta =
        finalRadius - startingRadius

    pdata.targetBeforeX =
        targetBefore and targetBefore.x or nil

    pdata.targetBeforeY =
        targetBefore and targetBefore.y or nil

    pdata.targetAfterX =
        targetAfter and targetAfter.x or nil

    pdata.targetAfterY =
        targetAfter and targetAfter.y or nil

    local dx =
        targetBefore
        and targetAfter
        and targetAfter.x - targetBefore.x
        or 0

    local dy =
        targetBefore
        and targetAfter
        and targetAfter.y - targetBefore.y
        or 0

    pdata.targetMovedDistance =
        math.sqrt(dx * dx + dy * dy)
end

script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    refresh_ship_weapon_radii
)

-- MOUSE_CONTROL is rendered every frame, including while paused. Its pre-render
-- callback runs before the targeting cursor is drawn, so weapon.radius reflects
-- a newly activated pilot ability or cloak state on the next rendered frame.
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

    local ship =
        Hyperspace.ships(
            projectile.ownerId
        )

    if not ship then
        return
    end

    refresh_dynamic_modifier_state(ship)

    -- Charge Test No. 1 may set this during its normal-priority
    -- PROJECTILE_FIRE handler. Consume it here so the old fallback
    -- remains available and cannot leak into a later projectile.
    local overrideRadius =
        consume_fire_radius_override(
            weapon
        )

    local calculation =
        get_shared_projectile_calculation(
            projectile,
            weapon
        )

    local startingRadius = nil
    local mode = "legacy_core"

    if calculation
        and type(calculation.startingRadius)
            == "number" then

        startingRadius =
            math.max(
                0,
                calculation.startingRadius
            )

        mode = "shared_weapon_radius"

    elseif overrideRadius ~= nil then
        startingRadius =
            overrideRadius

        mode = "legacy_override"
    end

    if startingRadius == nil then
        startingRadius =
            mods.sc.radius.get_final_radius(
                ship,
                weapon
            )
    end

    local finalRadius =
        mods.sc.radius.get_projectile_radius(
            ship,
            projectile,
            weapon,
            startingRadius
        )

    local targetBefore =
        Hyperspace.Pointf(
            projectile.target.x,
            projectile.target.y
        )

    if finalRadius <= 0 then
        store_applied_radius(
            projectile,
            calculation,
            mode,
            overrideRadius,
            startingRadius,
            finalRadius,
            targetBefore,
            targetBefore
        )

        return
    end

    -- Preserve the exact target-randomization method from the
    -- current Pre Radius Rebuild core.
    projectile.target =
        get_random_point_in_radius(
            targetBefore,
            finalRadius
        )

    store_applied_radius(
        projectile,
        calculation,
        mode,
        overrideRadius,
        startingRadius,
        finalRadius,
        targetBefore,
        projectile.target
    )
end

local function register_projectile_radius_handler()
    if mods.sc.radius._projectileApplyRegisteredTest4 then
        return
    end

    mods.sc.radius._projectileApplyRegisteredTest4 = true

    script.on_internal_event(
        Defines.InternalEvents.PROJECTILE_FIRE,
        apply_projectile_radius
    )
end

-- PROJECTILE_FIRE callbacks run in registration order. Register this
-- handler from on_load so the chain, charge, and chainstep scripts have
-- already registered the callbacks that store projectile scaling data.
script.on_load(register_projectile_radius_handler)
