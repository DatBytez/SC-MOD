--[[
This code is a reimplementation of TNE_ACTIVE_DRONE_LUA.lua from TNE
]]

mods.multiverse.droneTagParsers = mods.multiverse.droneTagParsers or {}
local droneTagParsers = mods.multiverse.droneTagParsers

mods.sc = mods.sc or {}
mods.sc.activeShield = mods.sc.activeShield or {}

local activeDrones = mods.sc.activeShield

table.insert(droneTagParsers, function(droneNode)
	local nameAttr = droneNode:first_attribute("name")
	if not nameAttr then return end

	local droneName = nameAttr:value()

	local tagNode = droneNode:first_node("sc-active-shield")
	if not tagNode then return end

	activeDrones[droneName] = true
end)

------------------------------------------------------------------------------------

script.on_internal_event(Defines.InternalEvents.DRONE_FIRE, function(projectile, spacedrone)

	local droneName = spacedrone.blueprint.name
	if (activeDrones[droneName] == nil) then
		return
	end

	local shipManager = nil

	if projectile.ownerId == 0 then
		shipManager = Hyperspace.ships.player
	else
		shipManager = Hyperspace.ships.enemy
	end
	projectile:Kill()

	local shieldSystem = shipManager.shieldSystem
	local droneLocation = spacedrone.currentLocation
	shieldSystem:AddSuperShield(Hyperspace.Point(droneLocation.x, droneLocation.y))

	return Defines.Chain.CONTINUE
end)