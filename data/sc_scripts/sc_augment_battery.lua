--[[
DESCRIPTION: Upgrades battery system to act as Shock Neutralizer and System Boost
		Systems powered by battery
		- Reduce ion damage more quickly
		- Engines increase evade
		- Oxygen suppresses fire
		- Drone rebuild faster (wip)
SOURCE CREDIT: MsBinaryLily
]]

local vter = mods.multiverse.vter
local helpers = mods.sc.helpers or require("mods.sc.helpers")

local activationTimer = 0
local sfxPlayed = false

-- Adjustable Scales (Still need lots of balancing)
local O2_REFILL_FACTOR_PER_SCALE = 5.00
local FIRE_EXTINGUISHER_AUG = "TERRAN_HIDDEN_FIRE_EXTINGUISHERS"
local FTL_BOOSTER_AUG = "TERRAN_HIDDEN_FTL_BOOSTER"

local function get_bars_and_level(shipManager, systemName)
    local system = helpers.get_system_by_name(shipManager, systemName)
    if not system then return 0, 0, 0 end

    local batteryPow = system.iBatteryPower
    local systemPow= system:GetEffectivePower()
    local systemLvl = system:GetMaxPower()
    return batteryPow, systemPow, systemLvl
end

local function piloting_allows_positive_dodge(shipManager)
    local piloting = helpers.get_system_by_name(shipManager, "piloting")
    if not piloting or piloting:CompletelyDestroyed() then return false end
    if not piloting.bManned then return false end

    local pilotingPower = piloting:GetEffectivePower()
    return pilotingPower > 0
end

local activeHiddenAugs = {}

local function get_hidden_aug_name(augName)
    return "HIDDEN " .. augName
end

-- Is this necessary?
local function get_ship_hidden_aug_table(shipManager)

    local shipId = shipManager.iShipId

    activeHiddenAugs[shipId] = activeHiddenAugs[shipId] or {}
    return activeHiddenAugs[shipId]
end

local function set_hidden_aug(shipManager, augName, enabled)

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

local function disable_battery_effects(shipManager)
    activationTimer = 0
    clear_scaling_hidden_aug(shipManager, FIRE_EXTINGUISHER_AUG, 0)
    set_hidden_aug(shipManager, FTL_BOOSTER_AUG, false)
end

-- Dodge bonus
script.on_internal_event(Defines.InternalEvents.GET_DODGE_FACTOR, function(shipManager, dodge)
    if not helpers.ship_has_augment(shipManager, "TERRAN_WRAITH_BATTERY") then return end

    local battery = shipManager.batterySystem
    if not (battery and battery.bTurnedOn) then return end

    local batteryPow, systemPow, systemLvl = get_bars_and_level(shipManager, "engines")
    if batteryPow < 1 or activationTimer <= 0 then return end

    local bonus = activationTimer * (2.0 + (0.4 * systemLvl) - (0.47 * systemPow))
    bonus = math.floor(bonus * batteryPow)

    -- Positive dodge bonuses require manned, functioning piloting.
    if bonus > 0 and not piloting_allows_positive_dodge(shipManager) then
        bonus = 0
    end

    if bonus == 0 then return end

    return 0, dodge + bonus
end)

-- Charge activationTimer while Battery is ON
script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
    if not helpers.ship_has_augment(shipManager, "TERRAN_WRAITH_BATTERY") then
        disable_battery_effects(shipManager)
        return
    end

    local batteryId = Hyperspace.ShipSystem.NameToSystemId("battery")
    if not helpers.ship_has_working_system(shipManager, batteryId) then
        disable_battery_effects(shipManager)
        return
    end

    local battery = shipManager.batterySystem
    if not (battery and battery.bTurnedOn) then
        disable_battery_effects(shipManager)
        return
    end

    local tick = Hyperspace.FPS.SpeedFactor / 16
    local multiplier = 0.15
    activationTimer = math.max(0, math.min(1, activationTimer + multiplier * tick))

    -- Ready sound once fully charged
    if activationTimer < 1 then
        sfxPlayed = false
    elseif not sfxPlayed then
        Hyperspace.Sounds:PlaySoundMix("lily_shock_neutralizer_select_1", -1, false)
        sfxPlayed = true
    end

    -- Shock neutralizer effect (systems de-ionize faster)
    for system in vter(shipManager.vSystemList) do
        if system then
            local batteryPow = system.iBatteryPower
            if batteryPow > 0 and system.iLockCount > 0 then
                local systemLvl = system:GetMaxPower()
                local scale = batteryPow * systemLvl
                local deionizationBoost = activationTimer * 0.15 * scale

                if system:GetId() == Hyperspace.ShipSystem.NameToSystemId("cloaking") then
                    deionizationBoost = deionizationBoost * 0.5
                end

                system.lockTimer.currTime = system.lockTimer.currTime + tick * deionizationBoost
            end
        end
    end

    -- Oxygen
    local oxygenSystem = helpers.get_system_by_name(shipManager, "oxygen")
    local oxygen = shipManager.oxygenSystem

    if not (oxygenSystem and oxygen and oxygenSystem:Powered()) then
        set_scaling_hidden_aug(shipManager, FIRE_EXTINGUISHER_AUG, false, 0)
    else
        local oxygenBatteryPow = (oxygenSystem.iBatteryPower)
        local oxygenBatteryActive = oxygenBatteryPow > 0

        if oxygenBatteryActive and activationTimer > 0 then
            local oxygenSystemPow = oxygenSystem:GetEffectivePower()
            if oxygenSystemPow > 0 then
                local refill = oxygen:GetRefillSpeed()
                local scale = oxygenBatteryPow * oxygenSystemPow
                local extraFactor = activationTimer * O2_REFILL_FACTOR_PER_SCALE * scale

                local delta = refill * tick * extraFactor
                if delta ~= 0 then
                    local levels = oxygen.oxygenLevels
                    for i = 0, levels:size() - 1 do
                        levels[i] = math.min(math.max(levels[i] + delta, 0), 100)
                    end
                end

            end
        end
        set_scaling_hidden_aug(shipManager, FIRE_EXTINGUISHER_AUG, oxygenBatteryActive, oxygenBatteryPow)
    end

    -- FTL booster: enable while Engines are receiving battery power
    local enginesSystem = helpers.get_system_by_name(shipManager, "engines")
    local enginesBatteryActive = false

    if enginesSystem and enginesSystem:Powered() then
        local enginesBatteryPow = enginesSystem.iBatteryPower
        enginesBatteryActive = enginesBatteryPow > 0
    end
    set_hidden_aug(shipManager, FTL_BOOSTER_AUG, enginesBatteryActive)
end)

-- Ship-floor visuals from Lily
local function render_shock_neutralizer_effects(ship, experimental)
    local shipManager = Hyperspace.ships(ship.iShipId)
    if not shipManager then return end
    if not helpers.ship_has_augment(shipManager, "TERRAN_WRAITH_BATTERY") then return end

    local batteryId = Hyperspace.ShipSystem.NameToSystemId("battery")
    if not helpers.ship_has_working_system(shipManager, batteryId) then return end

    local battery = shipManager.batterySystem
    if not (battery and battery.bTurnedOn) then return end

    --local level = get_battery_max_level(shipManager)
    local level = battery:GetMaxPower()
    if level <= 0 then return end

    local alpha = activationTimer
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