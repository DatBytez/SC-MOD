--[[
DESCRIPTION: Launches the Terran SCV temporary hull-repair drone when LAUNCH_REPAIR activates.
DEPENDENCIES: Multiverse spawn_temp_drone and userdata_table
]]

local userdata_table = mods.multiverse.userdata_table
local spawn_temp_drone = mods.multiverse.spawn_temp_drone

local REPAIR_DRONE_BLUEPRINT = Hyperspace.Blueprints:GetDroneBlueprint("TERRAN_SCV_HULL")

script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power)
    if power.def.name ~= "LAUNCH_REPAIR" then return end

    local crew = power.crew
    local ship = Hyperspace.Global.GetInstance():GetShipManager(crew.iShipId)

    local drone = spawn_temp_drone(REPAIR_DRONE_BLUEPRINT, ship, ship, 1.0, 0, 1.0)

    userdata_table(drone, "mods.mv.droneStuff").clearOnJump = true
end)