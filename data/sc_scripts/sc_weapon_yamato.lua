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
local yamatoCooldownByPower = {
    [1] = 10,
    [2] = 20,
    [3] = 30,
    [4] = 40
}

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
    for artillery in vter(ship.artillerySystems) do
        local weapon = artillery.projectileFactory

        if weapon.blueprint.name == "ARTILLERY_YAMATO_LASER" then
            local power = artillery.powerState.first
            local targetCooldown = yamatoCooldownByPower[power]

            if power > 0 and targetCooldown then
                local artilleryData = userdata_table(
                    artillery,
                    "mods.sc.yamatoCooldown"
                )

                -- Preserve charge percentage when artillery power changes.
                if artilleryData.lastPower ~= power then
                    local oldCooldown =
                        artilleryData.lastCooldown
                        or weapon.cooldown.second

                    local chargePercent = 0

                    if oldCooldown > 0 then
                        chargePercent = math.max(
                            0,
                            math.min(
                                1,
                                weapon.cooldown.first / oldCooldown
                            )
                        )
                    end

                    weapon.cooldown.second = targetCooldown
                    weapon.cooldown.first =
                        targetCooldown * chargePercent

                    artilleryData.lastPower = power
                    artilleryData.lastCooldown = targetCooldown
                else
                    -- Keep the displayed/full cooldown at our chosen value.
                    weapon.cooldown.second = targetCooldown
                end

                -- Counteract FTL's built-in artillery power scaling.
                if weapon.cooldown.first ~= weapon.cooldown.second then
                    local powerScale = -0.25 * (power - 2)

                    weapon.cooldown.first = math.max(
                        0,
                        math.min(
                            weapon.cooldown.second,
                            weapon.cooldown.first
                                + powerScale
                                * Hyperspace.FPS.SpeedFactor / 16
                        )
                    )
                end
            end
        end
    end
end)