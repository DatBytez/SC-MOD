--[[
DESCRIPTION: On-screen Cloaking duration diagnostics.
        - Shows sc-cloak tag registration and equipped augment values.
        - Compares the live Cloaking timer with the expected modified duration.
        - Tracks cloak activation and the cloak script's applied flag.
        - Shows elapsed-time scaling without modifying the timer goal.
        - Does not modify Cloaking, augments, or their timers.
DEPENDENCIES: sc_augment_cloak.lua (diagnostics remain visible if missing).
]]

local TEXT_X = 20
local TEXT_Y = 165
local LINE_HEIGHT = 16
local FONT = 10
local MAX_EVENTS = 3

local state = {
    [0] = {ticks = 0, activations = 0, events = {}},
    [1] = {ticks = 0, activations = 0, events = {}}
}

local function num(value)
    return type(value) == "number" and string.format("%.2f", value) or "-"
end

local function yn(value)
    return value and "Y" or "N"
end

local function flag(value)
    if value == nil then return "unset" end
    return yn(value)
end

local function get_cloak_tag_info(ship)
    local augments = mods.sc and mods.sc.cloakAugments
    local info = {registered = 0, equipped = 0, perPower = 0, names = {}}
    if not augments then return info end

    for name, value in pairs(augments) do
        info.registered = info.registered + 1

        if ship then
            local count = ship:HasAugmentation(name)
            if count > 0 then
                info.equipped = info.equipped + count
                local amount = tonumber(value)
                if amount then
                    info.perPower = info.perPower + amount * count
                end
                info.names[#info.names + 1] = string.format("%s x%d (%s)",
                    name, count, tostring(value))
            end
        end
    end

    table.sort(info.names)
    return info
end

local function get_cloak_script_data(ship)
    -- Read the same userdata namespace as sc_augment_cloak.lua, without creating it.
    local ok, data = pcall(function()
        return ship.table and ship.table["mods.sc.cloakDuration"]
    end)
    if not ok then return nil end
    return data
end

local function snapshot(ship)
    local info = get_cloak_tag_info(ship)
    local cloak = ship.cloakSystem
    local result = {augments = info, hasCloak = cloak ~= nil}
    if not cloak then return result end

    local timer = cloak.timer
    result.active = cloak.bTurnedOn
    result.power = cloak:GetEffectivePower()
    result.elapsed = timer and timer.currTime or nil
    result.goal = timer and timer.currGoal or nil
    result.running = timer and timer.running or false
    local scriptData = get_cloak_script_data(ship)
    result.applied = scriptData and scriptData.applied
    result.adjustments = scriptData and scriptData.adjustments or 0
    result.lastBefore = scriptData and scriptData.lastBefore
    result.lastAfter = scriptData and scriptData.lastAfter
    result.lastDelta = scriptData and scriptData.lastDelta
    result.lastScaledDelta = scriptData and scriptData.lastScaledDelta
    result.skippedJumps = scriptData and scriptData.skippedJumps or 0
    result.lastJumpDelta = scriptData and scriptData.lastJumpDelta
    result.rate = scriptData and scriptData.rate
    result.base = timer and timer.currGoal or 0
    result.bonus = info.perPower * result.power
    result.expected = math.max(0.1, result.base + result.bonus)
    return result
end

