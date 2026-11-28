--[[
DESCRIPTION: Playtest-only global rarity blocklist from TERRAN_FRIENDLY.
        - Sets rarity and baseRarity to 0 for every accessible blueprint.
        - Applies on startup, run initialization, and jumps.
        - Reports unsupported or non-persistent restrictions once per entry.
DEPENDENCIES: Hyperspace Lua
]]

local ENABLED = true
local LOG_FAILURES = true

-- Names copied from data/sector_data.xml.append, TERRAN_FRIENDLY <rarityList>.
local BLOCKED = {
    weapons = [[
        BEAM_1 BEAM_2 BEAM_3 BEAM_4 BEAM_ADAPT BEAM_ADAPT_2 BEAM_BIO BEAM_BIO_CHAIN BEAM_BIO_CONSERVATIVE BEAM_BREACH BEAM_CHAIN BEAM_CONSERVATIVE BEAM_FIRE BEAM_FIRE_INSTANT BEAM_FIRE_PIERCE BEAM_GUILLOTINE BEAM_HULL BEAM_HULL_2 BEAM_LONG BEAM_LONG_2 BEAM_MINING BEAM_PARTICLE BEAM_PIERCE BEAM_SCYTHE BEAM_STUN
        BOMB_1 BOMB_BIO BOMB_BREACH_1 BOMB_BUFF BOMB_CONSERVATIVE BOMB_FIRE BOMB_FREE BOMB_HEAL BOMB_HEAL_SYSTEM BOMB_ION BOMB_STUN
        ENERGY_1 ENERGY_2 ENERGY_3 ENERGY_CHAINGUN ENERGY_CHARGEGUN ENERGY_CONSERVATIVE ENERGY_HULL ENERGY_STUN
        FOCUS_1 FOCUS_2 FOCUS_3 FOCUS_BIO FOCUS_CHAIN
        ION_2 ION_3 ION_4 ION_BIO ION_CHAINGUN ION_CHARGEGUN ION_CHARGEGUN_2 ION_CONSERVATIVE ION_FIRE ION_HEAVY ION_INSTANT ION_PIERCE_1 ION_PIERCE_2 ION_STUN ION_STUN_2 ION_STUN_CHARGEGUN ION_STUN_HEAVY ION_TRI
        LASER_BIO LASER_BURST_2 LASER_BURST_3 LASER_BURST_5 LASER_CHAINGUN LASER_CHAINGUN_2 LASER_CHAINGUN_DAMAGE LASER_CHARGEGUN LASER_CHARGEGUN_2 LASER_CHARGEGUN_3 LASER_CHARGE_CHAIN LASER_CONSERVATIVE LASER_FIRE LASER_FROST_1 LASER_FROST_2 LASER_HEAVY_1 LASER_HEAVY_2 LASER_HEAVY_3 LASER_HEAVY_CHAINGUN LASER_HEAVY_PIERCE LASER_HULL_1 LASER_HULL_2 LASER_HULL_3 LASER_HULL_CHAINGUN LASER_LIGHT LASER_LIGHT_2 LASER_PARTICLE LASER_PARTICLE_2 LASER_PIERCE LASER_PIERCE_2 LASER_STUN
        MISSILES_2 MISSILES_3 MISSILES_4 MISSILES_BIO MISSILES_BURST MISSILES_BURST_2 MISSILES_CLOAK MISSILES_CONSERVATIVE MISSILES_FIRE MISSILES_FREE MISSILES_PARTICLE MISSILES_STUN
        SHOTGUN_1 SHOTGUN_2 SHOTGUN_3 SHOTGUN_4 SHOTGUN_CHAIN SHOTGUN_CHARGE SHOTGUN_FIRE SHOTGUN_INSTANT SHOTGUN_ION SHOTGUN_TOXIC
        LASER_BURST_2_A MISSILES_BREACH MISSILES_HULL ION_1 BOMB_BREACH_2 SHOTGUN MISSILE_CHARGEGUN
    ]],
    drones = [[
        AMPHI_DEFENSE ASSAULT_PARTICLE BATTLETOG2_DEFEND BATTLETOG_DEFEND COMBAT_1_LASER COMBAT_2_LASER COMBAT_CONSERVATIVE_LASER DEFENSE_1 DEFENSE_2 DEFENSE_3 DOCTOR_DEFENSE DRONE_SHIELD ENERGY_1_AMP2 FLAK_1_AMP2 FOCUS_1_AMP2 GUARDIAN_1_MISSILE GUARDIAN_2_MISSILE HELLRAISER_FIRE ION_1_AMP2 MANNING PEST_RAD RECON_BOARDER REPAIR SHIP_REPAIR
        COMBAT_1 COMBAT_BEAM COMBAT_2 BATTLE BOARDER BOARDER_ION ANTI_DRONE COMBAT_BEAM_2 COMBAT_FIRE
    ]],
    crew = [[
        human human_medic human_engineer engi engi_separatist energy zoltan zoltan_monk zoltan_devotee rock rock_outcast rock_commando mantis mantis_free slug slug_clansman shell shell_scientist shell_mechanic shell_guardian crystal crystal_liberator orchid orchid_vampweed leech lanius anaerobic phantom phantom_goul phantom_mare phantom_wraith
    ]],
    systems = [[
        shields teleporter mind
    ]],
}

