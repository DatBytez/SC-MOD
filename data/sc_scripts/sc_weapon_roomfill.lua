--[[
DESCRIPTION: Fills every tile in a room with fire and/or breaches when hit by a tagged weapon.
        - Beam weapons trigger once when entering a new room.
        - Area-hit projectiles trigger on impact.
        - Adds the appropriate room-fill information to the weapon stat box.
TAGS: <sc-fireFill/>
      <sc-breachFill/>
DEPENDENCIES: sc_tag.lua
]]

local fireFillWeapons = {}
local breachFillWeapons = {}

mods.sc.tag.register("weapon", "sc-fireFill", fireFillWeapons)
mods.sc.tag.register("weapon", "sc-breachFill", breachFillWeapons)

local function fill_room(shipManager, projectile, location)
    if not projectile then return end

    local weaponName = projectile.extend.name
    local fillFire = fireFillWeapons[weaponName]
    local fillBreach = breachFillWeapons[weaponName]

    if not fillFire and not fillBreach then return end

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
            if fillFire then
                shipManager:GetFire(x, y).fDamage = 100
            end

            if fillBreach then
                shipManager.ship:BreachSpecificHull(x, y)
            end
        end
    end
end

script.on_internal_event(Defines.InternalEvents.DAMAGE_BEAM, function(shipManager, projectile, location, _damage, _realNewTile, beamHitType)
    if beamHitType == Defines.BeamHit.NEW_ROOM then
        fill_room(shipManager, projectile, location)
    end

    return Defines.Chain.CONTINUE, beamHitType
end)

script.on_internal_event(Defines.InternalEvents.DAMAGE_AREA_HIT, function(shipManager, projectile, location)
    fill_room(shipManager, projectile, location)
end)

script.on_internal_event(Defines.InternalEvents.WEAPON_STATBOX, function(bp, stats)
    local modified = false

    if fireFillWeapons[bp.name] then
        stats = stats .. "\n\n" .. Hyperspace.Text:GetText("stat_fire_fill")
        modified = true
    end

    if breachFillWeapons[bp.name] then
        stats = stats .. "\n\n" .. Hyperspace.Text:GetText("stat_breach_fill")
        modified = true
    end

    if modified then
        return Defines.Chain.CONTINUE, stats
    end
end)