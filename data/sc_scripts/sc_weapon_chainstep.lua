-- Test No. 4

--[[
This code is a reimplementation of TNE_CHAINSTEP_LUA.lua from TNE.

Recommended XML pattern
-----------------------

Timing configuration:
    <sc-chainstep fireThreshold="4" chainStep="4" maxSteps="3"/>

Optional stat entries:
    <sc-chainstep stat="missileCost" base="4" amount="-1"/>
    <sc-chainstep stat="accuracyMod" amount="-45"/>
    <sc-chainstep stat="radius" amount="30"/>
    <sc-chainstep stat="breachChance" amount="2"/>
    <sc-chainstep stat="shots" amount="1"/>

The timing tag has at most three attributes.
Each stat tag has two or three attributes.

For missileCost:
    base   = cost at chainstep level 0
    amount = change per completed chainstep

Weapons using Lua-controlled missileCost should normally use:
    <missiles>0</missiles>
]]

local vter = mods.multiverse.vter
local userdata_table = mods.multiverse.userdata_table

mods.multiverse.weaponTagParsers =
    mods.multiverse.weaponTagParsers or {}

local weaponTagParsers =
    mods.multiverse.weaponTagParsers

mods.sc = mods.sc or {}
mods.sc.chainstep = mods.sc.chainstep or {}

local chainstepWeaponList =
    mods.sc.chainstep

local scaling =
    mods.sc.scaling

-- -----------------
-- XML PARSER
-- -----------------

table.insert(weaponTagParsers, function(weaponNode)
    local nameAttr =
        weaponNode:first_attribute("name")

    if not nameAttr then return end

    local weaponName =
        nameAttr:value()

    local fireThreshold = nil
    local chainStep = nil
    local maxSteps = nil
    local statBoosts = {}

    local tagNode =
        weaponNode:first_node("sc-chainstep")

    while tagNode do
        local fireThresholdAttr =
            tagNode:first_attribute("fireThreshold")

        local chainStepAttr =
            tagNode:first_attribute("chainStep")

        local maxStepsAttr =
            tagNode:first_attribute("maxSteps")

        local statAttr =
            tagNode:first_attribute("stat")

        local amountAttr =
            tagNode:first_attribute("amount")

        local baseAttr =
            tagNode:first_attribute("base")

        if fireThresholdAttr and chainStepAttr then
            fireThreshold =
                tonumber(fireThresholdAttr:value())

            chainStep =
                tonumber(chainStepAttr:value())

            maxSteps =
                maxStepsAttr
                and tonumber(maxStepsAttr:value())
                or nil
        end

        if statAttr then
            table.insert(statBoosts, {
                stat = statAttr:value(),

                amount =
                    amountAttr
                    and tonumber(amountAttr:value())
                    or 1,

                base =
                    baseAttr
                    and tonumber(baseAttr:value())
                    or nil
            })
        end

        tagNode =
            tagNode:next_sibling("sc-chainstep")
    end

    if not fireThreshold
        or not chainStep
        or chainStep <= 0 then

        return
    end

    chainstepWeaponList[weaponName] = {
        fireThreshold = fireThreshold,
        chainStep = chainStep,
        maxSteps = maxSteps,
        statBoosts = statBoosts
    }
end)

-- -----------------
-- HELPERS
-- -----------------

local function get_chainstep_weapon(weapon)
    if not weapon or not weapon.blueprint then
        return nil
    end

    return chainstepWeaponList[
        weapon.blueprint.name
    ]
end

local function get_chainstep_stat(
    chainWeapon,
    statName
)
    if not chainWeapon
        or not chainWeapon.statBoosts then

        return nil
    end

    for _, statBoost in ipairs(
        chainWeapon.statBoosts
    ) do
        if statBoost.stat == statName then
            return statBoost
        end
    end

    return nil
end

local function get_max_chainsteps(
    weapon,
    chainWeapon,
    fireThreshold,
    chainStep
)
    if chainWeapon.maxSteps ~= nil then
        return math.max(
            0,
            math.floor(chainWeapon.maxSteps)
        )
    end

    if weapon.blueprint
        and weapon.blueprint.boostPower
        and weapon.blueprint.boostPower.count then

        local boostCount =
            weapon.blueprint.boostPower.count

        if boostCount > 0 then
            return boostCount
        end
    end

    if chainStep > 0 then
        return math.max(
            0,
            math.floor(
                math.max(
                    weapon.cooldown.second
                        - fireThreshold,
                    0
                ) / chainStep
            )
        )
    end

    return 0
