--[[
DESCRIPTION: Shared targeting effects for Detector-style sources.
        - Adds projectile accuracy and reduces weapon targeting radius.
        - Allows weapon charging while the opposing ship is cloaked.
        - Preserves targeting against cloaked ships through an invisible crew.
        - Makes specifically listed invisible enemy crew targetable.
DEPENDENCIES: sc_radius_core.lua, Multiverse vter, Multiverse time_increment
]]

local vter = mods.multiverse.vter
local time_increment = mods.multiverse.time_increment

mods.sc.targeting = mods.sc.targeting or {}
local targeting = mods.sc.targeting

local ACCURACY_PER_STRENGTH = 2.5
local MISSILE_ACCURACY_MULTIPLIER = 2
local RADIUS_REDUCTION_PER_ACCURACY = 4
local CLOAK_CHARGE_PER_STRENGTH = 0.25

local CLOAK_PROXY_BOOST_DURATION = 99
local CLOAK_PROXY_BOOST_PRIORITY = 9999

local LIST_SC_CREW_INVISIBLE = {
    terran_ghost = true
}

local sources = {}
local cloakProxies = {}

local function create_cloak_proxy_boost(stat, value)
    local boost = Hyperspace.StatBoostDefinition()
    boost.stat = stat
    boost.value = value
    boost.boostType = Hyperspace.StatBoostDefinition.BoostType.SET
    boost.boostSource = Hyperspace.StatBoostDefinition.BoostSource.AUGMENT
    boost.shipTarget = Hyperspace.StatBoostDefinition.ShipTarget.ALL
    boost.crewTarget = Hyperspace.StatBoostDefinition.CrewTarget.ALL
    boost.duration = CLOAK_PROXY_BOOST_DURATION
    boost.priority = CLOAK_PROXY_BOOST_PRIORITY
    boost.realBoostId = Hyperspace.StatBoostDefinition.statBoostDefs:size()

    Hyperspace.StatBoostDefinition.statBoostDefs:push_back(boost)
    return boost
end

local cloakProxyNoControl = create_cloak_proxy_boost(Hyperspace.CrewStat.CONTROLLABLE, false)
local cloakProxyNotTarget = create_cloak_proxy_boost(Hyperspace.CrewStat.VALID_TARGET, false)
local cloakProxyNoAi = create_cloak_proxy_boost(Hyperspace.CrewStat.NO_AI, true)

function targeting.register_source(name, strengthProvider)
    sources[name] = strengthProvider
end

local function get_strength(ship)
    if not ship then return nil end

    local strongest

    for _, provider in pairs(sources) do
        local strength = provider(ship)

        if strength ~= nil and (strongest == nil or strength > strongest) then
            strongest = strength
        end
    end

    return strongest
end

local function has_effective_detection(ship)
    local strength = get_strength(ship)
    return strength ~= nil and strength > 0
end

script.on_internal_event(Defines.InternalEvents.CALCULATE_STAT_POST, function(crew, stat, _def, amount, value)
    if stat ~= Hyperspace.CrewStat.VALID_TARGET or value or not LIST_SC_CREW_INVISIBLE[crew.species] then
        return Defines.Chain.CONTINUE, amount, value
    end

    local crewShipId = crew.iShipId
    if crewShipId ~= 0 and crewShipId ~= 1 then
        return Defines.Chain.CONTINUE, amount, value
    end

    if has_effective_detection(Hyperspace.ships(1 - crewShipId)) then
        value = true
    end

    return Defines.Chain.CONTINUE, amount, value
end)

local function weapon_is_missile(weapon)
    return weapon.blueprint.typeName == "MISSILES"
        or weapon.blueprint.name == "TERRAN_MISSILE_HALO"
end

local function get_accuracy_bonus(ship, weapon)
    local strength = get_strength(ship)
    if strength == nil then return nil end

    local accuracyBonus = strength * ACCURACY_PER_STRENGTH

    if weapon_is_missile(weapon) then
        accuracyBonus = accuracyBonus * MISSILE_ACCURACY_MULTIPLIER
    end

    return math.ceil(accuracyBonus)
end

