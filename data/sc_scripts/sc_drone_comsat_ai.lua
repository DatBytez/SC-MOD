
local function update_enemy_comsat_ai(ship)
    if not ship or ship.iShipId ~= 1 or not ship.droneSystem then return end

    local playerShip = Hyperspace.ships(0)
    local playerCloaked = playerShip
        and playerShip.cloakSystem
        and playerShip.cloakSystem.bTurnedOn

    for drone in vter(ship.droneSystem.drones) do
        if comsat.is_comsat(drone)
            and not drone.bDead
            and not drone.deployed
            and not drone.powered then

            local desiredTimer = playerCloaked and 0 or 0.1

            if math.abs(drone.destroyedTimer - desiredTimer) > 0.0001 then
                drone.destroyedTimer = desiredTimer
            end
        end
    end
end
