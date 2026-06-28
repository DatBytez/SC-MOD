-- ------------------------
-- SC DRONE ENGINE OVERLAY
-- ------------------------
-- Draws engine images for space drones.
--
-- Custom per-drone engine images are set with this droneBlueprint tag:
-- <sc-droneEngine>matrix_drone_engine</sc-droneEngine>

local vter = mods.multiverse.vter

mods.multiverse.droneTagParsers = mods.multiverse.droneTagParsers or {}
local droneTagParsers = mods.multiverse.droneTagParsers

mods.sc = mods.sc or {}
mods.sc.droneEngine = mods.sc.droneEngine or {}
mods.sc.droneEngine.images = mods.sc.droneEngine.images or {}

local droneEngineImages = mods.sc.droneEngine.images

-- Default engine to draw for drones that do not have <sc-droneEngine>.
-- This is useful if the vanilla drone engine image has been replaced with a transparent image.
-- Set this to nil if you only want the script to draw tagged custom engines.
local DEFAULT_ENGINE_IMAGE = "ship/drones/sc_drone_engine.png"

-- Large correction because this render layer and spacedrone.currentLocation
-- do not share the same origin.
local SPACE_X_OFFSET = 0 -- 382
local SPACE_Y_OFFSET = 0 -- 172

-- Small screen-space engine adjustment.
-- These always behave like normal screen coordinates:
-- positive X = right
-- positive Y = down
local ENGINE_SCREEN_X_OFFSET = 0
local ENGINE_SCREEN_Y_OFFSET = 0

-- Small drone-local engine adjustment.
-- These rotate with the drone.
local ENGINE_LOCAL_X_OFFSET = -31
local ENGINE_LOCAL_Y_OFFSET = 31

local ENGINE_SCALE = 1.0
local ENGINE_MIRROR = false
local ENGINE_FLIP_VERTICAL = true

local ENGINE_RENDER_LAYER = Defines.RenderEvents.SHIP_ENGINES

local enginePrimitives = {}

local function trim(value)
    if value == nil then return nil end
    return tostring(value):match("^%s*(.-)%s*$")
end

local function normalize_engine_image_path(engineName)
    engineName = trim(engineName)
    if not engineName or engineName == "" then return nil end

    -- Resource paths should not include the leading img/ folder.
    if engineName:sub(1, 4) == "img/" then
        engineName = engineName:sub(5)
    end

    -- If only a filename/id is provided, assume img/ship/drones/<name>.png.
    if not engineName:find("/", 1, true) then
        engineName = "ship/drones/" .. engineName
    end

    -- If the extension is omitted, assume .png.
    if not engineName:match("%.png$") then
        engineName = engineName .. ".png"
    end

    return engineName
end

-- Parses:
-- <droneBlueprint name="TERRAN_DEFENSE_1">
--     <sc-droneEngine>matrix_drone_engine</sc-droneEngine>
-- </droneBlueprint>
table.insert(droneTagParsers, function(droneNode)
    local nameAttr = droneNode:first_attribute("name")
    if not nameAttr then return end

    local droneName = nameAttr:value()
    if not droneName or droneName == "" then return end

    local engineNode = droneNode:first_node("sc-droneEngine")
    if not engineNode then return end

    local enginePath = normalize_engine_image_path(engineNode:value())
    if not enginePath then return end

    droneEngineImages[droneName] = enginePath
end)

local function get_space_manager()
    local world = Hyperspace.App and Hyperspace.App.world
    return world and world.space
end

local function lua_bool(value)
    if value == nil then return nil end
    if value == false or value == 0 then return false end
    return true
end

local function drone_is_deployed(spacedrone)
    local deployed = lua_bool(spacedrone.deployed)
    if deployed ~= nil then return deployed end

    if spacedrone.GetDeployed then
        local ok, value = pcall(function() return spacedrone:GetDeployed() end)
        if ok then return lua_bool(value) end
    end

    -- If this Hyperspace build exposes neither the field nor the method,
    -- avoid blocking rendering for every drone.
    return true
end

local function drone_is_powered(spacedrone)
    local powered = lua_bool(spacedrone.powered)
    if powered ~= nil then return powered end

    if spacedrone.GetPowered then
        local ok, value = pcall(function() return spacedrone:GetPowered() end)
        if ok then return lua_bool(value) end
    end

    -- If this Hyperspace build exposes neither the field nor the method,
    -- avoid blocking rendering for every drone.
    return true
end

