--[[
SC shared targeting core.

Targeting sources register a function that returns a non-negative targeting
strength for a ship, or nil when that source is inactive. If more than one
source is active, the strongest source is used rather than stacking them.

The core owns the shared targeting effects used by those sources:
    1. Detector-style projectile accuracy.
    2. Detector-style weapon-radius reduction.
    3. Detector-style weapon charging while the enemy ship is cloaked.
    4. Anti-cloak targeting support while effective detection is active.

Anti-cloak targeting uses the same Lua-side workaround proven by Lily's
Targeting Core: while the opposing ship is cloaked, an inert hologram intruder
is temporarily placed aboard that ship. The hologram is uncontrollable,
untargetable, and has no AI. This preserves the enemy cloak state itself rather
than directly forcing ship.bCloaked false.

Source-specific activation logic remains in the source script. For example,
sc_augment_detector.lua determines whether the SC detector augment is present
and converts effective Sensors power into targeting strength.
]]

local vter = mods.multiverse.vter
local time_increment = mods.multiverse.time_increment

mods.sc = mods.sc or {}
mods.sc.targeting = mods.sc.targeting or {}

local targeting = mods.sc.targeting

local ACCURACY_PER_STRENGTH = 2.5
local MISSILE_ACCURACY_MULTIPLIER = 2
local RADIUS_REDUCTION_PER_ACCURACY = 4
local CLOAK_CHARGE_PER_STRENGTH = 0.25

local CLOAK_PROXY_NAME = "SC Targeting Proxy"
local CLOAK_PROXY_RACE = "hologram"
local CLOAK_PROXY_BOOST_DURATION = 99
local CLOAK_PROXY_BOOST_PRIORITY = 9999

targeting.sources = targeting.sources or {}
targeting.cloakProxies = targeting.cloakProxies or {}

local sources = targeting.sources
local cloakProxies = targeting.cloakProxies

-- Lily's anti-cloak workaround makes its temporary hologram completely inert.
-- Keep the same three protections here so the proxy cannot be selected,
-- controlled, or assigned AI tasks while it exists.
local cloakProxyNoControl = Hyperspace.StatBoostDefinition()
cloakProxyNoControl.stat = Hyperspace.CrewStat.CONTROLLABLE
cloakProxyNoControl.value = false
cloakProxyNoControl.boostType =
    Hyperspace.StatBoostDefinition.BoostType.SET
cloakProxyNoControl.boostSource =
    Hyperspace.StatBoostDefinition.BoostSource.AUGMENT
cloakProxyNoControl.shipTarget =
    Hyperspace.StatBoostDefinition.ShipTarget.ALL
cloakProxyNoControl.crewTarget =
    Hyperspace.StatBoostDefinition.CrewTarget.ALL
cloakProxyNoControl.duration = CLOAK_PROXY_BOOST_DURATION
cloakProxyNoControl.priority = CLOAK_PROXY_BOOST_PRIORITY
cloakProxyNoControl.realBoostId =
    Hyperspace.StatBoostDefinition.statBoostDefs:size()
Hyperspace.StatBoostDefinition.statBoostDefs:push_back(
    cloakProxyNoControl
)

local cloakProxyNotTarget = Hyperspace.StatBoostDefinition()
cloakProxyNotTarget.stat = Hyperspace.CrewStat.VALID_TARGET
cloakProxyNotTarget.value = false
cloakProxyNotTarget.boostType =
    Hyperspace.StatBoostDefinition.BoostType.SET
cloakProxyNotTarget.boostSource =
    Hyperspace.StatBoostDefinition.BoostSource.AUGMENT
cloakProxyNotTarget.shipTarget =
    Hyperspace.StatBoostDefinition.ShipTarget.ALL
cloakProxyNotTarget.crewTarget =
    Hyperspace.StatBoostDefinition.CrewTarget.ALL
cloakProxyNotTarget.duration = CLOAK_PROXY_BOOST_DURATION
cloakProxyNotTarget.priority = CLOAK_PROXY_BOOST_PRIORITY
cloakProxyNotTarget.realBoostId =
    Hyperspace.StatBoostDefinition.statBoostDefs:size()
Hyperspace.StatBoostDefinition.statBoostDefs:push_back(
    cloakProxyNotTarget
)

local cloakProxyNoAi = Hyperspace.StatBoostDefinition()
cloakProxyNoAi.stat = Hyperspace.CrewStat.NO_AI
cloakProxyNoAi.value = true
cloakProxyNoAi.boostType =
    Hyperspace.StatBoostDefinition.BoostType.SET
