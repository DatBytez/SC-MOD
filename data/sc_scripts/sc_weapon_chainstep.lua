--[[
This code is a reimplementation of TNE_CHAINSTEP_LUA.lua from TNE.

Optional missile-cost support:

<sc-chainstep
    fireThreshold="4"
    chainStep="4"
    maxSteps="3"
    missileCost="4"
    missileStep="1"
/>

missileCost:
    Missile cost when fired at the initial fire threshold.

missileStep:
    Amount removed from the missile cost per completed chainstep.

maxSteps:
    Maximum number of chainsteps.
    If omitted, the script falls back to blueprint.boostPower.count.

Weapons using missileCost should normally use:
    <missiles>0</missiles>

Lua then pays the entire missile cost once per volley.
]]

local vter = mods.multiverse.vter
local is_first_shot = mods.multiverse.is_first_shot
local userdata_table = mods.multiverse.userdata_table

mods.multiverse.weaponTagParsers = mods.multiverse.weaponTagParsers or {}
local weaponTagParsers = mods.multiverse.weaponTagParsers

mods.sc = mods.sc or {}
mods.sc.chainstep = mods.sc.chainstep or {}

local chainstepWeaponList = mods.sc.chainstep

-- -----------------
-- XML PARSER
-- -----------------

table.insert(weaponTagParsers, function(weaponNode)
    local nameAttr = weaponNode:first_attribute("name")
    if not nameAttr then return end

    local weaponName = nameAttr:value()

    local tagNode = weaponNode:first_node("sc-chainstep")
    if not tagNode then return end

    local fireThresholdAttr = tagNode:first_attribute("fireThreshold")
    local chainStepAttr = tagNode:first_attribute("chainStep")

    if not fireThresholdAttr or not chainStepAttr then
        return
    end

    local fireThreshold = tonumber(fireThresholdAttr:value())
    local chainStep = tonumber(chainStepAttr:value())

    if not fireThreshold or not chainStep or chainStep <= 0 then
        return
    end

    local maxStepsAttr = tagNode:first_attribute("maxSteps")
    local missileCostAttr = tagNode:first_attribute("missileCost")
    local missileStepAttr = tagNode:first_attribute("missileStep")

    local maxSteps =
        maxStepsAttr and tonumber(maxStepsAttr:value()) or nil

    local missileCost =
        missileCostAttr and tonumber(missileCostAttr:value()) or nil

    local missileStep =
        missileStepAttr and tonumber(missileStepAttr:value()) or 1

    chainstepWeaponList[weaponName] = {
        fireThreshold = fireThreshold,
        chainStep = chainStep,
        maxSteps = maxSteps,
        missileCost = missileCost,
        missileStep = missileStep
    }
end)

-- -----------------
-- HELPERS
-- -----------------

local function get_chainstep_weapon(weapon)
    if not weapon or not weapon.blueprint then
        return nil
    end

    return chainstepWeaponList[weapon.blueprint.name]
end

local function get_max_chainsteps(weapon, chainWeapon, fireThreshold, chainStep)
    if chainWeapon.maxSteps ~= nil then
        return math.max(0, math.floor(chainWeapon.maxSteps))
    end

    -- Preserve compatibility with existing chainstep weapons
    -- that use <boost><count>...</count></boost>.
    if weapon.blueprint
        and weapon.blueprint.boostPower
        and weapon.blueprint.boostPower.count then

        local boostCount = weapon.blueprint.boostPower.count

        if boostCount > 0 then
            return boostCount
        end
    end

    -- Final fallback: calculate how many full steps fit
    -- between the fire threshold and maximum cooldown.
    if chainStep > 0 then
        return math.max(
            0,
            math.floor(
                math.max(
                    weapon.cooldown.second - fireThreshold,
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
        math.floor(wdata.level or 0)
    )
end

local function get_chainstep_missile_cost(weapon, chainWeapon)
    if not weapon or not chainWeapon then
        return nil
    end

    if chainWeapon.missileCost == nil then
        return nil
    end

    local chainLevel = get_chainstep_level(weapon)

    local cost =
        chainWeapon.missileCost
        - chainLevel * chainWeapon.missileStep

    return math.max(
        1,
        math.floor(cost)
    )
end

-- -----------------
-- CHAINSTEP LOGIC
-- -----------------

script.on_internal_event(Defines.InternalEvents.ON_TICK, function()

    local weapons = {}

    pcall(function()
        weapons[0] = Hyperspace.ships.player.weaponSystem.weapons
    end)

    pcall(function()
        weapons[1] = Hyperspace.ships.enemy.weaponSystem.weapons
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

                    -- Weapon becomes fireable once it reaches
                    -- the initial fire threshold.
                    if weapon.cooldown.first >= fireThreshold then
                        weapon.chargeLevel = 1
                    else
                        weapon.chargeLevel = 0
                    end

                    -- Number of completed chainsteps AFTER
                    -- reaching the initial firing threshold.
                    local overCharge = math.floor(
                        math.max(
                            weapon.cooldown.first - fireThreshold,
                            0
                        ) / chainStep
                    )

                    local maxSteps = get_max_chainsteps(
                        weapon,
                        chainWeapon,
                        fireThreshold,
                        chainStep
                    )

                    overCharge = math.min(
                        overCharge,
                        maxSteps
                    )

                    if weapon.cooldown.first >= weapon.cooldown.second then
                        overCharge = maxSteps
                    end

                    weapon.boostLevel = overCharge

                    -- Store our own copy so missile cost does not
                    -- depend on projectile count or charge weapons.
                    local wdata = userdata_table(
                        weapon,
                        "mods.sc.chainstep"
                    )

                    wdata.level = overCharge
                end
            end
        end
    end
end)

-- -----------------
-- MISSILE CHECK
-- -----------------

script.on_internal_event(
    Defines.InternalEvents.SELECT_ARMAMENT_PRE,
    function(armamentSlot)

        local ship = Hyperspace.ships.player

        if not ship
            or not ship.weaponSystem
            or not ship.weaponSystem.weapons then

            return Defines.Chain.CONTINUE, armamentSlot
        end

        local weapon =
            ship.weaponSystem.weapons[armamentSlot]

        local chainWeapon =
            get_chainstep_weapon(weapon)

        if not chainWeapon
            or chainWeapon.missileCost == nil then

            return Defines.Chain.CONTINUE, armamentSlot
        end

        local missileCost =
            get_chainstep_missile_cost(
                weapon,
                chainWeapon
            )

        if missileCost
            and ship:GetMissileCount() < missileCost then

            return Defines.Chain.PREEMPT, armamentSlot
        end

        return Defines.Chain.CONTINUE, armamentSlot
    end
)

-- -----------------
-- MISSILE PAYMENT
-- -----------------

script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_FIRE,
    function(projectile, weapon)

        local chainWeapon =
            get_chainstep_weapon(weapon)

        if not chainWeapon
            or chainWeapon.missileCost == nil then
            return
        end

        -- Only charge player weapons.
        if weapon.iShipId ~= 0 then
            return
        end

        -- Most important part:
        -- pay ONCE for the entire volley.
        if not is_first_shot(weapon, true) then
            return
        end

        local ship = Hyperspace.ships.player
        if not ship then return end

        local missileCost =
            get_chainstep_missile_cost(
                weapon,
                chainWeapon
            )

        if missileCost and missileCost > 0 then
            ship:ModifyMissileCount(-missileCost)
        end
    end
)