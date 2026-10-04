--[[
DESCRIPTION: Fixed on-screen ranged crew combat diagnostic.
    Diagnostic only; gameplay logic does not depend on this file.

PURPOSE:
    CrewAnimation.fDamageDone is consumed during CrewMember::OnLoop before
    CREW_LOOP is exposed to Lua, so this diagnostic instead observes:

    1. Actual CrewMember health decreases.
    2. The attacking crew's crewTarget.
    3. Whether crewTarget directly compares equal to the damaged CrewMember.
    4. Whether crewTarget:GetPosition() matches the damaged CrewMember position.
    5. Live ranged-combat animation state and target coordinates.

    Direct equality and position matching are intentionally kept as separate
    tests. Neither is used as a fallback for the other.
]]

local vter = mods.multiverse.vter

mods.sc = mods.sc or {}
mods.sc.crewHitDebug = {
    damageEvents = 0,
    lastDamage = nil,
    lastRangedAttack = nil,
    recentDamage = {}
}

local debug = mods.sc.crewHitDebug

local PANEL_X = 20
local PANEL_Y = 235
local PANEL_W = 800
local PANEL_H = 410

local TEXT_X = PANEL_X + 10
local TEXT_Y = PANEL_Y + 8
local LINE_HEIGHT = 20
local FONT = 10

local STATE_KEY = "mods.sc.crewHitDebugState"
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

local function get_crew_target_position(crewTarget)
    if not crewTarget then
        return nil, false
    end

    local success, position = pcall(function()
        return crewTarget:GetPosition()
    end)

    if success then
        return position, true
    end

    return nil, false
end

local function get_crew_target_is_crew(crewTarget)
    if not crewTarget then
        return "N/A"
    end

    local success, result = pcall(function()
        return crewTarget:IsCrew()
    end)

    if success then
        return tostring(result)
    end

    return "ERROR"
end

local function get_target_matches(attacker)
    local result = {
        directMatch = "NONE",
        positionMatch = "NONE",
        targetPosition = nil,
        targetPositionCall = false
    }

    if not attacker.crewTarget then
        return result
    end

    local shipManager =
        Hyperspace.Global.GetInstance():GetShipManager(attacker.currentShipId)

    if not shipManager then
        return result
    end

    result.targetPosition, result.targetPositionCall =
        get_crew_target_position(attacker.crewTarget)

    local positionNames = {}

    for candidate in vter(shipManager.vCrewList) do
        -- TEST 1:
        -- Does CrewTarget compare directly to the CrewMember it represents?
        if attacker.crewTarget == candidate then
            result.directMatch = candidate:GetName()
        end

        -- TEST 2:
        -- Does CrewTarget:GetPosition() resolve to the CrewMember position?
        if result.targetPosition then
            local candidatePosition = candidate:GetPosition()

            if candidatePosition.x == result.targetPosition.x
                and candidatePosition.y == result.targetPosition.y then

                table.insert(
                    positionNames,
                    candidate:GetName()
                )
            end
        end
    end

    if #positionNames > 0 then
        result.positionMatch = table.concat(positionNames, ", ")
    end

    return result
end

local function update_last_ranged_attack(crew)
    local crewAnimation = crew.crewAnim

    if not crew.bFighting
        or not crew.crewTarget
        or crewAnimation.status ~= 7 then
        return
    end

    local targetMatches = get_target_matches(crew)

    debug.lastRangedAttack = {
        attacker = crew:GetName(),
        race = crewAnimation.race,
        ownerShip = crew.iShipId,
        currentShip = crew.currentShipId,
        status = crewAnimation.status,
        fDamageDone = crewAnimation.fDamageDone,
        animationTarget = crewAnimation.target,
        targetIsCrew = get_crew_target_is_crew(crew.crewTarget),
        targetPosition = targetMatches.targetPosition,
        targetPositionCall = targetMatches.targetPositionCall,
        directMatch = targetMatches.directMatch,
        positionMatch = targetMatches.positionMatch
    }
end

local function find_attackers_targeting(victim)
    local result = {
        directAttackers = {},
        positionAttackers = {}
    }

    local shipManager =
        Hyperspace.Global.GetInstance():GetShipManager(victim.currentShipId)

    if not shipManager then
        return result
    end

    local victimPosition = victim:GetPosition()

    for attacker in vter(shipManager.vCrewList) do
        if attacker ~= victim
            and attacker.bFighting
            and attacker.crewTarget then

            -- TEST 1:
            -- Direct CrewTarget -> CrewMember equality.
            if attacker.crewTarget == victim then
                table.insert(
                    result.directAttackers,
                    attacker:GetName()
                )
            end

            -- TEST 2:
            -- CrewTarget position -> damaged CrewMember position.
            local targetPosition =
                get_crew_target_position(attacker.crewTarget)

            if targetPosition
                and targetPosition.x == victimPosition.x
                and targetPosition.y == victimPosition.y then

                table.insert(
                    result.positionAttackers,
                    attacker:GetName()
                )
            end
        end
    end

    return result