cloakProxyNoAi.boostSource =
    Hyperspace.StatBoostDefinition.BoostSource.AUGMENT
cloakProxyNoAi.shipTarget =
    Hyperspace.StatBoostDefinition.ShipTarget.ALL
cloakProxyNoAi.crewTarget =
    Hyperspace.StatBoostDefinition.CrewTarget.ALL
cloakProxyNoAi.duration = CLOAK_PROXY_BOOST_DURATION
cloakProxyNoAi.priority = CLOAK_PROXY_BOOST_PRIORITY
cloakProxyNoAi.realBoostId =
    Hyperspace.StatBoostDefinition.statBoostDefs:size()
Hyperspace.StatBoostDefinition.statBoostDefs:push_back(
    cloakProxyNoAi
)

function targeting.register_source(name, strengthProvider)
    if type(name) ~= "string"
        or type(strengthProvider) ~= "function" then

        return false
    end

    sources[name] = strengthProvider
    return true
end

function targeting.unregister_source(name)
    if sources[name] == nil then
        return false
    end

    sources[name] = nil
    return true
end

function targeting.get_source_strength(name, ship)
    local provider = sources[name]

    if type(provider) ~= "function" then
        return nil
    end

    local strength = provider(ship)

    if type(strength) ~= "number" then
        return nil
    end

    return math.max(0, strength)
end

function targeting.get_strength(ship)
    if not ship then
        return nil
    end

    local strongest = nil

    for _, provider in pairs(sources) do
        local strength = provider(ship)

        if type(strength) == "number" then
            strength = math.max(0, strength)

            if strongest == nil
                or strength > strongest then

                strongest = strength
            end
        end
    end

    return strongest
end

function targeting.is_active(ship)
    return targeting.get_strength(ship) ~= nil
end

function targeting.has_effective_detection(ship)
    local strength = targeting.get_strength(ship)

    return type(strength) == "number"
        and strength > 0
end

function targeting.weapon_is_missile(weapon)
    if not weapon or not weapon.blueprint then
        return false
    end

    local blueprint = weapon.blueprint

    return blueprint.typeName == "MISSILES"
        or blueprint.type == "MISSILE"
        or blueprint.type == 2
        or blueprint.name == "TERRAN_MISSILE_HALO"
end

function targeting.get_accuracy_bonus_for_strength(
    strength,
    weapon
)
    if type(strength) ~= "number" then
        return nil
    end

    local accuracyBonus =
        math.max(0, strength)
        * ACCURACY_PER_STRENGTH

    if targeting.weapon_is_missile(weapon) then
        accuracyBonus =
            accuracyBonus
            * MISSILE_ACCURACY_MULTIPLIER
    end

    return math.ceil(accuracyBonus)
end

function targeting.get_accuracy_bonus(ship, weapon)
    return targeting.get_accuracy_bonus_for_strength(
        targeting.get_strength(ship),
        weapon
    )
end

function targeting.apply_radius_modifier(
    ship,
    weapon,
    radius,
    baseRadius
)
    local accuracyBonus =
        targeting.get_accuracy_bonus(
            ship,
            weapon
        )

    if accuracyBonus == nil then
        return radius
    end

    return math.max(
        0,
        radius
            - accuracyBonus
            * RADIUS_REDUCTION_PER_ACCURACY
    )
end

-- Shared scaling loads before this file, so registration is immediate.
mods.sc.scaling.register_weapon_radius_modifier(
    "sc_targeting",
    targeting.apply_radius_modifier,
    200
)

local function cloak_proxy_is_alive(proxy)
    return proxy
        and not proxy.bDead
        and not proxy:IsDead()
end

local function get_cloak_proxy_room(enemyShip)
    if not enemyShip then
        return nil
    end

    if enemyShip.cloakSystem
        and type(enemyShip.cloakSystem.roomId) == "number"
        and enemyShip.cloakSystem.roomId >= 0 then

        return enemyShip.cloakSystem.roomId
    end

    local rooms =
        enemyShip.ship
        and enemyShip.ship.vRoomList

    if rooms and rooms:size() > 0 then
        return 0
    end

    return nil
end

local function apply_cloak_proxy_boosts(proxy)
    if not proxy then
        return
    end

    local boostManager =
        Hyperspace.StatBoostManager.GetInstance()

    boostManager:CreateTimedAugmentBoost(
        Hyperspace.StatBoost(cloakProxyNoControl),
        proxy
    )

    boostManager:CreateTimedAugmentBoost(
        Hyperspace.StatBoost(cloakProxyNotTarget),
        proxy
    )

    boostManager:CreateTimedAugmentBoost(
        Hyperspace.StatBoost(cloakProxyNoAi),
        proxy
    )