local function add_event(track, message)
    table.insert(track.events, 1, message)
    while #track.events > MAX_EVENTS do
        table.remove(track.events)
    end
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    if not ship or (ship.iShipId ~= 0 and ship.iShipId ~= 1) then return end

    local track = state[ship.iShipId]
    track.ticks = track.ticks + 1
    local current = snapshot(ship)
    local previous = track.previous

    if current.hasCloak then
        if current.active and (not previous or not previous.active) then
            track.activations = track.activations + 1
            add_event(track, string.format("ON #%d: time=%s goal=%s applied=%s",
                track.activations, num(current.elapsed), num(current.goal), flag(current.applied)))
        elseif previous and previous.active and not current.active then
            add_event(track, string.format("OFF: time=%s goal=%s",
                num(current.elapsed), num(current.goal)))
        elseif current.active and previous and previous.active then
            if current.goal and previous.goal and math.abs(current.goal - previous.goal) > 0.01 then
                add_event(track, string.format("GOAL changed: %s -> %s (time=%s)",
                    num(previous.goal), num(current.goal), num(current.elapsed)))
            end
            if current.applied ~= previous.applied then
                add_event(track, string.format("applied changed: %s -> %s (time=%s)",
                    flag(previous.applied), flag(current.applied), num(current.elapsed)))
            end
        end
    end

    track.previous = current
end)

local function draw_line(line, value)
    Graphics.freetype.easy_print(FONT, TEXT_X, TEXT_Y + line * LINE_HEIGHT, value)
end

local function draw_panel()
    if not Hyperspace.App or not Hyperspace.App.world
        or not Hyperspace.App.world.bStartedGame then return end

    Graphics.CSurface.GL_PushMatrix()
    Graphics.CSurface.GL_LoadIdentity()
    Graphics.CSurface.GL_SetColor(Graphics.GL_Color(1, 1, 1, 1))

    local line = 0
    local function add(value)
        draw_line(line, value)
        line = line + 1
    end

    local loaded = mods.sc and mods.sc.cloakAugments ~= nil
    local registered = get_cloak_tag_info(nil).registered
    add(string.format("CLOAK DURATION TEST | Lua=%s | tagged blueprints=%d",
        loaded and "LOADED" or "MISSING", registered))
    add("Goal = normal timer duration; Time = adjusted elapsed; applied = script flag")

    for shipId = 0, 1 do
        local ship = Hyperspace.ships(shipId)
        local label = shipId == 0 and "PLAYER" or "ENEMY"
        local track = state[shipId]

        if not ship then
            add(label .. ": ship not present")
        else
            local current = snapshot(ship)
            if not current.hasCloak then
                add(label .. ": no Cloaking system")
            else
                add(string.format("%s | ON=%s power=%d | applied=%s | SHIP_LOOP=%d",
                    label, yn(current.active), current.power, flag(current.applied), track.ticks))
                add(string.format("  Timer: time=%s goal=%s remaining=%s running=%s",
                    num(current.elapsed), num(current.goal),
                    current.goal and current.elapsed and num(current.goal - current.elapsed) or "-",
                    yn(current.running)))
                add(string.format("  Augments: equipped=%d per-power=%s total bonus=%s",
                    current.augments.equipped, num(current.augments.perPower), num(current.bonus)))
                if #current.augments.names == 0 then
                    add("    No registered sc-cloak augments equipped")
                else
                    for i = 1, math.min(3, #current.augments.names) do
                        add("    " .. current.augments.names[i])
                    end
                end
                add(string.format("  Duration: normal goal=%s intended=%s speed=%s%%",
                    num(current.base), num(current.expected),
                    current.rate and num(current.rate * 100) or "-"))
                add(string.format("  Time adjustments=%d | last elapsed: %s -> %s",
                    current.adjustments, num(current.lastBefore), num(current.lastAfter)))
                add(string.format("  Frame advance: native=%s adjusted=%s | goal unchanged",
                    num(current.lastDelta), num(current.lastScaledDelta)))
                add(string.format("  Large jumps preserved=%d | last=%s",
                    current.skippedJumps, num(current.lastJumpDelta)))
                add(string.format("  Activations seen=%d | recent events:", track.activations))
                if #track.events == 0 then
                    add("    No activation observed yet")
                else
                    for _, event in ipairs(track.events) do
                        add("    " .. event)
                    end
                end
            end
        end
    end

    Graphics.CSurface.GL_PopMatrix()
end

script.on_render_event(Defines.RenderEvents.MOUSE_CONTROL, draw_panel, function() end)
