local userdata_table = mods.multiverse.userdata_table
local vter = mods.multiverse.vter
local is_first_shot = mods.multiverse.is_first_shot

mods.multiverse.weaponTagParsers = mods.multiverse.weaponTagParsers or {}
local weaponTagParsers = mods.multiverse.weaponTagParsers

mods.sc = mods.sc or {}
mods.sc.chargers = mods.sc.chargers or {}

local chargers = mods.sc.chargers

table.insert(weaponTagParsers, function(weaponNode)
    local nameAttr = weaponNode:first_attribute("name")
    if not nameAttr then return end
    local weaponName = nameAttr:value()

    local entries = {}

    local tagNode = weaponNode:first_node("sc-charge")
    while tagNode do
        local statAttr = tagNode:first_attribute("stat")
        local amountAttr = tagNode:first_attribute("amount")
        local baseAttr = tagNode:first_attribute("base")

        if statAttr then
            table.insert(entries, {
                stat = statAttr:value(),
                amount = amountAttr and tonumber(amountAttr:value()) or 1,
                base = baseAttr and tonumber(baseAttr:value()) or nil
            })
        end

        tagNode = tagNode:next_sibling("sc-charge")
    end

    if #entries > 0 then
        chargers[weaponName] = entries
    end
end)

local function get_stored_charge_boost(weapon)
    if not weapon then return 0 end

    local wdata = userdata_table(weapon, "mods.sc.weaponStuff")

    if not wdata.chargeBurstActive then
        local boostLevel = 0

        if weapon.weaponVisual then
            boostLevel = weapon.weaponVisual.boostLevel or 0
        end

        wdata.chargeBurstBoost = math.max(0, boostLevel)
        wdata.chargeBurstActive = true
    end

    return math.max(0, wdata.chargeBurstBoost or 0)
end

local function clear_stored_charge_boost_if_idle(weapon)
    if not weapon then return end

    local wdata = userdata_table(weapon, "mods.sc.weaponStuff")

    if weapon.queuedProjectiles:size() <= 0 and (weapon.cooldown.first or 0) > 0 then
        wdata.chargeBurstBoost = 0
        wdata.chargeBurstActive = false
    end
end

local function get_preview_radius_charge_boost(weapon)
    if not weapon then return 0 end
    return math.max(0, (weapon.chargeLevel or 0) - 1)
end

local function get_charge_missile_data(statBoosts)
    if not statBoosts then return nil end

    for _, statBoost in ipairs(statBoosts) do
        if statBoost.stat == "missileCost" then
            return statBoost
        end
    end

    return nil
end

local function get_charge_missile_cost(statBoost, boost)
    if not statBoost then return nil end

    local baseCost = statBoost.base or 1
    local amount = statBoost.amount or 0
    local cost = baseCost + boost * amount

    return math.max(1, math.floor(cost))
end

local function get_charge_shot_amount(statBoosts)
    if not statBoosts then return nil end

    for _, statBoost in ipairs(statBoosts) do
        if statBoost.stat == "shots" then
            return statBoost.amount
        end
    end

    return nil
end

function mods.sc.apply_charge_shot_limit(weapon, shotLimit)
    if not weapon or not shotLimit then return end

    local bp = weapon.blueprint
    local name = bp and bp.name
    if not name then return end

    local allowedShots = math.max(1, math.floor(shotLimit))

    local miniProjectileCount = 1

    if bp.miniProjectiles and bp.miniProjectiles:size() > 0 then
        miniProjectileCount = bp.miniProjectiles:size()
    end

    local allowedTotal = allowedShots * miniProjectileCount

    local wdata = userdata_table(weapon, "mods.sc.weaponStuff")
    local key = "chargeShotsFiredThisVolley_" .. name

    wdata[key] = (wdata[key] or 0) + 1

    if wdata[key] >= allowedTotal then
        weapon.queuedProjectiles:clear()
    end

    if weapon.queuedProjectiles:size() == 0 then
        wdata[key] = 0
    end
end

-- -------------------
-- CHARGE MISSILE COST
-- -------------------

script.on_internal_event(Defines.InternalEvents.SELECT_ARMAMENT_PRE, function(armamentSlot)
    local ship = Hyperspace.ships.player

    if not ship
        or not ship.weaponSystem
        or not ship.weaponSystem.weapons then
        return Defines.Chain.CONTINUE, armamentSlot
    end

    local weapon = ship.weaponSystem.weapons[armamentSlot]

    if not weapon or not weapon.blueprint then
        return Defines.Chain.CONTINUE, armamentSlot
    end

    local statBoosts = chargers[weapon.blueprint.name]
    local missileData = get_charge_missile_data(statBoosts)

    if not missileData then
        return Defines.Chain.CONTINUE, armamentSlot
    end

    local boost = math.max(0, (weapon.chargeLevel or 0) - 1)

    local missileCost = get_charge_missile_cost(
        missileData,
        boost
    )

    if ship:GetMissileCount() < missileCost then
        return Defines.Chain.PREEMPT, armamentSlot
    end

    return Defines.Chain.CONTINUE, armamentSlot
end)

