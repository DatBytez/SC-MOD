local vter = mods.multiverse.vter
local userdata_table = mods.multiverse.userdata_table

local FOLLOW_CREW_TYPE = "terran_goliath"
local FOLLOW_DRONE_BLUEPRINT = "TERRAN_GOLIATH_T"

local CREW_STATE_KEY = "mods.sc.goliathNativeFacingState"
local TURRET_STATE_KEY = "mods.sc.goliathTurretCompanion"

local FOLLOW_OFFSET_X = 3
local FOLLOW_OFFSET_Y = 0

-- Moves the native crew health bar relative to the Goliath legs.
-- Negative Y moves the bar upward to clear the attached turret.
local HEALTH_BAR_OFFSET_X = 1
local HEALTH_BAR_OFFSET_Y = -8

local MOVEMENT_EPSILON = 0.2

-- The former -90 adjustment is included directly in direction_angle().
local NATIVE_ANGLE_OFFSET = 0

-- Damage transferred to the connected Goliath legs when its turret is hit.
local TURRET_HIT_DAMAGE = 45

-- Leave FTL's native projectile targeting untouched during combat.
local PRESERVE_NATIVE_PROJECTILE_TARGETING = true

-- Keep these false for normal play. Errors still print.
local DEBUG_NATIVE_FACING = false
local DEBUG_SPAWNS = false

-- Set true only when troubleshooting Goliath power state.
local DEBUG_POWER_STATE = false
local DEBUG_INTERVAL_TICKS = 120

local debugTickCounter = 0
local renderApplyCount = 0
local activePairs = {}
local lastRenderError = nil

local lastPairPowerDebug = {}
local lastDevicePowerDebug = nil

local function configure_print_display()
    local success, printHelper = pcall(function()
        return Hyperspace.PrintHelper.GetInstance()
    end)

    if success and printHelper then
        printHelper.x = 20
        printHelper.y = 100
        printHelper.font = 10
        printHelper.lineLength = 700
        printHelper.messageLimit = 12
        printHelper.duration = 6
        printHelper.useSpeed = false
    end
end

local function debug_print(message)
    if DEBUG_NATIVE_FACING
        or DEBUG_SPAWNS
        or DEBUG_POWER_STATE then

        print("[GOLIATH POWER] " .. tostring(message))
    end
end

local function error_print(message)
    print("[GOLIATH ERROR] " .. tostring(message))
end


configure_print_display()
-- 

local function is_active_goliath(crew, shipManager)
    return crew
        and crew.type == FOLLOW_CREW_TYPE
        and not crew.bDead
        and crew.currentShipId == shipManager.iShipId
end

local function is_goliath_turret(drone, shipManager)
    return drone
        and drone.blueprint
        and drone.blueprint.name == FOLLOW_DRONE_BLUEPRINT
        and drone.blueprint.typeName == "DEFENSE"
        and drone.currentSpace == shipManager.iShipId
end

local function is_live_goliath_turret(drone, shipManager)
    return is_goliath_turret(drone, shipManager)
        and drone.deployed
        and not drone.bDead
end

local function collect_active_goliaths(shipManager)
    local crews = {}
    local crewsById = {}

    for crew in vter(shipManager.vCrewList) do
        if crew.type == FOLLOW_CREW_TYPE then
            local crewState = userdata_table(
                crew,
                CREW_STATE_KEY
            )

            if is_active_goliath(crew, shipManager) then
                local crewId = crew.extend.selfId

                table.insert(crews, crew)
                crewsById[crewId] = crew
            else
                -- Allow this crew-drone object to receive a new turret if it
                -- is deployed again later.
                crewState.companionInitialized = false
                crewState.turretId = nil
            end
        end
    end

    return crews, crewsById
end

local function find_active_goliath_by_id(
    shipManager,
    crewId
)
    if crewId == nil then
        return nil
    end

    for crew in vter(shipManager.vCrewList) do
        if is_active_goliath(crew, shipManager)
            and crew.extend.selfId == crewId then
            return crew
        end
    end

    return nil
