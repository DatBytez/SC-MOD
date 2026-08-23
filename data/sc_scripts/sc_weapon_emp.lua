--[[
DESCRIPTION: Weapon hits stun crew drones.
        - Weapons with <mv-aoe> also stun drones in adjacent rooms.
TAG: <sc-emp value="#"/>
DEPENDENCIES: sc_tag.lua, Multiverse vter, get_room_at_location, get_adjacent_rooms
]]

local vter = mods.multiverse.vter
local get_room_at_location = mods.multiverse.get_room_at_location
local get_adjacent_rooms = mods.multiverse.get_adjacent_rooms

local empWeapons = {}
local aoeWeapons = {}

mods.sc.tag.register("weapon", "sc-emp", empWeapons, "value")
mods.sc.tag.register("weapon", "mv-aoe", aoeWeapons)

local function get_affected_rooms(shipManager, location, hasAoe)
    local primaryRoomId = get_room_at_location(shipManager, location, false)
    if primaryRoomId == -1 then return nil end

    local affectedRooms = {[primaryRoomId] = true}

    if hasAoe then
        for roomId in pairs(get_adjacent_rooms(shipManager.iShipId, primaryRoomId, false)) do
            affectedRooms[roomId] = true
        end
    end

    return affectedRooms
end

local function stun_enemy_crew_drones(shipManager, affectedRooms, stunDuration)
    for crew in vter(shipManager.vCrewList) do
        if crew.iShipId == shipManager.iShipId and crew:IsDrone() and affectedRooms[crew.iRoomId] then
            crew.fStunTime = math.max(crew.fStunTime, stunDuration)
        end
    end
end

script.on_internal_event(Defines.InternalEvents.DAMAGE_AREA_HIT, function(shipManager, projectile, location, _damage, _shipFriendlyFire)
    if not projectile then return end
    if projectile.ownerId == shipManager.iShipId then return end

    local weaponName = projectile.extend.name
    local stunDuration = empWeapons[weaponName]
    if not stunDuration then return end

    local affectedRooms = get_affected_rooms(shipManager, location, aoeWeapons[weaponName])
    if not affectedRooms then return end

    stun_enemy_crew_drones(shipManager, affectedRooms, stunDuration)
end)