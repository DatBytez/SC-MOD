local userdata_table = mods.multiverse.userdata_table
local spawn_temp_drone = mods.multiverse.spawn_temp_drone

mods.sc_scv = mods.sc_scv or {}

script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power, shipManager)
    if not power or not power.def or power.def.name ~= "LAUNCH_REPAIR" then
        return
    end

    local crewmem = power.crew
    if not crewmem then return end
    if crewmem:GetSpecies() ~= "terran_scv" then return end

    local playerShip = Hyperspace.Global.GetInstance():GetShipManager(crewmem.iShipId)
    if not playerShip then return end

    if crewmem.iShipId ~= 0 then
        if not playerShip.ship or not playerShip.ship.hullIntegrity then return end
        if playerShip.ship.hullIntegrity.first > 5 then
            return
        end
    end

    local otherShip = Hyperspace.Global.GetInstance():GetShipManager(1 - crewmem.iShipId)
    if not otherShip then 
	otherShip = playerShip
    end

    local blueprint = Hyperspace.Blueprints:GetDroneBlueprint("TERRAN_SCV_HULL")
    if not blueprint then return end

    local target = 1.0
    local position = 1.0
    local shots = 9

    if playerShip and otherShip then
        local drone = spawn_temp_drone(
            blueprint,
            playerShip,
            otherShip,
            target,
            shots,
            position)
        userdata_table(drone, "mods.mv.droneStuff").clearOnJump = true
    end
end)