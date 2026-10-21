--[[
DESCRIPTION: Directs Terran Medic passive healing to the lowest-health friendly crew in the room.
        - Preserves the XML trueHealAmount boost; removes each medic's contribution from other recipients.
        - Excludes the medic itself, drones, dead crew, and crew at full health from selection.
        - Supports all three Terran Medic variants, both ships, and multiple medics.
DEPENDENCIES: Hyperspace, Heal-Crew XML stat boost with shipTarget CURRENT_ROOM.
]]

mods.sc = mods.sc or {}
mods.sc.medicHeal = mods.sc.medicHeal or {}

local medicHeal = mods.sc.medicHeal
local medicRaces = {
    terran_medic = true,
    terran_medic_1 = true,
    terran_medic_2 = true
}

-- Retained for the optional sc_debug.lua display.
medicHeal.postCalls = 0
medicHeal.adjustedCalls = 0

-- The XML definition is static; validate it once and reuse its amount.
local xmlHealAmount
local function get_xml_heal_amount()
    if xmlHealAmount ~= nil then return xmlHealAmount or nil end

    local def = Hyperspace.StatBoostDefinition.savedStatBoostDefs["Heal-Crew"]
    if not def then return nil end

    if def.stat == Hyperspace.CrewStat.TRUE_HEAL_AMOUNT
        and def.shipTarget == Hyperspace.StatBoostDefinition.ShipTarget.CURRENT_ROOM
        and def.boostType == Hyperspace.StatBoostDefinition.BoostType.FLAT then
        xmlHealAmount = def.amount
    else
        xmlHealAmount = false
    end

    return xmlHealAmount or nil
end

local function same_crew(a, b)
    return a and b and a.extend.selfId == b.extend.selfId
end

local function same_room_ally(medic, crew)
    return medic.iRoomId >= 0
        and crew.iRoomId == medic.iRoomId
        and crew.iShipId == medic.iShipId
        and crew.currentShipId == medic.currentShipId
end

local function is_eligible(medic, crew)
    return crew
        and not same_crew(medic, crew)
        and not crew.bDead
        and not crew:IsDrone()
        and crew.health.first > 0
        and crew.health.first < crew.health.second
        and same_room_ally(medic, crew)
end

function medicHeal.choose_target(medic, ship)
    if not ship or not medic or medic.bDead or not medic:Functional() then return nil end

    local lowest
    for i = 0, ship.vCrewList:size() - 1 do
        local crew = ship.vCrewList[i]
        if is_eligible(medic, crew)
            and (not lowest or crew.health.first < lowest.health.first) then
            lowest = crew
        end
    end
    return lowest
end

-- Count the XML contributions that apply, and the ones we want to keep.
function medicHeal.count_boosts(crew, ship)
    if not ship or not crew or crew.bDead or crew:IsDrone()
        or crew.iRoomId < 0 then
        return 0, 0
    end

    local sources, selected = 0, 0
    for i = 0, ship.vCrewList:size() - 1 do
        local medic = ship.vCrewList[i]
        if medic and not medic.bDead
            and medicRaces[medic:GetSpecies()]
            and medic:Functional()
            and not same_crew(medic, crew)
            and same_room_ally(medic, crew) then
            sources = sources + 1
            if same_crew(medicHeal.choose_target(medic, ship), crew) then
                selected = selected + 1
            end
        end
    end
    return sources, selected
end

script.on_internal_event(Defines.InternalEvents.CALCULATE_STAT_POST, function(crew, stat, _def, amount, value)
    if stat ~= Hyperspace.CrewStat.TRUE_HEAL_AMOUNT then
        return Defines.Chain.CONTINUE, amount, value
    end

    medicHeal.postCalls = medicHeal.postCalls + 1

    local healAmount = get_xml_heal_amount()
    if not healAmount then return Defines.Chain.CONTINUE, amount, value end

    local shipId = crew.currentShipId
    local ship = (shipId == 0 or shipId == 1)
        and Hyperspace.Global.GetInstance():GetShipManager(shipId) or nil
    local sources, selected = medicHeal.count_boosts(crew, ship)

    if sources > selected then
        medicHeal.adjustedCalls = medicHeal.adjustedCalls + 1
        amount = amount - (sources - selected) * healAmount
    end

    return Defines.Chain.CONTINUE, amount, value
end)
