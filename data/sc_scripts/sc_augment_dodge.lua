local userdata_table = mods.multiverse.userdata_table
local create_damage_message = mods.multiverse.create_damage_message
local damageMessages = mods.multiverse.damageMessages
local vter = mods.multiverse.vter

mods.sc = mods.sc or {}
mods.sc.dodgeAugments = mods.sc.dodgeAugments or {}

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

local function find_system_by_name(shipManager, systemName)
    local systemId = Hyperspace.ShipSystem.NameToSystemId(systemName)
    if not shipManager or not shipManager.vSystemList then return nil end
    for system in vter(shipManager.vSystemList) do
        if system and system.GetId and system:GetId() == systemId then
            return system
        end
    end
    return nil
end

local function find_system_by_id(shipMgr, sysId)
    if not shipMgr or not shipMgr.vSystemList then return nil end
    for sys in vter(shipMgr.vSystemList) do
        if sys and sys.GetId and sys:GetId() == sysId then
            return sys
        end
    end
    return nil
end

local function get_bars_and_level(shipManager, systemName)
    local system = find_system_by_name(shipManager, systemName)
    if not system then return 0, 0 end

    local batteryPow = system.iBatteryPower or 0
    local systemPow = system:GetEffectivePower()
    local systemLvl = system:GetMaxPower()
    return batteryPow, systemPow, systemLvl
end

-- Dodge bonus
script.on_internal_event(Defines.InternalEvents.GET_DODGE_FACTOR, function(shipManager, dodge)
    if not shipManager then return end

    local perPowerAmount = get_sc_dodge_amount(shipManager)
    if perPowerAmount == 0 then return end

    local batteryPow, systemPow, systemLvl = get_bars_and_level(shipManager, "engines")
    local bonus = perPowerAmount * systemPow
    dodge = dodge + bonus

    return 0, dodge
end)