end

local function get_chainstep_level(weapon)
    if not weapon then return 0 end

    local wdata = userdata_table(
        weapon,
        "mods.sc.chainstep"
    )

    return math.max(
        0,
        math.floor(
            wdata.level
                or weapon.boostLevel
                or 0
        )
    )
end

-- -----------------
-- CHAINSTEP SHOTS
-- -----------------

local function apply_chainstep_shots(
    weapon,
    startingShots,
    boost
)
    if not weapon or not startingShots then
        return
    end

    local bp = weapon.blueprint
    local name = bp and bp.name

    if not name then return end

    local wdata = userdata_table(
        weapon,
        "mods.sc.chainstep"
    )

    local key =
        "shotsFiredThisVolley_" .. name

    wdata[key] =
        (wdata[key] or 0) + 1

    local cap =
        (bp and bp.shots) or 1

    local allowedTotal =
        math.min(
            cap,
            startingShots - 1 + boost
        )

    allowedTotal =
        math.max(
            1,
            math.floor(allowedTotal)
        )

    if wdata[key] >= allowedTotal then
        weapon.queuedProjectiles:clear()
    end

    if weapon.queuedProjectiles:size() == 0 then
        wdata[key] = 0
    end
end

-- -----------------
-- CHAINSTEP LOGIC
-- -----------------

script.on_internal_event(
    Defines.InternalEvents.ON_TICK,
    function()
        local weapons = {}

        pcall(function()
            weapons[0] =
                Hyperspace.ships.player
                    .weaponSystem.weapons
        end)

        pcall(function()
            weapons[1] =
                Hyperspace.ships.enemy
                    .weaponSystem.weapons
        end)

        for i = 0, 1 do
            if weapons[i] then
                for weapon in vter(weapons[i]) do
                    local chainWeapon =
                        get_chainstep_weapon(weapon)

                    if chainWeapon then
                        local chargeRate =
                            weapon.cooldown.second
                            / weapon.baseCooldown

                        local fireThreshold =
                            chainWeapon.fireThreshold
                            * chargeRate

                        local chainStep =
                            chainWeapon.chainStep
                            * chargeRate

                        if weapon.cooldown.first
                            >= fireThreshold then

                            weapon.chargeLevel = 1
                        else
                            weapon.chargeLevel = 0
                        end

                        local overCharge =
                            math.floor(
                                math.max(
                                    weapon.cooldown.first
                                        - fireThreshold,
                                    0
                                ) / chainStep
                            )

                        local maxSteps =
                            get_max_chainsteps(
                                weapon,
                                chainWeapon,
                                fireThreshold,
                                chainStep
                            )

                        overCharge =
                            math.min(
                                overCharge,
                                maxSteps
                            )

                        if weapon.cooldown.first
                            >= weapon.cooldown.second then

                            overCharge = maxSteps
                        end

                        weapon.boostLevel =
                            overCharge

                        local wdata =
                            userdata_table(
                                weapon,
                                "mods.sc.chainstep"
                            )

                        local queuedShots =
                            weapon.queuedProjectiles:size()

                        if queuedShots <= 0
                            and not wdata.volleyActive then

                            wdata.level =
                                overCharge
                        end

                        if wdata.volleyActive
                            and queuedShots <= 0
                            and weapon.cooldown.first > 0 then

                            wdata.volleyActive = false
                            wdata.firingLevel = nil
                            wdata.missilePaid = false
                            wdata.level = overCharge
                        end
                    end
                end
            end
        end
    end
)

-- -----------------
-- MISSILE CHECK
-- -----------------

script.on_internal_event(
    Defines.InternalEvents.SELECT_ARMAMENT_PRE,
    function(armamentSlot)
        local ship =
            Hyperspace.ships.player

        if not ship
            or not ship.weaponSystem
            or not ship.weaponSystem.weapons then

            return Defines.Chain.CONTINUE,
                armamentSlot
        end

        local weapon =
            ship.weaponSystem.weapons[
                armamentSlot
            ]

        local chainWeapon =
            get_chainstep_weapon(weapon)

        local missileData =
            get_chainstep_stat(
                chainWeapon,
                "missileCost"
            )

        if not missileData then
            return Defines.Chain.CONTINUE,
                armamentSlot
        end

        local canPay =
            scaling.can_pay_missile_cost(
                ship,
                weapon,
                "chainstep",
                get_chainstep_level(weapon)
            )

        if not canPay then

            return Defines.Chain.PREEMPT,
                armamentSlot
        end

        return Defines.Chain.CONTINUE,
            armamentSlot
    end
)

