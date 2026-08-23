--[[
DESCRIPTION: Implements SC Chainstep weapon behavior.
        - Uses a configurable fire threshold, chainstep duration, and optional maximum steps.
        - Stores the frozen chainstep level on each fired projectile for shared stat/radius scaling.
        - Handles Chainstep shot-count scaling.
        - Handles Chainstep variable missile cost, payment, selection checks, and tooltip text.
TAG:
        <sc-chainstep fireThreshold="#" chainStep="#" maxSteps="#"/>
        <sc-chainstep stat="..." value="#"/>
        <sc-chainstep stat="missileCost" base="#" value="#"/>
DEPENDENCIES: sc_tag.lua, sc_projectile_scaling.lua, Multiverse userdata_table, Multiverse vter
]]

local vter = mods.multiverse.vter
local userdata_table = mods.multiverse.userdata_table
local scaling = mods.sc.scaling

mods.sc.chainstep = mods.sc.chainstep or {}
local chainstepWeaponList = mods.sc.chainstep

local function parse_chainstep(tagNode)
    local data = {
        statBoosts = {}
    }

    while tagNode do
        local fireThresholdAttr =
            tagNode:first_attribute("fireThreshold")

        local chainStepAttr =
            tagNode:first_attribute("chainStep")

        if fireThresholdAttr and chainStepAttr then
            data.fireThreshold =
                tonumber(fireThresholdAttr:value())

            data.chainStep =
                tonumber(chainStepAttr:value())

            local maxStepsAttr =
                tagNode:first_attribute("maxSteps")

            data.maxSteps =
                maxStepsAttr
                and tonumber(maxStepsAttr:value())
                or nil
        end

        local statAttr =
            tagNode:first_attribute("stat")

        if statAttr then
            local entry = {
                stat = statAttr:value(),
                value = tonumber(
                    tagNode:first_attribute("value"):value()
                )
            }

            local baseAttr =
                tagNode:first_attribute("base")

            if baseAttr then
                entry.base =
                    tonumber(baseAttr:value())
            end

            table.insert(
                data.statBoosts,
                entry
            )
        end

        tagNode =
            tagNode:next_sibling("sc-chainstep")
    end

    if not data.fireThreshold
        or not data.chainStep
        or data.chainStep <= 0 then

        return nil
    end

    return data
end

mods.sc.tag.register(
    "weapon",
    "sc-chainstep",
    chainstepWeaponList,
    parse_chainstep
)

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
    if not chainWeapon then return nil end

    for _, statBoost in ipairs(
        chainWeapon.statBoosts
    ) do
        if statBoost.stat == statName then
            return statBoost
        end
    end
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

    local boostPower =
        weapon.blueprint.boostPower

    if boostPower and boostPower.count > 0 then
        return boostPower.count
    end

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

local function get_chainstep_level(weapon)
    local wdata =
        userdata_table(
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

local function apply_chainstep_shots(
    weapon,
    startingShots,
    boost
)
    local name = weapon.blueprint.name

    local wdata =
        userdata_table(
            weapon,
            "mods.sc.chainstep"
        )

    local key =
        "shotsFiredThisVolley_" .. name

    wdata[key] =
        (wdata[key] or 0) + 1

    local allowedTotal =
        math.min(
            weapon.blueprint.shots or 1,
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

local function calculate_missile_cost(
    missileData,
    level
)
    local baseCost =
        tonumber(missileData.base) or 1

    local value =
        tonumber(missileData.value) or 0

    return math.max(
        1,
        math.floor(
            baseCost
            + math.max(0, tonumber(level) or 0)
            * value
        )
    )
end

local function can_pay_missile_cost(
    ship,
    missileData,
    level
)
    return ship:GetMissileCount()
        >= calculate_missile_cost(
            missileData,
            level
        )
end

local function pay_missile_cost_once(
    ship,
    missileData,
    level,
    wdata
)
    if not missileData
        or wdata.missilePaid then

        return
    end

    ship:ModifyMissileCount(
        -calculate_missile_cost(
            missileData,
            level
        )
    )

    wdata.missilePaid = true
end

script.on_internal_event(
    Defines.InternalEvents.ON_TICK,
    function()
        for shipId = 0, 1 do
            local ship =
                Hyperspace.ships(shipId)

            local weapons =
                ship
                and ship.weaponSystem
                and ship.weaponSystem.weapons

            if weapons then
                for weapon in vter(weapons) do
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

script.on_internal_event(
    Defines.InternalEvents.SELECT_ARMAMENT_PRE,
    function(armamentSlot)
        local ship =
            Hyperspace.ships.player

        local weapons =
            ship
            and ship.weaponSystem
            and ship.weaponSystem.weapons

        if not weapons then
            return Defines.Chain.CONTINUE,
                armamentSlot
        end

        local weapon =
            weapons[armamentSlot]

        local chainWeapon =
            get_chainstep_weapon(weapon)

        local missileData =
            get_chainstep_stat(
                chainWeapon,
                "missileCost"
            )

        if missileData
            and not can_pay_missile_cost(
                ship,
                missileData,
                get_chainstep_level(weapon)
            ) then

            return Defines.Chain.PREEMPT,
                armamentSlot
        end

        return Defines.Chain.CONTINUE,
            armamentSlot
    end
)

script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_FIRE,
    function(projectile, weapon)
        local chainWeapon =
            get_chainstep_weapon(weapon)

        if not chainWeapon then return end

        local wdata =
            userdata_table(
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

        local pdata =
            userdata_table(
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
                    _projectile,
                    currentWeapon,
                    statBoost,
                    level
                )
                    apply_chainstep_shots(
                        currentWeapon,
                        statBoost.value,
                        level
                    )
                end
            }
        )

        if weapon.iShipId == 0 then
            pay_missile_cost_once(
                Hyperspace.ships.player,
                get_chainstep_stat(
                    chainWeapon,
                    "missileCost"
                ),
                boost,
                wdata
            )
        end
    end
)

local function get_unique_player_weapon(
    weaponName
)
    local ship =
        Hyperspace.ships.player

    local weapons =
        ship
        and ship.weaponSystem
        and ship.weaponSystem.weapons

    if not weapons then return nil end

    local foundWeapon = nil

    for weapon in vter(weapons) do
        if weapon.blueprint.name
            == weaponName then

            if foundWeapon then
                return nil
            end

            foundWeapon = weapon
        end
    end

    return foundWeapon
end

local function get_tooltip_chainstep_level(
    weapon
)
    local wdata =
        userdata_table(
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
            chainstepWeaponList[bp.name]

        local missileData =
            get_chainstep_stat(
                chainWeapon,
                "missileCost"
            )

        if not missileData then return end

        local baseCost =
            math.max(
                1,
                math.floor(
                    missileData.base or 1
                )
            )

        local value =
            missileData.value or 0

        local maxSteps =
            chainWeapon.maxSteps or 0

        local minimumCost =
            math.max(
                1,
                math.floor(
                    baseCost
                    + maxSteps * value
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
                calculate_missile_cost(
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
                .. tostring(value)
                .. "\n"
                .. "Minimum missile cost: "
                .. tostring(minimumCost)
        end

        return Defines.Chain.CONTINUE,
            stats
    end
)
