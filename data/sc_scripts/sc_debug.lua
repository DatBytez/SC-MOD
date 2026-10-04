--[[
DESCRIPTION: Fixed on-screen ranged crew combat diagnostic.
    Diagnostic only; gameplay logic does not depend on this file.

PURPOSE:
    Detect crew health loss by sampling the global CrewMemberFactory once per
    completed game tick, then test which attacker -> target relationship is
    actually exposed to Lua.

    Established data used:
        Hyperspace.CrewFactory.crewMembers
        crew.extend.selfId
        crew.health.first
        crew.crewTarget
        crew.crewAnim.status
        crew.crewAnim.target

    Experimental target tests:
        TEST 1: crew.crewTarget == victim
        TEST 2: crew.crewTarget:GetPosition() == victim:GetPosition()

    TEST 2 is protected with pcall only because CrewTarget method exposure to
    Lua has not yet been established. It is diagnostic code, not a fallback.
]]

local vter = mods.multiverse.vter

mods.sc = mods.sc or {}
mods.sc.crewHitDebug = {
    tickCount = 0,
    crewCount = 0,
    damageEvents = 0,
    rangedAttackers = 0,
    lastDamage = nil,
    lastRanged = nil,
    recentDamage = {}
}

local debug = mods.sc.crewHitDebug
local healthById = {}

local PANEL_X = 20
local PANEL_Y = 235
local PANEL_W = 820
local PANEL_H = 430

local TEXT_X = PANEL_X + 10
local TEXT_Y = PANEL_Y + 8
local LINE_HEIGHT = 20
local FONT = 10

local MAX_RECENT_DAMAGE = 4

local function draw_line(line, text)
    Graphics.freetype.easy_print(
        FONT,
        TEXT_X,
        TEXT_Y + line * LINE_HEIGHT,
        text
    )
end

local function point_text(point)
    if not point then
        return "N/A"
    end

    return string.format(
        "%.1f, %.1f",
        point.x,
        point.y
    )
end

local function get_crew_id(crew)
    return crew.extend.selfId
end

local function get_crew_name(crew)
    return crew:GetName()
end

local function get_crew_target_position(crewTarget)
    local success, position = pcall(function()
        return crewTarget:GetPosition()
    end)

    if success then
        return position, true
    end

    return nil, false
end

local function get_crew_target_is_crew(crewTarget)
    local success, result = pcall(function()
        return crewTarget:IsCrew()
    end)

    if success then
        return tostring(result), true
    end

    return "ERROR", false
end

local function find_attackers_for_victim(victim)
    local directNames = {}
    local positionNames = {}
    local positionMethodAvailable = false

    local victimPosition = victim:GetPosition()

    for attacker in vter(Hyperspace.CrewFactory.crewMembers) do
        if attacker ~= victim
            and attacker.crewTarget
            and attacker.crewAnim
            and attacker.bFighting then

            -- TEST 1:
            -- Does CrewTarget directly compare equal to the CrewMember?
            if attacker.crewTarget == victim then
                table.insert(
                    directNames,
                    get_crew_name(attacker)
                )
            end

            -- TEST 2:
            -- Does CrewTarget:GetPosition() identify the damaged CrewMember?
            local targetPosition, available =
                get_crew_target_position(attacker.crewTarget)

            if available then
                positionMethodAvailable = true

                if targetPosition.x == victimPosition.x
                    and targetPosition.y == victimPosition.y then

                    table.insert(
                        positionNames,
                        get_crew_name(attacker)
                    )
                end
            end
        end
    end

    return {
        direct = #directNames > 0
            and table.concat(directNames, ", ")
            or "NONE",

        position = #positionNames > 0
            and table.concat(positionNames, ", ")
            or "NONE",

        positionMethodAvailable = positionMethodAvailable
    }
end

local function record_damage(victim, oldHealth, newHealth)
    local attackers = find_attackers_for_victim(victim)

    local event = {
        victim = get_crew_name(victim),
        victimId = get_crew_id(victim),
        race = victim.crewAnim and victim.crewAnim.race or "N/A",
        ownerShip = victim.iShipId,
        currentShip = victim.currentShipId,
        position = victim:GetPosition(),
        oldHealth = oldHealth,
        newHealth = newHealth,
        damage = oldHealth - newHealth,
        directAttackers = attackers.direct,
        positionAttackers = attackers.position,
        positionMethodAvailable = attackers.positionMethodAvailable
    }

    debug.damageEvents = debug.damageEvents + 1
    debug.lastDamage = event

    table.insert(
        debug.recentDamage,
        1,
        string.format(
            "%s [%d]   %.2f -> %.2f   Damage %.2f",
            event.victim,
            event.victimId,
            event.oldHealth,
            event.newHealth,
            event.damage
        )
    )

    if #debug.recentDamage > MAX_RECENT_DAMAGE then
        table.remove(debug.recentDamage)
    end
end

