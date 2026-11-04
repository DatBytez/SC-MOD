--[[
DESCRIPTION: Creates a particle trail for tagged HALO projectiles.
TAG: <sc-halo/>
DEPENDENCIES: sc_tag.lua, brightness_particles.lua, Multiverse userdata_table
]]

local Brightness = mods.brightness
local userdata_table = mods.multiverse.userdata_table

local haloWeapons = {}
mods.sc.tag.register("weapon", "sc-halo", haloWeapons)

local TRAIL_FOLDER = "projectiles/terran_halo_trail"
local FRAME_COUNT = 8
local FRAME_DURATION = 1.5 -- Total duration of all eight frames, in seconds.
local TRAIL_SCALE = 1.0 -- Original frames are 158 x 202 pixels.
local PARTICLE_SPACING = 40 -- Pixels travelled between particles.
local MAX_SEGMENT = 500 -- Do not draw a trail across a teleport/discontinuity.
local RENDER_LAYER = "SHIP"

local particles = {}

local function emit_particle(x, y, space)
    for i = #particles, 1, -1 do
        if particles[i]:isDestroyed() then table.remove(particles, i) end
    end

    local particle = Brightness.create_particle(TRAIL_FOLDER, FRAME_COUNT, FRAME_DURATION, Hyperspace.Pointf(x, y), 0, space, RENDER_LAYER)
    particle.scale = TRAIL_SCALE
    particles[#particles + 1] = particle
end

local function clear_particles()
    for _, particle in ipairs(particles) do
        if not particle:isDestroyed() then Brightness.destroy_particle(particle) end
    end
    particles = {}
end

script.on_internal_event(Defines.InternalEvents.PROJECTILE_UPDATE_POST, function(projectile)
    if not projectile.extend
        or not haloWeapons[projectile.extend.name]
        or projectile:Dead()
        or projectile.startedDeath then
        return Defines.Chain.CONTINUE
    end

    local gui = Hyperspace.App.gui
    if gui.bPaused or gui.bAutoPaused or gui.event_pause or gui.menu_pause then
        return Defines.Chain.CONTINUE
    end

    local data = userdata_table(projectile, "mods.sc.haloTrail")
    local space = projectile.currentSpace

    if space < 0 then
        data.space = nil
        return Defines.Chain.CONTINUE
    end

    local x, y = projectile.position.x, projectile.position.y

    if data.space ~= space then
        data.space, data.x, data.y, data.distance = space, x, y, 0
        return Defines.Chain.CONTINUE
    end

    local dx, dy = x - data.x, y - data.y
    local distance = math.sqrt(dx * dx + dy * dy)

    if distance > MAX_SEGMENT then
        data.distance = 0
    elseif distance > 0 then
        local nextDistance = PARTICLE_SPACING - data.distance

        while nextDistance <= distance do
            local fraction = nextDistance / distance
            emit_particle(data.x + dx * fraction, data.y + dy * fraction, space)
            nextDistance = nextDistance + PARTICLE_SPACING
        end

        data.distance = (data.distance + distance) % PARTICLE_SPACING
    end

    data.x, data.y = x, y

    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.JUMP_LEAVE, clear_particles)
script.on_game_event("START_BEACON", false, clear_particles)
script.on_game_event("DEATH", false, clear_particles)