--[[
DESCRIPTION: Gives HALO projectiles an angled launch that gradually straightens.
        - Alternates left/right offsets for projectiles fired by each weapon.
TAG: <sc-halo/>
DEPENDENCIES: sc_tag.lua, Multiverse userdata_table
]]

local userdata_table = mods.multiverse.userdata_table
local haloWeapons = {}
mods.sc.tag.register("weapon", "sc-halo", haloWeapons)

local LAUNCH_ANGLE = 35 -- Degrees either side of the original launch heading.
local STRAIGHTEN_DISTANCE = 350 -- Pixels travelled before returning to that heading.
local ANGLE_RANDOM_MIN = -20
local ANGLE_RANDOM_MAX = 20
local DISTANCE_RANDOM_MIN = -5
local DISTANCE_RANDOM_MAX = 5

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    if not haloWeapons[weapon.blueprint.name] then return end
    if projectile.currentSpace == projectile.destinationSpace then return end

    local weaponData = userdata_table(weapon, "mods.sc.haloLaunch")
    weaponData.side = -(weaponData.side or -1)

    local data = userdata_table(projectile, "mods.sc.haloLaunch")
    data.space = projectile.currentSpace
    data.heading = projectile.heading
    data.offset = math.max(0, LAUNCH_ANGLE + math.random(ANGLE_RANDOM_MIN, ANGLE_RANDOM_MAX)) * weaponData.side
    data.straightenDistance = math.max(1, STRAIGHTEN_DISTANCE + math.random(DISTANCE_RANDOM_MIN, DISTANCE_RANDOM_MAX))

    data.distance = 0
    data.x, data.y = projectile.position.x, projectile.position.y
    data.active = true
    projectile.heading = data.heading + data.offset
end)

script.on_internal_event(Defines.InternalEvents.PROJECTILE_UPDATE_POST, function(projectile)
    local data = userdata_table(projectile, "mods.sc.haloLaunch")
    if not data.active then return Defines.Chain.CONTINUE end

    if projectile:Dead() or projectile.startedDeath
        or projectile.currentSpace ~= data.space
        or projectile.currentSpace == projectile.destinationSpace then
        data.active = false
        return Defines.Chain.CONTINUE
    end

    local gui = Hyperspace.App.gui
    if gui.bPaused or gui.bAutoPaused or gui.event_pause or gui.menu_pause then
        return Defines.Chain.CONTINUE
    end

    local x, y = projectile.position.x, projectile.position.y
    local dx, dy = x - data.x, y - data.y
    data.distance = data.distance + math.sqrt(dx * dx + dy * dy)
    data.x, data.y = x, y

    local adjust = math.min(1, data.distance / data.straightenDistance)
    local remaining = 1 - adjust
    projectile.heading = data.heading + data.offset * remaining * remaining
    if adjust >= 1 then data.active = false end
    return Defines.Chain.CONTINUE
end)
