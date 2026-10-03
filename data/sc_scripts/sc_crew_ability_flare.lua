mods.sc.crewFlareDurations = mods.sc.crewFlareDurations or {}

local flareDurations = mods.sc.crewFlareDurations

mods.sc.tag.register("power", "sc-flare", flareDurations, "value")

local excludedDrones = {}
local droneList = Hyperspace.Blueprints:GetBlueprintList("SC_LIST_CREW_DRONES")

for i = 0, droneList:size() - 1 do
    excludedDrones[droneList[i]] = true
end

script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power, ship)
    local stunDuration = tonumber(flareDurations[power.def.name])

    if not stunDuration or stunDuration <= 0 then
        return Defines.Chain.CONTINUE
    end

    for i = 0, ship.vCrewList:size() - 1 do
        local crew = ship.vCrewList[i]

        if crew ~= power.crew
            and not crew.bDead
            and crew.iRoomId == power.powerRoom
            and not excludedDrones[crew:GetSpecies()]
            and ((crew.iShipId ~= power.crew.iShipId and not crew.bMindControlled)
                or (crew.iShipId == power.crew.iShipId and crew.bMindControlled)) then
            crew.fStunTime = math.max(crew.fStunTime, stunDuration)
        end
    end

    return Defines.Chain.CONTINUE
end)