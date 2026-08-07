local userdata_table = mods.multiverse.userdata_table
local spawn_temp_drone = mods.multiverse.spawn_temp_drone

mods.sc_drone_pod = mods.sc_drone_pod or {}

local POD_SPECIES = "terran_pod"
local LAUNCH_POWER = "LAUNCH"
local ATTACK_DRONE_BLUEPRINT = "COMBAT_1"
local ATTACK_DRONE_SHOTS = 9999

script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power, shipManager)
    if not power or not power.def or power.def.name ~= LAUNCH_POWER then
        return
    end

    local podCrew = power.crew
    if not podCrew then return end
    if podCrew:GetSpecies() ~= POD_SPECIES then return end

    local ownerShip = Hyperspace.Global.GetInstance():GetShipManager(podCrew.iShipId)
    if not ownerShip then return end

    local targetShip = Hyperspace.Global.GetInstance():GetShipManager(1 - podCrew.iShipId)
    if not targetShip then return end

    local blueprint = Hyperspace.Blueprints:GetDroneBlueprint(ATTACK_DRONE_BLUEPRINT)
    if not blueprint then return end
    if not spawn_temp_drone or not userdata_table then return end

    local drone = spawn_temp_drone(
        blueprint,
        ownerShip,
        targetShip,
        nil,
        ATTACK_DRONE_SHOTS,
        nil)

    if not drone then return end

    -- Mark this drone now so later stages can attach the stored crew data here.
    local podData = userdata_table(drone, "mods.sc.dronePod")
    podData.launchedByPod = true
    podData.sourceShipId = podCrew.iShipId

    -- Match the existing temporary-drone cleanup behavior used by SC-MOD/MV.
    userdata_table(drone, "mods.mv.droneStuff").clearOnJump = true
end)
