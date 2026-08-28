--[[
DESCRIPTION: Test script for dynamically blocking tagged weapons through Hyperspace shotLimit.
        - Weapons with <blocked/> are prevented from firing while artillery power is below 2.
        - Hides the Hyperspace shot-limit counter from the weapon box.
TAG: <blocked/>
DEPENDENCIES: sc_tag.lua, Multiverse vter
]]

local vter = mods.multiverse.vter

local blockedWeapons = {}

mods.sc.tag.register(
    "weapon",
    "blocked",
    blockedWeapons
)

local BLOCKED_SHOT_COUNT = 9999

script.on_internal_event(
    Defines.InternalEvents.SHIP_LOOP,
    function(ship)
        if not ship.weaponSystem then return end

        local artilleryPower = 0

        for artillery in vter(ship.artillerySystems) do
            artilleryPower = math.max(
                artilleryPower,
                artillery:GetEffectivePower()
            )
        end

        local blocked = artilleryPower < 2

        for weapon in vter(ship.weaponSystem.weapons) do
            if blockedWeapons[weapon.blueprint.name] then
                if blocked then
                    weapon.shotsFiredAtTarget =
                        BLOCKED_SHOT_COUNT
                else
                    weapon.shotsFiredAtTarget = 0
                end
            end
        end
    end
)

script.on_internal_event(
    Defines.InternalEvents.WEAPON_RENDERBOX,
    function(
        weapon,
        _cooldown,
        _maxCooldown,
        firstLine,
        secondLine,
        thirdLine
    )
        if blockedWeapons[weapon.blueprint.name] then
            thirdLine = ""
        end

        return Defines.Chain.CONTINUE,
            firstLine,
            secondLine,
            thirdLine
    end
)