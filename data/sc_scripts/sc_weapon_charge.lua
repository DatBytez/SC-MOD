--[[
DESCRIPTION: Applies shared stat scaling to tagged native Charge weapons.
        - Limits volleys for weapons with a tagged shot count.
        - Applies tagged Charge-based cooldown scaling while charging.
TAG: <sc-charge stat="..." value="#"/>
DEPENDENCIES: sc_tag.lua, sc_projectile_scaling.lua, Multiverse userdata_table, Multiverse vter
]]

local userdata_table = mods.multiverse.userdata_table
local vter = mods.multiverse.vter
local scaling = mods.sc.scaling

mods.sc.chargers = mods.sc.chargers or {}
local chargers = mods.sc.chargers

mods.sc.tag.register("weapon", "sc-charge", chargers, "stat")

local function get_stored_charge_level(weapon)
    local wdata = userdata_table(weapon, "mods.sc.weaponStuff")

    if not wdata.chargeBurstActive then
        wdata.chargeBurstLevel = weapon.queuedProjectiles:size()
        wdata.chargeBurstActive = true
    end

    return wdata.chargeBurstLevel
end

local function clear_stored_charge_level_if_idle(weapon)
    if weapon.queuedProjectiles:size() == 0 and weapon.cooldown.first > 0 then
        userdata_table(weapon, "mods.sc.weaponStuff").chargeBurstActive = false
    end
end

local function apply_charge_shot_limit(weapon, shotLimit)
    local wdata = userdata_table(weapon, "mods.sc.weaponStuff")

    wdata.chargeShotsFiredThisVolley = (wdata.chargeShotsFiredThisVolley or 0) + 1

    if wdata.chargeShotsFiredThisVolley >= shotLimit then
        weapon.queuedProjectiles:clear()
    end

    if weapon.queuedProjectiles:size() == 0 then
        wdata.chargeShotsFiredThisVolley = 0
    end
end

local function get_charge_cooldown_rate(weapon, cdBoost)
    if cdBoost > 0 then
        return 1 + weapon.chargeLevel * cdBoost
    end

    return 1 / (1 + weapon.chargeLevel * math.abs(cdBoost))
end

local function apply_charge_cooldown_bonus(weapon, cdBoost)
    if weapon.chargeLevel == 0 or weapon.chargeLevel >= weapon.weaponVisual.iChargeLevels then
        return
    end

    local wdata = userdata_table(weapon, "mods.sc.weaponStuff")
    local cdLast = wdata.cdLast

    if cdLast and weapon.cooldown.first > cdLast then
        local chargeUpdate = weapon.cooldown.first - cdLast
        local rate = get_charge_cooldown_rate(weapon, cdBoost)
        local chargeNew = weapon.cooldown.first - chargeUpdate + chargeUpdate * rate

        if chargeNew >= weapon.cooldown.second then
            weapon.chargeLevel = weapon.chargeLevel + 1

            if weapon.chargeLevel == weapon.weaponVisual.iChargeLevels then
                weapon.cooldown.first = weapon.cooldown.second
            else
                weapon.cooldown.first = 0
            end
        else
            weapon.cooldown.first = chargeNew
        end
    end

    wdata.cdLast = weapon.cooldown.first
end

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    if not chargers[weapon.blueprint.name] then return end

    local boost = get_stored_charge_level(weapon)
    local pdata = userdata_table(projectile, "mods.sc.projectileScaling")

    pdata.chargeLevel = boost

    scaling.apply_projectile_stats(projectile, weapon, "charge", boost, {
        shots = function(_projectile, currentWeapon, statBoost)
            apply_charge_shot_limit(currentWeapon, statBoost.value)
        end
    })
end)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    if not ship.weaponSystem then return end

    for weapon in vter(ship.weaponSystem.weapons) do
        if chargers[weapon.blueprint.name] then
            clear_stored_charge_level_if_idle(weapon)

            local cooldown = scaling.get_source_stat_entry("charge", weapon.blueprint.name, "cooldown")

            if cooldown then
                apply_charge_cooldown_bonus(weapon, cooldown.value)
            end
        end
    end
end)