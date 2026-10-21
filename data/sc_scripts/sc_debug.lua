--[[
DESCRIPTION: Temporary on-screen Terran Medic CREW_TARGET test.
        - Replaces the previous defense-drone diagnostics entirely.
        - Optionally assigns the first injured friendly non-drone in each medic's room.
        - Displays targeting, effective trueHealAmount, and HP changes.
        - Does not heal crew directly.
DEPENDENCIES: Hyperspace. Does not depend on any other SC debug script.
]]

local ASSIGN_TEST_TARGET = true -- Set false to observe a separate medic targeting script without changing its targets.
local REFRESH_TICKS = 15
local HEALTH_SAMPLE_TICKS = 30
local MAX_MEDICS_SHOWN = 3
local MAX_CREW_SHOWN = 5

local TEXT_X = 20
local TEXT_Y = 115
local LINE_HEIGHT = 16
local FONT = 10

local medicRaces = {
    terran_medic = true,
    terran_medic_1 = true,
    terran_medic_2 = true
}

local state = {
    ticks = {[0] = 0, [1] = 0},
    medics = {[0] = {}, [1] = {}},
    medicCounts = {[0] = 0, [1] = 0},
    lastHealth = {},
    healthDelta = {}
}

local function yn(value)
    return value and "Y" or "N"
end

local function number(value)
    if type(value) ~= "number" then return "-" end
    return string.format("%.1f", value)
end

local function name_of(crew)
    if not crew then return "none" end
    local ok, name = pcall(function() return crew:GetName() end)
    if not ok or not name then return crew:GetSpecies() end
    return tostring(name):gsub("[\r\n]", " "):sub(1, 18)
end

local function crew_id(crew)
    if not crew or not crew.extend then return "?" end
    return tostring(crew.extend.selfId)
end

local function same_room_friendly(medic, crew)
    return crew_id(crew) ~= crew_id(medic)
        and not crew.bDead
        and medic.iRoomId >= 0
        and crew.iRoomId == medic.iRoomId
        and crew.currentShipId == medic.currentShipId
        and crew.iShipId == medic.iShipId
end

local function is_eligible(medic, crew)
    return same_room_friendly(medic, crew)
        and not crew:IsDrone()
        and crew.health.first > 0
        and crew.health.first < crew.health.second
end

local function first_eligible(medic, ship)
    for i = 0, ship.vCrewList:size() - 1 do
        local crew = ship.vCrewList[i]
        if is_eligible(medic, crew) then return crew end
    end
    return nil
end

local function effective_heal(crew)
    local ok, amount = pcall(function()
        return crew.extend:CalculateStat(Hyperspace.CrewStat.TRUE_HEAL_AMOUNT)
    end)
    if not ok then return "ERR" end
    return number(amount)
end

local function health_key(shipId, crew)
    return tostring(shipId) .. ":" .. crew_id(crew)
end

local function sample_health(ship)
    for i = 0, ship.vCrewList:size() - 1 do
        local crew = ship.vCrewList[i]
        if crew and not crew.bDead then
            local key = health_key(ship.iShipId, crew)
            local now = crew.health.first
            local previous = state.lastHealth[key]
            if previous ~= nil then
                state.healthDelta[key] = now - previous
            end
            state.lastHealth[key] = now
        end
    end
end

