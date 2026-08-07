local userdata_table = mods.multiverse.userdata_table
local spawn_temp_drone = mods.multiverse.spawn_temp_drone

mods.sc_drone_pod = mods.sc_drone_pod or {}
local pod = mods.sc_drone_pod

local POD_SPECIES = "terran_pod"
local LAUNCH_POWER = "LAUNCH"

-- This dedicated BOARDER blueprint is mapped in hyperspace.xml.append to
-- terran_marine. Hyperspace therefore creates a Terran Marine when this
-- boarding drone reaches the target ship instead of creating the default
-- boarding-drone crew.
local ATTACK_DRONE_BLUEPRINT = "TERRAN_POD_BOARDER"
local TEST_PAYLOAD_BLUEPRINT = "terran_marine"
local ATTACK_DRONE_SHOTS = 9999

-- The integer ID and payload table are intentionally separate from the
-- temporary drone object. In the next stage, this table can hold serialized
-- data from an actual crew entity selected in the drone room.
pod.nextTransportId = pod.nextTransportId or 0
pod.activeTransports = pod.activeTransports or {}

local function create_transport_payload(sourceShipId, targetShipId)
    pod.nextTransportId = pod.nextTransportId + 1

    local payload = {
        transportId = pod.nextTransportId,
        mode = "blueprint_test",
        crewBlueprint = TEST_PAYLOAD_BLUEPRINT,
        sourceShipId = sourceShipId,
        targetShipId = targetShipId
    }

    pod.activeTransports[payload.transportId] = payload
    return payload
end

script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power, shipManager)
    if not power or not power.def or power.def.name ~= LAUNCH_POWER then
        return
    end

    local podCrew = power.crew
    if not podCrew then return end
    if podCrew:GetSpecies() ~= POD_SPECIES then return end

    local ownerShip = Hyperspace.Global.GetInstance():GetShipManager(podCrew.iShipId)
    if not ownerShip then return end

    local targetShipId = 1 - podCrew.iShipId
    local targetShip = Hyperspace.Global.GetInstance():GetShipManager(targetShipId)
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

    local payload = create_transport_payload(podCrew.iShipId, targetShipId)

    -- Store the transport ID and the current test payload directly on the
    -- launched drone. A later arrival handler can use this ID to retrieve the
    -- complete stored crew record from pod.activeTransports.
    local podData = userdata_table(drone, "mods.sc.dronePod")
    podData.launchedByPod = true
    podData.transportId = payload.transportId
    podData.crewBlueprint = payload.crewBlueprint
    podData.sourceShipId = payload.sourceShipId
    podData.targetShipId = payload.targetShipId

    -- Match the existing temporary-drone cleanup behavior used by SC-MOD/MV.
    userdata_table(drone, "mods.mv.droneStuff").clearOnJump = true
end)

-- A transport cannot remain valid after leaving the encounter. The later
-- dynamic-crew implementation can replace this with more specific cleanup
-- when a pod arrives, is destroyed, or misses.
script.on_internal_event(Defines.InternalEvents.JUMP_LEAVE, function()
    pod.activeTransports = {}
end)
