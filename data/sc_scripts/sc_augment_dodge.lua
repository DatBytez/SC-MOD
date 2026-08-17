local vter = mods.multiverse.vter

mods.sc = mods.sc or {}
mods.sc.dodgeAugments = mods.sc.dodgeAugments or {}
local helpers = mods.sc.helpers

local dodgeAugments = mods.sc.dodgeAugments

mods.sc.tag.register_augment_amount_tag("sc-dodge", dodgeAugments)

local function get_sc_dodge_amount(ship)
    local total = 0
    if not ship then return total end

    for augName, dodgeEntries in pairs(dodgeAugments) do
        local count = ship:HasAugmentation(augName) or 0
        if count > 0 then
            for _, entry in ipairs(dodgeEntries) do
                total = total + ((entry.amount or 0) * count)
            end
        end
    end

    return total
end

-- -------
-- Helpers
-- -------

local function get_bars_and_level(shipManager, systemName)
    local system = helpers.get_system_by_name(shipManager, systemName)
    if not system then return 0, 0, 0 end

    local batteryPow = system.iBatteryPower or 0
    local systemPow = system:GetEffectivePower()
    local systemLvl = system:GetMaxPower()
    return batteryPow, systemPow, systemLvl
end

local PILOT_SYSTEM_ID = 6

local function piloting_allows_positive_dodge(shipManager)
    if not shipManager then return false end

    local piloting = shipManager:GetSystem(PILOT_SYSTEM_ID)
    if not piloting then return false end

    if not piloting.bManned then return false end
    if piloting:CompletelyDestroyed() then return false end

    local pilotingPower = piloting:GetEffectivePower() or 0
    if pilotingPower <= 0 then return false end

    return true
end

-- Dodge bonus / penalty
script.on_internal_event(Defines.InternalEvents.GET_DODGE_FACTOR, function(shipManager, dodge)
    if not shipManager then return end

    local perPowerAmount = get_sc_dodge_amount(shipManager)
    if perPowerAmount == 0 then return end

    local batteryPow, systemPow, systemLvl = get_bars_and_level(shipManager, "engines")
    local bonus = perPowerAmount * systemPow

    -- Positive bonuses require manned, functioning piloting.
    -- Penalties still apply normally.
    if bonus > 0 and not piloting_allows_positive_dodge(shipManager) then
        bonus = 0
    end

    if bonus == 0 then return end

    dodge = dodge + bonus
    return 0, dodge
end)