end

local function distance_squared(pointA, pointB)
    local x = pointA.x - pointB.x
    local y = pointA.y - pointB.y

    return x * x + y * y
end

local function direction_name(directionX, directionY)
    if directionX > 0 then
        return "RIGHT"
    elseif directionX < 0 then
        return "LEFT"
    elseif directionY < 0 then
        return "UP"
    else
        return "DOWN"
    end
end

local function direction_angle(directionX, directionY)
    -- These values already contain the former -90 offset.
    --
    -- RIGHT = 0
    -- DOWN  = 90
    -- LEFT  = 180
    -- UP    = 270
    if directionX > 0 then
        return 0
    elseif directionY > 0 then
        return 90
    elseif directionX < 0 then
        return 180
    else
        return 270
    end
end

local function get_facing_state(crew)
    local state = userdata_table(
        crew,
        CREW_STATE_KEY
    )

    local position = crew:GetLocation()

    if not state.initialized then
        state.initialized = true

        state.lastX = position.x
        state.lastY = position.y

        state.directionX = 0
        state.directionY = 1
        state.directionName = "DOWN"
        state.idleAngle = direction_angle(0, 1)

        return state
    end

    local movementX = position.x - state.lastX
    local movementY = position.y - state.lastY

    state.lastX = position.x
    state.lastY = position.y

    if math.abs(movementX) > MOVEMENT_EPSILON
        or math.abs(movementY) > MOVEMENT_EPSILON then

        if math.abs(movementX) >= math.abs(movementY) then
            state.directionX = movementX > 0 and 1 or -1
            state.directionY = 0
        else
            state.directionX = 0
            state.directionY = movementY > 0 and 1 or -1
        end

        state.directionName = direction_name(
            state.directionX,
            state.directionY
        )

        state.idleAngle = direction_angle(
            state.directionX,
            state.directionY
        )
    end

    return state
end

local function set_cached_image_rotation(
    cachedImage,
    angle
)
    if not cachedImage then
        return
    end

    -- Newly created native drone images can briefly exist as invalid SWIG
    -- userdata. Ignore that single frame instead of aborting turret creation.
    pcall(function()
        cachedImage:SetRotation(angle)
        cachedImage.rotation = angle
    end)
end

local function copy_native_orientation(
    sourceDrone,
    targetDrone
)
    if not sourceDrone or not targetDrone then
        return
    end

    local angle =
        sourceDrone.current_angle
        or sourceDrone.aimingAngle
        or sourceDrone.desiredAimingAngle
        or 0

    targetDrone.current_angle = angle
    targetDrone.aimingAngle = angle
    targetDrone.lastAimingAngle = angle
    targetDrone.desiredAimingAngle = angle

    set_cached_image_rotation(
        targetDrone.gun_image_off,
        angle
    )

    set_cached_image_rotation(
        targetDrone.gun_image_charging,
        angle
    )

    set_cached_image_rotation(
        targetDrone.gun_image_on,
        angle
    )
end

local function has_incoming_hostile_projectile(
    shipManager
)
    local spaceManager = Hyperspace.App.world.space

    if not spaceManager then
        return false
    end

    for projectile in vter(spaceManager.projectiles) do
        if projectile
            and projectile.ownerId ~= shipManager.iShipId
            and projectile.destinationSpace == shipManager.iShipId
            and projectile.currentSpace == shipManager.iShipId
            and projectile.lifespan > 0 then
            return true
        end
    end

    return false
end

local function legs_are_operational(crew)
    if not crew or crew.bDead then
        return false
    end

    -- The debug results show that Functional() follows the actual
    -- TERRAN_GOLIATH device power state:
    --
    --     powered   -> Functional() == true
    --     unpowered -> Functional() == false
    --
    -- crewAnim.status does not change when this device is depowered, so it
    -- must not be used as the primary power test.
    local functional = false

    local success, result = pcall(function()
        return crew:Functional()
    end)

    if success then
        functional = result
    end

    local stunTime =
        crew.fStunTime or 0

    return functional
        and stunTime <= 0