local function apply_radius_modifier(ship, weapon, radius)
    local accuracyBonus = get_accuracy_bonus(ship, weapon)
    if accuracyBonus == nil then return radius end

    return math.max(0, radius - accuracyBonus * RADIUS_REDUCTION_PER_ACCURACY)
end

mods.sc.radius.register_modifier("sc_targeting", apply_radius_modifier, 200)

local function cloak_proxy_is_alive(proxy)
    return proxy and not proxy.bDead and not proxy:IsDead()
end

local function apply_cloak_proxy_boosts(proxy)
    local boostManager = Hyperspace.StatBoostManager.GetInstance()

    boostManager:CreateTimedAugmentBoost(Hyperspace.StatBoost(cloakProxyNoControl), proxy)
    boostManager:CreateTimedAugmentBoost(Hyperspace.StatBoost(cloakProxyNotTarget), proxy)
    boostManager:CreateTimedAugmentBoost(Hyperspace.StatBoost(cloakProxyNoAi), proxy)
end

local function retire_cloak_proxy(shipId)
    local proxy = cloakProxies[shipId]
    if not proxy then return end

    if cloak_proxy_is_alive(proxy) then
        proxy.health.first = 0
    else
        cloakProxies[shipId] = nil
    end
end

local function update_cloak_targeting_proxy(shipId, enemyShip, detectionActive)
    local proxy = cloakProxies[shipId]

    if proxy and not cloak_proxy_is_alive(proxy) then
        cloakProxies[shipId] = nil
        proxy = nil
    end

    if not detectionActive
        or not enemyShip
        or not enemyShip.cloakSystem
        or not enemyShip.cloakSystem.bTurnedOn then

        retire_cloak_proxy(shipId)
        return
    end

    local roomId = enemyShip.cloakSystem.roomId

    if roomId < 0 then
        retire_cloak_proxy(shipId)
        return
    end

    enemyShip.ship:SetRoomBlackout(roomId, false)

    if proxy then return end

    proxy = enemyShip:AddCrewMemberFromString("Targeting System", "hologram", true, roomId, true, false)

    if not proxy then return end

    apply_cloak_proxy_boosts(proxy)
    cloakProxies[shipId] = proxy
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    local targetingStrength = get_strength(ship)
    local enemyShip = Hyperspace.ships(1 - ship.iShipId)

    update_cloak_targeting_proxy(
        ship.iShipId,
        enemyShip,
        targetingStrength ~= nil and targetingStrength > 0
    )

    if not ship.weaponSystem or ship.weaponSystem.iHackEffect >= 2 then return end
    if targetingStrength == nil then return end
    if not enemyShip or not enemyShip.cloakSystem or not enemyShip.cloakSystem.bTurnedOn then return end

    for weapon in vter(ship.weaponSystem.weapons) do
        if weapon.powered
            and weapon.subCooldown.second <= weapon.subCooldown.first
            and not weapon.table["mods.multiverse.manualDecharge"] then

            local oldFirst = weapon.cooldown.first

            weapon.cooldown.first = math.min(
                weapon.cooldown.first
                    + targetingStrength
                    * CLOAK_CHARGE_PER_STRENGTH
                    * time_increment(),
                weapon.cooldown.second
            )

            if weapon.cooldown.second == weapon.cooldown.first
                and oldFirst < weapon.cooldown.second
                and weapon.chargeLevel < weapon.blueprint.chargeLevels then

                weapon.chargeLevel = weapon.chargeLevel + 1
                weapon.weaponVisual.boostLevel = 0
                weapon.weaponVisual.boostAnim:SetCurrentFrame(0)

                if weapon.chargeLevel < weapon.blueprint.chargeLevels then
                    weapon.cooldown.first = 0
                end
            else
                weapon.subCooldown.first = math.min(
                    weapon.subCooldown.first + time_increment(),
                    weapon.subCooldown.second
                )
            end
        end
    end
end)

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    local accuracyBonus = get_accuracy_bonus(Hyperspace.ships(projectile.ownerId), weapon)
    if accuracyBonus == nil then return end

    projectile.extend.customDamage.accuracyMod =
        projectile.extend.customDamage.accuracyMod + accuracyBonus
end)