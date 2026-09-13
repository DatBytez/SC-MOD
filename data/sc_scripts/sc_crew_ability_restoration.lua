--[[
DESCRIPTION: Implements the Terran Restoration ability.
        - Removes stun, mind control, silence and erosion from the user's room.
]]

local cleansedSilence = {}

script.on_internal_event(Defines.InternalEvents.CALCULATE_STAT_POST, function(crew, stat, _def, amount, value)
    if stat == Hyperspace.CrewStat.SILENCED and cleansedSilence[crew.extend.selfId] then
        if value then
            return Defines.Chain.CONTINUE, amount, false
        end

        cleansedSilence[crew.extend.selfId] = nil
    end

    return Defines.Chain.CONTINUE, amount, value
end)

script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power, ship)
    if power.def.name ~= "RESTORATION" then
        return Defines.Chain.CONTINUE
    end

    for i = 0, ship.vCrewList:size() - 1 do
        local crew = ship.vCrewList[i]

        if not crew.bDead
            and crew.iRoomId == power.powerRoom
            and crew.iShipId == power.crew.iShipId then

            crew.fStunTime = 0

            if crew.bMindControlled then
                crew:SetMindControl(false)
            end

            local _, silenced = crew.extend:CalculateStat(Hyperspace.CrewStat.SILENCED)

            if silenced then
                cleansedSilence[crew.extend.selfId] = true
            end
        end
    end

    local room = ship.vRoomList[power.powerRoom]

    if room then
        room.extend:StopErosion()
    end

    -- TODO: When expanding room/tile cleansing, include hacking.

    return Defines.Chain.CONTINUE
end)