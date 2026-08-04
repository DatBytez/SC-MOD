-- Test No. 2

local userdata_table = mods.multiverse.userdata_table

mods.sc = mods.sc or {}
mods.sc.chainers = mods.sc.chainers or {}

local chainers = mods.sc.chainers

mods.sc.tag.register_tag("sc-chain", chainers)

-- -------------
-- CHAIN STATS
-- -------------
script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    local statBoosts = chainers[weapon and weapon.blueprint and weapon.blueprint.name]
    if not statBoosts then return end

    local boost = math.max(0, weapon.boostLevel or 0)

    -- Store the exact chain level used by this projectile so a later
    -- shared scaling script can apply projectile effects independently
    -- of the weapon's live boost level.
    local pdata = userdata_table(projectile, "mods.sc.projectileScaling")
    pdata.scalingVersion = 1
    pdata.weaponName = weapon.blueprint.name
    pdata.hasChain = true
    pdata.chainLevel = boost
    pdata.chainRawLevel = weapon.boostLevel or 0

    for _, statBoost in ipairs(statBoosts) do
        local amount = statBoost.amount or 1

        if statBoost.stat == "accuracyMod" then
            if projectile.extend and projectile.extend.customDamage then
                local base = projectile.extend.customDamage.accuracyMod or 0
                projectile.extend.customDamage.accuracyMod = base + boost * amount
            end
        elseif statBoost.stat == "shots" then
            mods.sc.apply_warmup_chain_shots(weapon, amount)
        elseif statBoost.stat == "radius" then
            -- Handled by sc_projectile_scaling.lua
        else
            local base = projectile.damage[statBoost.stat] or 0
            projectile.damage[statBoost.stat] = base + boost * amount
        end
    end
end)

-- -------------
-- CHAIN SHOTS
-- -------------
function mods.sc.apply_warmup_chain_shots(weapon, startingShots)
    if not weapon or not startingShots then return end

    local bp = weapon.blueprint
    local name = bp and bp.name

    local wdata = userdata_table(weapon, "mods.sc.weaponStuff")
    local key = "shotsFiredThisVolley_" .. name
    wdata[key] = (wdata[key] or 0) + 1

    local boost = math.max(0, weapon.boostLevel or 0)
    local cap = (bp and bp.shots) or 1
    local allowedTotal = math.min(cap, startingShots-1 + boost)

    if wdata[key] >= allowedTotal then
        weapon.queuedProjectiles:clear()
    end

    if weapon.queuedProjectiles:size() == 0 then
        wdata[key] = 0
    end
end
