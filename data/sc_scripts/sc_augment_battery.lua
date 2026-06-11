--[[
DESCRIPTION: Upgrades battery system to act as Shock Neutralizer and System Boost
		Systems powered by battery
		- Reduice ion damage more quickly
		- Engines encrease evade
		- Oxygen supresses fire
		- Clone experience loss reduced (wip)
		- Drone rebuild faster (wip)
SOURCE CREDIT: MsBinaryLily
]]

local vter = mods.multiverse.vter
local modf = math.modf

local activationTimer = 0
local sfxPlayed = false

-- Adjustable Scales (Still need lots of balancing)
local O2_REFILL_FACTOR_PER_SCALE = 5.00

local FIRE_EXTINGUISHER_AUG = "TERRAN_HIDDEN_FIRE_EXTINGUISHERS"
local FTL_BOOSTER_AUG = "TERRAN_HIDDEN_FTL_BOOSTER"

local function find_system_by_name(shipManager, systemName)
    local systemId = Hyperspace.ShipSystem.NameToSystemId(systemName)
    if not shipManager or not shipManager.vSystemList then return nil end
    for system in vter(shipManager.vSystemList) do
        if system and system.GetId and system:GetId() == systemId then
            return system
        end
    end
    return nil
end
 
local function find_system_by_id(shipMgr, sysId)
    if not shipMgr or not shipMgr.vSystemList then return nil end
    for sys in vter(shipMgr.vSystemList) do
        if sys and sys.GetId and sys:GetId() == sysId then
            return sys
        end
    end
    return nil
end

local function get_bars_and_level(shipManager, systemName)
    local system = find_system_by_name(shipManager, systemName)
    if not system then return 0, 0, 0 end

    local batteryPow = system.iBatteryPower or 0
    local systemPow= system:GetEffectivePower()
    local systemLvl = system:GetMaxPower()
    return batteryPow, systemPow, systemLvl
end

local PILOT_SYSTEM_ID = 6

local function piloting_allows_positive_dodge(shipManager)
    if not shipManager then return false end

    local piloting = shipManager:GetSystem(PILOT_SYSTEM_ID)
    if not piloting then return false end

    if not piloting.bManned then return false end
    if piloting:CompletelyDestroyed() then return false end

    local pilotingPower = piloting:GetEffectivePower() or 0
    if pilotingPower <= 0 then return false end

    return true
end

local activeHiddenAugs = {}
local activeAugs = {}

local function get_hidden_aug_name(augName)
    return "HIDDEN " .. augName
end

local function get_ship_hidden_aug_table(shipManager)
    if not shipManager then return nil end

    local shipId = shipManager.iShipId
    if shipId == nil then
        shipId = -1
    end

    activeHiddenAugs[shipId] = activeHiddenAugs[shipId] or {}
    return activeHiddenAugs[shipId]
end

local function set_hidden_aug(shipManager, augName, enabled)
    if not shipManager then return end
    if not augName then return end

    local shipAugs = get_ship_hidden_aug_table(shipManager)
    if not shipAugs then return end

    local hiddenAug = get_hidden_aug_name(augName)
    local currentlyEnabled = shipAugs[augName] == true

    if enabled and not currentlyEnabled then
        shipManager:AddAugmentation(hiddenAug)
        shipAugs[augName] = true

    elseif not enabled and currentlyEnabled then
        shipManager:RemoveAugmentation(hiddenAug)
        shipAugs[augName] = false
    end
end

local function set_aug(shipManager, augName, enabled)
    local shipId = shipManager.iShipId or 0
    activeAugs[shipId] = activeAugs[shipId] or {}
    local shipAugs = activeAugs[shipId]

    local currentlyEnabled = shipAugs[augName] == true
    if enabled == nil then enabled = false end

    local augBp = Hyperspace.Blueprints:GetAugmentBlueprint(augName)
    if not augBp then
        shipAugs[augName] = false
        return
    end

    if enabled and not currentlyEnabled then
        shipManager:AddAugmentation(augBp)
        shipAugs[augName] = true

    elseif not enabled and currentlyEnabled then
        shipManager:RemoveAugmentation(augBp)
        shipAugs[augName] = false
    end
end

