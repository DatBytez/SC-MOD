--[[
DESCRIPTION: Grants advanced Sensors abilities based on Sensors power.
        - Restores Sensors power in nebulas when the installed level is 4 or greater.
        - Reveals cloaked enemy rooms and makes listed invisible crew targetable at effective Sensors level 5 or greater.
        - Allows weapons to charge at their normal rate against cloaked ships at effective Sensors level 5 or greater.
        - Does not require the Detector augment or an active Comsat.
DEPENDENCIES: Multiverse vter, Multiverse time_increment, SC_LIST_CREW_INVISIBLE, sc_target
]]

local vter = mods.multiverse.vter
local time_increment = mods.multiverse.time_increment

mods.sc = mods.sc or {}
mods.sc.sensors = mods.sc.sensors or {}

local sensorsCore = mods.sc.sensors
local cloakProxies = {}
local invisibleCrew = {}

for crew in vter(Hyperspace.Blueprints:GetBlueprintList("SC_LIST_CREW_INVISIBLE")) do
    invisibleCrew[crew] = true
end

function sensorsCore.can_detect_stealth(ship)
    local sensors = ship and ship:GetSystem(7)

    return sensors ~= nil
        and sensors:Functioning()
        and sensors:GetEffectivePower() >= 5
end

script.on_internal_event(Defines.InternalEvents.CALCULATE_STAT_POST, function(crew, stat, _def, amount, value)
    if stat ~= Hyperspace.CrewStat.VALID_TARGET or value or not invisibleCrew[crew.species] then
        return Defines.Chain.CONTINUE, amount, value
    end

    local crewShipId = crew.iShipId
    if crewShipId ~= 0 and crewShipId ~= 1 then
        return Defines.Chain.CONTINUE, amount, value
    end

    if sensorsCore.can_detect_stealth(Hyperspace.ships(1 - crewShipId)) then
        value = true
    end

    return Defines.Chain.CONTINUE, amount, value
end)

local function retire_cloak_proxy(shipId)
    local proxy = cloakProxies[shipId]
    if not proxy then return end

    if not proxy.bDead and not proxy:IsDead() then
        proxy.health.first = 0
    else
        cloakProxies[shipId] = nil
    end
end

local function update_cloak_targeting_proxy(shipId, enemyShip, detectionActive)
    local proxy = cloakProxies[shipId]

    if proxy and (proxy.bDead or proxy:IsDead()) then
        cloakProxies[shipId] = nil
        proxy = nil
    end

    if not detectionActive or not enemyShip or enemyShip.bDestroyed
        or not enemyShip.cloakSystem or not enemyShip.cloakSystem.bTurnedOn then

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

    proxy = enemyShip:AddCrewMemberFromString("Detector", "sc_target", true, roomId, true, false)
    if not proxy then return end

    cloakProxies[shipId] = proxy
end

local function charge_weapons_against_cloak(ship, enemyShip)
    if not ship.weaponSystem or ship.weaponSystem.iHackEffect >= 2 then return end
    if not enemyShip or not enemyShip.cloakSystem or not enemyShip.cloakSystem.bTurnedOn then return end

    for weapon in vter(ship.weaponSystem.weapons) do
        if weapon.powered
            and weapon.subCooldown.second <= weapon.subCooldown.first
            and not weapon.table["mods.multiverse.manualDecharge"] then

            local oldFirst = weapon.cooldown.first

            weapon.cooldown.first = math.min(
                weapon.cooldown.first + time_increment(),
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
end

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    local shipId = ship.iShipId
    if shipId ~= 0 and shipId ~= 1 then return end

    local sensors = ship:GetSystem(7)

    if sensors and Hyperspace.App.world.space.bNebula
        and sensors.powerState.second >= 4 then

        sensors:SetPowerCap(sensors.powerState.second + 22)
    end

    local enemyShip = Hyperspace.ships(1 - shipId)
    local detectionActive = sensorsCore.can_detect_stealth(ship)

    update_cloak_targeting_proxy(shipId, enemyShip, detectionActive)

    if not detectionActive then return end
    charge_weapons_against_cloak(ship, enemyShip)
end)

script.on_init(function()
    cloakProxies = {}
end)

script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, function()
    cloakProxies = {}
end)

script.on_render_event(Defines.RenderEvents.CREW_MEMBER_HEALTH, function(crew)
        if crew.species == "sc_target" then
            return Defines.Chain.PREEMPT
        end

        return Defines.Chain.CONTINUE
    end,
    function() end)
