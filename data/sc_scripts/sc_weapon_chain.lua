--[[
DESCRIPTION: Applies shared stat scaling to tagged native Chain weapons.
        - Limits each volley to the number of shots allowed by the current Chain level.
TAG: <sc-chain stat="..." value="#"/>
DEPENDENCIES: sc_tag.lua, sc_projectile_scaling.lua, Multiverse userdata_table
]]

local userdata_table = mods.multiverse.userdata_table
local scaling = mods.sc.scaling

mods.sc.chainers = mods.sc.chainers or {}
local chainers = mods.sc.chainers

mods.sc.tag.register("weapon", "sc-chain", chainers, "stat")

local function apply_warmup_chain_shots(weapon, startingShots)
    local allowedTotal = math.min(weapon.blueprint.shots, startingShots - 1 + math.max(0, weapon.boostLevel))

    scaling.apply_shot_limit(weapon, "shotsFiredThisVolley_" .. weapon.blueprint.name, allowedTotal)
end

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
        local statBoosts = chainers[weapon.blueprint.name]
        if not statBoosts then return end

        local boost = math.max(0, weapon.boostLevel)
        local pdata = userdata_table(projectile, "mods.sc.projectileScaling")

        pdata.chainLevel = boost

        scaling.apply_projectile_stats(projectile, weapon, "chain", boost,
            {
                shots = function(_projectile, currentWeapon, statBoost)
                    apply_warmup_chain_shots(currentWeapon, statBoost.value)
                end
            }
        )
    end
)