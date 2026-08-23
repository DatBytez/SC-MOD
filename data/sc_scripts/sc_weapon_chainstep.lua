--[[
DESCRIPTION: Implements SC Chainstep weapon behavior.
        - Tracks Chainstep level from tagged fire threshold and step duration.
        - Derives the maximum Chainstep level from weapon cooldown.
        - Handles variable missile cost, payment, selection checks, and tooltip text.
TAG: <sc-chainstep stat="..." value="#"/>
DEPENDENCIES: sc_tag.lua, sc_projectile_scaling.lua, Multiverse userdata_table, Multiverse vter
]]

local userdata_table = mods.multiverse.userdata_table
local vter = mods.multiverse.vter
local scaling = mods.sc.scaling

mods.sc.chainstep = mods.sc.chainstep or {}
local chainstepWeapons = mods.sc.chainstep

mods.sc.tag.register("weapon", "sc-chainstep", chainstepWeapons, "stat")

local function get_stat_value(weaponName, statName)
    return scaling.get_source_stat_entry("chainstep", weaponName, statName).value
end

local function get_chainstep_level(weapon)
    local wdata = userdata_table(weapon, "mods.sc.chainstep")
    return wdata.level or weapon.boostLevel
end

local function calculate_missile_cost(weaponName, level)
    local baseCost = get_stat_value(weaponName, "missileBase")
    local value = get_stat_value(weaponName, "missileCost")
    return math.max(1, math.floor(baseCost + level * value)) 
end

local function update_chainstep_weapon(weapon)
    local weaponName = weapon.blueprint.name
    local chargeRate = weapon.cooldown.second / weapon.baseCooldown
    local fireThreshold = get_stat_value(weaponName, "fireThreshold") * chargeRate
    local chainStep = get_stat_value(weaponName, "chainStep") * chargeRate

    if weapon.cooldown.first >= fireThreshold then
        weapon.chargeLevel = 1
    else
        weapon.chargeLevel = 0
    end

    local overCharge = math.floor(math.max(weapon.cooldown.first - fireThreshold, 0) / chainStep)
    local maxSteps = math.ceil((weapon.cooldown.second - fireThreshold) / chainStep)

    overCharge = math.min(overCharge, maxSteps)

    if weapon.cooldown.first >= weapon.cooldown.second then
        overCharge = maxSteps
    end

    weapon.boostLevel = overCharge

    local wdata = userdata_table(weapon, "mods.sc.chainstep")
    local queuedShots = weapon.queuedProjectiles:size()

    if wdata.volleyActive and queuedShots == 0 and weapon.cooldown.first > 0 then
        wdata.volleyActive = false
        wdata.firingLevel = nil
        wdata.missilePaid = false
    end

    if not wdata.volleyActive and queuedShots == 0 then
        wdata.level = overCharge
    end
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    if not ship.weaponSystem then return end

    for weapon in vter(ship.weaponSystem.weapons) do
        if chainstepWeapons[weapon.blueprint.name] then
            update_chainstep_weapon(weapon)
        end
    end
end)

script.on_internal_event(Defines.InternalEvents.SELECT_ARMAMENT_PRE, function(armamentSlot)
    local ship = Hyperspace.ships.player
    local weapon = ship.weaponSystem.weapons[armamentSlot]
    local weaponName = weapon.blueprint.name
    local missileCost = scaling.get_source_stat_entry("chainstep", weaponName, "missileCost")

    if missileCost and ship:GetMissileCount() < calculate_missile_cost(weaponName, get_chainstep_level(weapon)) then
        return Defines.Chain.PREEMPT, armamentSlot
    end

    return Defines.Chain.CONTINUE, armamentSlot
end)

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    local weaponName = weapon.blueprint.name
    if not chainstepWeapons[weaponName] then return end

    local wdata = userdata_table(weapon, "mods.sc.chainstep")

    if not wdata.volleyActive then
        wdata.volleyActive = true
        wdata.firingLevel = wdata.level or weapon.boostLevel
        wdata.missilePaid = false
    end

    local boost = wdata.firingLevel
    local pdata = userdata_table(projectile, "mods.sc.projectileScaling")

    pdata.chainstepLevel = boost
    scaling.apply_projectile_stats(projectile, weapon, "chainstep", boost)

    if weapon.iShipId == 0 and scaling.get_source_stat_entry("chainstep", weaponName, "missileCost") and not wdata.missilePaid then
        Hyperspace.ships.player:ModifyMissileCount(-calculate_missile_cost(weaponName, boost))
        wdata.missilePaid = true
    end
end)

local function get_unique_player_weapon(weaponName)
    if not Hyperspace.ships.player.weaponSystem then return nil end

    local foundWeapon

    for weapon in vter(Hyperspace.ships.player.weaponSystem.weapons) do
        if weapon.blueprint.name == weaponName then
            if foundWeapon then return nil end
            foundWeapon = weapon
        end
    end

    return foundWeapon
end

local function get_tooltip_chainstep_level(weapon)
    local wdata = userdata_table(weapon, "mods.sc.chainstep")
    return wdata.firingLevel or wdata.level or weapon.boostLevel
end

script.on_internal_event(Defines.InternalEvents.WEAPON_STATBOX, function(bp, stats)
    local missileCost = scaling.get_source_stat_entry("chainstep", bp.name, "missileCost")
    if not missileCost then return end

    local baseCost = get_stat_value(bp.name, "missileBase")
    local value = missileCost.value
    local fireThreshold = get_stat_value(bp.name, "fireThreshold")
    local chainStep = get_stat_value(bp.name, "chainStep")
    local maxSteps = math.ceil((bp.cooldown - fireThreshold) / chainStep)
    local minimumCost = calculate_missile_cost(bp.name, maxSteps)
    local weapon = get_unique_player_weapon(bp.name)

    if weapon then
        local currentCost = calculate_missile_cost(bp.name, get_tooltip_chainstep_level(weapon))
        local discounted = math.max(0, baseCost - currentCost)

        stats = stats
            .. "\n\nCurrent missile cost: " .. currentCost
            .. "\nMissiles discounted: " .. discounted
    else
        stats = stats
            .. "\n\nBase missile cost: " .. baseCost
            .. "\nMissile change per chainstep: " .. value
            .. "\nMinimum missile cost: " .. minimumCost
    end

    return Defines.Chain.CONTINUE, stats
end)