local reportedFailures = {}

local function report_failure(category, name, reason)
    if not LOG_FAILURES then return end

    local key = category .. ":" .. name
    if reportedFailures[key] then return end
    reportedFailures[key] = true

    print("[SC rarity test] Could not block " .. key .. ": " .. tostring(reason))
end

local function block_blueprint(category, name, getter)
    if type(getter) ~= "function" then
        report_failure(category, name, "blueprint getter not exposed by Hyperspace")
        return
    end

    local ok, reason = pcall(function()
        local blueprints = Hyperspace.Blueprints
        local blueprint = getter(blueprints, name)

        if not blueprint or blueprint.name ~= name then
            error("blueprint not found")
        end
        if not blueprint.desc then
            error("blueprint has no rarity description")
        end

        blueprint.desc.rarity = 0
        blueprint.desc.baseRarity = 0

        -- Some APIs may return a copy rather than a mutable stored blueprint.
        local current = getter(blueprints, name)
        if not current or current.name ~= name or not current.desc
            or current.desc.rarity ~= 0 or current.desc.baseRarity ~= 0 then
            error("rarity did not persist after re-reading the blueprint")
        end
    end)

    if not ok then
        report_failure(category, name, reason)
    end
end

local function apply_blocklist()
    if not ENABLED then return end

    local blueprints = Hyperspace.Blueprints
    if not blueprints then return end

    -- System blueprints lack a documented getter. Probe safely so an absent
    -- method cannot interrupt all the other rarity overrides.
    local okSystemGetter, systemGetter = pcall(function()
        return blueprints.GetSystemBlueprint
    end)

    local getters = {
        weapons = blueprints.GetWeaponBlueprint,
        drones = blueprints.GetDroneBlueprint,
        crew = blueprints.GetCrewBlueprint,
        systems = okSystemGetter and systemGetter or nil,
    }

    for category, names in pairs(BLOCKED) do
        for name in names:gmatch("%S+") do
            block_blueprint(category, name, getters[category])
        end
    end
end

script.on_load(apply_blocklist)
script.on_init(apply_blocklist)

-- Apply before leaving, as the destination event/store may be generated next.
script.on_internal_event(Defines.InternalEvents.JUMP_LEAVE, function(ship)
    if ship and ship.iShipId == 0 then
        apply_blocklist()
    end
end)

-- Reapply after arrival in case a sector overrides rarity values.
script.on_internal_event(Defines.InternalEvents.JUMP_ARRIVE, function(ship)
    if ship and ship.iShipId == 0 then
        apply_blocklist()
    end
end)

-- Extra pass before events show their choice box.
script.on_internal_event(Defines.InternalEvents.PRE_CREATE_CHOICEBOX, function()
    apply_blocklist()
end)
