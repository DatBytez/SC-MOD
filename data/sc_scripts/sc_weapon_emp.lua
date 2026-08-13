-- EMP crew-drone stun effect.
--
-- Weapons opt into this script with:
--
--     <sc-emp droneStun="30"/>
--
-- When the weapon successfully hits an enemy ship, crew drones belonging to
-- that ship are stunned in the directly hit room and, when the weapon also
-- has <mv-aoe>, every orthogonally adjacent room affected by Multiverse AOE.

mods.sc = mods.sc or {}
mods.sc.empWeapons = mods.sc.empWeapons or {}

local empWeapons = mods.sc.empWeapons
local weaponTagParsers = mods.multiverse.weaponTagParsers
local vter = mods.multiverse.vter
local get_room_at_location = mods.multiverse.get_room_at_location
local get_adjacent_rooms = mods.multiverse.get_adjacent_rooms

-- Parse <sc-emp droneStun="..."/> and remember whether the same weapon uses
-- Multiverse's <mv-aoe> tag.
table.insert(weaponTagParsers, function(weaponNode)
    local nameAttr = weaponNode:first_attribute("name")
    if not nameAttr then
        return
    end

    local empNode = weaponNode:first_node("sc-emp")
    if not empNode then
        return
    end

    local stunAttr = empNode:first_attribute("droneStun")
    local droneStun = stunAttr and tonumber(stunAttr:value()) or nil

    if not droneStun or droneStun <= 0 then
        return
    end

    empWeapons[nameAttr:value()] = {
        droneStun = droneStun,
        hasAoe = weaponNode:first_node("mv-aoe") ~= nil
    }
end)

local function get_affected_rooms(shipManager, location, hasAoe)
    local primaryRoomId = get_room_at_location(shipManager, location, false)
    if primaryRoomId == -1 then
        return nil
    end

    local affectedRooms = {
        [primaryRoomId] = true
    }

    if hasAoe then
        for roomId, _ in pairs(
            get_adjacent_rooms(
                shipManager.iShipId,
                primaryRoomId,
                false
            )
        ) do
            affectedRooms[roomId] = true
        end
    end

    return affectedRooms
end

local function stun_enemy_crew_drones(shipManager, affectedRooms, stunDuration)
    for crew in vter(shipManager.vCrewList) do
        if crew.iShipId == shipManager.iShipId
            and crew:IsDrone()
            and affectedRooms[crew.iRoomId] then

            crew.fStunTime = math.max(
                crew.fStunTime,
                stunDuration
            )
        end
    end
end

script.on_internal_event(
    Defines.InternalEvents.DAMAGE_AREA_HIT,
    function(
        shipManager,
        projectile,
        location,
        damage,
        shipFriendlyFire
    )
        if not shipManager
            or not projectile
            or not projectile.extend
            or not projectile.extend.name then

            return
        end

        -- The EMP effect is only for the opposing ship, not self/friendly hits.
        if projectile.ownerId == shipManager.iShipId then
            return
        end

        local empData = empWeapons[projectile.extend.name]
        if not empData then
            return
        end

        local affectedRooms = get_affected_rooms(
            shipManager,
            location,
            empData.hasAoe
        )

        if not affectedRooms then
            return
        end

        stun_enemy_crew_drones(
            shipManager,
            affectedRooms,
            empData.droneStun
        )
    end
)