end

local function compact_bool(value)
    if value == nil then
        return "?"
    end

    return value and "1" or "0"
end

local function safe_method_bool(object, methodName)
    if not object then
        return nil
    end

    local success, value = pcall(function()
        local method = object[methodName]

        if not method then
            return nil
        end

        return method(object)
    end)

    if not success then
        return nil
    end

    return value
end

local function compact_number(value)
    if type(value) ~= "number" then
        return "?"
    end

    return string.format("%.1f", value)
end

local function get_device_power_snapshot(shipManager)
    if not shipManager
        or not shipManager.droneSystem then

        return "device=missing"
    end

    local entries = {}

    local success = pcall(function()
        for drone in vter(
            shipManager.droneSystem.drones
        ) do
            if drone.blueprint
                and drone.blueprint.name
                    == "TERRAN_GOLIATH" then

                table.insert(
                    entries,
                    "id="
                    .. tostring(drone.selfId)
                    .. " p="
                    .. compact_bool(
                        drone.powered
                    )
                    .. "/"
                    .. compact_bool(
                        safe_method_bool(
                            drone,
                            "GetPowered"
                        )
                    )
                    .. " d="
                    .. compact_bool(
                        safe_method_bool(
                            drone,
                            "GetDeployed"
                        )
                    )
                )
            end
        end
    end)

    if not success then
        return "device=scan_error"
    end

    if #entries == 0 then
        return "device=none"
    end

    table.sort(entries)

    return table.concat(entries, " | ")
end

local function print_compact_power_debug(
    shipManager
)
    if not DEBUG_POWER_STATE
        or not shipManager then

        return
    end

    local deviceSnapshot =
        get_device_power_snapshot(
            shipManager
        )

    if deviceSnapshot
        ~= lastDevicePowerDebug then

        lastDevicePowerDebug =
            deviceSnapshot

        debug_print(
            "DEVICE "
            .. deviceSnapshot
        )
    end

    local currentCrewIds = {}

    for crewId, pair in pairs(
        activePairs
    ) do
        currentCrewIds[crewId] = true

        local crew = pair.crew
        local turret = pair.drone

        local functional =
            safe_method_bool(
                crew,
                "Functional"
            )

        local legsDecision =
            legs_are_operational(crew)

        local snapshot =
            "c="
            .. tostring(crewId)
            .. " anim="
            .. tostring(
                crew
                and crew.crewAnim
                and crew.crewAnim.status
                or "?"
            )
            .. " stun="
            .. compact_number(
                crew
                and crew.fStunTime
            )
            .. " func="
            .. compact_bool(
                functional
            )
            .. " legs="
            .. compact_bool(
                legsDecision
            )
            .. " turret="
            .. compact_bool(
                turret
                and turret.powered
            )
            .. "/"
            .. compact_bool(
                safe_method_bool(
                    turret,
                    "GetPowered"
                )
            )

        if lastPairPowerDebug[
            crewId
        ] ~= snapshot then

            lastPairPowerDebug[
                crewId
            ] = snapshot

            debug_print(snapshot)
        end
    end

    for crewId, _ in pairs(
        lastPairPowerDebug
    ) do
        if not currentCrewIds[crewId] then
            lastPairPowerDebug[
                crewId
            ] = nil

            debug_print(
                "c="
                .. tostring(crewId)
                .. " pair=removed"
            )
        end
    end
end


local function update_turret_power_from_legs(
    crew,
    defenseDrone
)
    if not defenseDrone then
        return false
    end

    local shouldBePowered =
        legs_are_operational(crew)

    local turretState = userdata_table(
        defenseDrone,
        TURRET_STATE_KEY
    )

    if shouldBePowered then
        -- The companion does not consume separate drone-system power.
        defenseDrone.powerRequired = 0

        -- Reassert deployment and power when recovering from a stun or from
        -- the legs being switched off. SetInstantPowered is wrapped because
        -- older Hyperspace builds may not expose it to Lua.
        defenseDrone:SetDeployed(true)
        defenseDrone:SetPowered(true)

        pcall(function()
            defenseDrone:SetInstantPowered()
        end)

        defenseDrone.powered = true
    else
        defenseDrone:SetPowered(false)
        defenseDrone.powered = false
        defenseDrone.bFire = false
    end

    turretState.linkedPowered =
        shouldBePowered


    return shouldBePowered
