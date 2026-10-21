
--[[
DESCRIPTION: Tests medic healing through CREW_TARGET.
        - Targets the first injured friendly non-drone crew in the medic's room.
        - Does not directly modify health.
]]

local medicRaces = {
    terran_medic = true,
    terran_medic_1 = true,
    terran_medic_2 = true
}

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    if ship.iShipId ~= 0 then return end

    for i = 0, ship.vCrewList:size() - 1 do
        local medic = ship.vCrewList[i]

        if not medic.bDead and medicRaces[medic:GetSpecies()] then
            local target = nil

            for j = 0, ship.vCrewList:size() - 1 do
                local crew = ship.vCrewList[j]

                if crew ~= medic
                    and not crew.bDead
                    and not crew:IsDrone()
                    and crew.iShipId == medic.iShipId
                    and crew.currentShipId == medic.currentShipId
                    and crew.iRoomId == medic.iRoomId
                    and medic.iRoomId >= 0
                    and crew.health.first < crew.health.second then

                    target = crew
                    break
                end
            end

            medic.crewTarget = target
        end
    end
end)
