script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power, ship)
    if power.def.name ~= "SC_OPTICAL_FLARE" then
        return Defines.Chain.CONTINUE
    end

    for i = 0, ship.vCrewList:size() - 1 do
        local crew = ship.vCrewList[i]

        if crew ~= power.crew
            and not crew.bDead
            and crew.iRoomId == power.powerRoom
            and crew.iShipId == power.crew.iShipId
            and crew.bMindControlled then

            crew.fStunTime = math.max(crew.fStunTime, power:GetPowerDamage().iStun)
        end
    end

    return Defines.Chain.CONTINUE
end)