-- Test No. 4

local userdata_table =
    mods.multiverse.userdata_table

mods.sc = mods.sc or {}
mods.sc.chainers = mods.sc.chainers or {}

local chainers = mods.sc.chainers

mods.sc.tag.register_tag(
    "sc-chain",
    chainers
)

-- -------------
-- CHAIN STATS
-- -------------
script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_FIRE,
    function(projectile, weapon)
        local statBoosts =
            chainers[
                weapon
                and weapon.blueprint
                and weapon.blueprint.name
            ]

        if not statBoosts then
            return
        end

        local boost =
            math.max(
                0,
                weapon.boostLevel or 0
            )

        local pdata =
            userdata_table(
                projectile,
                "mods.sc.projectileScaling"
            )

        pdata.weaponName =
            weapon.blueprint.name

        pdata.hasChain = true
        pdata.chainLevel = boost

        mods.sc.scaling.apply_projectile_stats(
            projectile,
            weapon,
            "chain",
            boost,
            {
                shots = function(
                    currentProjectile,
                    currentWeapon,
                    statBoost
                )
                    mods.sc.apply_warmup_chain_shots(
                        currentWeapon,
                        statBoost.amount or 1
                    )
                end
            }
        )
    end
)

-- -------------
-- CHAIN SHOTS
-- -------------
function mods.sc.apply_warmup_chain_shots(
    weapon,
    startingShots
)
    if not weapon or not startingShots then
        return
    end

    local bp = weapon.blueprint
    local name = bp and bp.name

    if not name then
        return
    end

    local wdata =
        userdata_table(
            weapon,
            "mods.sc.weaponStuff"
        )

    local key =
        "shotsFiredThisVolley_" .. name

    wdata[key] =
        (wdata[key] or 0) + 1

    local boost =
        math.max(
            0,
            weapon.boostLevel or 0
        )

    local cap =
        (bp and bp.shots) or 1

    local allowedTotal =
        math.min(
            cap,
            startingShots - 1 + boost
        )

    if wdata[key] >= allowedTotal then
        weapon.queuedProjectiles:clear()
    end

    if weapon.queuedProjectiles:size() == 0 then
        wdata[key] = 0
    end
end
