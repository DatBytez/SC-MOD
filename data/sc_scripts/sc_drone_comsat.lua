--[[
SC Comsat drone targeting source.

A drone blueprint tagged with:

    <sc-comsat/>

or:

    <sc-comsat>15</sc-comsat>

provides the same targeting strength as the SC Detector augment while that
specific drone is deployed, powered, and alive. The tag value is the drone's
maximum deployed lifetime in seconds. An empty tag defaults to 10 seconds. The strength is the ship's
current effective Sensors power, so the Comsat inherits the shared targeting
core's existing Detector behavior without duplicating any gameplay callbacks.

The shared targeting core owns:
    1. Projectile accuracy bonus.
    2. Missile accuracy multiplier.
    3. Weapon-radius reduction.
    4. Weapon charging while the enemy ship is cloaked.
    5. Anti-cloak targeting/firing support.

If Detector and Comsat are active at the same time, the shared targeting core
uses the strongest registered source rather than stacking them. Since both use
Sensors power, they therefore provide the same strength rather than doubling
the effect.
]]

mods.multiverse.droneTagParsers =
    mods.multiverse.droneTagParsers or {}

local droneTagParsers =
    mods.multiverse.droneTagParsers

local vter = mods.multiverse.vter

mods.sc = mods.sc or {}
mods.sc.comsat = mods.sc.comsat or {}
mods.sc.comsatDrones = mods.sc.comsatDrones or {}

local comsat = mods.sc.comsat
local comsatDrones = mods.sc.comsatDrones
local targeting = mods.sc.targeting

local DEFAULT_COMSAT_LIFETIME = 10

local function get_comsat_lifetime(drone)
    if not drone
        or not drone.blueprint
        or not drone.blueprint.name then

        return nil
    end

    return comsatDrones[drone.blueprint.name]
end

local function drone_has_comsat_tag(drone)
    return get_comsat_lifetime(drone) ~= nil
end

local function drone_is_active_comsat(drone)
    if not drone_has_comsat_tag(drone) then
        return false
    end

    if drone.deployed ~= true then
        return false
    end

    if drone.powered ~= true then
        return false
    end

    if drone.bDead == true then
        return false
    end

    return true
end

local function ship_has_active_comsat(ship)
    if not ship
        or not ship.droneSystem
        or not ship.droneSystem.drones then

        return false
    end

    for drone in vter(ship.droneSystem.drones) do
        if drone_is_active_comsat(drone) then
            return true
        end
    end

    return false
end

local function get_comsat_strength(ship)
    if not ship_has_active_comsat(ship) then
        return nil
    end

    local sensors = ship:GetSystem(7)

    if not sensors then
        return nil
    end

    return sensors:GetEffectivePower()
end

-- Public helpers for later Comsat-specific features such as full room reveal
-- and invisible-crew detection.
comsat.drone_has_comsat_tag =
    drone_has_comsat_tag

comsat.get_lifetime =
    get_comsat_lifetime

comsat.drone_is_active =
    drone_is_active_comsat

comsat.ship_has_active_comsat =
    ship_has_active_comsat

comsat.get_strength =
    get_comsat_strength

-- Register Comsat as a temporary activation source for the shared targeting
-- package. No projectile, radius, or cloak callbacks are duplicated here.
targeting.register_source(
    "sc_comsat",
    get_comsat_strength
)

-- Read the Comsat lifetime from droneBlueprint nodes before tag-data-read.lua
-- runs.
--
--     <sc-comsat/>       = 10 seconds
--     <sc-comsat>15</sc-comsat> = 15 seconds
--
-- Invalid, zero, or negative values fall back to the 10-second default.
table.insert(
    droneTagParsers,
    function(droneNode)
        local nameAttr =
            droneNode:first_attribute("name")

        if not nameAttr then
            return
        end

        local tagNode =
            droneNode:first_node("sc-comsat")

        if not tagNode then
            return
        end

        local lifetime =
            tonumber(tagNode:value())

        if not lifetime
            or lifetime <= 0 then

            lifetime =
                DEFAULT_COMSAT_LIFETIME
        end

        comsatDrones[nameAttr:value()] =
            lifetime
    end
)


