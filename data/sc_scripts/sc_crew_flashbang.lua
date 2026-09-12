local FLASHBANG_NAME = "FLASHBANG"
local FLASHBANG_STUN = 10

script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power, ship)
    if power.def.name ~= FLASHBANG_NAME then
        return Defines.Chain.CONTINUE
    end

    for i = 0, ship.vCrewList:size() - 1 do
        local crew = ship.vCrewList[i]

        if crew ~= power.crew
            and not crew.bDead -- Probably not necessary.
            and crew.iRoomId == power.powerRoom
            and crew.iShipId == power.crew.iShipId
            and crew.bMindControlled then

            crew.fStunTime = math.max(crew.fStunTime, FLASHBANG_STUN)
        end
    end

    return Defines.Chain.CONTINUE
end)