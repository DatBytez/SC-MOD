mods.sc = mods.sc or {}
mods.sc.radius = mods.sc.radius or {}

local userdata_table = mods.multiverse.userdata_table
local vter = mods.multiverse.vter

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
-- startingRadius is optional. It is used by fireRadiusOverride so the
-- existing override behavior is preserved before projectile-specific
-- modifiers are applied.
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

script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    function(ship)
        local weapons =
            ship
            and ship.weaponSystem
            and ship.weaponSystem.weapons

        if not weapons then
            return
        end

        for weapon in vter(weapons) do
            weapon.radius =
                mods.sc.radius.get_final_radius(
                    ship,
                    weapon
                )
        end
    end
)

script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_FIRE,
    function(projectile, weapon)
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

        local wdata =
            userdata_table(
                weapon,
                "mods.sc.weaponStuff"
            )

        local startingRadius =
            nil

        if wdata.fireRadiusOverrideActive then
            startingRadius =
                math.max(
                    0,
                    wdata.fireRadiusOverride or 0
                )

            wdata.fireRadiusOverrideActive =
                false

            wdata.fireRadiusOverride =
                nil
        end

        local radius =
            mods.sc.radius.get_projectile_radius(
                ship,
                projectile,
                weapon,
                startingRadius
            )

        if radius <= 0 then
            return
        end

        -- Save the untouched projectile target before assigning the
        -- single randomized result. Projectile modifiers change only
        -- the radius used for this one calculation.
        local center =
            Hyperspace.Pointf(
                projectile.target.x,
                projectile.target.y
            )

        projectile.target =
            get_random_point_in_radius(
                center,
                radius
            )
    end
)