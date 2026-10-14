--[[
DESCRIPTION: Tests restoring Sensors power while a nebula is present.
        - Clears the player's Sensors power loss each ship loop in a nebula.
        - No augment or Sensors upgrade level is required.
        - May also clear other effects using the same power-loss value.
DEPENDENCIES: Hyperspace
]]

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    if ship.iShipId ~= 0 or not Hyperspace.App.world.space.bNebula then return end

    local sensors = ship:GetSystem(7)
    if not sensors then return end

    sensors:SetPowerCap(sensors.powerState.second+1)
end)
