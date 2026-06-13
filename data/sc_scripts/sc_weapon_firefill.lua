--[[
////////////////////
IMPORTS AND UTIL
////////////////////
]]--

-- Make tag tables local
local weaponTagParsers = mods.multiverse.weaponTagParsers

--[[
////////////////////
DATA & PARSER
////////////////////
]]--

local fireFillWeapons = {}
table.insert(weaponTagParsers, function(weaponNode)
    if weaponNode:first_node("sc-fireFill") then
        fireFillWeapons[weaponNode:first_attribute("name"):value()] = true
    end
end)

--[[
////////////////////
LOGIC
////////////////////
]]--

-- Fill rooms hit with fire
do
    local function fill_room_fire(shipManager, projectile, location)
        if fireFillWeapons[projectile and projectile.extend and projectile.extend.name] then
            local shipGraph = Hyperspace.ShipGraph.GetShipInfo(shipManager.iShipId)
            local room = shipGraph:GetSelectedRoom(location.x, location.y, false)
            if room > -1 then
                local roomShape = shipGraph:GetRoomShape(room)
                local startX = roomShape.x // 35
                local startY = roomShape.y // 35
                local endX = startX + (roomShape.w // 35) - 1
                local endY = startY + (roomShape.h // 35) - 1
                for x = startX, endX do
                    for y = startY, endY do
                        local fire = shipManager:GetFire(x, y)
                        fire.fDamage = 100
                    end
                end
            end
        end
    end

    script.on_internal_event(Defines.InternalEvents.DAMAGE_BEAM, function(shipManager, projectile, location, damage, realNewTile, beamHitType)
        if beamHitType == Defines.BeamHit.NEW_ROOM then
            fill_room_fire(shipManager, projectile, location)
        end
        return Defines.Chain.CONTINUE, beamHitType
    end)

    script.on_internal_event(Defines.InternalEvents.DAMAGE_AREA_HIT, function(shipManager, projectile, location, damage, shipFriendlyFire)
        fill_room_fire(shipManager, projectile, location)
    end)
end

-- Add info to stats
script.on_internal_event(Defines.InternalEvents.WEAPON_STATBOX, function(bp, stats)
    if fireFillWeapons[bp.name] then
        return Defines.Chain.CONTINUE, stats.."\n\n"..Hyperspace.Text:GetText("stat_fire_fill")
    end
end)
