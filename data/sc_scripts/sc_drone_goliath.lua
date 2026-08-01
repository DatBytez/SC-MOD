local vter = mods.multiverse.vter
local userdata_table = mods.multiverse.userdata_table

local FOLLOW_CREW_TYPE = "terran_goliath"
local FOLLOW_DRONE_BLUEPRINT = "TERRAN_GOLIATH_T"

local FOLLOW_OFFSET_X = 3
local FOLLOW_OFFSET_Y = 0

-- Optional adjustment applied to every rendered head angle.
-- Leave at 0 initially. Change this if the image appears consistently
-- 90, 180, or 270 degrees away from the intended direction.
local HEAD_ROTATION_OFFSET = 0

-- Optional final positioning adjustment for the manually rendered head.
local HEAD_RENDER_OFFSET_X = 0
local HEAD_RENDER_OFFSET_Y = 0

-- The filename supplied by the user. The script also tries paths derived
-- automatically from the drone blueprint's <droneImage> value.
local PREFERRED_HEAD_IMAGE =
    "ship/drones/terran_goliath_turret.png"

local IDLE_LOOK_DISTANCE = 100
local MOVEMENT_EPSILON = 0.1

local DEBUG_RENDER = true
local DEBUG_INTERVAL_TICKS = 120

local debugTickCounter = 0
local lastStatus = nil
local headTexture = nil
local headTexturePath = nil
local textureSearchFinished = false

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
    if DEBUG_RENDER then
        print("[GOLIATH HEAD] " .. tostring(message))
    end
end

local function print_status_once(message)
    if message ~= lastStatus then
        lastStatus = message
        game_print(message)
    end
end

configure_print_display()
game_print("Custom head-render script loaded.")

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

local function fallback_direction_angle(directionX, directionY)
    -- These values assume the unrotated gun image points right.
    -- HEAD_ROTATION_OFFSET can correct a different base orientation.
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

local function update_facing_state(crew)
    local state = userdata_table(
        crew,
        "mods.sc.goliathCustomHeadState"
    )

    local position = crew:GetLocation()

    if not state.initialized then
        state.initialized = true
        state.lastX = position.x
        state.lastY = position.y
        state.directionX = 0
        state.directionY = 1
        state.directionName = "DOWN"
        state.idleAngle = fallback_direction_angle(0, 1)

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

        state.idleAngle = fallback_direction_angle(
            state.directionX,
            state.directionY
        )

        if newDirectionName ~= state.directionName then
            state.directionName = newDirectionName

            game_print(
                "Leg direction: "
                .. newDirectionName
                .. "; fallback angle="
                .. tostring(state.idleAngle)
            )
        end
    end

    return state
end

local function hide_native_gun(defenseDrone)
    -- The original defense-drone renderer is what keeps overriding the
    -- requested rotation, so hide all of its possible gun-image states.
    if defenseDrone.gun_image_off then
        defenseDrone.gun_image_off:SetScale(0, 0)
    end

    if defenseDrone.gun_image_charging then
        defenseDrone.gun_image_charging:SetScale(0, 0)
    end

    if defenseDrone.gun_image_on then
        defenseDrone.gun_image_on:SetScale(0, 0)
    end
end

local function try_load_texture(path)
    if not path or path == "" then
        return nil
    end

    local success, texture = pcall(function()
        return Hyperspace.Resources:GetImageId(path)
    end)

    if success
        and texture
        and texture.width
        and texture.height
        and texture.width > 1
        and texture.height > 1 then
        return texture
    end

    return nil
end

local function load_head_texture(defenseDrone)
    if textureSearchFinished then
        return headTexture
    end

    textureSearchFinished = true

    local candidates = {
        PREFERRED_HEAD_IMAGE
    }

    if defenseDrone.blueprint
        and defenseDrone.blueprint.droneImage
        and defenseDrone.blueprint.droneImage ~= "" then

        local imageBase = defenseDrone.blueprint.droneImage

        table.insert(
            candidates,
            "ship/drones/" .. imageBase .. "_gun_on.png"
        )

        table.insert(
            candidates,
            "ship/drones/" .. imageBase .. "_gun.png"
        )

        table.insert(
            candidates,
            "ship/drones/" .. imageBase .. "_gun_charged.png"
        )
    end

    for _, path in ipairs(candidates) do
        local texture = try_load_texture(path)

        if texture then
            headTexture = texture
            headTexturePath = path

            game_print(
                "Using head image "
                .. path
                .. " ("
                .. tostring(texture.width)
                .. "x"
                .. tostring(texture.height)
                .. ")."
            )

            return headTexture
        end
    end

    game_print(
        "Could not load a head image. Checked: "
        .. table.concat(candidates, ", ")
    )

    return nil
