--[[
DESCRIPTION: Minimal paired missile-cost diagnostic.
    Diagnostic only; gameplay logic does not depend on this file.

PURPOSE:
    Check whether missile spend is being pulled from ProjectileFactory.iSpendMissile
    or from WeaponBlueprint.missiles.
]]

mods.sc_paired_missile_debug = mods.sc_paired_missile_debug or {}
local debug = mods.sc_paired_missile_debug

local SCREEN_X = 45
local SCREEN_Y = 105
local LINE_HEIGHT = 16
local MAX_LINES = 8
local MAX_WEAPON_SLOTS = 4

debug.lines = debug.lines or {}
debug.lastMissiles = nil
debug.frame = 0

local function run_has_started()
    return Hyperspace.App
        and Hyperspace.App.world
        and Hyperspace.App.world.bStartedGame
end

local function add_line(text)
    local line = tostring(text)
    print("SC MISSILE DEBUG | " .. line)

    table.insert(debug.lines, line)

    while #debug.lines > MAX_LINES do
        table.remove(debug.lines, 1)
    end
end

local function safe_get(root, key)
    if root == nil then return nil end

    local ok, value = pcall(function()
        return root[key]
    end)

    if not ok then return nil end

    return value
end

local function safe_set(root, key, value)
    if root == nil then return false end

    local ok = pcall(function()
        root[key] = value
    end)

    return ok
end

local function safe_size(vector)
    if not vector then return 0 end

    local ok, size = pcall(function()
        return vector:size()
    end)

    if not ok then return 0 end

    return size or 0
end

local function get_player_ship()
    return Hyperspace.ships and Hyperspace.ships.player
end

local function get_player_missiles()
    local ship = get_player_ship()
    if not ship then return nil end

    local ok, count = pcall(function()
        return ship:GetMissileCount()
    end)

    if ok then return count end

    return nil
end

local function get_weapon_name(weapon)
    local blueprint = safe_get(weapon, "blueprint")
    return safe_get(blueprint, "name") or "UNKNOWN"
end

local function get_weapon_slot(weapon)
    local ship = get_player_ship()
    if not ship or not ship.weaponSystem then return nil end

    local weapons = ship.weaponSystem.weapons

    for i = 0, weapons:size() - 1 do
        if weapons[i] == weapon then return i end
    end

    return nil
end

local function weapon_line(slot, weapon)
    local blueprint = safe_get(weapon, "blueprint")
    local queuedProjectiles = safe_get(weapon, "queuedProjectiles")
    local cooldown = safe_get(weapon, "cooldown")
    local cooldownFirst = cooldown and safe_get(cooldown, "first") or nil
    local cooldownSecond = cooldown and safe_get(cooldown, "second") or nil

    return string.format(
        "S%d %s | pwr=%s | iSpend=%s | bp=%s | q=%d | cd=%.1f/%.1f | ready=%s",
        slot + 1,
        get_weapon_name(weapon),
        tostring(safe_get(weapon, "powered")),
        tostring(safe_get(weapon, "iSpendMissile")),
        tostring(blueprint and safe_get(blueprint, "missiles") or nil),
        safe_size(queuedProjectiles),
        tonumber(cooldownFirst) or 0,
        tonumber(cooldownSecond) or 0,
        tostring(safe_get(weapon, "fireWhenReady"))
    )
end

local function watch_missile_count()
    local missiles = get_player_missiles()

    if debug.lastMissiles == nil then
        debug.lastMissiles = missiles
        add_line("Initial missiles=" .. tostring(missiles))
        return
    end

    if missiles ~= debug.lastMissiles then
        add_line("MISSILES " .. tostring(debug.lastMissiles) .. " -> " .. tostring(missiles))
        debug.lastMissiles = missiles
    end
end

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    if not run_has_started() or not weapon then return end

    local slot = get_weapon_slot(weapon)
    local blueprint = safe_get(weapon, "blueprint")

    add_line(
        "FIRE S"
            .. tostring(slot and (slot + 1) or "?")
            .. " "
            .. get_weapon_name(weapon)
            .. " missiles="
            .. tostring(get_player_missiles())
            .. " iSpend="
            .. tostring(safe_get(weapon, "iSpendMissile"))
            .. " bp="
            .. tostring(blueprint and safe_get(blueprint, "missiles") or nil)
    )
end)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if not run_has_started() then return end
    if not shipManager or shipManager.iShipId ~= 0 then return end

    debug.frame = debug.frame + 1
    if debug.frame % 2 == 0 then
        watch_missile_count()
    end
end)

script.on_render_event(
    Defines.RenderEvents.MOUSE_CONTROL,

    function()
        return Defines.Chain.CONTINUE
    end,

    function()
        if not run_has_started() then return end

        local y = SCREEN_Y
        Graphics.freetype.easy_print(0, SCREEN_X, y, "SC Missile Cost Probe")
        y = y + LINE_HEIGHT
        Graphics.freetype.easy_print(0, SCREEN_X, y, "Missiles: " .. tostring(get_player_missiles()))
        y = y + LINE_HEIGHT

        local ship = get_player_ship()
        if ship and ship.weaponSystem then
            local weapons = ship.weaponSystem.weapons
            local maxSlot = math.min(weapons:size() - 1, MAX_WEAPON_SLOTS - 1)

            for i = 0, maxSlot do
                Graphics.freetype.easy_print(0, SCREEN_X, y, weapon_line(i, weapons[i]))
                y = y + LINE_HEIGHT
            end
        end

        y = y + LINE_HEIGHT
        Graphics.freetype.easy_print(0, SCREEN_X, y, "Recent:")
        y = y + LINE_HEIGHT

        for _, line in ipairs(debug.lines) do
            Graphics.freetype.easy_print(0, SCREEN_X, y, line)
            y = y + LINE_HEIGHT
        end
    end
)