local function valid_drone(spacedrone)
    return spacedrone
        and spacedrone.blueprint
        and spacedrone.currentLocation
        and drone_is_deployed(spacedrone)
        and drone_is_powered(spacedrone)
        and not spacedrone.bDead
end

local function make_primitive(imagePath)
    return Hyperspace.Resources:CreateImagePrimitiveString(
        imagePath,
        0,
        0,
        0,
        Graphics.GL_Color(1, 1, 1, 1),
        1.0,
        ENGINE_MIRROR
    )
end

local function get_engine_primitive(imagePath)
    if not imagePath then return nil end

    if not enginePrimitives[imagePath] then
        enginePrimitives[imagePath] = make_primitive(imagePath)
    end

    return enginePrimitives[imagePath]
end

local function get_engine_image_for_drone(spacedrone)
    if not valid_drone(spacedrone) then return nil end

    local droneName = spacedrone.blueprint.name
    return droneEngineImages[droneName] or DEFAULT_ENGINE_IMAGE
end

local function get_render_ship_id(ship)
    if not ship then return nil end

    local playerShip = Hyperspace.ships(0)
    if playerShip and playerShip.ship == ship then
        return 0
    end

    local enemyShip = Hyperspace.ships(1)
    if enemyShip and enemyShip.ship == ship then
        return 1
    end

    return nil
end

local function normalize_ship_id(value)
    if value == nil then return nil end

    if type(value) == "number" then
        return value
    end

    if type(value) == "boolean" then
        return value and 1 or 0
    end

    if type(value) == "userdata" or type(value) == "table" then
        if value.iShipId ~= nil then
            return value.iShipId
        end

        if value.shipId ~= nil then
            return value.shipId
        end
    end

    return nil
end

local function get_drone_ship_id(spacedrone)
    if not spacedrone then return nil end

    -- SpaceDrone normally exposes currentSpace for which ship-space it is in.
    local currentSpace = normalize_ship_id(spacedrone.currentSpace)
    if currentSpace ~= nil then return currentSpace end

    -- Fallbacks, in case a different Hyperspace build exposes a different field.
    local iShipId = normalize_ship_id(spacedrone.iShipId)
    if iShipId ~= nil then return iShipId end

    local ownerId = normalize_ship_id(spacedrone.ownerId)
    if ownerId ~= nil then return ownerId end

    return nil
end

local function drone_matches_render_ship(spacedrone, renderShipId)
    -- Non-ship render layers pass no ship, so preserve the old behavior there.
    if renderShipId == nil then return true end

    local droneShipId = get_drone_ship_id(spacedrone)
    if droneShipId == nil then return false end

    return droneShipId == renderShipId
end

local function render_engine_for_drone(spacedrone, primitive)
    if not primitive then return end

    local loc = spacedrone.currentLocation
    if not loc then return end

    Graphics.CSurface.GL_PushMatrix()

    -- Base space correction plus fine screen-space tuning.
    Graphics.CSurface.GL_Translate(
        loc.x + SPACE_X_OFFSET + ENGINE_SCREEN_X_OFFSET,
        loc.y + SPACE_Y_OFFSET + ENGINE_SCREEN_Y_OFFSET,
        0
    )

    -- Rotate to match the drone.
    Graphics.CSurface.GL_Rotate(spacedrone.current_angle or 0, 0, 0, 1)

    -- Fine local offset after rotation.
    Graphics.CSurface.GL_Translate(
        ENGINE_LOCAL_X_OFFSET,
        ENGINE_LOCAL_Y_OFFSET,
        0
    )

    local scaleX = ENGINE_SCALE
    local scaleY = ENGINE_SCALE

    if ENGINE_FLIP_VERTICAL then
        scaleY = -scaleY
    end

    Graphics.CSurface.GL_Scale(scaleX, scaleY, 1)
    Graphics.CSurface.GL_RenderPrimitive(primitive)
    Graphics.CSurface.GL_PopMatrix()
end

script.on_render_event(ENGINE_RENDER_LAYER, function() end, function(ship, ...)
    local renderShipId = get_render_ship_id(ship)

    local spaceManager = get_space_manager()
    if not spaceManager or not spaceManager.drones then return end

    for spacedrone in vter(spaceManager.drones) do
        if drone_matches_render_ship(spacedrone, renderShipId) then
            local engineImage = get_engine_image_for_drone(spacedrone)
            if engineImage then
                render_engine_for_drone(spacedrone, get_engine_primitive(engineImage))
            end
        end
    end
end)
