local vter = mods.multiverse.vter
local userdata_table = mods.multiverse.userdata_table

local FOLLOW_CREW_TYPE = "terran_goliath"
local FOLLOW_DRONE_BLUEPRINT = "TERRAN_GOLIATH_T"

local FOLLOW_OFFSET_X = 3
local FOLLOW_OFFSET_Y = 0

-- Position of the manually rendered turret relative to the crew position.
local HEAD_RENDER_OFFSET_X = 0
local HEAD_RENDER_OFFSET_Y = 0

-- Apply this to every angle if the image's default orientation is different.
-- Try 90, 180, 270, or -90 if the head appears rotated consistently.
local HEAD_ROTATION_OFFSET = 0

-- The native defense-drone gun images are now transparent.
-- This separate image is rendered by Lua.
local HEAD_IMAGE_PATH = "ship/drones/terran_goliath_turret.png"

local MOVEMENT_EPSILON = 0.1

local DEBUG_RENDER = true
local DEBUG_INTERVAL_TICKS = 120

local debugTickCounter = 0
local lastStatus = nil
local headTexture = nil
local renderCallbackConfirmed = false
local renderErrorPrinted = false
local textureFailurePrinted = false

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
game_print("Corrected custom head-render script loaded.")

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
    -- These values assume that the unrotated turret image points right.
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

local function load_head_texture()
    if headTexture then
        return headTexture
    end

    local success, texture = pcall(function()
        return Hyperspace.Resources:GetImageId(HEAD_IMAGE_PATH)
    end)

    if success
        and texture
        and texture.width
        and texture.height
        and texture.width > 1
        and texture.height > 1 then

        headTexture = texture

        game_print(
            "Loaded "
            .. HEAD_IMAGE_PATH
            .. " size="
            .. tostring(texture.width)
            .. "x"
            .. tostring(texture.height)
        )

        return headTexture
    end

    if not textureFailurePrinted then
        textureFailurePrinted = true

        game_print(
            "Unable to load "
            .. HEAD_IMAGE_PATH
            .. "; success="
            .. tostring(success)
            .. " texture="
            .. tostring(texture)
        )
    end

    return nil
end

local function get_render_angle(
    shipManager,
    defenseDrone,
    state
)
    if has_incoming_hostile_projectile(shipManager) then
        -- The invisible native gun still updates this angle while targeting.
        if type(defenseDrone.current_angle) == "number" then
            return defenseDrone.current_angle, "COMBAT"
        end
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

        load_head_texture()

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

-- IMPORTANT:
-- Defines.RenderEvents.SHIP passes a Ship object, not a ShipManager.
-- Retrieve the real ShipManager before accessing vCrewList or spaceDrones.
script.on_render_event(
    Defines.RenderEvents.SHIP,
    function() end,
    function(ship)
        if not ship or ship.iShipId ~= 0 then
            return
        end

        local shipManager = Hyperspace.ships.player

        if not shipManager then
            return
        end

        if not renderCallbackConfirmed then
            renderCallbackConfirmed = true
            game_print("SHIP render callback reached successfully.")
        end

        local crew = find_follow_crew(shipManager)
        local defenseDrone = find_follow_drone(shipManager)

        if not crew or not defenseDrone then
            return
        end

        local texture = load_head_texture()

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

        local angle, mode = get_render_angle(
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

        local success, errorMessage = pcall(function()
            Graphics.CSurface.GL_PushMatrix()

            Graphics.CSurface.GL_Translate(
                centerX,
                centerY,
                0
            )

            Graphics.CSurface.GL_BlitImage(
                texture,
                -texture.width / 2,
                -texture.height / 2,
                texture.width,
                texture.height,
                angle,
                Graphics.GL_Color(1, 1, 1, 1),
                false
            )

            Graphics.CSurface.GL_PopMatrix()
        end)

        if not success and not renderErrorPrinted then
            renderErrorPrinted = true
            game_print(
                "Render error: "
                .. tostring(errorMessage)
            )
        end
    end
)