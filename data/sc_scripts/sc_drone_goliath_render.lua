--[[
DESCRIPTION: Render handling for the Terran Goliath crew-drone system.
        - Forces idle companion-turret facing to follow the connected Goliath's movement direction.
        - Leaves native defense-drone targeting untouched while hostile projectiles are incoming.
        - Rotates the turret's native cached gun images with its idle facing.
        - Repositions the Goliath's native health bar to clear the attached turret.
DEPENDENCIES: sc_drone_goliath_core.lua, sc_drone_goliath_pair.lua
]]

local goliath = mods.sc.goliath

-- Moves the native crew health bar relative to the Goliath legs.
-- Negative Y moves the bar upward to clear the attached turret.
local HEALTH_BAR_OFFSET_X = 1
local HEALTH_BAR_OFFSET_Y = -8

local lastRenderError = nil

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

local function apply_all_native_facing()
    local success, errorMessage = pcall(function()
        local shipManager =
            Hyperspace.ships.player

        if not shipManager
            or goliath.ship_is_destroyed(
                shipManager
            ) then

            return
        end

        for _, pair in pairs(goliath.activePairs) do
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

-- Move only the native health overlay for Goliath crew drones. The render
-- event wraps CrewMember:OnRenderHealth(), so the matrix translation affects
-- the health bar without moving the crew sprite or attached turret.
script.on_render_event(
    Defines.RenderEvents.CREW_MEMBER_HEALTH,
    function(crew)
        if crew.type == goliath.FOLLOW_CREW_TYPE then
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
    Defines.RenderEvents.LAYER_PLAYER,
    function()
        apply_all_native_facing()
    end,
    function() end
)

script.on_render_event(
    Defines.RenderEvents.SHIP,
    function(ship)
        if ship.iShipId == 0 then
            apply_all_native_facing()
        end
    end,
    function() end
)
