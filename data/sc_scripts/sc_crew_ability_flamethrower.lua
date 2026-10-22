
--[[
DESCRIPTION: Directs Terran Firebat flames to the lowest-health enemy in the room.
        - Preserves the native fire effect and cooldown.
        - Supports friendly and enemy ships.
        - Falls back to the Firebat's position when no enemy is present.
DEPENDENCIES: Hyperspace, SC_FLAMETHROWER XML ability.
]]

script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power, ship)
    if power.def.name ~= "SC_FLAMETHROWER" or not ship then
        return Defines.Chain.CONTINUE
    end

    local firebat = power.crew
    if not firebat then return Defines.Chain.CONTINUE end

    local target
    local lowestHealth

    for i = 0, ship.vCrewList:size() - 1 do
        local crew = ship.vCrewList[i]

        local enemy = (crew.iShipId ~= firebat.iShipId and not crew.bMindControlled)
            or (crew.iShipId == firebat.iShipId and crew.bMindControlled)

        if enemy
            and not crew.bDead
            and crew.health.first > 0
            and crew.iRoomId == power.powerRoom
            and crew.currentShipId == power.powerShip then

            if not lowestHealth or crew.health.first < lowestHealth then
                target = crew
                lowestHealth = crew.health.first
            end
        end
    end

    if target then
        power.effectWorldPos = Hyperspace.Pointf(target.x, target.y)
    end

    return Defines.Chain.CONTINUE
end)
