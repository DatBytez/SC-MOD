--[[
DESCRIPTION: Adds SC armor plating behavior through Lily's System Bracers.
        - Registers augments with <sc-armor/>.
        - Registers SC armor as a Lily bracer protection source for system damage.
        - Handles hull damage blocking for armor plating while leaving system damage
          interception to lily_system_bracers.lua.
DEPENDENCIES: lily_system_bracers.lua, sc_tag.lua, sc_helpers.lua,
              multiverse_userdata_table.lua, multiverse_damage_messages.lua
SOURCE CREDIT: MsBinaryLily
]]

local userdata_table = mods.multiverse.userdata_table
local create_damage_message = mods.multiverse.create_damage_message
local damageMessages = mods.multiverse.damageMessages

mods.sc = mods.sc or {}
mods.sc.armorAugments = mods.sc.armorAugments or {}

local helpers = mods.sc.helpers
local armorAugments = mods.sc.armorAugments
local systemBracers = mods.lilyinno.systemBracers

mods.sc.tag.register("augment", "sc-armor", armorAugments)

local BLOCK_CHANCE_PER_HP = 0.40

local function ship_has_sc_armor(ship)
    return helpers.ship_has_augment(ship, armorAugments)
end

local function get_armor_bracers(ship)
    if not ship_has_sc_armor(ship) then return nil end

    return systemBracers.get_bracers_system(ship)
end

local function get_block_chance(bracers)
    if not bracers then return 0 end

    return math.min(
        1.0,
        bracers.healthState.first * BLOCK_CHANCE_PER_HP
    )
end

local function roll_armor_block(bracers)
    return math.random() <= get_block_chance(bracers)
end

local function damage_is_self_friendly_fire(ship, damage)
    return damage
        and damage.bFriendlyFire
        and damage.ownerId == ship.iShipId
end

local function show_negated_message(ship, location)
    if not ship or not location then return end

    create_damage_message(
        ship.iShipId,
        damageMessages.NEGATED,
        location.x,
        location.y
    )
end

systemBracers.register_protection_source(
    "sc_armor",
    {
        ship_qualifies = function(ship, bracers, context)
            return ship_has_sc_armor(ship)
        end,

        get_block_chance = function(ship, bracers, context)
            return get_block_chance(bracers)
        end,

        on_absorb = function(ship, bracers, context)
            local sys = context and context.system
            if not sys then return end

            if sys:GetId() == Hyperspace.ShipSystem.NameToSystemId("weapons")
                and context.remainingSystemDamage <= 0 then

                userdata_table(
                    ship,
                    "mods.lilyinno.systembracers"
                ).weaponRepowerArmorConfirmed = true
            end

            show_negated_message(
                ship,
                ship:GetRoomCenter(
                    sys:GetRoomId()
                )
            )
        end
    }
)

local function store_projectile_hull_block(projectile, ship, blockedDamage)
    if not projectile or blockedDamage <= 0 then return end

    local pdata = userdata_table(projectile, "mods.sc.armor")

    pdata.pendingHullBlock =
        (pdata.pendingHullBlock or 0)
        + blockedDamage

    pdata.pendingHullShipId = ship.iShipId
end

local function block_hull_damage(ship, location, damage, projectile)
    if not ship or not damage then return end
    if not damage.iDamage or damage.iDamage <= 0 then return end
    if damage_is_self_friendly_fire(ship, damage) then return end

    local bracers = get_armor_bracers(ship)
    if not bracers then return end
    if not roll_armor_block(bracers) then return end

    local blockedDamage = math.min(
        damage.iDamage,
        bracers.healthState.first
    )

    if blockedDamage <= 0 then return end

    damage.iDamage =
        damage.iDamage - blockedDamage

    if projectile then
        store_projectile_hull_block(
            projectile,
            ship,
            blockedDamage
        )

        return
    end

    systemBracers.damage_bracers(
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
    function(ship, projectile, location, damage, forceHit, shipFriendlyFire)
        block_hull_damage(
            ship,
            location,
            damage,
            projectile
        )
    end
)

script.on_internal_event(
    Defines.InternalEvents.DAMAGE_AREA_HIT,
    function(ship, projectile, location)
        if not ship or not projectile then return end

        local pdata = userdata_table(projectile, "mods.sc.armor")
        local blockedDamage = pdata.pendingHullBlock or 0

        if blockedDamage <= 0 then return end
        if pdata.pendingHullShipId ~= ship.iShipId then return end

        local bracers = get_armor_bracers(ship)
        if bracers then
            systemBracers.damage_bracers(
                bracers,
                blockedDamage
            )

            show_negated_message(
                ship,
                location
            )
        end

        pdata.pendingHullBlock = 0
        pdata.pendingHullShipId = nil
    end
)

script.on_internal_event(
    Defines.InternalEvents.DAMAGE_BEAM,
    function(ship, projectile, location, damage, realNewTile, beamHitType)
        if beamHitType == Defines.BeamHit.NEW_ROOM then
            block_hull_damage(
                ship,
                location,
                damage,
                nil
            )
        end
    end
)