-- -------------
-- CHARGE STATS
-- -------------
script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    local statBoosts = chargers[weapon and weapon.blueprint and weapon.blueprint.name]
    if not statBoosts then return end

    -- Capture first-shot state before the shot limiter changes the queue.
    local firstShot = is_first_shot(weapon, true)

    -- Actual charge level, independent of number of shots/projectiles.
    local boost = get_stored_charge_boost(weapon)

    -- Limit the physical number of shots.
    local shotAmount = get_charge_shot_amount(statBoosts)

    if shotAmount then
        mods.sc.apply_charge_shot_limit(weapon, shotAmount)
    end

    local missileData = get_charge_missile_data(statBoosts)

    if missileData
        and weapon.iShipId == 0
        and firstShot then

        local ship = Hyperspace.ships.player

        if ship then
            local totalMissileCost =
                get_charge_missile_cost(missileData, boost)

            if totalMissileCost > 0 then
                ship:ModifyMissileCount(-totalMissileCost)
            end
        end
    end

    -- -------------------
    -- OTHER CHARGE STATS
    -- -------------------

    for _, statBoost in ipairs(statBoosts) do
        local amount = statBoost.amount or 1

        if statBoost.stat == "accuracyMod" then
            if projectile.extend and projectile.extend.customDamage then
                local base = projectile.extend.customDamage.accuracyMod or 0
                projectile.extend.customDamage.accuracyMod = base + boost * amount
            end

        elseif statBoost.stat == "cooldown" then
            -- handled in SHIP_LOOP

        elseif statBoost.stat == "shots" then
            -- handled above

        elseif statBoost.stat == "missileCost" then
            -- handled above

        elseif statBoost.stat == "radius" then
            local baseRadius = mods.sc.radius.get_base_radius(weapon)

            local firedRadius = math.max(
                0,
                (weapon.radius or mods.sc.radius.get_base_radius(weapon))
                    + amount * boost
            )

            local wdata = userdata_table(
                weapon,
                "mods.sc.weaponStuff"
            )

            wdata.fireRadiusOverride = firedRadius
            wdata.fireRadiusOverrideActive = true

        else
            local base = projectile.damage[statBoost.stat] or 0
            projectile.damage[statBoost.stat] = base + boost * amount
        end
    end
end)

-- -------------
-- CHARGE COOLDOWN
-- -------------
local function get_charge_cooldown_rate(weapon, cdBoost)
    local effectiveCharge = math.max(0, (weapon and weapon.chargeLevel or 0))

    if effectiveCharge <= 0 or not cdBoost or cdBoost == 0 then
        return 1
    end

    if cdBoost > 0 then
        return 1 + effectiveCharge * cdBoost
    else
        return 1 / (1 + effectiveCharge * math.abs(cdBoost))
    end
end

function mods.sc.apply_charge_cooldown_bonus(weapon, cdBoost)
    if not weapon or cdBoost == nil then return end
    if weapon.chargeLevel == 0 or weapon.chargeLevel >= weapon.weaponVisual.iChargeLevels then return end

    local wdata = userdata_table(weapon, "mods.sc.weaponStuff")
    local cdLast = wdata.cdLast

    if cdLast and weapon.cooldown.first > cdLast then
        local chargeUpdate = weapon.cooldown.first - cdLast
        local rate = get_charge_cooldown_rate(weapon, cdBoost)
        local chargeNew = weapon.cooldown.first - chargeUpdate + (chargeUpdate * rate)

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

-- --------------
-- CHARGE RADIUS
-- --------------
mods.sc.radius.register_modifier("charge_charge", function(ship, weapon, radius, baseRadius)
    local statBoosts = chargers[weapon and weapon.blueprint and weapon.blueprint.name]
    if not statBoosts then
        return radius
    end

    local perCharge = nil
    for _, statBoost in ipairs(statBoosts) do
        if statBoost.stat == "radius" then
            perCharge = statBoost.amount or 0
            break
        end
    end

    if not perCharge then
        return radius
    end

    local boost = get_preview_radius_charge_boost(weapon)
    local newRadius = radius + perCharge * boost

    return math.max(0, newRadius)
end)