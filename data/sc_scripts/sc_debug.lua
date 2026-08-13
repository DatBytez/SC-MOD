-- Active projectile flight-state debug.
-- Diagnostic only. Gameplay must not depend on this file.

local SCREEN_X = 65
local SCREEN_Y = 110
local LINE_HEIGHT = 18

-- Keep a stable display number for each projectile while it remains active.
-- Projectile selfId is stable for the lifetime of the projectile.
local projectileLabels = {}

local function format_number(value)
    if type(value) ~= "number" then
        return "?"
    end

    return string.format("%.1f", value)
end

local function projectile_key(projectile, vectorIndex)
    if projectile and projectile.selfId ~= nil then
        return tostring(projectile.selfId)
    end

    -- selfId should normally exist, but keep the debug script safe if a
    -- projectile subtype does not expose it for some reason.
    return "index:" .. tostring(vectorIndex)
end

local function get_active_projectiles()
    local app = Hyperspace.App
    local world = app and app.world
    local space = world and world.space
    local projectiles = space and space.projectiles

    if not projectiles then
        return {}
    end

    local active = {}
    local activeKeys = {}

    for index = 0, projectiles:size() - 1 do
        local projectile = projectiles[index]

        if projectile and not projectile:Dead() then
            local key = projectile_key(projectile, index)

            active[#active + 1] = {
                projectile = projectile,
                key = key,
            }

            activeKeys[key] = true
        end
    end

    -- Remove labels belonging to projectiles that no longer exist.
    for key, _ in pairs(projectileLabels) do
        if not activeKeys[key] then
            projectileLabels[key] = nil
        end
    end

    -- Preserve labels already assigned to surviving projectiles.
    local usedLabels = {}

    for _, entry in ipairs(active) do
        local label = projectileLabels[entry.key]

        if label then
            usedLabels[label] = true
        end
    end

    -- Give newly-seen projectiles the lowest currently unused number.
    for _, entry in ipairs(active) do
        if not projectileLabels[entry.key] then
            local label = 1

            while usedLabels[label] do
                label = label + 1
            end

            projectileLabels[entry.key] = label
            usedLabels[label] = true
        end

        entry.label = projectileLabels[entry.key]
    end

    table.sort(
        active,
        function(a, b)
            return a.label < b.label
        end
    )

    return active
end

local function projectile_debug_line(label, projectile)
    local position = projectile.position
    local target = projectile.target

    local px = position and format_number(position.x) or "?"
    local py = position and format_number(position.y) or "?"
    local tx = target and format_number(target.x) or "?"
    local ty = target and format_number(target.y) or "?"

    return string.format(
        "Projectile %d: h:%s p:(%s,%s) t:(%s,%s), cS:%s dS:%s",
        label,
        format_number(projectile.heading),
        px,
        py,
        tx,
        ty,
        tostring(projectile.currentSpace),
        tostring(projectile.destinationSpace)
    )
end

script.on_render_event(
    Defines.RenderEvents.MOUSE_CONTROL,

    function()
        return Defines.Chain.CONTINUE
    end,

    function()
        local activeProjectiles = get_active_projectiles()

        for lineIndex, entry in ipairs(activeProjectiles) do
            Graphics.freetype.easy_print(
                0,
                SCREEN_X,
                SCREEN_Y + LINE_HEIGHT * (lineIndex - 1),
                projectile_debug_line(
                    entry.label,
                    entry.projectile
                )
            )
        end
    end
)