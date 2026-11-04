--[[
DESCRIPTION: Tracks Terran Comsat drone IDs across deployment, destruction, and rebuild.
        - Shows each current Comsat's selfId and state.
        - Counts deployments observed for each selfId.
        - If the same selfId reaches deployment #2, that ID was reused after a rebuild.
DEPENDENCIES: None
]]

local TEXT_X = 20
local TEXT_Y = 165
local LINE_HEIGHT = 16
local FONT = 10
local MAX_EVENTS = 10

local COMSAT_BLUEPRINT = "TERRAN_COMSAT"

local observations = {
    [0] = {},
    [1] = {}
}

local recentEvents = {}

local function add_event(message)
    table.insert(recentEvents, 1, message)

    if #recentEvents > MAX_EVENTS then
        table.remove(recentEvents)
    end
end

local function get_state(drone)
    if drone.bDead then
        return "DEAD"
    elseif drone.deployed and drone.powered then
        return "ACTIVE"
    elseif drone.deployed then
        return "DEPLOYED/UNPOWERED"
    elseif drone.powered then
        return "POWERED"
    end

    return "READY"
end

local function ship_label(shipId)
    return shipId == 0 and "PLAYER" or "ENEMY"
end

local function track_comsat(shipId, drone)
    local droneId = drone.selfId
    local state = get_state(drone)
    local deployed = drone.deployed and not drone.bDead
    local record = observations[shipId][droneId]

    if not record then
        record = {
            state = state,
            wasDeployed = false,
            deployments = 0
        }

        observations[shipId][droneId] = record
        add_event(string.format("%s ID %s SEEN (%s)", ship_label(shipId), tostring(droneId), state))
    end

    if deployed and not record.wasDeployed then
        record.deployments = record.deployments + 1

        local reused = record.deployments > 1 and "  <-- ID REUSED" or ""

        add_event(string.format(
            "%s ID %s DEPLOY #%d%s",
            ship_label(shipId),
            tostring(droneId),
            record.deployments,
            reused
        ))
    end

    if state ~= record.state then
        add_event(string.format(
            "%s ID %s %s -> %s",
            ship_label(shipId),
            tostring(droneId),
            record.state,
            state
        ))

        record.state = state
    end

    record.wasDeployed = deployed
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    if not ship.droneSystem then return end

    for i = 0, ship.droneSystem.drones:size() - 1 do
        local drone = ship.droneSystem.drones[i]

        if drone.blueprint.name == COMSAT_BLUEPRINT then
            track_comsat(ship.iShipId, drone)
        end
    end
end)

local function reset_debug()
    observations[0] = {}
    observations[1] = {}
    recentEvents = {}
end

script.on_init(reset_debug)
script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, reset_debug)

local function draw_panel()
    if not Hyperspace.App or not Hyperspace.App.world
        or not Hyperspace.App.world.bStartedGame then
        return
    end

    Graphics.CSurface.GL_PushMatrix()
    Graphics.CSurface.GL_LoadIdentity()
    Graphics.CSurface.GL_SetColor(Graphics.GL_Color(1, 1, 1, 1))

    local line = 0

    local function add(text)
        Graphics.freetype.easy_print(FONT, TEXT_X, TEXT_Y + line * LINE_HEIGHT, text)
        line = line + 1
    end

    add("COMSAT ID TEST")

    for shipId = 0, 1 do
        local ship = Hyperspace.ships(shipId)
        local found = false

        if ship and ship.droneSystem then
            for i = 0, ship.droneSystem.drones:size() - 1 do
                local drone = ship.droneSystem.drones[i]

                if drone.blueprint.name == COMSAT_BLUEPRINT then
                    found = true

                    local record = observations[shipId][drone.selfId]

                    add(string.format(
                        "%s slot=%d ID=%s state=%s deploys=%d timer=%.2f",
                        ship_label(shipId),
                        i,
                        tostring(drone.selfId),
                        get_state(drone),
                        record and record.deployments or 0,
                        drone.destroyedTimer
                    ))
                end
            end
        end

        if not found then
            add(ship_label(shipId) .. ": no Comsat")
        end
    end

    add("")
    add("Recent transitions:")

    for _, event in ipairs(recentEvents) do
        add(event)
    end

    Graphics.CSurface.GL_PopMatrix()
end

script.on_render_event(Defines.RenderEvents.MOUSE_CONTROL, draw_panel, function() end)