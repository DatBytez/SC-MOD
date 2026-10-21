--[[
DESCRIPTION: On-screen Terran Medic healing diagnostics.
        - Displays medic selection, affected crew, XML boost targeting, and effective healing.
        - Does not assign targets or alter healing.
DEPENDENCIES: sc_crew_ability_heal.lua (diagnostics remain visible if missing).
]]

local REFRESH_TICKS = 15
local HEALTH_SAMPLE_TICKS = 30
local MAX_MEDICS_SHOWN = 3
local MAX_CREW_SHOWN = 5

local TEXT_X = 20
local TEXT_Y = 165
local LINE_HEIGHT = 16
local FONT = 10

local medicRaces = {
    terran_medic = true,
    terran_medic_1 = true,
    terran_medic_2 = true
}

local state = {
    ticks = {[0] = 0, [1] = 0},
    healthBefore = {},
    healthDelta = {},
    snapshots = {[0] = {}, [1] = {}},
    medicCounts = {[0] = 0, [1] = 0}
}

local function name_of(crew)
    if not crew then return "none" end
    return tostring(crew:GetName()):gsub("[\r\n]", " "):sub(1, 15)
end

local function id_of(crew)
    return crew and crew.extend and tostring(crew.extend.selfId) or "-"
end

local function num(n)
    return type(n) == "number" and string.format("%.1f", n) or "-"
end

local function yn(v)
    return v and "Y" or "N"
end

local function health_key(shipId, crew)
    return tostring(shipId) .. ":" .. id_of(crew)
end

local function sample_health(ship)
    for i = 0, ship.vCrewList:size() - 1 do
        local crew = ship.vCrewList[i]
        if crew and not crew.bDead then
            local key = health_key(ship.iShipId, crew)
            local before = state.healthBefore[key]
            if before ~= nil then
                state.healthDelta[key] = crew.health.first - before
            end
            state.healthBefore[key] = crew.health.first
        end
    end
end

local function effective_heal(crew)
    local ok, amount = pcall(function()
        return crew.extend:CalculateStat(Hyperspace.CrewStat.TRUE_HEAL_AMOUNT)
    end)
    return ok and num(amount) or "ERR"
end

local function build_medic_snapshot(medic, ship, heal)
    local target = heal and heal.choose_target(medic, ship) or nil
    local snapshot = {
        header = string.format("Medic %s#%s r%d active=%s -> %s#%s",
            name_of(medic), id_of(medic), medic.iRoomId,
            yn(medic:Functional()), name_of(target), id_of(target)),
        crewLines = {}
    }

    for i = 0, ship.vCrewList:size() - 1 do
        local crew = ship.vCrewList[i]

        if crew and not crew.bDead and crew.extend.selfId ~= medic.extend.selfId
            and crew.iRoomId == medic.iRoomId
            and crew.currentShipId == medic.currentShipId
            and crew.iShipId == medic.iShipId then

            local sources, selected = 0, 0
            if heal then sources, selected = heal.count_boosts(crew, ship) end
            local isTarget = target and target.extend.selfId == crew.extend.selfId
            local marker = crew:IsDrone() and "D" or (isTarget and "*" or "-")
            local change = state.healthDelta[health_key(ship.iShipId, crew)]
            snapshot.crewLines[#snapshot.crewLines + 1] = string.format(
                " %s %s#%s HP %s/%s heal=%s src=%d sel=%d d30=%s",
                marker, name_of(crew), id_of(crew),
                num(crew.health.first), num(crew.health.second),
                effective_heal(crew), sources, selected,
                change and string.format("%+.1f", change) or "-"
            )
        end
    end

    return snapshot
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    if not ship or (ship.iShipId ~= 0 and ship.iShipId ~= 1) then return end

    local shipId = ship.iShipId
    state.ticks[shipId] = state.ticks[shipId] + 1
    local ticks = state.ticks[shipId]

    if ticks % HEALTH_SAMPLE_TICKS == 0 then
        sample_health(ship)
    end

    if ticks ~= 1 and ticks % REFRESH_TICKS ~= 0 then return end

    local heal = mods.sc and mods.sc.medicHeal
    local snapshots = {}
    local count = 0

    for i = 0, ship.vCrewList:size() - 1 do
        local medic = ship.vCrewList[i]
        if medic and not medic.bDead and medicRaces[medic:GetSpecies()] then
            count = count + 1
            if count <= MAX_MEDICS_SHOWN then
                snapshots[#snapshots + 1] = build_medic_snapshot(medic, ship, heal)
            end
        end
    end

    state.snapshots[shipId] = snapshots
    state.medicCounts[shipId] = count
end)

local function boost_info()
    local ok, def = pcall(function()
        return Hyperspace.StatBoostDefinition.savedStatBoostDefs["Heal-Crew"]
    end)
    if not ok or not def then return "XML Heal-Crew=MISSING" end

    return string.format("XML Heal-Crew: room=%s stat=%s amt=%s",
        yn(def.shipTarget == Hyperspace.StatBoostDefinition.ShipTarget.CURRENT_ROOM),
        yn(def.stat == Hyperspace.CrewStat.TRUE_HEAL_AMOUNT),
        num(def.amount))
end

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

    local heal = mods.sc and mods.sc.medicHeal
    add("MEDIC HEAL TEST | Lua=" .. (heal and "ON" or "MISSING"))
    add(boost_info())
    add(string.format("POST calls=%s adjusted=%s | *=selected D=drone | d30=HP delta",
        heal and tostring(heal.postCalls) or "-",
        heal and tostring(heal.adjustedCalls) or "-"))

    local displayed = 0
    for shipId = 0, 1 do
        if (state.medicCounts[shipId] > 0) then
            add(string.format("%s medics=%d ticks=%d",
                shipId == 0 and "PLAYER" or "ENEMY",
                state.medicCounts[shipId], state.ticks[shipId]))

            for _, snapshot in ipairs(state.snapshots[shipId]) do
                if displayed >= MAX_MEDICS_SHOWN then break end
                displayed = displayed + 1
                add(snapshot.header)
                for i = 1, math.min(MAX_CREW_SHOWN, #snapshot.crewLines) do
                    add(snapshot.crewLines[i])
                end
                if #snapshot.crewLines == 0 then add(" No friendly crew in medic's room") end
            end
        end
    end

    if displayed == 0 then add("No Terran Medics found on either ship") end

    Graphics.CSurface.GL_PopMatrix()
end

script.on_render_event(Defines.RenderEvents.MOUSE_CONTROL, draw_panel, function() end)
