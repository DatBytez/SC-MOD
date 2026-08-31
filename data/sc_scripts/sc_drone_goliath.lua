--[[
DESCRIPTION: Runtime event controller for the Terran Goliath crew-drone system.
        - Synchronizes Goliath/turret pairs for both active ships.
        - Keeps companion turrets positioned and powered with their Goliath legs.
        - Allows native defense-drone firing only while hostile projectiles are incoming.
        - Prevents projectile damage to paired turrets and transfers 45 damage to the connected legs instead.
        - Removes companion turrets when either active ship is destroyed.
DEPENDENCIES: sc_drone_goliath_core.lua, sc_drone_goliath_pair.lua
]]

local userdata_table = mods.multiverse.userdata_table
local goliath = mods.sc.goliath

local TURRET_HIT_DAMAGE = 45

local function update_ship_goliaths(
    shipManager
)
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

    for _, pair in pairs(
        goliath.get_active_pairs(
            shipManager
        )
    ) do
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

script.on_internal_event(
    Defines.InternalEvents.ON_TICK,
    function()
        local playerShip =
            goliath.get_ship_manager(0)

        if playerShip then
            update_ship_goliaths(
                playerShip
            )
        else
            goliath.activePairsByShip[0] = {}
        end

        local otherShip =
            goliath.get_ship_manager(1)

        if otherShip
            and otherShip._targetable
            and otherShip._targetable.hostile then
            update_ship_goliaths(
                otherShip
            )
        else
            goliath.activePairsByShip[1] = {}
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
            goliath.get_ship_manager(
                defenseDrone.currentSpace
            )

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

        crew:DirectModifyHealth(
            -TURRET_HIT_DAMAGE
        )

        return Defines.Chain.PREEMPT
    end
)