local function clear_scaling_hidden_aug(shipManager, augName, batteryPow)
    -- Clear all scaling variants except the one matching batteryPow.
    if batteryPow ~= 1 then
        set_hidden_aug(shipManager, augName .. "_1", false)
    end
    if batteryPow ~= 2 then
        set_hidden_aug(shipManager, augName .. "_2", false)
    end
    if batteryPow ~= 3 then
        set_hidden_aug(shipManager, augName .. "_3", false)
    end
end

local function set_scaling_hidden_aug(shipManager, augName, enabled, batteryPow)
	clear_scaling_hidden_aug(shipManager, augName, batteryPow)
	if batteryPow >= 3 then
    	    set_hidden_aug(shipManager, augName .. "_3", enabled)
	elseif batteryPow == 2 then
	    set_hidden_aug(shipManager, augName .. "_2", enabled)
	elseif batteryPow == 1 then
	    set_hidden_aug(shipManager, augName .. "_1", enabled)
		end
	end

-- Dodge bonus
script.on_internal_event(Defines.InternalEvents.GET_DODGE_FACTOR, function(shipManager, dodge)
    if shipManager:HasAugmentation("TERRAN_WRAITH_BATTERY") <= 0 then return end

    local battery = shipManager.batterySystem
    if not (battery and battery.bTurnedOn) then return end

    local batteryPow, systemPow, systemLvl = get_bars_and_level(shipManager, "engines")
    if batteryPow < 1 then return end

    local alpha = activationTimer
    if alpha <= 0 then return end

    local penalty = (0.47 * systemPow)
    local bonus = alpha * (2.0 + (0.4 * systemLvl) - penalty)
    bonus = math.floor(bonus * batteryPow)

    -- Positive dodge bonuses require manned, functioning piloting.
    if bonus > 0 and not piloting_allows_positive_dodge(shipManager) then
        bonus = 0
    end

    if bonus == 0 then return end

    dodge = dodge + bonus

    return 0, dodge
end)

-- Charge activationTimer while Battery is ON
script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if shipManager:HasAugmentation("TERRAN_WRAITH_BATTERY") <= 0 then
        activationTimer = 0
	clear_scaling_hidden_aug(shipManager, FIRE_EXTINGUISHER_AUG, 0)
	set_hidden_aug(shipManager, FTL_BOOSTER_AUG, false)
        return
    end

    local batteryId = Hyperspace.ShipSystem.NameToSystemId("battery")
    if not shipManager:HasSystem(batteryId) then
        activationTimer = 0
	clear_scaling_hidden_aug(shipManager, FIRE_EXTINGUISHER_AUG, 0)
	set_hidden_aug(shipManager, FTL_BOOSTER_AUG, false)
        return
    end

    local battery = shipManager.batterySystem
    if not (battery and battery.bTurnedOn) then
        activationTimer = 0
	clear_scaling_hidden_aug(shipManager, FIRE_EXTINGUISHER_AUG, 0)
	set_hidden_aug(shipManager, FTL_BOOSTER_AUG, false)
        return
    end

    local tick = Hyperspace.FPS.SpeedFactor / 16

    local multiplier = 0.15
    activationTimer = math.max(
        0,
        math.min(1, (activationTimer or 0) + multiplier * tick)
    )

    -- Ready sound once fully charged
    if (activationTimer or 0) < 1 then
        sfxPlayed = false
    end
    if (activationTimer or 0) >= 1 and not sfxPlayed then
        Hyperspace.Sounds:PlaySoundMix("lily_shock_neutralizer_select_1", -1, false)
        sfxPlayed = true
    end

    -- Shock neutralizer effect (systems de-ionize faster)
    for system in vter(shipManager.vSystemList) do
        if system then
            local batteryPow = (system.iBatteryPower or 0)
            if batteryPow > 0 then
                if system.iLockCount and system.iLockCount > 0 then
                    local systemLvl = system:GetMaxPower()
                    local scale = math.max(0, batteryPow * systemLvl)
                    local deionizationBoost = (activationTimer or 0) * 0.15 * scale

                    if system:GetId() == Hyperspace.ShipSystem.NameToSystemId("cloaking") then
                        deionizationBoost = deionizationBoost * 0.5
                    end

                    system.lockTimer.currTime = system.lockTimer.currTime + tick * deionizationBoost
                end
            end
        end
    end

    -- Oxygen
    local oxygenSystem = find_system_by_name(shipManager, "oxygen")
    local oxygen = shipManager.oxygenSystem
    local oxygenBatteryActive = false
    local oxygenBatteryPow = 0

    if oxygenSystem and oxygen and oxygen.oxygenLevels and oxygenSystem:Powered() then
        oxygenBatteryPow = oxygenSystem.iBatteryPower
        if oxygenBatteryPow == nil then
            oxygenBatteryPow = 0
        end

        if oxygenBatteryPow > 0 then
            oxygenBatteryActive = true

            local oxygenSystemPow = oxygenSystem:GetEffectivePower()
            local alpha = activationTimer
            if alpha == nil then
                alpha = 0
            end

            if alpha > 0 and oxygenSystemPow > 0 then
                local refill = oxygen:GetRefillSpeed()
                local scale = math.max(0, oxygenBatteryPow * oxygenSystemPow)
                local extraFactor = alpha * O2_REFILL_FACTOR_PER_SCALE * scale

                if extraFactor > 0 then
                    local delta = refill * tick * extraFactor
                    if delta ~= 0 then
                        local levels = oxygen.oxygenLevels
                        for i = 0, levels:size() - 1 do
                            levels[i] = math.min(math.max(levels[i] + delta, 0), 100)
                        end
                    end
                end
            end
        end
    end
    set_scaling_hidden_aug(shipManager, FIRE_EXTINGUISHER_AUG, oxygenBatteryActive, oxygenBatteryPow)

    -- FTL booster: enable while Engines are receiving battery power
    local enginesSystem = find_system_by_name(shipManager, "engines")
    local enginesBatteryActive = false
    if enginesSystem and enginesSystem:Powered() then
        local enginesBatteryPow = enginesSystem.iBatteryPower
        if enginesBatteryPow == nil then enginesBatteryPow = 0 end
        if enginesBatteryPow > 0 then enginesBatteryActive = true end
    end
    set_hidden_aug(shipManager, FTL_BOOSTER_AUG, enginesBatteryActive)