end

local function record_damage(crew, oldHealth, newHealth)
    local attackers = find_attackers_targeting(crew)

    local directAttackers = "NONE"
    if #attackers.directAttackers > 0 then
        directAttackers = table.concat(
            attackers.directAttackers,
            ", "
        )
    end

    local positionAttackers = "NONE"
    if #attackers.positionAttackers > 0 then
        positionAttackers = table.concat(
            attackers.positionAttackers,
            ", "
        )
    end

    local event = {
        victim = crew:GetName(),
        race = crew.crewAnim and crew.crewAnim.race or "N/A",
        ownerShip = crew.iShipId,
        currentShip = crew.currentShipId,
        position = crew:GetPosition(),
        oldHealth = oldHealth,
        newHealth = newHealth,
        damage = oldHealth - newHealth,
        lastDamageTimer = crew.lastDamageTimer,
        lastHealthChange = crew.lastHealthChange,
        directAttackers = directAttackers,
        positionAttackers = positionAttackers
    }

    debug.damageEvents = debug.damageEvents + 1
    debug.lastDamage = event

    table.insert(
        debug.recentDamage,
        1,
        string.format(
            "%s   %.2f -> %.2f   Damage: %.2f",
            event.victim,
            oldHealth,
            newHealth,
            event.damage
        )
    )

    if #debug.recentDamage > MAX_RECENT_DAMAGE then
        table.remove(debug.recentDamage)
    end
end

script.on_internal_event(
    Defines.InternalEvents.CREW_LOOP,
    function(crew)
        local state = userdata_table(crew, STATE_KEY)
        local currentHealth = crew.health.first

        if state.lastHealth == nil then
            state.lastHealth = currentHealth
        elseif currentHealth < state.lastHealth then
            record_damage(
                crew,
                state.lastHealth,
                currentHealth
            )

            state.lastHealth = currentHealth
        elseif currentHealth ~= state.lastHealth then
            state.lastHealth = currentHealth
        end

        if crew.crewAnim then
            update_last_ranged_attack(crew)
        end
    end
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
        "Crew health decreases detected: "
        .. tostring(debug.damageEvents)
    )

    local damage = debug.lastDamage

    if damage then
        draw_line(
            2,
            string.format(
                "Last damaged: %s   Race: %s",
                damage.victim,
                tostring(damage.race)
            )
        )

        draw_line(
            3,
            string.format(
                "Health: %.2f -> %.2f   Damage: %.2f",
                damage.oldHealth,
                damage.newHealth,
                damage.damage
            )
        )

        draw_line(
            4,
            string.format(
                "Owner Ship: %s   Current Ship: %s   Position: %s",
                tostring(damage.ownerShip),
                tostring(damage.currentShip),
                point_text(damage.position)
            )
        )

        draw_line(
            5,
            string.format(
                "lastDamageTimer: %.3f   lastHealthChange: %.3f",
                damage.lastDamageTimer,
                damage.lastHealthChange
            )
        )

        draw_line(
            6,
            "TEST 1 - Direct attacker(s): "
            .. damage.directAttackers
        )

        draw_line(
            7,
            "TEST 2 - Position attacker(s): "
            .. damage.positionAttackers
        )
    else
        draw_line(
            3,
            "Waiting for a CrewMember health decrease..."
        )
    end

    local attack = debug.lastRangedAttack

    draw_line(9, "LAST OBSERVED RANGED ATTACK STATE")

    if attack then
        draw_line(
            10,
            string.format(
                "Attacker: %s   Race: %s   Status: %s",
                attack.attacker,
                tostring(attack.race),
                tostring(attack.status)
            )
        )

        draw_line(
            11,
            string.format(
                "Owner Ship: %s   Current Ship: %s   fDamageDone at CREW_LOOP: %.3f",
                tostring(attack.ownerShip),
                tostring(attack.currentShip),
                attack.fDamageDone
            )
        )

        draw_line(
            12,
            "crewAnim.target: "
            .. point_text(attack.animationTarget)
        )

        draw_line(
            13,
            string.format(
                "crewTarget:IsCrew(): %s   GetPosition call: %s",
                attack.targetIsCrew,
                tostring(attack.targetPositionCall)
            )
        )

        draw_line(
            14,
            "crewTarget position: "
            .. point_text(attack.targetPosition)
        )

        draw_line(
            15,
            "TEST 1 - Direct CrewMember match: "
            .. attack.directMatch
        )

        draw_line(
            16,
            "TEST 2 - Position CrewMember match: "
            .. attack.positionMatch
        )
    else
        draw_line(
            10,
            "Waiting to observe crewAnim.status == 7 while fighting..."
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
