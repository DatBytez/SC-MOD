--[[
DESCRIPTION: Tagged augments modify ship dodge based on effective Engines power.
TAG: <sc-dodge value="#"/>
DEPENDENCIES: sc_tag.lua
]]

mods.sc = mods.sc or {}
mods.sc.dodgeAugments = mods.sc.dodgeAugments or {}

local dodgeAugments = mods.sc.dodgeAugments

mods.sc.tag.register("augment", "sc-dodge", dodgeAugments, "value")

local ENGINES_SYSTEM_ID = Hyperspace.ShipSystem.NameToSystemId("engines")
local PILOT_SYSTEM_ID = Hyperspace.ShipSystem.NameToSystemId("pilot")

local ENGINE_DODGE_BY_LEVEL = {5, 10, 15, 20, 25, 28, 31, 35}

local function get_sc_dodge_amount(ship)
    local total = 0

    for augName, value in pairs(dodgeAugments) do
        total = total + value * ship:HasAugmentation(augName)
    end

    return total
end

local function piloting_allows_positive_dodge(ship)
    local piloting = ship:GetSystem(PILOT_SYSTEM_ID)

    return piloting
        and not piloting:CompletelyDestroyed()
        and piloting.bManned
        and piloting:GetEffectivePower() > 0
end

script.on_internal_event(
    Defines.InternalEvents.GET_DODGE_FACTOR,
    function(ship, dodge)
        local perPowerAmount = get_sc_dodge_amount(ship)
        if perPowerAmount == 0 then return end

        local engines = ship:GetSystem(ENGINES_SYSTEM_ID)
        if not engines then return end

        local bonus = perPowerAmount * engines:GetEffectivePower()

        if bonus > 0 and not piloting_allows_positive_dodge(ship) then
            bonus = 0
        end

        return Defines.Chain.CONTINUE, math.max(0, dodge + bonus)
    end
)

-- Engines Level Descriptions

script.on_internal_event(
    Defines.InternalEvents.GET_LEVEL_DESCRIPTION,
    function(systemId, level, tooltip)
        if systemId ~= ENGINES_SYSTEM_ID or level < 1 then return end

        local ship = Hyperspace.ships(0)
        if not ship then return end

        local perPowerAmount = get_sc_dodge_amount(ship)
        if perPowerAmount == 0 then return end

        local baseDodge = ENGINE_DODGE_BY_LEVEL[level] or (5 * level - 5)
        local dodge = math.max(0, baseDodge + perPowerAmount * level)
        local ftl = 0.75 + level / 4

        return string.format("Dodge: %g / FTL: %gx", dodge, ftl)
    end
)