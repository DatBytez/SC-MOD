mods.sc = mods.sc or {}
mods.sc.dodgeAugments = mods.sc.dodgeAugments or {}
local helpers = mods.sc.helpers

local dodgeAugments = mods.sc.dodgeAugments

mods.sc.tag.register_augment_amount_tag("sc-dodge", dodgeAugments)

local function get_sc_dodge_amount(ship)
    if not ship then return 0 end
    local total = 0

    for augName, dodgeEntries in pairs(dodgeAugments) do
        local count = ship:HasAugmentation(augName) or 0
        local entry = dodgeEntries[1]

        if entry then
            total = total + (entry.amount or 0) * count
        end
    end

    return total
end

local PILOT_SYSTEM_ID = 6

local function piloting_allows_positive_dodge(shipManager)
    local piloting = shipManager and shipManager:GetSystem(PILOT_SYSTEM_ID)
    if not piloting or piloting:CompletelyDestroyed() or not piloting.bManned then
        return false
    end

    return (piloting:GetEffectivePower() or 0) > 0
end

script.on_internal_event(Defines.InternalEvents.GET_DODGE_FACTOR, function(shipManager, dodge)
    if not shipManager then return end

    local perPowerAmount = get_sc_dodge_amount(shipManager)
    if perPowerAmount == 0 then return end

    local engines = helpers.get_system_by_name(shipManager, "engines")
    if not engines then return end

    local bonus = perPowerAmount * (engines:GetEffectivePower() or 0)

    if bonus > 0 and not piloting_allows_positive_dodge(shipManager) then
        bonus = 0
    end

    if bonus == 0 then return end

    return 0, dodge + bonus
end)