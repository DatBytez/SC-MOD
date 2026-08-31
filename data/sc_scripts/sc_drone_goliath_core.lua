--[[
DESCRIPTION: Shared core helpers and state for the Terran Goliath crew-drone system.
        - Tracks Goliath movement and idle facing.
        - Positions companion turrets with their connected Goliath.
        - Synchronizes companion-turret power with the Goliath legs.
DEPENDENCIES: Multiverse vter, userdata_table
]]

local vter = mods.multiverse.vter
local userdata_table = mods.multiverse.userdata_table

mods.sc = mods.sc or {}
mods.sc.goliath = mods.sc.goliath or {}

local goliath = mods.sc.goliath

goliath.FOLLOW_CREW_TYPE = "terran_goliath"
goliath.FOLLOW_DRONE_BLUEPRINT = "TERRAN_GOLIATH_T"

goliath.CREW_STATE_KEY = "mods.sc.goliathNativeFacingState"
goliath.TURRET_STATE_KEY = "mods.sc.goliathTurretCompanion"

local FOLLOW_OFFSET_X = 3
local FOLLOW_OFFSET_Y = 0
local MOVEMENT_EPSILON = 0.2

goliath.activePairsByShip =
    goliath.activePairsByShip or {
        [0] = {},
        [1] = {}
    }

function goliath.get_ship_manager(shipId)
    if shipId == 0 then
        return Hyperspace.ships.player
    elseif shipId == 1 then
        return Hyperspace.ships.enemy
    end

    return nil
end

function goliath.get_active_pairs(shipManager)
    return goliath.activePairsByShip[
        shipManager.iShipId
    ]
end

function goliath.set_active_pairs(
    shipManager,
    pairs
)
    goliath.activePairsByShip[
        shipManager.iShipId
    ] = pairs
end

function goliath.error_print(message)
    print("[GOLIATH ERROR] " .. tostring(message))
end

function goliath.is_active_goliath(crew, shipManager)
    return crew.type == goliath.FOLLOW_CREW_TYPE
        and not crew.bDead
        and crew.currentShipId == shipManager.iShipId
end

function goliath.is_live_goliath_turret(drone, shipManager)
    return drone.blueprint.name == goliath.FOLLOW_DRONE_BLUEPRINT
        and drone.currentSpace == shipManager.iShipId
        and drone.deployed
        and not drone.bDead
end

local function direction_angle(directionX, directionY)
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

function goliath.get_facing_state(crew)
    local state = userdata_table(
        crew,
        goliath.CREW_STATE_KEY
    )

    local position = crew:GetLocation()

    if not state.initialized then
        state.initialized = true

        state.lastX = position.x
        state.lastY = position.y

        state.directionX = 0
        state.directionY = 1
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

        state.idleAngle = direction_angle(
            state.directionX,
            state.directionY
        )
    end

    return state
end

function goliath.set_cached_image_rotation(
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

function goliath.has_incoming_hostile_projectile(
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
    -- Functional() follows the actual TERRAN_GOLIATH device power state.
    return crew:Functional()
        and crew.fStunTime <= 0
end

function goliath.update_turret_power_from_legs(
    crew,
    defenseDrone
)
    local shouldBePowered =
        legs_are_operational(crew)

    if shouldBePowered then
        defenseDrone.powerRequired = 0
        defenseDrone:SetDeployed(true)
        defenseDrone:SetPowered(true)

        defenseDrone:SetInstantPowered()
        defenseDrone.powered = true
    else
        defenseDrone:SetPowered(false)
        defenseDrone.powered = false
        defenseDrone.bFire = false
    end

    return shouldBePowered
end

function goliath.position_turret_with_crew(
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

function goliath.ship_is_destroyed(shipManager)
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
