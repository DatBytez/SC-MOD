--[[
DESCRIPTION: On-screen diagnostics for custom temporary-effect shooting and punching timers.
        - Reports parsed power tags and the temporary-effect script's activity.
        - Shows active powers, requested timers, saved originals, and live crew timers.
        - Counts observed shooting-timer resets to help distinguish timing from animation behavior.
        - Does not change crew powers, attack timers, or damage.
DEPENDENCIES: sc_temporaryEffects.lua (diagnostics remain visible if missing).
]]

local TEXT_X = 20
local TEXT_Y = 165
local LINE_HEIGHT = 16
local FONT = 10
local MAX_CREW_PER_SHIP = 2

local observations = {}
local resets = {}

local function num(value)
    return type(value) == "number" and string.format("%.3f", value) or "-"
end

local function integer(value)
    return type(value) == "number" and string.format("%.0f", value) or "-"
end

local function yn(value)
    return value and "Y" or "N"
end

local function interval(config)
    if not config then return "none" end
    return integer(config.min) .. "-" .. integer(config.max)
end

local function live_timer(timer)
    if not timer then return "MISSING" end
    return string.format("%s-%s ms | goal=%s time=%s run=%s",
        integer(timer.minTime), integer(timer.maxTime),
        num(timer.currGoal), num(timer.currTime), yn(timer.running))
end

local function matching_power(crew, configs)
    local powers = crew.extend and crew.extend.crewPowers
    if not powers then return false end

    for i = 0, powers:size() - 1 do
        local power = powers[i]
        local name = power and power.def and power.def.name
        if name == "SC_STIMPACK" or (name and configs and configs[name]) then
            return true
        end
    end

    return false
end

-- The actual crew loop runs after native crew updates. A lower timer value
-- can indicate a new attack cycle; this is a timer-reset count, not a hit count.
script.on_internal_event(Defines.InternalEvents.CREW_LOOP, function(crew)
    if not crew or not crew.extend or not crew.crewAnim then return end
    local diagnostics = mods.sc and mods.sc.temporaryEffectDebug
    local configs = diagnostics and diagnostics.powerTimers

    if crew:GetSpecies() ~= "terran_marine_1" and not matching_power(crew, configs) then return end

    local id = crew.extend.selfId
    local timer = crew.crewAnim.shootTimer
    local old = observations[id]

    if old and timer.currTime + 0.025 < old then
        resets[id] = (resets[id] or 0) + 1
    end

    observations[id] = timer.currTime
end)

local function add_crew_lines(add, crew, diagnostics)
    local name = tostring(crew:GetName()):gsub("[\r\n]", " "):sub(1, 18)
    local id = crew.extend and crew.extend.selfId or "-"
    local configs = diagnostics and diagnostics.powerTimers

    add(string.format(" %s #%s (%s) | observed resets=%d",
        name, tostring(id), crew:GetSpecies(), resets[id] or 0))

    local found = false
    local powers = crew.extend and crew.extend.crewPowers
    if powers then
        for i = 0, powers:size() - 1 do
            local power = powers[i]
            local powerName = power and power.def and power.def.name
            if powerName == "SC_STIMPACK" or (powerName and configs and configs[powerName]) then
                found = true
                local duration = power.temporaryPowerDuration
                add(string.format("  power=%s ACTIVE=%s remain=%ss tagged=%s",
                    powerName, yn(power.temporaryPowerActive),
                    duration and num(duration.first) or "-",
                    yn(configs and configs[powerName] ~= nil)))
            end
        end
    end

    if not found then add("  No matching power in crew.crewPowers") end

    local state, shoot, punch
    if diagnostics and diagnostics.inspect then
        local ok, a, b, c = pcall(diagnostics.inspect, crew)
        if ok then
            state, shoot, punch = a, b, c
        else
            add("  inspect ERROR: " .. tostring(a):sub(1, 70))
        end
    else
        add("  inspect unavailable (temporaryEffect script missing/old)")
    end

    add("  requested: shoot=" .. interval(shoot) .. "ms punch=" .. interval(punch) .. "ms")
    add("  originals: shoot=" .. interval(state and state.shoot)
        .. "ms punch=" .. interval(state and state.punch) .. "ms")

    local anim = crew.crewAnim
    add("  SHOOT " .. live_timer(anim.shootTimer))
    add("  PUNCH " .. live_timer(anim.punchTimer))
end

local function draw_panel()
    if not Hyperspace.App or not Hyperspace.App.world
        or not Hyperspace.App.world.bStartedGame then return end

    Graphics.CSurface.GL_PushMatrix()
    Graphics.CSurface.GL_LoadIdentity()
    Graphics.CSurface.GL_SetColor(Graphics.GL_Color(1, 1, 1, 1))

    local line = 0
    local function add(value)
        Graphics.freetype.easy_print(FONT, TEXT_X, TEXT_Y + line * LINE_HEIGHT, value)
        line = line + 1
    end

    local diagnostics = mods.sc and mods.sc.temporaryEffectDebug
    local configs = diagnostics and diagnostics.powerTimers or {}
    local registered = 0
    for _ in pairs(configs) do registered = registered + 1 end

    add(string.format("TEMP TIMER TEST | script=%s | parsed powers=%d | crew loops=%s",
        diagnostics and "LOADED" or "MISSING", registered,
        diagnostics and tostring(diagnostics.crewLoops) or "-"))
    add(string.format(" Parser: crew=%s powers=%s temp=%s | tags=%s invalid=%s",
        diagnostics and tostring(diagnostics.crewNodes) or "-",
        diagnostics and tostring(diagnostics.powerNodes) or "-",
        diagnostics and tostring(diagnostics.temporaryNodes) or "-",
        diagnostics and tostring(diagnostics.tagsFound) or "-",
        diagnostics and tostring(diagnostics.invalidTags) or "-"))
    add(string.format(" Changed=%s restored=%s | active loops=%s",
        diagnostics and tostring(diagnostics.timerChanges) or "-",
        diagnostics and tostring(diagnostics.timerRestores) or "-",
        diagnostics and tostring(diagnostics.activeLoops) or "-"))

    local stim = configs.SC_STIMPACK
    add(" SC_STIMPACK parsed: shoot=" .. interval(stim and stim.shoot)
        .. "ms punch=" .. interval(stim and stim.punch) .. "ms")
    add(" Timers: min-max in ms; goal/time in seconds; resets are approximate")

    for shipId = 0, 1 do
        local ship = Hyperspace.ships(shipId)
        local label = shipId == 0 and "PLAYER" or "ENEMY"

        if not ship then
            add(label .. ": ship not present")
        else
            local count = 0
            local displayed = 0
            for i = 0, ship.vCrewList:size() - 1 do
                local crew = ship.vCrewList[i]
                if crew and not crew.bDead and
                    (crew:GetSpecies() == "terran_marine_1" or matching_power(crew, configs)) then
                    count = count + 1
                    if displayed < MAX_CREW_PER_SHIP then
                        displayed = displayed + 1
                        add(label .. " CREW " .. tostring(displayed))
                        local ok, err = pcall(add_crew_lines, add, crew, diagnostics)
                        if not ok then add("  DEBUG READ ERROR: " .. tostring(err):sub(1, 80)) end
                    end
                end
            end
            if count == 0 then add(label .. ": no tagged crew / terran_marine_1") end
            if count > displayed then add(label .. ": " .. tostring(count - displayed) .. " more crew hidden") end
        end
    end

    Graphics.CSurface.GL_PopMatrix()
end

script.on_render_event(Defines.RenderEvents.MOUSE_CONTROL, draw_panel, function() end)
