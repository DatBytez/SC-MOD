--[[
TEST: Goliath turret CachedImage scaling

Purpose:
    Force every TERRAN_GOLIATH_T native defense-drone image to scale 0
    so we can verify whether CachedImage:SetScale(0, 0) reliably hides
    the turret.

Note:
    TERRAN_GOLIATH_T also has <sc-droneEngine value="drone_engine"/>.
    That separate overlay is drawn by sc_drone_engine.lua and may remain
    visible even if this test successfully hides the native turret.
]]

local vter = mods.multiverse.vter

local GOLIATH_TURRET = "TERRAN_GOLIATH_T"

local function set_scale_zero(image)
    if image then
        pcall(function()
            image:SetScale(0, 0)
        end)
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

            set_scale_zero(drone.drone_image)
            set_scale_zero(drone.gun_image_off)
            set_scale_zero(drone.gun_image_charging)
            set_scale_zero(drone.gun_image_on)
            set_scale_zero(drone.engine_image)
        end
    end
end

script.on_internal_event(
    Defines.InternalEvents.ON_TICK,
    hide_goliath_turrets
)

script.on_render_event(
    Defines.RenderEvents.SHIP,
    function()
        hide_goliath_turrets()
    end,
    function() end
)