local function sample_ranged_attackers()
    local rangedCount = 0
    local lastRanged = nil

    for crew in vter(Hyperspace.CrewFactory.crewMembers) do
        if crew.crewAnim
            and crew.bFighting
            and crew.crewTarget
            and crew.crewAnim.status == 7 then

            rangedCount = rangedCount + 1

            local targetPosition, positionAvailable =
                get_crew_target_position(crew.crewTarget)

            local targetIsCrew, isCrewAvailable =
                get_crew_target_is_crew(crew.crewTarget)

            lastRanged = {
                attacker = get_crew_name(crew),
                attackerId = get_crew_id(crew),
                race = crew.crewAnim.race,
                ownerShip = crew.iShipId,
                currentShip = crew.currentShipId,
                animationTarget = crew.crewAnim.target,
                targetPosition = targetPosition,
                positionAvailable = positionAvailable,
                targetIsCrew = targetIsCrew,
                isCrewAvailable = isCrewAvailable
            }
        end
    end

    debug.rangedAttackers = rangedCount

    if lastRanged then
        debug.lastRanged = lastRanged
    end
end

local function sample_crew()
    if not Hyperspace.App
        or not Hyperspace.App.world
        or not Hyperspace.App.world.bStartedGame then
        return
    end

    debug.tickCount = debug.tickCount + 1

    local crewCount = 0

    for crew in vter(Hyperspace.CrewFactory.crewMembers) do
        crewCount = crewCount + 1

        local crewId = get_crew_id(crew)
        local currentHealth = crew.health.first
        local previousHealth = healthById[crewId]

        if previousHealth ~= nil
            and currentHealth < previousHealth then

            record_damage(
                crew,
                previousHealth,
                currentHealth
            )
        end

        healthById[crewId] = currentHealth
    end

    debug.crewCount = crewCount
    sample_ranged_attackers()
end

script.on_internal_event(
    Defines.InternalEvents.ON_TICK,
    sample_crew
)

local function draw_panel()
    if not Hyperspace.App
        or not Hyperspace.App.world
        or not Hyperspace.App.world.bStartedGame then
        return
    end

    Graphics.CSurface.GL_PushMatrix()
    Graphics.CSurface.GL_LoadIdentity()

    Graphics.CSurface.GL_DrawRect(
        PANEL_X,
        PANEL_Y,
        PANEL_W,
        PANEL_H,
        Graphics.GL_Color(0, 0, 0, 0.82)
    )

    Graphics.CSurface.GL_SetColor(
        Graphics.GL_Color(1, 1, 1, 1)
    )

    draw_line(0, "CREW HIT DEBUG")

    draw_line(
        1,
        string.format(
            "ON_TICK samples: %d   CrewFactory crew: %d   Damage events: %d",
            debug.tickCount,
            debug.crewCount,
            debug.damageEvents
        )
    )

    draw_line(
        2,
        "Ranged attackers currently observed (status 7): "
        .. tostring(debug.rangedAttackers)
    )

    local damage = debug.lastDamage

    draw_line(4, "LAST CREW HEALTH DECREASE")

    if damage then
        draw_line(
            5,
            string.format(
                "Victim: %s   ID: %d   Race: %s",
                damage.victim,
                damage.victimId,
                tostring(damage.race)
            )
        )

        draw_line(
            6,
            string.format(
                "Health: %.2f -> %.2f   Damage: %.2f",
                damage.oldHealth,
                damage.newHealth,
                damage.damage
            )
        )

        draw_line(
            7,
            string.format(
                "Owner Ship: %s   Current Ship: %s   Position: %s",
                tostring(damage.ownerShip),
                tostring(damage.currentShip),
                point_text(damage.position)
            )
        )

        draw_line(
            8,
            "TEST 1 - crewTarget == victim: "
            .. damage.directAttackers
        )

        draw_line(
            9,
            string.format(
                "TEST 2 - CrewTarget position: %s   Method available: %s",
                damage.positionAttackers,
                tostring(damage.positionMethodAvailable)
            )
        )
    else
        draw_line(
            5,
            "Waiting for CrewFactory health sampling to observe damage..."
        )
    end

    draw_line(11, "LAST OBSERVED STATUS-7 RANGED ATTACKER")

    local ranged = debug.lastRanged

    if ranged then
        draw_line(
            12,
            string.format(
                "Attacker: %s   ID: %d   Race: %s",
                ranged.attacker,
                ranged.attackerId,
                tostring(ranged.race)
            )
        )

        draw_line(
            13,
            string.format(
                "Owner Ship: %s   Current Ship: %s",
                tostring(ranged.ownerShip),
                tostring(ranged.currentShip)
            )
        )

        draw_line(
            14,
            "crewAnim.target: "
            .. point_text(ranged.animationTarget)
        )

        draw_line(
            15,
            string.format(
                "crewTarget:GetPosition(): %s   Available: %s",
                point_text(ranged.targetPosition),
                tostring(ranged.positionAvailable)
            )
        )

        draw_line(
            16,
            string.format(
                "crewTarget:IsCrew(): %s   Available: %s",
                ranged.targetIsCrew,
                tostring(ranged.isCrewAvailable)
            )
        )
    else
        draw_line(
            12,
            "No status-7 ranged attacker has been observed yet."
        )
    end

    draw_line(18, "RECENT CREW HEALTH DECREASES")

    for i = 1, MAX_RECENT_DAMAGE do
        draw_line(
            18 + i,
            debug.recentDamage[i] or "-"
        )
    end

    Graphics.CSurface.GL_PopMatrix()
end

script.on_render_event(
    Defines.RenderEvents.MOUSE_CONTROL,
    draw_panel,
    function() end
)
