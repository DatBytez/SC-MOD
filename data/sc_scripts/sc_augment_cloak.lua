--[[
DESCRIPTION: Tagged augments modify Cloaking duration based on effective Cloaking power.
        - Applies the configured number of seconds per effective Cloaking power.
        - Positive values extend Cloaking; negative values shorten it.
        - Scales elapsed Cloaking time without changing the timer's normal goal.
        - Changes duration, not the Cloaking cooldown.
TAG: <sc-cloak value="#"/>
DEPENDENCIES: sc_tag.lua, Multiverse userdata_table
]]

mods.sc = mods.sc or {}
mods.sc.cloakAugments = mods.sc.cloakAugments or {}

local cloakAugments = mods.sc.cloakAugments
local userdata_table = mods.multiverse.userdata_table

mods.sc.tag.register("augment", "sc-cloak", cloakAugments, "value")

local CLOAK_SYSTEM_ID = Hyperspace.ShipSystem.NameToSystemId("cloaking")
local MIN_CLOAK_DURATION = 0.1
local MAX_NORMAL_STEP = 0.25 -- Preserve large timer jumps such as weapon-fire penalties.

local function get_sc_cloak_amount(ship)
    local total = 0

    for augName, value in pairs(cloakAugments) do
        total = total + value * ship:HasAugmentation(augName)
    end

    return total
end

script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    function(shipManager)
        local cloaking = shipManager.cloakSystem
        if not cloaking then return end

        local data = userdata_table(shipManager, "mods.sc.cloakDuration")

        if not cloaking.bTurnedOn then
            data.applied = false
            data.lastTime = nil
            return
        end

        local timer = cloaking.timer
        if not timer or not timer.running or timer.currGoal <= 0 then return end

        local perPowerAmount = get_sc_cloak_amount(shipManager)
        local bonus = perPowerAmount * cloaking:GetEffectivePower()
        local duration = math.max(MIN_CLOAK_DURATION, timer.currGoal + bonus)
        local rate = timer.currGoal / duration

        if not data.applied then
            data.applied = true
            -- Include the first native tick if the cloak has just begun.
            -- An already-running cloak loaded from a save starts from its current time.
            data.lastTime = timer.currTime <= MAX_NORMAL_STEP and 0 or timer.currTime
            data.adjustments = 0
            data.lastBefore = nil
            data.lastAfter = nil
            data.lastDelta = nil
            data.lastScaledDelta = nil
            data.skippedJumps = 0
            data.lastJumpDelta = nil
        end

        data.duration = duration
        data.rate = rate
        data.bonus = bonus

        -- The native cloak system may restart its timer when currGoal is edited.
        -- Leave currGoal unchanged and scale ONLY time added since the last loop.
        local delta = timer.currTime - data.lastTime
        if delta > MAX_NORMAL_STEP then
            -- Preserve sudden penalties/other external changes to elapsed time.
            data.skippedJumps = data.skippedJumps + 1
            data.lastJumpDelta = delta
        elseif delta > 0 and bonus ~= 0 then
            local adjusted = math.min(timer.currGoal, data.lastTime + delta * rate)

            data.lastBefore = timer.currTime
            data.lastAfter = adjusted
            data.lastDelta = delta
            data.lastScaledDelta = adjusted - data.lastTime
            data.adjustments = data.adjustments + 1

            timer.currTime = adjusted
        end

        data.lastTime = timer.currTime
    end
)

-- Cloaking Level Descriptions

script.on_internal_event(
    Defines.InternalEvents.GET_LEVEL_DESCRIPTION,
    function(systemId, level, tooltip)
        if systemId ~= CLOAK_SYSTEM_ID or level < 1 then return end

        local ship = Hyperspace.ships(0)
        if not ship then return end

        local perPowerAmount = get_sc_cloak_amount(ship)
        if perPowerAmount == 0 then return end

        -- Describe the selected level when Cloaking is fully powered.
        local baseDuration = level * 5
        local duration = math.max(MIN_CLOAK_DURATION, baseDuration + perPowerAmount * level)

        return string.format("Cloaking Duration: %g seconds", duration)
    end
)