end

local function position_turret_with_crew(
    crew,
    defenseDrone
)
    local crewPosition = crew:GetLocation()

    local followPosition = Hyperspace.Pointf(
        crewPosition.x + FOLLOW_OFFSET_X,
        crewPosition.y + FOLLOW_OFFSET_Y
    )

    defenseDrone:SetCurrentLocation(followPosition)

    defenseDrone.destinationLocation = Hyperspace.Pointf(
        followPosition.x,
        followPosition.y
    )

    defenseDrone.speedVector = Hyperspace.Pointf(0, 0)
end

local function mark_turret_pair(
    defenseDrone,
    crew
)
    local crewId = crew.extend.selfId

    local state = userdata_table(
        defenseDrone,
        TURRET_STATE_KEY
    )

    state.managed = true
    state.crewId = crewId
    state.replacing = false
    state.retired = false
    state.linkedPowered = nil

    local crewState = userdata_table(
        crew,
        CREW_STATE_KEY
    )

    crewState.companionInitialized = true
    crewState.turretId = defenseDrone.selfId
end

local function retire_turret(defenseDrone)
    local state = userdata_table(
        defenseDrone,
        TURRET_STATE_KEY
    )

    -- Keep the turret marked as managed/retired until the engine removes it.
    -- Clearing the pairing first can turn a lingering turret into an
    -- unmarked turret that another Goliath is allowed to adopt.
    state.managed = true
    state.replacing = false
    state.retired = true

    defenseDrone.bFire = false
    defenseDrone.powered = false

    -- false means that this is a permanent deletion rather than a destroyed
    -- inventory drone waiting to be rebuilt.
    defenseDrone:SetDestroyed(true, false)
end

local function spawn_companion_turret(
    shipManager,
    crew,
    templateDrone,
    replacementReason
)
    local droneBlueprint =
        Hyperspace.Blueprints:GetDroneBlueprint(
            FOLLOW_DRONE_BLUEPRINT
        )

    if not droneBlueprint then
        error_print(
            "Could not find drone blueprint "
            .. FOLLOW_DRONE_BLUEPRINT
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

        if templateDrone then
            drone:SetCurrentLocation(
                Hyperspace.Pointf(
                    templateDrone.currentLocation.x,
                    templateDrone.currentLocation.y
                )
            )

            drone.destinationLocation =
                Hyperspace.Pointf(
                    templateDrone.currentLocation.x,
                    templateDrone.currentLocation.y
                )

            drone.speedVector =
                Hyperspace.Pointf(0, 0)

            copy_native_orientation(
                templateDrone,
                drone
            )
        else
            position_turret_with_crew(
                crew,
                drone
            )

            local facingState =
                get_facing_state(crew)

            local angle =
                facingState.idleAngle
                + NATIVE_ANGLE_OFFSET

            drone.current_angle = angle
            drone.aimingAngle = angle
            drone.lastAimingAngle = angle
            drone.desiredAimingAngle = angle

            set_cached_image_rotation(
                drone.gun_image_off,
                angle
            )

            set_cached_image_rotation(
                drone.gun_image_charging,
                angle
            )

            set_cached_image_rotation(
                drone.gun_image_on,
                angle
            )
        end

        mark_turret_pair(
            drone,
            crew
        )

        update_turret_power_from_legs(
            crew,
            drone
        )

        return drone
    end)

    if not success then
        error_print(
            "Failed to summon "
            .. FOLLOW_DRONE_BLUEPRINT
            .. ": "
            .. tostring(defenseDrone)
        )

        return nil
    end

    if DEBUG_SPAWNS
        and replacementReason ~= "collision"
        and replacementReason ~= "destroyed" then

        debug_print(
            "Summoned turret for crewId="
            .. tostring(crew.extend.selfId)
        )
    end

    return defenseDrone