------------------------------------------------------------------------------------
-- Comsat deployment lifetime
--
-- Use the same timing method as sc_pilot_ui.lua:
--
--     timer += Hyperspace.FPS.SpeedFactor / 16
--
-- Timer state is kept in ordinary Lua tables rather than userdata storage.
-- Each drone is keyed by shipId + SpaceDrone.selfId so simultaneous Comsats
-- receive independent timers.
--
-- Lifetime begins when the Comsat is deployed. Depowering does not pause the
-- timer, although an unpowered Comsat still stops contributing targeting
-- strength through drone_is_active_comsat().
local comsatTimers = {
    [0] = {},
    [1] = {}
}

comsat.timers =
    comsatTimers

local function get_ship_timer_table(shipId)
    if not comsatTimers[shipId] then
        comsatTimers[shipId] = {}
    end

    return comsatTimers[shipId]
end

local function get_drone_timer_key(drone)
    if not drone
        or drone.selfId == nil then

        return nil
    end

    return drone.selfId
end

local function get_timer_state(
    shipId,
    droneSelfId
)
    local shipTimers =
        comsatTimers[shipId]

    if not shipTimers then
        return nil
    end

    return shipTimers[droneSelfId]
end

comsat.get_timer_state =
    get_timer_state

local function reset_all_timers()
    comsatTimers[0] = {}
    comsatTimers[1] = {}
end

local function update_comsat_lifetime(
    ship,
    drone
)
    local lifetime =
        get_comsat_lifetime(drone)

    if not lifetime
        or not ship then

        return
    end

    local shipId =
        ship.iShipId

    local droneKey =
        get_drone_timer_key(drone)

    if shipId == nil
        or droneKey == nil then

        return
    end

    local shipTimers =
        get_ship_timer_table(shipId)

    local state =
        shipTimers[droneKey]

    -- A non-deployed, living drone is ready for a fresh future deployment.
    if drone.deployed ~= true then
        if drone.bDead ~= true then
            shipTimers[droneKey] = nil
        end

        return
    end

    -- Do not restart or continue a timer after the drone is already dead.
    if drone.bDead == true then
        return
    end

    if not state then
        state = {
            started = true,
            remaining = lifetime,
            expired = false
        }

        shipTimers[droneKey] =
            state
    end

    if state.expired then
        return
    end

    state.remaining =
        math.max(
            0,
            state.remaining
                - Hyperspace.FPS.SpeedFactor
                / 16
        )

    if state.remaining <= 0 then
        state.expired = true

        -- dead=true, rebuildRequired=false
        drone:SetDestroyed(
            true,
            false
        )
    end
end

script.on_init(
    reset_all_timers
)

script.on_internal_event(
    Defines.InternalEvents.JUMP_ARRIVE,
    function()
        reset_all_timers()
    end
)

script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    function(ship)
        if not ship
            or not ship.droneSystem
            or not ship.droneSystem.drones then

            return
        end

        for drone in vter(
            ship.droneSystem.drones
        ) do
            if drone_has_comsat_tag(drone) then
                update_comsat_lifetime(
                    ship,
                    drone
                )
            end
        end
    end
)

------------------------------------------------------------------------------------
-- Comsat scan projectile visuals
--
-- The projectile blueprint uses a normal stock projectile image so FTL always has
-- a valid projectile animation. Hide only the in-flight animation here. The death
-- animation is deliberately left unchanged so the impact explosion remains visible
-- and can later be replaced by the Comsat sparkling scan effect.
script.on_internal_event(
    Defines.InternalEvents.DRONE_FIRE,
    function(projectile, spacedrone)
        if not projectile
            or not drone_has_comsat_tag(spacedrone) then

            return
        end

        if projectile.flight_animation then
            projectile.flight_animation.fScale = 0
        end
    end
)