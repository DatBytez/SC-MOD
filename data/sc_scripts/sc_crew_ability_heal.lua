--[[
DESCRIPTION: Directs Terran Medic passive healing to the lowest-health friendly crew in the room.
        - Preserves the XML trueHealAmount boost; removes each medic's contribution from other recipients.
        - Excludes the medic itself, drones, dead crew, and crew at full health from selection.
        - Supports tagged healer races, both ships, and multiple healers.
TAG: <sc-heal/>
DEPENDENCIES: sc_tag.lua, Hyperspace, Heal-Crew XML stat boost with shipTarget CURRENT_ROOM.
]]

mods.sc = mods.sc or {}

local medicRaces = {}
mods.sc.tag.register("crew", "sc-heal", medicRaces)

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

local function select_lowest_health(medic, crewList, previousTarget)
    local lowest
    local lowestGroup

    for _, crew in ipairs(crewList) do
        if is_eligible(medic, crew) then
            local group = math.floor(crew.health.first)
            if not lowest or group < lowestGroup
                or (group == lowestGroup and same_crew(crew, previousTarget)) then
                lowest = crew
                lowestGroup = group
            end
        end
    end
    return lowest
end

-- Freeze choices and source counts between game updates. Recalculating them in
-- CALCULATE_STAT_POST could select a different target as earlier crew get healed.
local snapshots = {}

local function update_snapshot(ship)
    local crewList = {}
    local previousSnapshot = snapshots[ship.iShipId]
    local snapshot = {targets = {}, recipients = {}}

    for i = 0, ship.vCrewList:size() - 1 do
        local crew = ship.vCrewList[i]
        crewList[#crewList + 1] = crew

        if not crew.bDead and not crew:IsDrone() and crew.iRoomId >= 0 then
            snapshot.recipients[crew.extend.selfId] = {
                sources = 0,
                selected = 0,
                room = crew.iRoomId,
                owner = crew.iShipId,
                ship = crew.currentShipId
            }
        end
    end

    for _, medic in ipairs(crewList) do
        if not medic.bDead and medicRaces[medic:GetSpecies()] and medic:Functional() then
            local previousTarget = previousSnapshot and previousSnapshot.targets[medic.extend.selfId]
            local target = select_lowest_health(medic, crewList, previousTarget)
            snapshot.targets[medic.extend.selfId] = target

            for _, crew in ipairs(crewList) do
                local recipient = snapshot.recipients[crew.extend.selfId]
                if recipient and not same_crew(medic, crew)
                    and same_room_ally(medic, crew) then
                    recipient.sources = recipient.sources + 1
                    if same_crew(target, crew) then
                        recipient.selected = recipient.selected + 1
                    end
                end
            end
        end
    end

    snapshots[ship.iShipId] = snapshot
end

-- ON_TICK runs after the game update; the snapshot is used consistently by
-- every crew stat calculation during the following update.
script.on_internal_event(Defines.InternalEvents.ON_TICK, function()
    if not Hyperspace.App or not Hyperspace.App.world
        or not Hyperspace.App.world.bStartedGame then
        snapshots[0], snapshots[1] = nil, nil
        return
    end

    local global = Hyperspace.Global.GetInstance()
    for shipId = 0, 1 do
        local ship = global:GetShipManager(shipId)
        if ship then
            update_snapshot(ship)
        else
            snapshots[shipId] = nil
        end
    end
end)

local function count_boosts(crew, ship)
    if not ship or not crew or crew.bDead or crew:IsDrone()
        or crew.iRoomId < 0 then
        return 0, 0
    end

    local snapshot = snapshots[ship.iShipId]
    local recipient = snapshot and snapshot.recipients[crew.extend.selfId]
    if not recipient or recipient.room ~= crew.iRoomId
        or recipient.owner ~= crew.iShipId
        or recipient.ship ~= crew.currentShipId then
        return 0, 0
    end

    return recipient.sources, recipient.selected
end

script.on_internal_event(Defines.InternalEvents.CALCULATE_STAT_POST, function(crew, stat, _def, amount, value)
    if stat ~= Hyperspace.CrewStat.TRUE_HEAL_AMOUNT then
        return Defines.Chain.CONTINUE, amount, value
    end

    local healAmount = get_xml_heal_amount()
    if not healAmount then return Defines.Chain.CONTINUE, amount, value end

    local shipId = crew.currentShipId
    local ship = (shipId == 0 or shipId == 1)
        and Hyperspace.Global.GetInstance():GetShipManager(shipId) or nil
    local sources, selected = count_boosts(crew, ship)

    if sources > selected then
        amount = amount - (sources - selected) * healAmount
    end

    return Defines.Chain.CONTINUE, amount, value
end)
