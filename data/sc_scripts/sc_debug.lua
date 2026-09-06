--[[
DESCRIPTION: Minimal paired weapon target-selection diagnostic.
    Diagnostic only; gameplay logic does not depend on this file.

PURPOSE:
    Test whether a weapon exposes target selection before it fires.

FOCUSED FIELDS:
    - selected slot from SELECT_ARMAMENT_PRE
    - targetId
    - lastTargets pointer/value
    - fireWhenReady
    - queued projectile count/target if any
    - PROJECTILE_FIRE target/destination when a projectile actually fires
]]

mods.sc_paired_target_debug = mods.sc_paired_target_debug or {}
local debug = mods.sc_paired_target_debug

local SCREEN_X = 45
local SCREEN_Y = 105
local LINE_HEIGHT = 16
local MAX_WEAPON_SLOTS = 4
local MAX_LOG_LINES = 6

debug.selectedSlot = debug.selectedSlot
debug.lastSlotState = debug.lastSlotState or {}
debug.lines = debug.lines or {}

local function run_has_started()
    return Hyperspace.App
        and Hyperspace.App.world
        and Hyperspace.App.world.bStartedGame
end

local function add_line(text)
    local line = tostring(text)
    print("SC TARGET DEBUG | " .. line)

    table.insert(debug.lines, line)

    while #debug.lines > MAX_LOG_LINES do
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

local function safe_size(vector)
    if not vector then return 0 end

    local ok, size = pcall(function()
        return vector:size()
    end)

    if not ok then return 0 end

    return size or 0
end

local function point_text(point)
    if not point then return "nil" end

    local x = safe_get(point, "x")
    local y = safe_get(point, "y")

    if type(x) == "number" and type(y) == "number" then
        return string.format("%.0f,%.0f", x, y)
    end

    return tostring(point)
end

local function basic_value(value)
    if value == nil then return "nil" end

    local valueType = type(value)

    if valueType == "number" then
        return string.format("%.0f", value)
    end

    if valueType == "boolean" then
        return tostring(value)
    end

    if valueType == "string" then
        return value
    end

    return tostring(value)
end

local function get_player_weapons()
    local ship = Hyperspace.ships and Hyperspace.ships.player
    if not ship or not ship.weaponSystem then return nil end

    return ship.weaponSystem.weapons
end

local function get_weapon_name(weapon)
    local blueprint = safe_get(weapon, "blueprint")
    return safe_get(blueprint, "name") or "UNKNOWN"
end

local function get_queued_projectile(weapon)
    local queuedProjectiles = safe_get(weapon, "queuedProjectiles")
    if safe_size(queuedProjectiles) <= 0 then return nil end

    local ok, projectile = pcall(function()
        return queuedProjectiles[0]
    end)

    if not ok then return nil end

    return projectile
end

local function get_slot_state(slot, weapon)
    local queuedProjectiles = safe_get(weapon, "queuedProjectiles")
    local queuedCount = safe_size(queuedProjectiles)
    local queuedProjectile = get_queued_projectile(weapon)

    local queuedTarget = "nil"
    local queuedDestination = "nil"

    if queuedProjectile then
        queuedTarget = point_text(safe_get(queuedProjectile, "target"))
        queuedDestination = basic_value(safe_get(queuedProjectile, "destinationSpace"))
    end

    return table.concat({
        "slot=" .. tostring(slot + 1),
        "name=" .. get_weapon_name(weapon),
        "targetId=" .. basic_value(safe_get(weapon, "targetId")),
        "lastTargets=" .. basic_value(safe_get(weapon, "lastTargets")),
        "fireWhenReady=" .. basic_value(safe_get(weapon, "fireWhenReady")),
        "queued=" .. tostring(queuedCount),
        "qTarget=" .. queuedTarget,
        "qDest=" .. queuedDestination
    }, " | ")
end

local function update_slot_change_log()
    if not run_has_started() then return end

    local weapons = get_player_weapons()
    if not weapons then return end

    local maxSlot = math.min(weapons:size() - 1, MAX_WEAPON_SLOTS - 1)

    for i = 0, maxSlot do
        local weapon = weapons[i]

        if weapon then
            local state = get_slot_state(i, weapon)

            if debug.lastSlotState[i] ~= state then
                debug.lastSlotState[i] = state
                add_line(state)
            end
        end
    end
end

script.on_internal_event(Defines.InternalEvents.SELECT_ARMAMENT_PRE, function(armamentSlot)
    debug.selectedSlot = armamentSlot
    add_line("selected slot " .. tostring(armamentSlot + 1))

    return Defines.Chain.CONTINUE, armamentSlot
end)

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    if not run_has_started() then return end
    if not projectile or not weapon then return end

    add_line(
        "FIRED "
            .. get_weapon_name(weapon)
            .. " target="
            .. point_text(safe_get(projectile, "target"))
            .. " dest="
            .. basic_value(safe_get(projectile, "destinationSpace"))
    )
end)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if not shipManager or shipManager.iShipId ~= 0 then return end

    update_slot_change_log()
end)

script.on_render_event(
    Defines.RenderEvents.MOUSE_CONTROL,

    function()
        return Defines.Chain.CONTINUE
    end,

    function()
        if not run_has_started() then return end

        local y = SCREEN_Y
        Graphics.freetype.easy_print(0, SCREEN_X, y, "SC Target Probe")
        y = y + LINE_HEIGHT

        Graphics.freetype.easy_print(
            0,
            SCREEN_X,
            y,
            "Selected slot: " .. tostring(debug.selectedSlot and (debug.selectedSlot + 1) or "nil")
        )
        y = y + LINE_HEIGHT

        local weapons = get_player_weapons()

        if weapons then
            local maxSlot = math.min(weapons:size() - 1, MAX_WEAPON_SLOTS - 1)

            for i = 0, maxSlot do
                local weapon = weapons[i]

                if weapon then
                    Graphics.freetype.easy_print(0, SCREEN_X, y, get_slot_state(i, weapon))
                    y = y + LINE_HEIGHT
                end
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
