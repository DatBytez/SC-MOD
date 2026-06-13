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

local breachFillWeapons = {}
table.insert(weaponTagParsers, function(weaponNode)
    if weaponNode:first_node("sc-breachFill") then
        breachFillWeapons[weaponNode:first_attribute("name"):value()] = true
    end
end)

--[[
////////////////////
LOGIC
////////////////////
]]--

-- Fill rooms hit with breaches
do
    local function fill_room_breach(shipManager, projectile, location)
        if breachFillWeapons[projectile and projectile.extend and projectile.extend.name] then
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
                        shipManager.ship:BreachSpecificHull(x, y)
                    end
                end
            end
        end
    end

    script.on_internal_event(Defines.InternalEvents.DAMAGE_BEAM, function(shipManager, projectile, location, damage, realNewTile, beamHitType)
        if beamHitType == Defines.BeamHit.NEW_ROOM then
            fill_room_breach(shipManager, projectile, location)
        end
        return Defines.Chain.CONTINUE, beamHitType
    end)

    script.on_internal_event(Defines.InternalEvents.DAMAGE_AREA_HIT, function(shipManager, projectile, location, damage, shipFriendlyFire)
        fill_room_breach(shipManager, projectile, location)
    end)
end

-- Add info to stats
script.on_internal_event(Defines.InternalEvents.WEAPON_STATBOX, function(bp, stats)
    if breachFillWeapons[bp.name] then
        return Defines.Chain.CONTINUE, stats.."\n\n"..Hyperspace.Text:GetText("stat_breach_fill")
    end
end)