end

local function calculate_idle_angle(
    defenseDrone,
    state
)
    local targetPoint = Hyperspace.Pointf(
        defenseDrone.currentLocation.x
            + state.directionX * IDLE_LOOK_DISTANCE,

        defenseDrone.currentLocation.y
            + state.directionY * IDLE_LOOK_DISTANCE
    )

    -- Use FTL's own angle calculation when available, but store the result
    -- for our separate render pass instead of relying on the native gun draw.
    local success, calculatedAngle = pcall(function()
        return defenseDrone:UpdateAimingAngle(
            targetPoint,
            1,
            1
        )
    end)

    if success and type(calculatedAngle) == "number" then
        state.idleAngle = calculatedAngle
    elseif defenseDrone.desiredAimingAngle
        and type(defenseDrone.desiredAimingAngle) == "number" then
        state.idleAngle = defenseDrone.desiredAimingAngle
    else
        state.idleAngle = fallback_direction_angle(
            state.directionX,
            state.directionY
        )
    end

    return state.idleAngle
end

local function get_render_angle(
    shipManager,
    defenseDrone,
    state
)
    if has_incoming_hostile_projectile(shipManager) then
        -- Preserve the defense drone's native projectile-tracking direction.
        return defenseDrone.current_angle or state.idleAngle, "COMBAT"
    end

    return state.idleAngle, "IDLE"
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

        local state = update_facing_state(crew)

        if not has_incoming_hostile_projectile(shipManager) then
            calculate_idle_angle(
                defenseDrone,
                state
            )
        end

        hide_native_gun(defenseDrone)
        load_head_texture(defenseDrone)

        debugTickCounter = debugTickCounter + 1

        if DEBUG_RENDER
            and debugTickCounter >= DEBUG_INTERVAL_TICKS then
            debugTickCounter = 0

            local renderAngle, mode = get_render_angle(
                shipManager,
                defenseDrone,
                state
            )

            game_print(
                "mode="
                .. mode
                .. " direction="
                .. tostring(state.directionName)
                .. " renderAngle="
                .. tostring(renderAngle)
                .. " nativeAngle="
                .. tostring(defenseDrone.current_angle)
            )
        end
    end
)

-- Draw the head ourselves after the ship has finished rendering.
-- This bypasses the defense drone's native gun renderer.
script.on_render_event(
    Defines.RenderEvents.SHIP,
    function() end,
    function(shipManager)
        if not shipManager
            or shipManager.iShipId ~= 0 then
            return
        end

        local crew = find_follow_crew(shipManager)
        local defenseDrone = find_follow_drone(shipManager)

        if not crew or not defenseDrone then
            return
        end

        local texture = load_head_texture(defenseDrone)

        if not texture then
            return
        end

        local state = userdata_table(
            crew,
            "mods.sc.goliathCustomHeadState"
        )

        if not state.initialized then
            return
        end

        local angle = get_render_angle(
            shipManager,
            defenseDrone,
            state
        )

        angle = angle + HEAD_ROTATION_OFFSET

        local crewPosition = crew:GetLocation()

        local centerX =
            crewPosition.x
            + FOLLOW_OFFSET_X
            + HEAD_RENDER_OFFSET_X

        local centerY =
            crewPosition.y
            + FOLLOW_OFFSET_Y
            + HEAD_RENDER_OFFSET_Y

        local drawX = centerX - texture.width / 2
        local drawY = centerY - texture.height / 2

        Graphics.CSurface.GL_BlitImage(
            texture,
            drawX,
            drawY,
            texture.width,
            texture.height,
            angle,
            Graphics.GL_Color(1, 1, 1, 1),
            false
        )
    end
)