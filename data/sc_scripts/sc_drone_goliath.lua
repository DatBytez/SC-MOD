local vter = mods.multiverse.vter
local userdata_table = mods.multiverse.userdata_table

local FOLLOW_CREW_TYPE = "terran_goliath"
local FOLLOW_DRONE_BLUEPRINT = "TERRAN_GOLIATH_T"

local FOLLOW_OFFSET_X = 3
local FOLLOW_OFFSET_Y = 0

-- Distance from the native defense drone to the artificial idle look point.
local IDLE_LOOK_DISTANCE = 100

-- Ignore tiny coordinate changes that are not deliberate crew movement.
local MOVEMENT_EPSILON = 0.1

-- These values use the direction mapping that worked with the replacement
-- turret image:
--
--     UP    = 0
--     RIGHT = 90
--     DOWN  = 180
--     LEFT  = 270
--
-- Adjust this only if the restored native gun images use a different
-- unrotated orientation.
local NATIVE_ANGLE_OFFSET = -90

-- Leave native projectile targeting untouched whenever a hostile projectile
-- is present in the player's space.
local PRESERVE_NATIVE_PROJECTILE_TARGETING = true

-- In-game troubleshooting messages.
local DEBUG_NATIVE_FACING = true
local DEBUG_INTERVAL_TICKS = 120

local debugTickCounter = 0
local renderApplyCount = 0
local lastStatus = nil
local lastRenderError = nil

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

local function game_print(message)
    if DEBUG_NATIVE_FACING then
        print("[GOLIATH NATIVE] " .. tostring(message))
    end
end

local function print_status_once(message)
    if message ~= lastStatus then
        lastStatus = message
        game_print(message)
    end
end

configure_print_display()
game_print("Native defense-drone facing test loaded.")

local function find_follow_crew(shipManager)
    for crew in vter(shipManager.vCrewList) do
        if crew.type == FOLLOW_CREW_TYPE
            and not crew.bDead
            and crew.currentShipId == shipManager.iShipId then
            return crew
        end
    end

    return nil
end

local function find_follow_drone(shipManager)
    for drone in vter(shipManager.spaceDrones) do
        if drone.blueprint
            and drone.blueprint.name == FOLLOW_DRONE_BLUEPRINT
            and drone.blueprint.typeName == "DEFENSE"
            and drone.deployed
            and not drone.bDead
            and drone.currentSpace == shipManager.iShipId then
            return drone
        end
    end

    return nil
end

local function has_incoming_hostile_projectile(shipManager)
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
    if directionX > 0 then
        return 90
    elseif directionY > 0 then
        return 180
    elseif directionX < 0 then
        return 270
    else
        return 0
    end
end

