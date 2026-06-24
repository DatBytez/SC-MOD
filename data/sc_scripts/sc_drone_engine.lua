-- ------------------------
-- SC DRONE ENGINE OVERLAY
-- ------------------------
-- Draws a custom engine image for TERRAN_DEFENSE_1.
--
-- Custom image location:
-- img/ship/drones/matrix_drone_engine.png
--
-- Lua image path:
-- ship/drones/matrix_drone_engine.png

local vter = mods.multiverse.vter

local TARGET_DRONE = "TERRAN_DEFENSE_1"
--local TARGET_ENGINE_IMAGE = "ship/drones/matrix_drone_engine.png"
local TARGET_ENGINE_IMAGE = "ship/drones/matrix_drone_engine.png"

-- Optional: use this later if you replace the vanilla drone engine image
-- with a transparent image and want to manually restore normal engines.
local DEFAULT_ENGINE_IMAGE = "ship/drones/drone_engine.png"

-- Screen-space offset.
-- These always behave like normal screen coordinates:
-- positive X = right
-- positive Y = down
local ENGINE_SCREEN_X_OFFSET = 382 -- 382
local ENGINE_SCREEN_Y_OFFSET = 172 -- 172

-- Drone-local offset.
-- These rotate with the drone.
-- If the drone turns, these directions turn with it.
local ENGINE_LOCAL_X_OFFSET = -9 -- -9
local ENGINE_LOCAL_Y_OFFSET = 9 -- 9

local ENGINE_SCALE = 1.0

-- Try LAYER_FRONT first.
-- If it still draws too low, temporarily test MOUSE_CONTROL.
local ENGINE_RENDER_LAYER = Defines.RenderEvents.MOUSE_CONTROL
--local ENGINE_RENDER_LAYER = Defines.RenderEvents.MOUSE_CONTROL

local targetEnginePrimitive = nil
local defaultEnginePrimitive = nil

local function get_space_manager()
    local world = Hyperspace.App and Hyperspace.App.world
    return world and world.space
end

local function valid_drone(spacedrone)
    return spacedrone
        and spacedrone.blueprint
        and spacedrone.currentLocation
        and spacedrone.deployed
        and not spacedrone.bDead
end

local function is_target_drone(spacedrone)
    return valid_drone(spacedrone)
        and spacedrone.blueprint.name == TARGET_DRONE
end

local function make_primitive(imagePath)
    return Hyperspace.Resources:CreateImagePrimitiveString(
        imagePath,
        0,
        0,
        0,
        Graphics.GL_Color(1, 1, 1, 1),
        1.0,
        false
    )
end

local function ensure_primitives()
    if not targetEnginePrimitive then
        targetEnginePrimitive = make_primitive(TARGET_ENGINE_IMAGE)
    end

    -- Leave this disabled unless you blank the vanilla engine globally
    -- and want to restore ordinary engines for all other drones.
    -- if not defaultEnginePrimitive then
    --     defaultEnginePrimitive = make_primitive(DEFAULT_ENGINE_IMAGE)
    -- end
end

local function render_engine_for_drone(spacedrone, primitive)
    if not primitive then return end

    local loc = spacedrone.currentLocation
    if not loc then return end

    Graphics.CSurface.GL_PushMatrix()

    -- First move to the drone location using normal screen-space coordinates.
    Graphics.CSurface.GL_Translate(
        loc.x + ENGINE_SCREEN_X_OFFSET,
        loc.y + ENGINE_SCREEN_Y_OFFSET,
        0
    )

    -- Rotate to match the drone.
    -- If the engine rotates incorrectly, comment this line out.
    Graphics.CSurface.GL_Rotate(spacedrone.current_angle or 0, 0, 0, 1)

    -- Then apply local offset after rotation.
    -- This means local X/Y move relative to the drone's facing direction.
    Graphics.CSurface.GL_Translate(
        ENGINE_LOCAL_X_OFFSET,
        ENGINE_LOCAL_Y_OFFSET,
        0
    )

    Graphics.CSurface.GL_Scale(1, -1, 1)

    if ENGINE_SCALE ~= 1.0 then
        Graphics.CSurface.GL_Scale(ENGINE_SCALE, ENGINE_SCALE, 1)
    end

    Graphics.CSurface.GL_RenderPrimitive(primitive)
    Graphics.CSurface.GL_PopMatrix()
end

script.on_render_event(ENGINE_RENDER_LAYER, function() end, function()
    local spaceManager = get_space_manager()
    if not spaceManager or not spaceManager.drones then return end

    ensure_primitives()

    for spacedrone in vter(spaceManager.drones) do
        if is_target_drone(spacedrone) then
            render_engine_for_drone(spacedrone, targetEnginePrimitive)
        end

        -- Optional fallback if you blank the vanilla drone engine globally:
        --
        -- if valid_drone(spacedrone) and not is_target_drone(spacedrone) then
        --     render_engine_for_drone(spacedrone, defaultEnginePrimitive)
        -- end
    end
end)