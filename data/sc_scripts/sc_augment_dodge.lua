--[[
DESCRIPTION: Tagged augments modify ship dodge based on effective Engines power.
        - Applies the configured dodge amount per effective Engines power.
TAG: <sc-dodge value="#"/>
]]

mods.sc = mods.sc or {}
mods.sc.dodgeAugments = mods.sc.dodgeAugments or {}
local helpers = mods.sc.helpers

local dodgeAugments = mods.sc.dodgeAugments

mods.sc.tag.register("augment", "sc-dodge", dodgeAugments, "value")

local function get_sc_dodge_amount(ship)
    local total = 0

    for augName, value in pairs(dodgeAugments) do
        total = total + value * ship:HasAugmentation(augName)
    end

    return total
end

local PILOT_SYSTEM_ID = 6

local function piloting_allows_positive_dodge(shipManager)
    local piloting = shipManager:GetSystem(PILOT_SYSTEM_ID)

    if not piloting
        or piloting:CompletelyDestroyed()
        or not piloting.bManned then

        return false
    end

    return piloting:GetEffectivePower() > 0
end

script.on_internal_event(
    Defines.InternalEvents.GET_DODGE_FACTOR,
    function(shipManager, dodge)
        local perPowerAmount = get_sc_dodge_amount(shipManager)
        if perPowerAmount == 0 then return end

        local engines = helpers.get_system_by_name(shipManager, "engines")
        if not engines then return end

        local bonus = perPowerAmount * engines:GetEffectivePower()

        if bonus > 0 and not piloting_allows_positive_dodge(shipManager) then

            bonus = 0
        end

        return 0, dodge + bonus
    end
)