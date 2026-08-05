-- Test No. 7

--[[
SC radius core.

Calculation order:
    1. Base radius.
    2. Live C/Q/S for targeting preview, or frozen C/Q/S for a fired shot.
    3. Shared weapon modifiers such as artillery, pilot, and detector.
    4. Flat projectile-only radius deltas, summed and clamped once.

SHIP_LOOP refreshes weapon.radius while unpaused. MOUSE_CONTROL pre-render
also refreshes the player weapon radii while paused, before the targeting
cursor is drawn.

Projectile targeting uses the existing FTL projectile target as the center and
replaces it once with a randomized Hyperspace.Pointf. ComputeHeading is not
called.
]]

mods.sc = mods.sc or {}
mods.sc.radius = mods.sc.radius or {}

local vter = mods.multiverse.vter

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
-- Each callback returns one numeric delta. The core sums all deltas and
-- clamps the final result once.
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
        local previewRadius =
            mods.sc.scaling.get_weapon_preview_radius(
                ship,
                weapon
            )

        weapon.radius = math.max(
            0,
            previewRadius
                or mods.sc.scaling.get_base_radius(weapon)
        )
    end
end

mods.sc.radius.refresh_ship_weapon_radii =
    refresh_ship_weapon_radii

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

    local startingRadius =
        mods.sc.scaling.get_projectile_starting_radius(
            projectile,
            weapon
        )
        or mods.sc.scaling.get_base_radius(weapon)

    local finalRadius =
        mods.sc.radius.get_projectile_radius(
            ship,
            projectile,
            weapon,
            math.max(0, startingRadius)
        )

    if finalRadius <= 0 then
        return
    end

    local targetCenter = Hyperspace.Pointf(
        projectile.target.x,
        projectile.target.y
    )

    projectile.target = get_random_point_in_radius(
        targetCenter,
        finalRadius
    )
end

local function register_projectile_radius_handler()
    if mods.sc.radius._projectileApplyRegistered then
        return
    end

    mods.sc.radius._projectileApplyRegistered = true

    script.on_internal_event(
        Defines.InternalEvents.PROJECTILE_FIRE,
        apply_projectile_radius
    )
end

-- Chain, charge, and chainstep register their metadata handlers while their
-- files load. Registering this callback from on_load places it afterward.
script.on_load(register_projectile_radius_handler)
