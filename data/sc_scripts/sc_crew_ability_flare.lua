--[[
DESCRIPTION: Stuns hostile non-drone crew in the activating crew member's room.
        - Mind-controlled crew are treated according to their current allegiance.
        - Crew listed in SC_LIST_CREW_DRONES are excluded.
TAG: <sc-flare value="#"/>
DEPENDENCIES: sc_tag.lua, sc_helpers.lua
]]

local helpers = mods.sc.helpers
local flareDurations = {}

mods.sc.tag.register("power", "sc-flare", flareDurations, "value")

local excludedDrones = helpers.blueprint_list_to_set("SC_LIST_CREW_DRONES")

script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power, ship)
    local stunDuration = flareDurations[power.def.name]

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