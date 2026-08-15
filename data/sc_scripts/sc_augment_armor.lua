--[[
DESCRIPTION: Modify Lily's System Bracers to act as full ship plating.
		- Chance (bracers health * 40%) to Negate damage to hull and systems.
DEPENDENCIES: lily_system_bracers
SOURCE CREDIT: MsBinaryLily
]]

local userdata_table = mods.multiverse.userdata_table
local create_damage_message = mods.multiverse.create_damage_message
local damageMessages = mods.multiverse.damageMessages

mods.sc = mods.sc or {}
mods.sc.armorAugments = mods.sc.armorAugments or {}

local helpers = mods.sc.helpers or require("mods.sc.helpers")

local armorAugments = mods.sc.armorAugments

mods.sc.tag.register_augment_tag("sc-armor", armorAugments)

local BRACERS_ID = Hyperspace.ShipSystem.NameToSystemId("lily_system_bracers")
local BLOCK_CHANCE_PER_HP = 0.40

local function handle_reduction_armor(ship, projectile, location, damage)
     if not helpers.ship_has_augment(ship, armorAugments) then return end
    if not helpers.ship_has_working_system(ship, BRACERS_ID) then return end

    if not damage or damage.iDamage <= 0 then return end
    if damage.bFriendlyFire and damage.ownerId == ship.iShipId then return end

    local bracers = ship:GetSystem(BRACERS_ID)
    local bracersHP = bracers.healthState.first or 0

    if bracersHP <= 0 then return end

    local blockChance = math.min(1.0, bracersHP * BLOCK_CHANCE_PER_HP)
    if math.random() > blockChance then return end

    local blockedDamage = math.min(damage.iDamage, bracersHP)
    damage.iDamage = damage.iDamage - blockedDamage

    if projectile then
        userdata_table(projectile, "mods.mv.reductionArmor").pendingSoak = blockedDamage
        userdata_table(projectile, "mods.mv.reductionArmor").showMsg = true
    else
        bracers.healthState.first = math.max(0, bracers.healthState.first - blockedDamage)
        create_damage_message(ship.iShipId, damageMessages.NEGATED, location.x, location.y)
    end
end

script.on_internal_event(Defines.InternalEvents.DAMAGE_AREA, handle_reduction_armor)

script.on_internal_event(Defines.InternalEvents.DAMAGE_AREA_HIT, function(ship, projectile, location)
    if not projectile then return end

    local pdata = userdata_table(projectile, "mods.mv.reductionArmor")
    local blockedDamage = pdata.pendingSoak or 0

    if blockedDamage > 0 and ship:HasSystem(BRACERS_ID) then
        local bracers = ship:GetSystem(BRACERS_ID)
        if bracers and not bracers:CompletelyDestroyed() then
            bracers.healthState.first = math.max(0, bracers.healthState.first - blockedDamage)
        end
    end

    pdata.pendingSoak = 0

    if pdata.showMsg then
        pdata.showMsg = false
        create_damage_message(ship.iShipId, damageMessages.NEGATED, location.x, location.y)
    end
end)

script.on_internal_event(Defines.InternalEvents.DAMAGE_BEAM, function(ship, projectile, location, damage, realNewTile, beamHitType)
    if beamHitType == Defines.BeamHit.NEW_ROOM then
        handle_reduction_armor(ship, nil, location, damage)
    end
end)