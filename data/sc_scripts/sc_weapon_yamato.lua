--[[
DESCRIPTION: Scales the Yamato artillery volley with artillery power and adjusts its cooldown progression.
        - Limits each volley to the number of shots allowed by the artillery's effective power.
        - Preserves the Yamato-specific cooldown correction for artillery power levels.
TAG: <sc-chain-artillery stat="shots" value="#"/>
DEPENDENCIES: sc_tag.lua, Multiverse userdata_table, Multiverse vter
SOURCE: Arc Fishing.lua
]]

local userdata_table = mods.multiverse.userdata_table
local vter = mods.multiverse.vter

local chainArtillery = {}

mods.sc.tag.register("weapon", "sc-chain-artillery", chainArtillery, "stat")

local function get_matching_artillery(ship, weapon)
    for artillery in vter(ship.artillerySystems) do
        if artillery.projectileFactory == weapon then
            return artillery
        end
    end
end

local function apply_chain_artillery_shots(weapon, startingShots, artillery)
    local weaponData = userdata_table(weapon, "mods.sc.weaponStuff")
    weaponData.shotsFiredThisVolley = (weaponData.shotsFiredThisVolley or 0) + 1

    local allowedTotal = math.min(weapon.blueprint.shots, startingShots + artillery:GetEffectivePower())

    if weaponData.shotsFiredThisVolley >= allowedTotal then
        weapon.queuedProjectiles:clear()
    end

    if weapon.queuedProjectiles:size() == 0 then
        weaponData.shotsFiredThisVolley = 0
    end
end

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(_projectile, weapon)
    local statBoosts = chainArtillery[weapon.blueprint.name]
    if not statBoosts then return end

    local artillery = get_matching_artillery(Hyperspace.ships(weapon.iShipId), weapon)
    if not artillery then return end

    for _, statBoost in ipairs(statBoosts) do
        if statBoost.stat == "shots" then
            apply_chain_artillery_shots(weapon, statBoost.value, artillery)
        end
    end
end)

-- ARTILLERY COOLDOWN
-- ------------------------
-- YAMATO ARTILLERY COOLDOWN
-- ------------------------

-- FTL artillery scaling:
-- Power 1 = base × 1.25
-- Power 2 = base × 1.00
-- Power 3 = base × 0.75
-- Power 4 = base × 0.50
--
-- These values produce a final cooldown of ~25 seconds
-- at every artillery power level.
local yamatoBaseCooldownByPower = {
    [1] = 20,
    [2] = 25,
    [3] = 25 / 0.75,
    [4] = 50
}

local POWER_INCREASE_CHARGE_MULT = 0.80

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    for artillery in vter(ship.artillerySystems) do
        local weapon = artillery.projectileFactory

        if weapon
        and weapon.blueprint
        and weapon.blueprint.name == "ARTILLERY_YAMATO_LASER" then

            local power = artillery.powerState.first
            local targetBase = yamatoBaseCooldownByPower[power]

            if power > 0 and targetBase then
                local data = userdata_table(
                    artillery,
                    "mods.sc.yamatoCooldown"
                )

                -- Keep Yamato at approximately 25 seconds
                -- regardless of artillery power.
                weapon.blueprint.cooldown = targetBase

                -- Initialize power tracking.
                if data.lastPower == nil then
                    data.lastPower = power
                end

                -- ------------------------
                -- POWER INCREASE
                -- ------------------------
                if power > data.lastPower then

                    -- Reduce accumulated charge by 20%.
                    weapon.cooldown.first =
                        weapon.cooldown.first
                        * POWER_INCREASE_CHARGE_MULT

                    -- Save the existing ion state so our temporary
                    -- ion effect does not erase legitimate ion damage.
                    data.originalIonCount =
                        artillery.iLockCount

                    -- Apply at least one point of temporary ion lock.
                    artillery.iLockCount =
                        math.max(
                            1,
                            artillery.iLockCount
                        )

                    -- Keep it ionized for one full loop before restoring.
                    data.artificialIonActive = true
                end

                data.lastPower = power

                -- ------------------------
                -- TEMPORARY ION RESTORE
                -- ------------------------

                -- First loop after applying ion:
                -- leave the artillery ionized.
                if data.artificialIonActive then
                    data.artificialIonActive = false
                    data.restoreIonNextLoop = true

                -- Following loop:
                -- restore whatever ion count existed before our effect.
                elseif data.restoreIonNextLoop then
                    artillery.iLockCount =
                        data.originalIonCount or 0

                    data.originalIonCount = nil
                    data.restoreIonNextLoop = false
                end
            end
        end
    end
end)