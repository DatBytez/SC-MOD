--[[
DESCRIPTION: Fills every tile in a room with fire when hit by a tagged weapon.
        - Beam weapons trigger once when entering a new room.
        - Area-hit projectiles trigger on impact.
        - Adds fire-fill information to the weapon stat box.
TAG: <sc-fireFill/>
DEPENDENCIES: sc_tag.lua
]]

local fireFillWeapons = {}

mods.sc.tag.register("weapon", "sc-fireFill", fireFillWeapons)

local function fill_room_fire(shipManager, projectile, location)
    if not projectile then return end
    if not fireFillWeapons[projectile.extend.name] then return end

    local shipGraph = Hyperspace.ShipGraph.GetShipInfo(shipManager.iShipId)
    local room = shipGraph:GetSelectedRoom(location.x, location.y, false)

    if room < 0 then return end

    local roomShape = shipGraph:GetRoomShape(room)
    local startX = roomShape.x // 35
    local startY = roomShape.y // 35
    local endX = startX + (roomShape.w // 35) - 1
    local endY = startY + (roomShape.h // 35) - 1

    for x = startX, endX do
        for y = startY, endY do
            shipManager:GetFire(x, y).fDamage = 100
        end
    end
end

script.on_internal_event(Defines.InternalEvents.DAMAGE_BEAM, function(shipManager, projectile, location, _damage, _realNewTile, beamHitType)
        if beamHitType == Defines.BeamHit.NEW_ROOM then
            fill_room_fire(shipManager, projectile, location)
        end

        return Defines.Chain.CONTINUE, beamHitType
    end
)

script.on_internal_event(Defines.InternalEvents.DAMAGE_AREA_HIT, function(shipManager, projectile, location)
        fill_room_fire(shipManager, projectile, location)
    end
)

script.on_internal_event(Defines.InternalEvents.WEAPON_STATBOX, function(bp, stats)
        if fireFillWeapons[bp.name] then
            return Defines.Chain.CONTINUE,
                stats .. "\n\n" .. Hyperspace.Text:GetText("stat_fire_fill")
        end
    end
)