end

local function find_nearest_unclaimed_turret(
    crew,
    liveTurrets,
    usedDroneIds
)
    local crewPosition = crew:GetLocation()
    local nearestDrone = nil
    local nearestDistance = nil

    for _, drone in ipairs(liveTurrets) do
        if not usedDroneIds[drone.selfId] then
            local distance = distance_squared(
                crewPosition,
                drone.currentLocation
            )

            if nearestDistance == nil
                or distance < nearestDistance then
                nearestDrone = drone
                nearestDistance = distance
            end
        end
    end

    return nearestDrone
end

local function ship_is_destroyed(shipManager)
    if not shipManager then
        return true
    end

    if shipManager.bDestroyed then
        return true
    end

    local success, hullDestroyed = pcall(function()
        return shipManager.ship
            and shipManager.ship.hullIntegrity
            and shipManager.ship.hullIntegrity.first <= 0
    end)

    return success and hullDestroyed or false
end

local function remove_all_goliath_turrets(
    shipManager
)
    if not shipManager then
        activePairs = {}
        return
    end

    for defenseDrone in vter(
        shipManager.spaceDrones
    ) do
        if defenseDrone
            and defenseDrone.blueprint
            and defenseDrone.blueprint.name
                == FOLLOW_DRONE_BLUEPRINT
            and not defenseDrone.bDead then

            local turretState = userdata_table(
                defenseDrone,
                TURRET_STATE_KEY
            )

            -- Keep it permanently excluded from pairing while the engine
            -- finishes deleting it.
            turretState.managed = true
            turretState.retired = true
            turretState.replacing = false

            defenseDrone.bFire = false
            defenseDrone.powered = false

            pcall(function()
                defenseDrone:SetPowered(false)
            end)

            -- Permanent deletion: do not leave a rebuildable inventory drone.
            defenseDrone:SetDestroyed(
                true,
                false
            )
        end
    end

    activePairs = {}
end

