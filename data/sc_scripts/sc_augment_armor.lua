--[[
DESCRIPTION: Adds SC armor plating behavior through Lily's System Bracers.
        - Registers augments with <sc-armor/>.
        - Registers SC armor as a Lily bracer protection source for system damage.
        - Handles hull damage blocking while Lily's bracer script handles system damage.
DEPENDENCIES: lily_system_bracers.lua, sc_tag.lua, sc_helpers.lua,
              Multiverse userdata_table, Multiverse damage messages
SOURCE CREDIT: MsBinaryLily
]]

local userdata_table = mods.multiverse.userdata_table
local create_damage_message = mods.multiverse.create_damage_message
local damageMessages = mods.multiverse.damageMessages
local helpers = mods.sc.helpers
local systemBracers = mods.lilyinno.systemBracers

local armorAugments = {}

mods.sc.tag.register("augment", "sc-armor", armorAugments)

local WEAPONS_ID = Hyperspace.ShipSystem.NameToSystemId("weapons")
local BLOCK_CHANCE_PER_HP = 0.40

local function get_armor_bracers(ship)
    if not helpers.ship_has_augment(ship, armorAugments) then return nil end
    return systemBracers.get_bracers_system(ship)
end

local function get_block_chance(bracers)
    return math.min(1, bracers.healthState.first * BLOCK_CHANCE_PER_HP)
end

local function show_negated_message(ship, location)
    create_damage_message(ship.iShipId, damageMessages.NEGATED, location.x, location.y)
end

systemBracers.register_protection_source("sc_armor", {
    ship_qualifies = function(ship)
        return helpers.ship_has_augment(ship, armorAugments)
    end,

    get_block_chance = function(_, bracers)
        return get_block_chance(bracers)
    end,

    on_absorb = function(ship, _, context)
        local system = context.system

        if system:GetId() == WEAPONS_ID and context.remainingSystemDamage <= 0 then
            userdata_table(ship, "mods.lilyinno.systembracers").weaponRepowerArmorConfirmed = true
        end

        show_negated_message(ship, ship:GetRoomCenter(system:GetRoomId()))
    end
})

local function block_hull_damage(ship, projectile, location, damage)
    if damage.iDamage <= 0 then return end
    if damage.bFriendlyFire and damage.ownerId == ship.iShipId then return end

    local bracers = get_armor_bracers(ship)
    if not bracers then return end
    if math.random() > get_block_chance(bracers) then return end

    local blockedDamage = math.min(damage.iDamage, bracers.healthState.first)
    damage.iDamage = damage.iDamage - blockedDamage

    if projectile then
        local pdata = userdata_table(projectile, "mods.sc.armor")
        pdata.pendingHullBlock = (pdata.pendingHullBlock or 0) + blockedDamage
        return
    end

    systemBracers.damage_bracers(bracers, blockedDamage)
    show_negated_message(ship, location)
end

script.on_internal_event(Defines.InternalEvents.DAMAGE_AREA, block_hull_damage)

script.on_internal_event(
    Defines.InternalEvents.DAMAGE_AREA_HIT,
    function(ship, projectile, location)
        if not projectile then return end

        local pdata = userdata_table(projectile, "mods.sc.armor")
        local blockedDamage = pdata.pendingHullBlock or 0
        if blockedDamage <= 0 then return end

        local bracers = get_armor_bracers(ship)

        if bracers then
            systemBracers.damage_bracers(bracers, blockedDamage)
            show_negated_message(ship, location)
        end

        pdata.pendingHullBlock = nil
    end
)

script.on_internal_event(
    Defines.InternalEvents.DAMAGE_BEAM,
    function(ship, _projectile, location, damage, _realNewTile, beamHitType)
        if beamHitType == Defines.BeamHit.NEW_ROOM then
            block_hull_damage(ship, nil, location, damage)
        end
    end
)
