--[[
DESCRIPTION: Tests Hyperspace's native boarding-drone creation without adding
             a blueprint to Drone Control.
        - Runs once per beacon when the player encounters a hostile ship.
        - Creates a vanilla BOARDER pod via CreateSpaceDrone.
        - Checks crew through ship.vCrewList, not the pod's opaque CrewDrone pointer.
        - Attempts to deploy the pod and reports newly registered crew.
DEPENDENCIES: Hyperspace only
TEST ONLY: Use on a disposable save; remove the script after testing.
]]

local TEST_BLUEPRINT = "BOARDER"
local attemptedThisBeacon = false
local watchFrames = 0
local knownCounts = {[0] = 0, [1] = 0}

local function log(message)
    print("[SC Native Boarding Test] " .. tostring(message))
end

local function crew_count(ship)
    if not ship or not ship.vCrewList then return 0 end
    local ok, count = pcall(function() return ship.vCrewList:size() end)
    return ok and count or 0
end

local function inspect_new_crew(ship, label)
    if not ship then return end

    local shipId = ship.iShipId
    local count = crew_count(ship)
    local previous = knownCounts[shipId] or 0

    if count > previous then
        for i = previous, count - 1 do
            local ok, details = pcall(function()
                local crew = ship.vCrewList[i]
                return "species=" .. tostring(crew.species)
                    .. ", IsDrone()=" .. tostring(crew:IsDrone())
                    .. ", owner=" .. tostring(crew.iShipId)
                    .. ", currentShip=" .. tostring(crew.currentShipId)
            end)

            if ok then
                log("NEW " .. label .. " crew [" .. i .. "]: " .. details)
            else
                log("Could not inspect " .. label .. " crew [" .. i .. "]: " .. tostring(details))
            end
        end
    end

    knownCounts[shipId] = count
end

local function try_step(label, callback)
    local ok, result = pcall(callback)
    if ok then
        log(label .. ": OK" .. (result ~= nil and (" (" .. tostring(result) .. ")") or ""))
    else
        log(label .. ": ERROR: " .. tostring(result))
    end
    return ok
end

local function reset_test()
    attemptedThisBeacon = false
    watchFrames = 0
    knownCounts[0] = 0
    knownCounts[1] = 0
end

script.on_init(function()
    reset_test()
    log("Loaded. Waiting for a hostile enemy ship.")
end)

script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, function(ship)
    if ship and ship.iShipId == 0 then
        reset_test()
        log("Player arrived. Ready for a new test.")
    end
end)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    if not ship or ship.iShipId ~= 0 then return end

    if watchFrames > 0 then
        inspect_new_crew(ship, "player")
        inspect_new_crew(ship.current_target, "enemy")
        watchFrames = watchFrames - 1
        if watchFrames == 0 then
            log("Observation complete. Check the NEW crew lines above.")
        end
    end

    if attemptedThisBeacon then return end

    local enemy = ship.current_target
    if not enemy or enemy.bDestroyed or not enemy._targetable or not enemy._targetable.hostile then
        return
    end

    attemptedThisBeacon = true
    log("Hostile target detected. Starting native boarding-drone test.")

    knownCounts[0] = crew_count(ship)
    knownCounts[1] = crew_count(enemy)
    log("Before creation: player crew=" .. knownCounts[0] .. ", enemy crew=" .. knownCounts[1])

    local okBlueprint, blueprint = pcall(function()
        return Hyperspace.Blueprints:GetDroneBlueprint(TEST_BLUEPRINT)
    end)
    if not okBlueprint or not blueprint then
        log("ERROR: Could not get blueprint " .. TEST_BLUEPRINT .. ": " .. tostring(blueprint))
        return
    end
    if blueprint.typeName ~= "BOARDER" then
        log("ERROR: Blueprint type is " .. tostring(blueprint.typeName) .. ", expected BOARDER.")
        return
    end

    local okPod, pod = pcall(function() return ship:CreateSpaceDrone(blueprint) end)
    if not okPod or not pod then
        log("ERROR: CreateSpaceDrone failed: " .. tostring(pod))
        return
    end

    log("CreateSpaceDrone succeeded. Native drone type=" .. tostring(pod.type))
    if pod.type ~= 4 then
        log("ERROR: Returned object is not a boarding pod. Aborting deployment.")
        return
    end

    local okCrew, opaqueCrew = pcall(function() return pod:GetBoardingDrone() end)
    if okCrew then
        log("GetBoardingDrone returned " .. type(opaqueCrew)
            .. ". Do not index this pointer; inspecting ship crew lists instead.")
    else
        log("GetBoardingDrone ERROR: " .. tostring(opaqueCrew))
    end

    inspect_new_crew(ship, "player")
    inspect_new_crew(enemy, "enemy")

    try_step("SetMovementTarget", function() pod:SetMovementTarget(enemy._targetable) end)
    try_step("Set powerRequired=0", function() pod.powerRequired = 0 end)
    try_step("SetDeployed(true)", function() pod:SetDeployed(true) end)
    try_step("SetPowered(true)", function() pod:SetPowered(true) end)
    try_step("SetInstantPowered()", function() pod:SetInstantPowered() end)

    watchFrames = 600
    log("Monitoring player/enemy crew lists for new drone entities.")
end)
