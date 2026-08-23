--[[
DESCRIPTION: Heals 1 hull when a completely destroyed system is repaired.
TAG: <sc-repair/>
DEPENDENCIES: sc_tag.lua
]]
mods.sc.repairAugments = mods.sc.repairAugments or {}

local repairAugments = mods.sc.repairAugments

mods.sc.tag.register("augment", "sc-repair", repairAugments)

local HULL_HEAL_AMOUNT = 1
local LILY_SYSTEM_BRACERS_ID = Hyperspace.ShipSystem.NameToSystemId("lily_system_bracers")

local vter = mods.multiverse.vter
local helpers = mods.sc.helpers

local function update_system_state(ship, system)
    if not system then return end

    system.table.sc_terran_repair_hull = system.table.sc_terran_repair_hull or {}
    local state = system.table.sc_terran_repair_hull
    local currentlyDestroyed = system:CompletelyDestroyed()

    if state.wasCompletelyDestroyed and not currentlyDestroyed then
        if helpers.ship_has_augment(ship, repairAugments) then
            local hull = ship.ship.hullIntegrity

            if hull.first < hull.second then
                ship:DamageHull(-HULL_HEAL_AMOUNT, true)
            end
        end

        state.wasCompletelyDestroyed = false
    elseif currentlyDestroyed then
        state.wasCompletelyDestroyed = true
    end
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    for system in vter(ship.vSystemList) do
        update_system_state(ship, system)
    end

    update_system_state(ship, ship:GetSystem(LILY_SYSTEM_BRACERS_ID))
end)