end

local function retire_cloak_proxy(shipId)
    local proxy = cloakProxies[shipId]

    if not proxy then
        return
    end

    if cloak_proxy_is_alive(proxy) then
        proxy.health.first = 0
    else
        cloakProxies[shipId] = nil
    end
end

local function update_cloak_targeting_proxy(
    ship,
    enemyShip,
    detectionActive
)
    if not ship then
        return
    end

    local shipId = ship.iShipId
    local proxy = cloakProxies[shipId]

    if proxy and not cloak_proxy_is_alive(proxy) then
        cloakProxies[shipId] = nil
        proxy = nil
    end

    local enemyCloaked =
        enemyShip
        and enemyShip.cloakSystem
        and enemyShip.cloakSystem.bTurnedOn

    if not detectionActive
        or not enemyCloaked then

        retire_cloak_proxy(shipId)
        return
    end

    local roomId =
        get_cloak_proxy_room(enemyShip)

    if roomId == nil then
        retire_cloak_proxy(shipId)
        return
    end

    -- Lily refreshes room blackout every loop while the anti-cloak proxy is
    -- active. Do the same for only the proxy room here. Full enemy-room reveal
    -- remains a later Comsat/Detector feature step.
    enemyShip.ship:SetRoomBlackout(
        roomId,
        false
    )

    if proxy then
        return
    end

    proxy = enemyShip:AddCrewMemberFromString(
        CLOAK_PROXY_NAME,
        CLOAK_PROXY_RACE,
        true,
        roomId,
        true,
        false
    )

    if not proxy then
        return
    end

    apply_cloak_proxy_boosts(proxy)
    cloakProxies[shipId] = proxy
end

targeting.update_cloak_targeting_proxy =
    update_cloak_targeting_proxy

-- Cloak targeting and cloak charging
script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    function(ship)
        if not ship then
            return
        end

        local targetingStrength =
            targeting.get_strength(ship)

        local enemyShip =
            Hyperspace.ships(1 - ship.iShipId)

        update_cloak_targeting_proxy(
            ship,
            enemyShip,
            type(targetingStrength) == "number"
                and targetingStrength > 0
        )

        if not ship.weaponSystem
            or not ship.weaponSystem.weapons
            or ship.weaponSystem.iHackEffect >= 2 then

            return
        end

        if targetingStrength == nil then
            return
        end

        if not enemyShip
            or not enemyShip.cloakSystem
            or not enemyShip.cloakSystem.bTurnedOn then

            return
        end

        for weapon in vter(
            ship.weaponSystem.weapons
        ) do
            if weapon.powered
                and weapon.subCooldown.second
                    <= weapon.subCooldown.first
                and not weapon.table[
                    "mods.multiverse.manualDecharge"
                ] then

                local oldFirst =
                    weapon.cooldown.first

                local oldSecond =
                    weapon.cooldown.second

                weapon.cooldown.first =
                    weapon.cooldown.first
                    + targetingStrength
                    * CLOAK_CHARGE_PER_STRENGTH
                    * time_increment()

                weapon.cooldown.first =
                    math.min(
                        weapon.cooldown.first,
                        weapon.cooldown.second
                    )

                if weapon.cooldown.second
                        == weapon.cooldown.first
                    and oldFirst < oldSecond
                    and weapon.chargeLevel
                        < weapon.blueprint.chargeLevels then

                    weapon.chargeLevel =
                        weapon.chargeLevel + 1

                    weapon.weaponVisual.boostLevel = 0
                    weapon.weaponVisual.boostAnim
                        :SetCurrentFrame(0)

                    if weapon.chargeLevel
                        < weapon.blueprint.chargeLevels then

                        weapon.cooldown.first = 0
                    end
                else
                    weapon.subCooldown.first =
                        weapon.subCooldown.first
                        + time_increment()

                    weapon.subCooldown.first =
                        math.min(
                            weapon.subCooldown.first,
                            weapon.subCooldown.second
                        )
                end
            end
        end
    end
)

-- Bonus accuracy
script.on_internal_event(
    Defines.InternalEvents.PROJECTILE_FIRE,
    function(projectile, weapon)
        if not projectile then
            return
        end

        local ship =
            Hyperspace.ships(projectile.ownerId)

        local accuracyBonus =
            targeting.get_accuracy_bonus(
                ship,
                weapon
            )

        if accuracyBonus ~= nil
            and projectile.extend
            and projectile.extend.customDamage then

            projectile.extend.customDamage.accuracyMod =
                projectile.extend.customDamage.accuracyMod
                + accuracyBonus
        end
    end
)