end)

-- Ship-floor visuals from Lily
local function render_shock_neutralizer_effects(ship, experimental)
    local shipManager = Hyperspace.ships(ship.iShipId)
    if not shipManager then return end
    if shipManager:HasAugmentation("TERRAN_WRAITH_BATTERY") <= 0 then return end

    local batteryId = Hyperspace.ShipSystem.NameToSystemId("battery")
    if not shipManager:HasSystem(batteryId) then return end

    local battery = shipManager.batterySystem
    if not (battery and battery.bTurnedOn) then return end

    --local level = get_battery_max_level(shipManager)
    local level = battery:GetMaxPower()
    if level <= 0 then return end

    local shipId = shipManager.iShipId or 0
    local alpha = activationTimer or 0
    if alpha <= 0 then return end

    local poweredRooms = {}
    for sys in vter(shipManager.vSystemList) do
        if sys and ((sys.iBatteryPower or 0) > 0) then
            poweredRooms[sys.roomId] = true
        end
    end

    local rooms = ship.vRoomList
    for roomId, _ in pairs(poweredRooms) do
        local roomdata = rooms[roomId]
        if roomdata then
            local rect = roomdata.rect
            local baseG = math.min(1, (25 * level + 154) / 255)
            local color1 = Graphics.GL_Color(14 / 255, baseG, 255 / 255, alpha)
            local color2 = Graphics.GL_Color(14 / 255, baseG, 255 / 255, 0.4 * alpha)

            Graphics.CSurface.GL_PushMatrix()
            Graphics.CSurface.GL_DrawRectOutline(rect.x, rect.y, rect.w, rect.h, color2, (level + 5) * alpha)
            Graphics.CSurface.GL_DrawRectOutline(rect.x, rect.y, rect.w, rect.h, color2, (level + 3) * alpha)
            Graphics.CSurface.GL_DrawRectOutline(rect.x, rect.y, rect.w, rect.h, color1, (level + 1) * alpha)
            Graphics.CSurface.GL_PopMatrix()
        end
    end
end
script.on_render_event(Defines.RenderEvents.SHIP_FLOOR, function() end, render_shock_neutralizer_effects)