--[[
DESCRIPTION: Resolves Terran Drop Pod transport projectiles.
        - Recreates transported crew in the room struck by a successful projectile.
        - Kills transported crew if their projectile is destroyed before delivery.
DEPENDENCIES: sc_drone_pod_transport.lua, sc_crew_copy.lua
]]

local crew_copy = mods.sc.crew_copy
local pod = mods.sc.dronePod

script.on_internal_event(Defines.InternalEvents.DAMAGE_AREA_HIT, function(shipManager, projectile, location)
    local transportId, payload = pod.get_transport(projectile)
    if not payload then return Defines.Chain.CONTINUE end

    local roomId = Hyperspace.ShipGraph
        .GetShipInfo(shipManager.iShipId)
        :GetSelectedRoom(location.x, location.y, true)

    if roomId < 0 then
        return Defines.Chain.CONTINUE
    end

    if crew_copy.recreate(payload.snapshot, shipManager, roomId) then
        pod.complete_transport(transportId)
    end

    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.PROJECTILE_UPDATE_POST, function(projectile)
    local transportId, payload = pod.get_transport(projectile)

    if payload and projectile:Dead() then
        pod.kill_transport(transportId)
    end

    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.JUMP_LEAVE, function()
    pod.clear_transports()
end)