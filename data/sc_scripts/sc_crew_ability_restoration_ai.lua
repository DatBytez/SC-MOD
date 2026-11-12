
--[[
DESCRIPTION: Allows enemy Terran Medics to activate Restoration when it can cleanse
        a friendly crew member in the same room.
        - Checks for stun, mind control, or silence.
        - Does not change the existing Restoration effects or cooldown.
DEPENDENCIES: sc_crew_ability_restoration.lua
]]

local POWER_READY = 1
local POWER_NOT_READY_COOLDOWN = 0

local function needs_restoration(crew)
    if crew.fStunTime > 0 or crew.bMindControlled then return true end

    local _, silenced = crew.extend:CalculateStat(Hyperspace.CrewStat.SILENCED)
    return silenced
end

script.on_internal_event(Defines.InternalEvents.POWER_READY, function(power, ready)
    if not power.def or power.def.name ~= "SC_RESTORATION"
        or not power.crew or power.crew.iShipId ~= 1
        or power.crew.bMindControlled or ready ~= POWER_READY then
        return Defines.Chain.CONTINUE, ready
    end

    local medic = power.crew
    local ship = Hyperspace.Global.GetInstance():GetShipManager(medic.currentShipId)

    if not ship or medic.iRoomId < 0 then
        return Defines.Chain.CONTINUE, POWER_NOT_READY_COOLDOWN
    end

    for i = 0, ship.vCrewList:size() - 1 do
        local crew = ship.vCrewList[i]

        if not crew.bDead
            and crew.iRoomId == medic.iRoomId
            and crew.iShipId == medic.iShipId
            and crew.currentShipId == medic.currentShipId
            and needs_restoration(crew) then
            return Defines.Chain.CONTINUE, ready
        end
    end

    return Defines.Chain.CONTINUE, POWER_NOT_READY_COOLDOWN
end)
