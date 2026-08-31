--[[
DESCRIPTION: Manages pairing between Terran Goliath crew-drones and their companion turrets.
        - Collects active terran_goliath crew-drones for either active ship.
        - Creates one TERRAN_GOLIATH_T companion turret for each unpaired Goliath.
        - Reuses valid managed pair state when available after loading.
        - Removes duplicate, orphaned, and retired companion turrets.
        - Publishes current crew/turret pairs separately for ship IDs 0 and 1.
DEPENDENCIES: sc_drone_goliath_core.lua
]]

local vter = mods.multiverse.vter
local userdata_table = mods.multiverse.userdata_table
local goliath = mods.sc.goliath

local function collect_active_goliaths(shipManager)
    local crews = {}
    local crewsById = {}

    for crew in vter(shipManager.vCrewList) do
        if crew.type == goliath.FOLLOW_CREW_TYPE then
            local crewState = userdata_table(
                crew,
                goliath.CREW_STATE_KEY
            )

            if goliath.is_active_goliath(crew, shipManager) then
                local crewId = crew.extend.selfId
                table.insert(crews, crew)
                crewsById[crewId] = crew
            else
                crewState.companionInitialized = false
            end
        end
    end

    return crews, crewsById
end

function goliath.find_active_goliath_by_id(
    shipManager,
    crewId
)
    for crew in vter(shipManager.vCrewList) do
        if goliath.is_active_goliath(crew, shipManager)
            and crew.extend.selfId == crewId then
            return crew
        end
    end

    return nil
end

local function mark_turret_pair(
    defenseDrone,
    crew
)
    local state = userdata_table(
        defenseDrone,
        goliath.TURRET_STATE_KEY
    )

    state.managed = true
    state.crewId = crew.extend.selfId
    state.retired = false

    local crewState = userdata_table(
        crew,
        goliath.CREW_STATE_KEY
    )

    crewState.companionInitialized = true
end

local function retire_turret(defenseDrone)
    local state = userdata_table(
        defenseDrone,
        goliath.TURRET_STATE_KEY
    )

    state.managed = true
    state.retired = true

    defenseDrone.bFire = false
    defenseDrone.powered = false
    defenseDrone:SetDestroyed(true, false)
end

local function spawn_companion_turret(
    shipManager,
    crew
)
    local droneBlueprint =
        Hyperspace.Blueprints:GetDroneBlueprint(
            goliath.FOLLOW_DRONE_BLUEPRINT
        )

    if not droneBlueprint then
        goliath.error_print(
            "Could not find drone blueprint "
            .. goliath.FOLLOW_DRONE_BLUEPRINT
            .. "."
        )
        return nil
    end

    local success, defenseDrone = pcall(function()
        local drone =
            shipManager:CreateSpaceDrone(
                droneBlueprint
            )

        drone.powerRequired = 0
        drone.powered = true
        drone:SetDeployed(true)
        drone.bDead = false
        drone.bFire = false

        goliath.position_turret_with_crew(
            crew,
            drone
        )

        local angle =
            goliath.get_facing_state(crew).idleAngle

        drone.current_angle = angle
        drone.aimingAngle = angle
        drone.lastAimingAngle = angle
        drone.desiredAimingAngle = angle

        goliath.set_cached_image_rotation(
            drone.gun_image_off,
            angle
        )
        goliath.set_cached_image_rotation(
            drone.gun_image_charging,
            angle
        )
        goliath.set_cached_image_rotation(
            drone.gun_image_on,
            angle
        )

        mark_turret_pair(
            drone,
            crew
        )

        goliath.update_turret_power_from_legs(
            crew,
            drone
        )

        return drone
    end)

    if not success then
        goliath.error_print(
            "Failed to summon "
            .. goliath.FOLLOW_DRONE_BLUEPRINT
            .. ": "
            .. tostring(defenseDrone)
        )
        return nil
    end

    return defenseDrone
end

function goliath.remove_all_turrets(
    shipManager
)
    for defenseDrone in vter(
        shipManager.spaceDrones
    ) do
        if defenseDrone.blueprint.name
                == goliath.FOLLOW_DRONE_BLUEPRINT
            and not defenseDrone.bDead then

            local turretState = userdata_table(
                defenseDrone,
                goliath.TURRET_STATE_KEY
            )

            turretState.managed = true
            turretState.retired = true

            defenseDrone.bFire = false
            defenseDrone.powered = false
            defenseDrone:SetPowered(false)
            defenseDrone:SetDestroyed(
                true,
                false
            )
        end
    end

    goliath.set_active_pairs(
        shipManager,
        {}
    )
end

function goliath.synchronize_pairs(
    shipManager
)
    local crews, crewsById =
        collect_active_goliaths(shipManager)

    local managedLiveByCrewId = {}
    local duplicateOrOrphanedTurrets = {}

    for drone in vter(shipManager.spaceDrones) do
        if goliath.is_live_goliath_turret(
            drone,
            shipManager
        ) then
            local turretState = userdata_table(
                drone,
                goliath.TURRET_STATE_KEY
            )

            local assignedCrew =
                turretState.managed
                and crewsById[turretState.crewId]
                or nil

            if turretState.retired then
                table.insert(
                    duplicateOrOrphanedTurrets,
                    drone
                )
            elseif assignedCrew then
                local current =
                    managedLiveByCrewId[
                        turretState.crewId
                    ]

                if not current then
                    managedLiveByCrewId[
                        turretState.crewId
                    ] = drone
                else
                    local crewPosition =
                        assignedCrew:GetLocation()

                    local currentDistance =
                        distance_squared(
                            crewPosition,
                            current.currentLocation
                        )

                    local candidateDistance =
                        distance_squared(
                            crewPosition,
                            drone.currentLocation
                        )

                    if candidateDistance
                        < currentDistance then
                        table.insert(
                            duplicateOrOrphanedTurrets,
                            current
                        )
                        managedLiveByCrewId[
                            turretState.crewId
                        ] = drone
                    else
                        table.insert(
                            duplicateOrOrphanedTurrets,
                            drone
                        )
                    end
                end
            else
                table.insert(
                    duplicateOrOrphanedTurrets,
                    drone
                )
            end
        end
    end

    local newPairs = {}

    for _, crew in ipairs(crews) do
        local crewId = crew.extend.selfId

        local crewState = userdata_table(
            crew,
            goliath.CREW_STATE_KEY
        )

        local defenseDrone =
            managedLiveByCrewId[crewId]

        if defenseDrone then
            mark_turret_pair(
                defenseDrone,
                crew
            )
        elseif not crewState.companionInitialized then
            defenseDrone =
                spawn_companion_turret(
                    shipManager,
                    crew
                )
        end

        if defenseDrone then
            goliath.position_turret_with_crew(
                crew,
                defenseDrone
            )

            goliath.update_turret_power_from_legs(
                crew,
                defenseDrone
            )

            newPairs[crewId] = {
                crew = crew,
                drone = defenseDrone
            }
        end
    end

    for _, drone in ipairs(
        duplicateOrOrphanedTurrets
    ) do
        retire_turret(drone)
    end

    goliath.set_active_pairs(
        shipManager,
        newPairs
    )
end
