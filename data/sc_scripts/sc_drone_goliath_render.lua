--[[
DESCRIPTION: Render handling for the Terran Goliath crew-drone system.
        - Forces idle companion-turret facing to follow the connected Goliath's movement direction.
        - Supports Goliaths on both the player and the one other active ship.
        - Leaves native defense-drone targeting untouched while hostile projectiles are incoming.
        - Draws the visible Goliath turret from terran_goliath_turret.png with pixel-aligned positioning and centered matrix rotation.
        - Draws the turret during the connected crew's health-render pass so its visibility follows the Goliath legs.
        - Repositions the Goliath's native health bar to clear the attached turret.
DEPENDENCIES: sc_drone_goliath_core.lua, sc_drone_goliath_pair.lua
]]

local goliath = mods.sc.goliath

local TURRET_IMAGE = "ship/drones/terran_goliath_turret.png"

local HEALTH_BAR_OFFSET_X = 1
local HEALTH_BAR_OFFSET_Y = -8

local TURRET_OFFSET_X = -26
local TURRET_OFFSET_Y = -26
local TURRET_ROTATION_OFFSET = 90

local turretPrimitive = nil
local lastRenderError = nil

local function get_turret_primitive()
    if not turretPrimitive then
        turretPrimitive =
            Hyperspace.Resources:CreateImagePrimitiveString(
                TURRET_IMAGE,
                TURRET_OFFSET_X,
                TURRET_OFFSET_Y,
                0,
                Graphics.GL_Color(1, 1, 1, 1),
                1,
                false
            )
    end

    return turretPrimitive
end

local function round_pixel(value)
    return math.floor(value + 0.5)
end

local function render_turret_for_crew(crew)
    local shipManager =
        goliath.get_ship_manager(
            crew.currentShipId
        )

    if not shipManager
        or not goliath.is_active_goliath(
            crew,
            shipManager
        ) then
        return
    end

    local pair =
        goliath.get_active_pairs(
            shipManager
        )[crew.extend.selfId]

    if not pair
        or not goliath.is_live_goliath_turret(
            pair.drone,
            shipManager
        ) then
        return
    end

    local primitive = get_turret_primitive()

    if not primitive then
        return
    end

    local location = pair.drone.currentLocation
    local angle =
        (pair.drone.aimingAngle + TURRET_ROTATION_OFFSET) % 360

    Graphics.CSurface.GL_PushMatrix()

    Graphics.CSurface.GL_Translate(
        round_pixel(location.x),
        round_pixel(location.y),
        0
    )

    Graphics.CSurface.GL_Rotate(
        angle,
        0,
        0,
        1
    )

    Graphics.CSurface.GL_RenderPrimitive(
        primitive
    )

    Graphics.CSurface.GL_PopMatrix()
end

local function force_native_idle_facing(
    shipManager,
    crew,
    defenseDrone
)
    if not goliath.is_active_goliath(
        crew,
        shipManager
    ) then
        return
    end

    if not goliath.is_live_goliath_turret(
        defenseDrone,
        shipManager
    ) then
        return
    end

    if not goliath.update_turret_power_from_legs(
        crew,
        defenseDrone
    ) then
        return
    end

    local state = goliath.get_facing_state(crew)

    if goliath.has_incoming_hostile_projectile(
        shipManager
    ) then
        return
    end

    local angle = state.idleAngle

    defenseDrone.current_angle = angle
    defenseDrone.aimingAngle = angle
    defenseDrone.lastAimingAngle = angle
    defenseDrone.desiredAimingAngle = angle

    goliath.set_cached_image_rotation(
        defenseDrone.gun_image_off,
        angle
    )
    goliath.set_cached_image_rotation(
        defenseDrone.gun_image_charging,
        angle
    )
    goliath.set_cached_image_rotation(
        defenseDrone.gun_image_on,
        angle
    )

    defenseDrone.bFire = false
end

local function apply_all_native_facing(
    shipManager
)
    local success, errorMessage = pcall(function()
        if not shipManager
            or goliath.ship_is_destroyed(
                shipManager
            ) then
            return
        end

        for _, pair in pairs(
            goliath.get_active_pairs(
                shipManager
            )
        ) do
            force_native_idle_facing(
                shipManager,
                pair.crew,
                pair.drone
            )
        end
    end)

    if not success
        and errorMessage ~= lastRenderError then
        lastRenderError = errorMessage

        goliath.error_print(
            "Render error: "
            .. tostring(errorMessage)
        )
    end
end

script.on_render_event(
    Defines.RenderEvents.CREW_MEMBER_HEALTH,
    function(crew)
        if crew.type == goliath.FOLLOW_CREW_TYPE then
            render_turret_for_crew(crew)

            Graphics.CSurface.GL_PushMatrix()

            Graphics.CSurface.GL_Translate(
                HEALTH_BAR_OFFSET_X,
                HEALTH_BAR_OFFSET_Y,
                0
            )
        end
    end,
    function(crew)
        if crew.type == goliath.FOLLOW_CREW_TYPE then
            Graphics.CSurface.GL_PopMatrix()
        end
    end
)

script.on_render_event(
    Defines.RenderEvents.SHIP,
    function(ship)
        apply_all_native_facing(
            goliath.get_ship_manager(
                ship.iShipId
            )
        )
    end,
    function() end
)