local function get_facing_state(crew)
    local state = userdata_table(
        crew,
        "mods.sc.goliathNativeFacingState"
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

        game_print("Facing state initialized.")
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

        local newDirectionName = direction_name(
            state.directionX,
            state.directionY
        )

        state.idleAngle = direction_angle(
            state.directionX,
            state.directionY
        )

        if newDirectionName ~= state.directionName then
            state.directionName = newDirectionName

            game_print(
                "Leg direction="
                .. newDirectionName
                .. " idleAngle="
                .. tostring(state.idleAngle)
            )
        end
    end

    return state
end

local function set_cached_image_rotation(cachedImage, angle)
    if not cachedImage then
        return
    end

    -- SetRotation rebuilds the cached primitive with the requested rotation.
    cachedImage:SetRotation(angle)

    -- Also assign the exposed field directly so the value can be checked
    -- through the in-game diagnostics.
    cachedImage.rotation = angle
end

local function force_native_idle_facing(
    shipManager,
    crew,
    defenseDrone,
    sourceName
)
    local state = get_facing_state(crew)

    if PRESERVE_NATIVE_PROJECTILE_TARGETING
        and has_incoming_hostile_projectile(shipManager) then
        return false, "COMBAT", state
    end

    local angle =
        state.idleAngle
        + NATIVE_ANGLE_OFFSET

    -- Do not assign targetLocation, pointTarget, or call
    -- UpdateAimingAngle with an artificial point. Those fields cause the
    -- defense drone to treat the idle direction as a real firing target.

    -- Apply the known four-direction mapping directly to every exposed
    -- SpaceDrone aiming field immediately before rendering.
    defenseDrone.current_angle = angle
    defenseDrone.aimingAngle = angle
    defenseDrone.lastAimingAngle = angle
    defenseDrone.desiredAimingAngle = angle

    -- Apply the same value to each possible native defense-drone gun image.
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

    -- Prevent a stale firing instruction from continuing while idle.
    -- Native targeting can set bFire normally again when a real projectile
    -- appears and the idle override is skipped.
    defenseDrone.bFire = false

    renderApplyCount = renderApplyCount + 1

    return true, sourceName, state
end

local function apply_native_facing_before_render(sourceName)
    local success, errorMessage = pcall(function()
        local shipManager = Hyperspace.ships.player

        if not shipManager then
            return
        end

        local crew = find_follow_crew(shipManager)
        local defenseDrone = find_follow_drone(shipManager)

        if not crew or not defenseDrone then
            return
        end

        force_native_idle_facing(
            shipManager,
            crew,
            defenseDrone,
            sourceName
        )
    end)

    if not success
        and errorMessage ~= lastRenderError then

        lastRenderError = errorMessage

        game_print(
            sourceName
            .. " render error: "
            .. tostring(errorMessage)
        )
    end
end

script.on_internal_event(
    Defines.InternalEvents.ON_TICK,
    function()
        local shipManager = Hyperspace.ships.player

        if not shipManager then
            print_status_once("Player ship not found.")
            return
        end

        local crew = find_follow_crew(shipManager)

        if not crew then
            print_status_once(
                "Crew type "
                .. FOLLOW_CREW_TYPE
                .. " not found."
            )
            return
        end

        local defenseDrone = find_follow_drone(shipManager)

        if not defenseDrone then
            print_status_once(
                "Deployed defense drone "
                .. FOLLOW_DRONE_BLUEPRINT
                .. " not found."
            )
            return
        end

        print_status_once("Crew and defense drone found.")

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

        local state = get_facing_state(crew)
        local incomingProjectile =
            has_incoming_hostile_projectile(shipManager)

        -- Clear firing during idle during the game-loop phase as well.
        if not incomingProjectile then
            defenseDrone.bFire = false
        end

        debugTickCounter = debugTickCounter + 1

        if DEBUG_NATIVE_FACING
            and debugTickCounter >= DEBUG_INTERVAL_TICKS then

            debugTickCounter = 0

            local incoming = incomingProjectile

            game_print(
                "direction="
                .. tostring(state.directionName)
                .. " idleAngle="
                .. tostring(
                    state.idleAngle
                    + NATIVE_ANGLE_OFFSET
                )
                .. " incoming="
                .. tostring(incoming)
                .. " bFire="
                .. tostring(defenseDrone.bFire)
                .. " renderApplies="
                .. tostring(renderApplyCount)
            )

            game_print(
                "native current="
                .. tostring(defenseDrone.current_angle)
                .. " aiming="
                .. tostring(defenseDrone.aimingAngle)
                .. " desired="
                .. tostring(defenseDrone.desiredAimingAngle)
                .. " gunOnRotation="
                .. tostring(
                    defenseDrone.gun_image_on
                    and defenseDrone.gun_image_on.rotation
                )
            )

            renderApplyCount = 0
        end
    end
)

-- Apply after all normal game-loop aiming updates but immediately before
-- the player rendering sequence begins.
script.on_render_event(
    Defines.RenderEvents.LAYER_PLAYER,
    function()
        apply_native_facing_before_render(
            "LAYER_PLAYER"
        )
    end,
    function() end
)

-- Apply again at the start of the player's Ship render. This gives us a
-- second timing point inside the player-render sequence without drawing a
-- replacement image.
script.on_render_event(
    Defines.RenderEvents.SHIP,
    function(ship)
        if ship and ship.iShipId == 0 then
            apply_native_facing_before_render(
                "SHIP"
            )
        end
    end,
    function() end
)