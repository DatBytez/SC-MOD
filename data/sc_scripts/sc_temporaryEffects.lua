--[[
DESCRIPTION: Extends shootTimer and punchTimer to work inside crew powers <temporaryEffect>
TAGS: <shootTimer min="#" max="#"/>, <punchTimer min="#" max="#"/>
DEPENDENCIES: sc_tag.lua, Multiverse userdata_table, tag-data-read.lua.
]]

local userdata_table = mods.multiverse.userdata_table
local powerTimers = {}

local function parse_timer(node)
    if not node then return nil end

    local value = tonumber(node:value())
    local minAttribute = node:first_attribute("min")
    local maxAttribute = node:first_attribute("max")
    local min = minAttribute and tonumber(minAttribute:value()) or value
    local max = maxAttribute and tonumber(maxAttribute:value()) or value

    min = min or max
    max = max or min

    if not min or not max or min <= 0 or max < min then return nil end

    return {min = min, max = max}
end

table.insert(mods.multiverse.crewTagParsers, function(raceNode)
    local powerNode = raceNode:first_node("powerEffect")
    while powerNode do
        local effectNode = powerNode:first_node("temporaryEffect")
        if effectNode then
            local shoot = parse_timer(effectNode:first_node("shootTimer"))
            local punch = parse_timer(effectNode:first_node("punchTimer"))

            local name = powerNode:first_attribute("name")
            if name and (shoot or punch) then
                powerTimers[name:value()] = {shoot = shoot, punch = punch}
            end
        end

        powerNode = powerNode:next_sibling("powerEffect")
    end
end)

local function get_active_timers(crew)
    local shoot, punch
    local powers = crew.extend.crewPowers

    for i = 0, powers:size() - 1 do
        local power = powers[i]
        local config = power.def and powerTimers[power.def.name]

        if config and power.temporaryPowerActive then
            if config.shoot and (not shoot or
                config.shoot.min + config.shoot.max < shoot.min + shoot.max) then
                shoot = config.shoot
            end

            if config.punch and (not punch or
                config.punch.min + config.punch.max < punch.min + punch.max) then
                punch = config.punch
            end
        end
    end

    return shoot, punch
end

local function rescale_punch_animation(animation, ratio)
    local success, punchAnimation = pcall(function()
        return animation.anims[animation.direction][1]
    end)

    if success and punchAnimation then
        local tracker = punchAnimation.tracker
        tracker.time = tracker.time * ratio
        tracker.current_time = tracker.current_time * ratio
    end
end

local function update_timer(animation, timerType, desired, state)
    local timer = timerType == "shoot" and animation.shootTimer or animation.punchTimer
    local original = state[timerType]

    if desired and not original then
        original = {min = timer.minTime, max = timer.maxTime}
        state[timerType] = original
    end

    local target = desired or original
    if not target then return end

    timer.minTime = target.min
    timer.maxTime = target.max

    local oldGoal = timer.currGoal
    if oldGoal > 0 then
        local newGoal = math.max(target.min / 1000, math.min(oldGoal, target.max / 1000))

        if newGoal ~= oldGoal then
            local ratio = newGoal / oldGoal
            timer.currTime = timer.currTime * ratio
            timer.currGoal = newGoal

            if timerType == "punch" then
                rescale_punch_animation(animation, ratio)
            end
        end
    end

    if not desired then
        state[timerType] = nil
    end
end

script.on_internal_event(Defines.InternalEvents.CREW_LOOP, function(crew)
    if not crew.extend or not crew.crewAnim then return end

    local shoot, punch = get_active_timers(crew)
    local state = userdata_table(crew, "mods.sc.temporaryEffect")

    if not shoot and not punch and not state.shoot and not state.punch then return end

    update_timer(crew.crewAnim, "shoot", shoot, state)
    update_timer(crew.crewAnim, "punch", punch, state)
end)
