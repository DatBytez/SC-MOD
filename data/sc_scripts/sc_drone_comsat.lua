--[[
SC Comsat drone targeting source.

A drone blueprint tagged with:

    <sc-comsat/>

provides the same targeting strength as the SC Detector augment while that
specific drone is deployed, powered, and alive. The strength is the ship's
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

local function drone_has_comsat_tag(drone)
    if not drone
        or not drone.blueprint
        or not drone.blueprint.name then

        return false
    end

    return comsatDrones[drone.blueprint.name] == true
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

-- Read <sc-comsat/> from droneBlueprint nodes before tag-data-read.lua runs.
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

        comsatDrones[nameAttr:value()] = true
    end
)