local function make_snapshot(medic, target, writeOk, writeError, preTarget)
    local afterTarget = medic.crewTarget
    local snapshot = {
        medicName = name_of(medic),
        medicId = crew_id(medic),
        room = medic.iRoomId,
        functional = medic:Functional(),
        intended = target and (name_of(target) .. "#" .. crew_id(target)) or "none",
        priorPresent = preTarget ~= nil,
        afterPresent = afterTarget ~= nil,
        writeStatus = not ASSIGN_TEST_TARGET and "OBSERVE" or (writeOk and "OK" or "ERROR"),
        writeError = writeError,
        crewLines = {}
    }

    -- This list includes excluded drones and full-health crew to explain the choice.
    local ship = Hyperspace.Global.GetInstance():GetShipManager(medic.currentShipId)
    if not ship then return snapshot end

    for i = 0, ship.vCrewList:size() - 1 do
        local crew = ship.vCrewList[i]
        if same_room_friendly(medic, crew) then
            local status = target and crew_id(crew) == crew_id(target) and "*" or " "
            if crew:IsDrone() then
                status = "D"
            elseif crew.health.first >= crew.health.second then
                status = "F"
            end
            local change = state.healthDelta[health_key(ship.iShipId, crew)]
            snapshot.crewLines[#snapshot.crewLines + 1] = string.format(
                "%s %s#%s HP %s/%s trueHeal=%s d%d=%s",
                status,
                name_of(crew),
                crew_id(crew),
                number(crew.health.first),
                number(crew.health.second),
                effective_heal(crew),
                HEALTH_SAMPLE_TICKS,
                change == nil and "-" or string.format("%+.1f", change)
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

    local makeDisplay = ticks == 1 or ticks % REFRESH_TICKS == 0
    local snapshots = {}
    local medicCount = 0

    for i = 0, ship.vCrewList:size() - 1 do
        local medic = ship.vCrewList[i]

        if medic and not medic.bDead and medicRaces[medic:GetSpecies()] then
            medicCount = medicCount + 1
            local target = first_eligible(medic, ship)
            local previous = medic.crewTarget
            local writeOk, writeError = true, nil

            if ASSIGN_TEST_TARGET then
                writeOk, writeError = pcall(function()
                    medic.crewTarget = target
                end)
            end

            if makeDisplay and medicCount <= MAX_MEDICS_SHOWN then
                snapshots[#snapshots + 1] = make_snapshot(
                    medic, target, writeOk, writeError, previous
                )
            end
        end
    end

    if makeDisplay then
        state.medics[shipId] = snapshots
        state.medicCounts[shipId] = medicCount
    end
end)

local function boost_definition_line()
    local ok, def = pcall(function()
        return Hyperspace.StatBoostDefinition.savedStatBoostDefs["Heal-Crew"]
    end)

    if not ok then return "Heal-Crew: could not inspect saved XML definition" end
    if not def then return "Heal-Crew: MISSING saved XML definition" end

    return string.format(
        "Heal-Crew: target=CREW_TARGET:%s stat=TRUE_HEAL:%s amount=%s",
        yn(def.shipTarget == Hyperspace.StatBoostDefinition.ShipTarget.CREW_TARGET),
        yn(def.stat == Hyperspace.CrewStat.TRUE_HEAL_AMOUNT),
        number(def.amount)
    )
end

local function draw_line(line, value)
    Graphics.freetype.easy_print(
        FONT, TEXT_X, TEXT_Y + line * LINE_HEIGHT, value
    )
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

    add("MEDIC CREW_TARGET TEST | assignment=" .. (ASSIGN_TEST_TARGET and "ON" or "OFF"))
    add(boost_definition_line())
    add("Legend: *=selected D=drone F=full | d30=HP change per 30 ship loops")

    local shown = 0
    for shipId = 0, 1 do
        local ship = Hyperspace.Global.GetInstance():GetShipManager(shipId)
        if ship then
            add(string.format("%s ship: %d medics | loop %d",
                shipId == 0 and "PLAYER" or "ENEMY",
                state.medicCounts[shipId] or 0,
                state.ticks[shipId] or 0
            ))

            for _, medic in ipairs(state.medics[shipId]) do
                if shown >= MAX_MEDICS_SHOWN then break end
                shown = shown + 1
                add(string.format(" Medic %s#%s room %s functional=%s",
                    medic.medicName, medic.medicId, tostring(medic.room), yn(medic.functional)))
                add(string.format(" Pick: %s | write=%s | before=%s after=%s",
                    medic.intended, medic.writeStatus,
                    yn(medic.priorPresent), yn(medic.afterPresent)))
                if medic.writeError then add(" Assignment error: " .. tostring(medic.writeError):sub(1, 90)) end
                for i = 1, math.min(MAX_CREW_SHOWN, #medic.crewLines) do
                    add("  " .. medic.crewLines[i])
                end
                if #medic.crewLines == 0 then add("  No other friendly crew in medic room") end
                if #medic.crewLines > MAX_CREW_SHOWN then
                    add("  ..." .. tostring(#medic.crewLines - MAX_CREW_SHOWN) .. " more crew")
                end
            end
        end
    end

    if shown == 0 then add("No living Terran Medics detected on either ship") end
    Graphics.CSurface.GL_PopMatrix()
end

script.on_render_event(
    Defines.RenderEvents.MOUSE_CONTROL,
    draw_panel,
    function() end
)
