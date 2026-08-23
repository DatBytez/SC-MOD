--[[
DESCRIPTION: Draws engine overlays for active space drones.
        - Tagged drones use the engine image named by <sc-droneEngine>.
        - Untagged drones use the default SC drone engine image.
        - Engines render only for deployed, powered, living drones in the current ship space.
TAG: <sc-droneEngine value="#"/>
]]

local vter = mods.multiverse.vter

local DEFAULT_ENGINE_IMAGE = "ship/drones/sc_drone_engine.png"

local ENGINE_X_OFFSET = -31
local ENGINE_Y_OFFSET = 31
local ENGINE_SCALE = 1.0
local ENGINE_MIRROR = false
local ENGINE_FLIP_VERTICAL = true

local droneEngineImages = {}
local enginePrimitives = {}

mods.sc.tag.register("drone", "sc-droneEngine", droneEngineImages, "value")

local function get_engine_primitive(imagePath)
    local primitive = enginePrimitives[imagePath]

    if not primitive then
        primitive = Hyperspace.Resources:CreateImagePrimitiveString(
        imagePath, 0, 0, 0, Graphics.GL_Color(1, 1, 1, 1), 1.0, ENGINE_MIRROR)

        enginePrimitives[imagePath] = primitive
    end

    return primitive
end

local function render_engine(spacedrone, primitive)
    local location = spacedrone.currentLocation

    Graphics.CSurface.GL_PushMatrix()
    Graphics.CSurface.GL_Translate(location.x, location.y, 0)
    Graphics.CSurface.GL_Rotate(spacedrone.current_angle, 0, 0, 1)
    Graphics.CSurface.GL_Translate(ENGINE_X_OFFSET, ENGINE_Y_OFFSET, 0)

    local scaleY = ENGINE_FLIP_VERTICAL and -ENGINE_SCALE or ENGINE_SCALE
    Graphics.CSurface.GL_Scale(ENGINE_SCALE, scaleY, 1)

    Graphics.CSurface.GL_RenderPrimitive(primitive)
    Graphics.CSurface.GL_PopMatrix()
end

script.on_render_event(Defines.RenderEvents.SHIP_ENGINES, function() end, function(ship)
    for spacedrone in vter(Hyperspace.App.world.space.drones) do
        if spacedrone.currentSpace == ship.iShipId
            and spacedrone.deployed
            and spacedrone.powered
            and not spacedrone.bDead then

            local engineImage = droneEngineImages[spacedrone.blueprint.name]
            local imagePath = engineImage and "ship/drones/" .. engineImage .. ".png" or DEFAULT_ENGINE_IMAGE
            render_engine(spacedrone, get_engine_primitive(imagePath))
        end
    end
end)