local function synchronize_goliath_pairs(
    shipManager
)
    local crews, crewsById =
        collect_active_goliaths(shipManager)

    local managedLiveByCrewId = {}
    local unmarkedLiveTurrets = {}
    local duplicateOrOrphanedTurrets = {}

    for drone in vter(shipManager.spaceDrones) do
        if is_live_goliath_turret(
            drone,
            shipManager
        ) then
            local turretState = userdata_table(
                drone,
                TURRET_STATE_KEY
            )

            local assignedCrew =
                turretState.managed
                and crewsById[turretState.crewId]
                or nil

            if turretState.retired then
                -- A deletion may take until the engine finishes this frame.
                -- Never allow a retired turret back into the pairing pool.
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
            elseif turretState.managed then
                -- This turret's recorded Goliath is no longer active.
                table.insert(
                    duplicateOrOrphanedTurrets,
                    drone
                )
            else
                -- Only genuinely unmarked turrets may be adopted. A turret
                -- managed by another Goliath is never eligible.
                table.insert(
                    unmarkedLiveTurrets,
                    drone
                )
            end
        end
    end

    local usedDroneIds = {}
    local newPairs = {}

    -- Reserve all existing valid pairs before processing unpaired Goliaths.
    -- This prevents one Goliath from briefly taking another Goliath's turret.
    for _, drone in pairs(
        managedLiveByCrewId
    ) do
        usedDroneIds[drone.selfId] = true
    end

    for _, crew in ipairs(crews) do
        local crewId = crew.extend.selfId

        local crewState = userdata_table(
            crew,
            CREW_STATE_KEY
        )

        local defenseDrone =
            managedLiveByCrewId[crewId]

        if defenseDrone then
            -- Refresh the crew-side state after loading a save.
            mark_turret_pair(
                defenseDrone,
                crew
            )
        elseif not crewState.companionInitialized then
            -- Adoption is only used for old saves or transition testing.
            defenseDrone =
                find_nearest_unclaimed_turret(
                    crew,
                    unmarkedLiveTurrets,
                    usedDroneIds
                )

            if defenseDrone then
                mark_turret_pair(
                    defenseDrone,
                    crew
                )
            else
                defenseDrone =
                    spawn_companion_turret(
                        shipManager,
                        crew,
                        nil,
                        "initial"
                    )
            end
        end

        -- No destruction respawn occurs here. Projectile destruction is
        -- prevented by DRONE_COLLISION. A missing managed turret cannot
        -- claim another Goliath's turret or create a replacement.
        if defenseDrone then
            usedDroneIds[defenseDrone.selfId] =
                true

            position_turret_with_crew(
                crew,
                defenseDrone
            )

            update_turret_power_from_legs(
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
        if is_live_goliath_turret(
            drone,
            shipManager
        ) then
            retire_turret(drone)
        end
    end

    activePairs = newPairs
end

local function force_native_idle_facing(
    shipManager,
    crew,
    defenseDrone
)
    if not is_active_goliath(
        crew,
        shipManager
    ) then
        return
    end

    if not is_live_goliath_turret(
        defenseDrone,
        shipManager
    ) then
        return
    end

    if not update_turret_power_from_legs(
        crew,
        defenseDrone
    ) then
        return
    end

    local state = get_facing_state(crew)

    if PRESERVE_NATIVE_PROJECTILE_TARGETING
        and has_incoming_hostile_projectile(
            shipManager
        ) then
        return
    end

    local angle =
        state.idleAngle
        + NATIVE_ANGLE_OFFSET

    defenseDrone.current_angle = angle
    defenseDrone.aimingAngle = angle
    defenseDrone.lastAimingAngle = angle
    defenseDrone.desiredAimingAngle = angle

    set_cached_image_rotation(
        defenseDrone.gun_image_off,
        angle
    )

    set_cached_image_rotation(
        defenseDrone.gun_image_charging,
        angle
    )

    set_cached_image_rotation(
        defenseDrone.gun_image_on,
        angle
    )

    defenseDrone.bFire = false
    renderApplyCount = renderApplyCount + 1
end

local function apply_all_native_facing()
    local success, errorMessage = pcall(function()
        local shipManager =
            Hyperspace.ships.player

        if not shipManager
            or ship_is_destroyed(
                shipManager
            ) then

            return
        end

        for _, pair in pairs(activePairs) do
            force_native_idle_facing(
                shipManager,
                pair.crew,
                pair.drone
            )
        end
    end)

    if not success
        and errorMessage ~= lastRenderError then

        lastRenderError = errorMessage

        error_print(
            "Render error: "
            .. tostring(errorMessage)
        )
    end
end

local function damage_connected_legs(crew)
    if not crew or crew.bDead then
        return
    end

    crew:DirectModifyHealth(
        -TURRET_HIT_DAMAGE
    )

    -- Debug:
    -- debug_print(
    --     "Transferred "
    --     .. tostring(TURRET_HIT_DAMAGE)
    --     .. " damage to crewId="
    --     .. tostring(crew.extend.selfId)
    --     .. "; health="
    --     .. tostring(crew.health.first)
    -- )
end

script.on_internal_event(
    Defines.InternalEvents.ON_TICK,
    function()
        local shipManager =
            Hyperspace.ships.player

        if not shipManager then
            activePairs = {}
            return
        end

        if ship_is_destroyed(
            shipManager
        ) then
            remove_all_goliath_turrets(
                shipManager
            )

            return
        end

        synchronize_goliath_pairs(
            shipManager
        )

        local incomingProjectile =
            has_incoming_hostile_projectile(
                shipManager
            )

        for _, pair in pairs(activePairs) do
            position_turret_with_crew(
                pair.crew,
                pair.drone
            )

            local turretPowered =
                update_turret_power_from_legs(
                    pair.crew,
                    pair.drone
                )

            local state =
                get_facing_state(pair.crew)

            if not turretPowered
                or not incomingProjectile then

                pair.drone.bFire = false
            end

            if DEBUG_NATIVE_FACING then
                pair.debugDirection =
                    state.directionName
            end
        end

        debugTickCounter =
            debugTickCounter + 1

        if DEBUG_NATIVE_FACING
            and debugTickCounter
                >= DEBUG_INTERVAL_TICKS then

            debugTickCounter = 0

            local pairCount = 0

            for crewId, pair in pairs(
                activePairs
            ) do
                pairCount = pairCount + 1

                local state =
                    get_facing_state(
                        pair.crew
                    )

                debug_print(
                    "crewId="
                    .. tostring(crewId)
                    .. " turretId="
                    .. tostring(
                        pair.drone.selfId
                    )
                    .. " direction="
                    .. tostring(
                        state.directionName
                    )
                    .. " angle="
                    .. tostring(
                        state.idleAngle
                        + NATIVE_ANGLE_OFFSET
                    )
                )
            end

            debug_print(
                "pairCount="
                .. tostring(pairCount)
                .. " renderApplies="
                .. tostring(
                    renderApplyCount
                )
            )

            renderApplyCount = 0
        end

        print_compact_power_debug(
            shipManager
        )
    end
)

-- Protect the paired turret from hostile projectile damage and transfer
-- 45 health damage to the connected Goliath legs instead.
script.on_internal_event(
    Defines.InternalEvents.DRONE_COLLISION,
    function(
        defenseDrone,
        projectile,
        damage,
        response
    )
        local shipManager =
            Hyperspace.ships.player

        if not shipManager
            or not is_live_goliath_turret(
                defenseDrone,
                shipManager
            ) then
            return Defines.Chain.CONTINUE
        end

        if projectile
            and projectile.ownerId
                == shipManager.iShipId then
            return Defines.Chain.CONTINUE
        end

        local turretState = userdata_table(
            defenseDrone,
            TURRET_STATE_KEY
        )

        if not turretState.managed
            or turretState.crewId == nil then
            return Defines.Chain.CONTINUE
        end

        local crew =
            find_active_goliath_by_id(
                shipManager,
                turretState.crewId
            )

        if not crew then
            return Defines.Chain.CONTINUE
        end

        damage_connected_legs(crew)

        -- PREEMPT prevents the normal collision damage from being applied
        -- to the turret. The projectile keeps its normal collision response.
        return Defines.Chain.PREEMPT
    end
)

script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    function(shipManager)
        if shipManager
            and shipManager.iShipId == 0
            and ship_is_destroyed(
                shipManager
            ) then

            remove_all_goliath_turrets(
                shipManager
            )
        end
    end
)

-- Move only the native health overlay for Goliath crew drones. The render
-- event wraps CrewMember:OnRenderHealth(), so the matrix translation affects
-- the health bar without moving the crew sprite or attached turret.
script.on_render_event(
    Defines.RenderEvents.CREW_MEMBER_HEALTH,
    function(crew)
        if crew
            and crew.type == FOLLOW_CREW_TYPE then

            Graphics.CSurface.GL_PushMatrix()

            Graphics.CSurface.GL_Translate(
                HEALTH_BAR_OFFSET_X,
                HEALTH_BAR_OFFSET_Y,
                0
            )
        end
    end,
    function(crew)
        if crew
            and crew.type == FOLLOW_CREW_TYPE then

            Graphics.CSurface.GL_PopMatrix()
        end
    end
)

script.on_render_event(
    Defines.RenderEvents.LAYER_PLAYER,
    function()
        apply_all_native_facing()
    end,
    function() end
)

script.on_render_event(
    Defines.RenderEvents.SHIP,
    function(ship)
        if ship and ship.iShipId == 0 then
            apply_all_native_facing()
        end
    end,
    function() end
)