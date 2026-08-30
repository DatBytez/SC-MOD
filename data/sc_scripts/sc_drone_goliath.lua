--[[
DESCRIPTION: Runtime event controller for the Terran Goliath crew-drone system.
        - Synchronizes Goliath/turret pairs during gameplay.
        - Keeps companion turrets positioned and powered with their Goliath legs.
        - Allows native defense-drone firing only while hostile projectiles are incoming.
        - Prevents projectile damage to paired turrets and transfers 45 damage to the connected legs instead.
        - Removes companion turrets when the player ship is destroyed.
DEPENDENCIES: sc_drone_goliath_core.lua, sc_drone_goliath_pair.lua
]]

local userdata_table = mods.multiverse.userdata_table
local goliath = mods.sc.goliath

local TURRET_HIT_DAMAGE = 45

local function damage_connected_legs(crew)
    crew:DirectModifyHealth(
        -TURRET_HIT_DAMAGE
    )
end

script.on_internal_event(
    Defines.InternalEvents.ON_TICK,
    function()
        local shipManager =
            Hyperspace.ships.player

        if not shipManager then
            goliath.activePairs = {}
            return
        end

        if goliath.ship_is_destroyed(
            shipManager
        ) then
            goliath.remove_all_turrets(
                shipManager
            )

            return
        end

        goliath.synchronize_pairs(
            shipManager
        )

        local incomingProjectile =
            goliath.has_incoming_hostile_projectile(
                shipManager
            )

        for _, pair in pairs(goliath.activePairs) do
            goliath.position_turret_with_crew(
                pair.crew,
                pair.drone
            )

            local turretPowered =
                goliath.update_turret_power_from_legs(
                    pair.crew,
                    pair.drone
                )

            goliath.get_facing_state(pair.crew)

            if not turretPowered
                or not incomingProjectile then

                pair.drone.bFire = false
            end
        end
    end
)

script.on_internal_event(
    Defines.InternalEvents.DRONE_COLLISION,
    function(
        defenseDrone,
        projectile
    )
        local shipManager =
            Hyperspace.ships.player

        if not shipManager
            or not goliath.is_live_goliath_turret(
                defenseDrone,
                shipManager
            ) then
            return Defines.Chain.CONTINUE
        end

        if projectile
            and projectile.ownerId
                == shipManager.iShipId then
            return Defines.Chain.CONTINUE
        end

        local turretState = userdata_table(
            defenseDrone,
            goliath.TURRET_STATE_KEY
        )

        if not turretState.managed
            or turretState.crewId == nil then
            return Defines.Chain.CONTINUE
        end

        local crew =
            goliath.find_active_goliath_by_id(
                shipManager,
                turretState.crewId
            )

        if not crew then
            return Defines.Chain.CONTINUE
        end

        damage_connected_legs(crew)

        -- PREEMPT prevents the normal collision damage from being applied
        -- to the turret. The projectile keeps its normal collision response.
        return Defines.Chain.PREEMPT
    end
)

script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    function(shipManager)
        if shipManager.iShipId == 0
            and goliath.ship_is_destroyed(
                shipManager
            ) then

            goliath.remove_all_turrets(
                shipManager
            )
        end
    end
)
