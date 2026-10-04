--[[
TEST: Goliath turret CachedImage replacement + primitive rebuild

Purpose:
    Test whether a native TERRAN_GOLIATH_T space-drone image can be hidden by:
        1. Replacing the CachedImage texture with effects/invisible.png
        2. Rebuilding the CachedImage's render primitive

Reason:
    CachedImage stores both image/texture data and a CachedPrimitive.
    SetImage() alone did not visibly change the Goliath turret, so this test
    explicitly rebuilds the primitive after the image change.

This does not alter deployment, power, targeting, position, or collision.
]]

local vter = mods.multiverse.vter

local GOLIATH_TURRET = "TERRAN_GOLIATH_T"
local INVISIBLE_IMAGE = "effects/invisible.png"

local applied = {}

local function replace_image(image)
    image:SetImage(INVISIBLE_IMAGE)
    image:CreatePrimitive()
end

local function try_hide_goliath_turret(drone)
    if applied[drone.selfId] then
        return
    end

    local success, errorMessage = pcall(function()
        replace_image(drone.drone_image)
        replace_image(drone.gun_image_off)
        replace_image(drone.gun_image_charging)
        replace_image(drone.gun_image_on)
        replace_image(drone.engine_image)
    end)

    if success then
        applied[drone.selfId] = true
        print(
            "[GOLIATH IMAGE TEST] Applied invisible image and rebuilt primitives to turret "
            .. tostring(drone.selfId)
        )
    else
        print(
            "[GOLIATH IMAGE TEST] Waiting/retrying turret "
            .. tostring(drone.selfId)
            .. ": "
            .. tostring(errorMessage)
        )
    end
end

local function hide_goliath_turrets()
    local spaceManager = Hyperspace.App.world.space

    if not spaceManager then
        return
    end

    for drone in vter(spaceManager.drones) do
        if drone
            and drone.blueprint
            and drone.blueprint.name == GOLIATH_TURRET then
            try_hide_goliath_turret(drone)
        end
    end
end

script.on_internal_event(
    Defines.InternalEvents.ON_TICK,
    hide_goliath_turrets
)
