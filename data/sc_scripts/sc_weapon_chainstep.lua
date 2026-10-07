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
    return math.max(0, math.floor(baseCost + level * value)) 
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

    if ship:GetMissileCount() < weapon.blueprint.missiles then
        return Defines.Chain.CONTINUE, armamentSlot
    end

    if weapon.powered and missileCost and ship:GetMissileCount() < calculate_missile_cost(weaponName, get_chainstep_level(weapon)) then
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

script.on_internal_event(Defines.InternalEvents.WEAPON_RENDERBOX, function(weapon, _, _, firstLine, secondLine, thirdLine)
    local missileCost = scaling.get_source_stat_entry("chainstep", weapon.blueprint.name, "missileCost")
    if not missileCost then
        return Defines.Chain.CONTINUE, firstLine, secondLine, thirdLine
    end

    local currentCost = calculate_missile_cost(weapon.blueprint.name, weapon.boostLevel)
        + math.floor(weapon.blueprint.missiles)

    secondLine = "Missile cost: " .. currentCost

    return Defines.Chain.CONTINUE, firstLine, secondLine, thirdLine
end)

script.on_internal_event(Defines.InternalEvents.WEAPON_STATBOX, function(blueprint, stats)
    local missileCost = scaling.get_source_stat_entry("chainstep", blueprint.name, "missileCost")
    if not missileCost then return end

    local fireThreshold = get_stat_value(blueprint.name, "fireThreshold")
    local chainStep = get_stat_value(blueprint.name, "chainStep")
    local maxSteps = math.ceil((blueprint.cooldown - fireThreshold) / chainStep)

    local vanillaChargeTime =
        Hyperspace.Text:GetText("charge_time")

    vanillaChargeTime =
        vanillaChargeTime:gsub(
            "\\1",
            string.format("%g", blueprint.cooldown)
        )

    local chainstepChargeTime =
        Hyperspace.Text:GetText("charge_time")

    chainstepChargeTime =
        chainstepChargeTime:gsub(
            "\\1",
            string.format("%g - %g", fireThreshold, blueprint.cooldown)
        )

    stats = stats:gsub(
        vanillaChargeTime,
        chainstepChargeTime
    )

    local vanillaMissileCost =
        Hyperspace.Text:GetText("stat_resources_missiles")

    vanillaMissileCost =
        vanillaMissileCost:gsub(
            "\\1",
            tostring(math.floor(blueprint.missiles))
        )

    local baseCost = get_stat_value(blueprint.name, "missileBase")
    local minimumCost = calculate_missile_cost(blueprint.name, maxSteps)
    local blueprintCost = math.floor(blueprint.missiles)
    local missileStats =
        "Missile cost: " .. (baseCost + blueprintCost)
        .. " - " .. (minimumCost + blueprintCost)
        .. "\nMissile cost per step: " .. missileCost.value

    stats = stats:gsub(
        vanillaMissileCost .. "\n",
        missileStats .. "\n"
    )

    local radius = scaling.get_source_stat_entry("chainstep", blueprint.name, "radius")

    if radius then
        local startingRadius = blueprint.radius
        local endingRadius = math.max(0, blueprint.radius + maxSteps * radius.value)

        local vanillaRadius =
            Hyperspace.Text:GetText("shot_radius")

        vanillaRadius =
            vanillaRadius:gsub(
                "\\1",
                string.format("%g", blueprint.radius)
            )

        local chainstepRadius =
            Hyperspace.Text:GetText("shot_radius")

        chainstepRadius =
            chainstepRadius:gsub(
                "\\1",
                string.format("%g - %g", startingRadius, endingRadius)
            )

        stats = stats:gsub(
            vanillaRadius,
            chainstepRadius
        )
    end

    return Defines.Chain.CONTINUE, stats
end)