-- -----------------
-- CHAINSTEP STATS
-- -----------------

script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_FIRE,
    function(projectile, weapon)
        local chainWeapon =
            get_chainstep_weapon(weapon)

        if not chainWeapon then
            return
        end

        local wdata = userdata_table(
            weapon,
            "mods.sc.chainstep"
        )

        if not wdata.volleyActive then
            wdata.volleyActive = true

            wdata.firingLevel =
                math.max(
                    0,
                    math.floor(
                        wdata.level
                            or weapon.boostLevel
                            or 0
                    )
                )

            wdata.missilePaid = false
        end

        local boost =
            math.max(
                0,
                math.floor(
                    wdata.firingLevel or 0
                )
            )

        local pdata = userdata_table(
            projectile,
            "mods.sc.projectileScaling"
        )

        pdata.weaponName =
            weapon.blueprint.name

        pdata.hasChainstep = true
        pdata.chainstepLevel = boost

        scaling.apply_projectile_stats(
            projectile,
            weapon,
            "chainstep",
            boost,
            {
                shots = function(
                    currentProjectile,
                    currentWeapon,
                    statBoost,
                    level
                )
                    apply_chainstep_shots(
                        currentWeapon,
                        statBoost.amount or 1,
                        level
                    )
                end
            }
        )

        if weapon.iShipId == 0 then
            scaling.pay_missile_cost_once(
                Hyperspace.ships.player,
                weapon,
                "chainstep",
                boost,
                wdata,
                "missilePaid"
            )
        end
    end
)

-- -----------------
-- CHAINSTEP TOOLTIP
-- -----------------

local function get_unique_player_weapon(weaponName)
    local ship =
        Hyperspace.ships.player

    local weapons =
        ship
        and ship.weaponSystem
        and ship.weaponSystem.weapons

    if not weapons then
        return nil
    end

    local foundWeapon = nil

    for weapon in vter(weapons) do
        if weapon
            and weapon.blueprint
            and weapon.blueprint.name == weaponName then

            if foundWeapon then
                return nil
            end

            foundWeapon = weapon
        end
    end

    return foundWeapon
end

local function get_tooltip_chainstep_level(weapon)
    if not weapon then
        return 0
    end

    local wdata = userdata_table(
        weapon,
        "mods.sc.chainstep"
    )

    if wdata.volleyActive
        and wdata.firingLevel ~= nil then

        return math.max(
            0,
            math.floor(wdata.firingLevel)
        )
    end

    return math.max(
        0,
        math.floor(
            wdata.level
                or weapon.boostLevel
                or 0
        )
    )
end

script.on_internal_event(
    Defines.InternalEvents.WEAPON_STATBOX,
    function(bp, stats)
        local chainWeapon =
            chainstepWeaponList[
                bp and bp.name
            ]

        local missileData =
            get_chainstep_stat(
                chainWeapon,
                "missileCost"
            )

        if not missileData then
            return
        end

        local baseCost =
            math.max(
                1,
                math.floor(
                    missileData.base or 1
                )
            )

        local amount =
            missileData.amount or 0

        local maxSteps =
            chainWeapon.maxSteps or 0

        local minimumCost =
            math.max(
                1,
                math.floor(
                    baseCost
                        + maxSteps
                        * amount
                )
            )

        local weapon =
            get_unique_player_weapon(
                bp.name
            )

        if weapon then
            local chainLevel =
                get_tooltip_chainstep_level(
                    weapon
                )

            local currentCost =
                scaling.calculate_missile_cost(
                    missileData,
                    chainLevel
                )

            local discounted =
                math.max(
                    0,
                    baseCost - currentCost
                )

            stats =
                stats
                .. "\n\n"
                .. "Current missile cost: "
                .. tostring(currentCost)
                .. "\n"
                .. "Missiles discounted: "
                .. tostring(discounted)
        else
            stats =
                stats
                .. "\n\n"
                .. "Base missile cost: "
                .. tostring(baseCost)
                .. "\n"
                .. "Missile change per chainstep: "
                .. tostring(amount)
                .. "\n"
                .. "Minimum missile cost: "
                .. tostring(minimumCost)
        end

        return Defines.Chain.CONTINUE,
            stats
    end
)
