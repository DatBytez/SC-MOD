--[[
DESCRIPTION: Modify Lily's System Bracers to act as full ship plating.
		- Chance (bracers health * 20%) to Negate damage to hull and systems.
		- Bracers take 1 damage for every 2 damage Negated this way.
DEPENDENCIES: lily_system_bracers
SOURCE CREDIT: MsBinaryLily
]]

local userdata_table = mods.multiverse.userdata_table
local create_damage_message = mods.multiverse.create_damage_message
local damageMessages = mods.multiverse.damageMessages
local vter = mods.multiverse.vter

mods.sc = mods.sc or {}
mods.sc.armorAugments = mods.sc.armorAugments or {}

local helpers = mods.sc.helpers or require("mods.sc.helpers")

local armorAugments = mods.sc.armorAugments

mods.sc.tag.register_augment_flag_tag("sc-armor", armorAugments)

-- Armored modification of Lily's bracers.
local function handle_reduction_armor(ship, projectile, location, damage, forceHit, shipFriendlyFire)
    if not helpers.ship_has_augment_in_set(ship, armorAugments) then return end

    local bracersId = Hyperspace.ShipSystem.NameToSystemId("lily_system_bracers")
    if not helpers.ship_has_powered_system(ship, bracersId) then return end

    if not damage or damage.iDamage <= 0 then return end
    if damage.bFriendlyFire and damage.ownerId == ship.iShipId then return end

    local bracers = ship:GetSystem(bracersId)

    local bracersHP = bracers.healthState.first or 0
    if bracersHP <= 0 then return end

    local blockChance = math.min(1.0, bracersHP * 0.40)
    if math.random() > blockChance then return end

    local soaked = math.min(damage.iDamage, bracersHP)

    if damage.iDamage > bracersHP then
        damage.iDamage = damage.iDamage - bracersHP
    else
        damage.iDamage = 0

        if projectile then
            userdata_table(projectile, "mods.mv.reductionArmor").showMsg = true
        else
            create_damage_message(ship.iShipId, damageMessages.NEGATED, location.x, location.y)
        end
    end

    if projectile then
        userdata_table(projectile, "mods.mv.reductionArmor").pendingSoak = soaked
    else
	local bdata = userdata_table(bracers, "mods.mv.bracersSoak")
        bdata.soakBank = (bdata.soakBank or 0) + soaked
        
	while bdata.soakBank >= 2 and bracers.healthState.first > 0 do
            bdata.soakBank = bdata.soakBank - 2
            bracers.healthState.first = bracers.healthState.first - 1
        end

	bracers.healthState.first = math.max(0, bracers.healthState.first or 0)
    end
end

script.on_internal_event(Defines.InternalEvents.DAMAGE_AREA, handle_reduction_armor)

script.on_internal_event(Defines.InternalEvents.DAMAGE_AREA_HIT, function(ship, projectile, location)
    if not projectile then return end

    local pdata = userdata_table(projectile, "mods.mv.reductionArmor")
    local soaked = pdata.pendingSoak or 0

    if soaked > 0 and ship then
        local bracersId = Hyperspace.ShipSystem.NameToSystemId("lily_system_bracers")
        if ship:HasSystem(bracersId) then
            local bracers = ship:GetSystem(bracersId)
            if bracers and not bracers:CompletelyDestroyed() then
                local bdata = userdata_table(bracers, "mods.mv.bracersSoak")
                bdata.soakBank = (bdata.soakBank or 0) + soaked

                while bdata.soakBank >= 2 and bracers.healthState.first > 0 do
                    bdata.soakBank = bdata.soakBank - 2
                    bracers.healthState.first = bracers.healthState.first - 1
                end

                bracers.healthState.first = math.max(0, bracers.healthState.first or 0)
            end
        end
    end

    -- clear the pending soak so it can't double-apply
    pdata.pendingSoak = 0

    if pdata.showMsg then
        pdata.showMsg = false
        create_damage_message(ship.iShipId, damageMessages.NEGATED, location.x, location.y)
    end
end)

script.on_internal_event(Defines.InternalEvents.DAMAGE_BEAM, function(ship, projectile, location, damage, realNewTile, beamHitType)
    if beamHitType == Defines.BeamHit.NEW_ROOM then
        -- For beams, consume soak immediately
        handle_reduction_armor(ship, nil, location, damage, nil, nil)
    end
end)


-- Reset soak between battles
local function reset_bracers_soak_bank(ship)
    local bracersId = Hyperspace.ShipSystem.NameToSystemId("lily_system_bracers")
    local bracers = ship and ship:HasSystem(bracersId) and ship:GetSystem(bracersId)
    if not bracers then return end

    local bdata = userdata_table(bracers, "mods.mv.bracersSoak")
    bdata.soakBank = 0
end

script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, function(ship)
    reset_bracers_soak_bank(ship)
end)

script.on_internal_event(Defines.InternalEvents.ON_WAIT, function(ship)
    reset_bracers_soak_bank(ship)
end)