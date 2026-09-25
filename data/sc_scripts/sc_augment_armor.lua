--[[
DESCRIPTION: Modify Lily's System Bracers to act as full ship plating.
        - Chance (bracers health * 40%) to negate hull and system damage.
        - Hull damage is reduced during DAMAGE_AREA / DAMAGE_BEAM.
        - System damage is intercepted during SYSTEM_ADD_DAMAGE before vanilla
          system damage side effects are allowed to continue.
DEPENDENCIES: lily_system_bracers, sc_tag.lua, sc_helpers.lua, multiverse_damage_messages.lua
SOURCE CREDIT: MsBinaryLily
]]

local create_damage_message = mods.multiverse.create_damage_message
local damageMessages = mods.multiverse.damageMessages

mods.sc = mods.sc or {}
mods.sc.armorAugments = mods.sc.armorAugments or {}

local helpers = mods.sc.helpers

local armorAugments = mods.sc.armorAugments

mods.sc.tag.register("augment", "sc-armor", armorAugments)

local BRACERS_ID = Hyperspace.ShipSystem.NameToSystemId("lily_system_bracers")
local BLOCK_CHANCE_PER_HP = 0.40

local overflowSystemDamageInProgress = {
    [0] = false,
    [1] = false
}

local function get_working_bracers(ship)
    if not helpers.ship_has_augment(ship, armorAugments) then return nil end
    if not helpers.ship_has_working_system(ship, BRACERS_ID) then return nil end

    local bracers = ship:GetSystem(BRACERS_ID)
    if not bracers then return nil end
    if bracers.healthState.first <= 0 then return nil end

    return bracers
end

local function roll_bracers_block(bracers)
    local blockChance = math.min(
        1.0,
        bracers.healthState.first * BLOCK_CHANCE_PER_HP
    )

    return math.random() <= blockChance
end

local function damage_is_self_friendly_fire(ship, damage)
    return damage
        and damage.bFriendlyFire
        and damage.ownerId == ship.iShipId
end

local function show_negated_message(ship, location)
    if not location then return end

    create_damage_message(
        ship.iShipId,
        damageMessages.NEGATED,
        location.x,
        location.y
    )
end

local function damage_bracers(bracers, amount)
    bracers.healthState.first = math.max(
        0,
        bracers.healthState.first - amount
    )
end

local function handle_hull_damage(ship, location, damage)
    if not ship or not damage then return end
    if damage.iDamage <= 0 then return end
    if damage_is_self_friendly_fire(ship, damage) then return end

    local bracers = get_working_bracers(ship)
    if not bracers then return end
    if not roll_bracers_block(bracers) then return end

    local blockedDamage = math.min(
        damage.iDamage,
        bracers.healthState.first
    )

    if blockedDamage <= 0 then return end

    damage.iDamage =
        damage.iDamage - blockedDamage

    damage_bracers(
        bracers,
        blockedDamage
    )

    show_negated_message(
        ship,
        location
    )
end

script.on_internal_event(
    Defines.InternalEvents.DAMAGE_AREA,
    handle_hull_damage
)

script.on_internal_event(
    Defines.InternalEvents.DAMAGE_BEAM,
    function(ship, projectile, location, damage, realNewTile, beamHitType)
        if beamHitType == Defines.BeamHit.NEW_ROOM then
            handle_hull_damage(
                ship,
                location,
                damage
            )
        end
    end
)

script.on_internal_event(
    Defines.InternalEvents.SYSTEM_ADD_DAMAGE,
    function(sys, projectile, amount)
        if not sys then
            return Defines.Chain.CONTINUE, amount
        end

        if not amount or amount <= 0 then
            return Defines.Chain.CONTINUE, amount
        end

        local shipObject = sys._shipObj
        if not shipObject then
            return Defines.Chain.CONTINUE, amount
        end

        local shipId = shipObject.iShipId
        local ship = Hyperspace.ships(shipId)

        if not ship then
            return Defines.Chain.CONTINUE, amount
        end

        if overflowSystemDamageInProgress[shipId] then
            return Defines.Chain.CONTINUE, amount
        end

        local bracers = get_working_bracers(ship)
        if not bracers then
            return Defines.Chain.CONTINUE, amount
        end

        if bracers:GetRoomId() == sys:GetRoomId() then
            return Defines.Chain.CONTINUE, amount
        end

        if not roll_bracers_block(bracers) then
            return Defines.Chain.CONTINUE, amount
        end

        local effectiveSystemDamage = math.min(
            amount,
            sys.healthState.first
        )

        local blockedDamage = math.min(
            bracers.healthState.first,
            effectiveSystemDamage
        )

        if blockedDamage <= 0 then
            return Defines.Chain.CONTINUE, amount
        end

        local remainingSystemDamage =
            effectiveSystemDamage - blockedDamage

        damage_bracers(
            bracers,
            blockedDamage
        )

        show_negated_message(
            ship,
            ship:GetRoomCenter(
                sys:GetRoomId()
            )
        )

        if remainingSystemDamage > 0 then
            local overflowDamage = Hyperspace.Damage()

            overflowDamage.ownerId =
                projectile and projectile.ownerId or ship.iShipId

            overflowDamage.iSystemDamage =
                remainingSystemDamage

            overflowSystemDamageInProgress[shipId] = true

            ship:DamageSystem(
                sys:GetRoomId(),
                overflowDamage
            )

            overflowSystemDamageInProgress[shipId] = false
        end

        return Defines.Chain.PREEMPT, 0
    end,
    2147483647
)