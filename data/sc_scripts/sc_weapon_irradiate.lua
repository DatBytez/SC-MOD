-- Irradiate erosion scaling test.
--
-- The original TERRAN_BEAM_IRRADIATE erosion remains unchanged.
-- Each newly struck beam tile receives one additional hidden erosion impact
-- selected from the frozen chainstep level stored on the beam projectile.
--
-- Level 0: no bonus impact
-- Level 1: SC_IRRADIATE_EROSION_BONUS_1
-- Level 2: SC_IRRADIATE_EROSION_BONUS_2
-- Level 3+: SC_IRRADIATE_EROSION_BONUS_3
--
-- Load after:
--     sc_projectile_scaling.lua
--     sc_weapon_chainstep.lua

mods.sc = mods.sc or {}
mods.sc.irradiate = mods.sc.irradiate or {}

local irradiate = mods.sc.irradiate

local IRRADIATE_WEAPONS = {
    TERRAN_BEAM_IRRADIATE = true
}

local EROSION_BLUEPRINT_BY_LEVEL = {
    [1] = "SC_IRRADIATE_EROSION_BONUS_1",
    [2] = "SC_IRRADIATE_EROSION_BONUS_2",
    [3] = "SC_IRRADIATE_EROSION_BONUS_3",
    [4] = "SC_IRRADIATE_EROSION_BONUS_4",
    [5] = "SC_IRRADIATE_EROSION_BONUS_5"
}

local function get_room_center(shipId, location)
    local roomId =
        Hyperspace.ShipGraph
            .GetShipInfo(shipId)
            :GetSelectedRoom(
                location.x,
                location.y,
                true
            )

    if roomId == -1 then
        return nil
    end

    return Hyperspace.Pointf(
        math.floor(location.x / 35) * 35 + 17.5,
        math.floor(location.y / 35) * 35 + 17.5
    )
end

local function get_erosion_blueprint_name(projectile)
    if not projectile
        or not projectile.extend
        or not projectile.extend.name
        or not IRRADIATE_WEAPONS[
            projectile.extend.name
        ] then

        return nil
    end

    if not mods.sc.scaling
        or not mods.sc.scaling.get_level then

        return nil
    end

    local level =
        mods.sc.scaling.get_level(
            projectile,
            "chainstep"
        )

    level = math.max(
        0,
        math.floor(tonumber(level) or 0)
    )

    if level <= 0 then
        return nil
    end

    level = math.min(
        level,
        #EROSION_BLUEPRINT_BY_LEVEL
    )

    return EROSION_BLUEPRINT_BY_LEVEL[level]
end

local function spawn_erosion_impact(
    shipManager,
    projectile,
    location,
    blueprintName
)
    local target =
        get_room_center(
            shipManager.iShipId,
            location
        )

    if not target then
        return
    end

    local blueprint =
        Hyperspace.Blueprints
            :GetWeaponBlueprint(
                blueprintName
            )

    if not blueprint then
        return
    end

    local spaceManager =
        Hyperspace.Global
            .GetInstance()
            :GetCApp()
            .world
            .space

    spaceManager:CreateLaserBlast(
        blueprint,
        target,
        shipManager.iShipId,
        projectile.ownerId,
        target,
        shipManager.iShipId,
        0
    )
end

script.on_internal_event(
    Defines.InternalEvents.DAMAGE_BEAM,
    function(
        shipManager,
        projectile,
        location,
        damage,
        realNewTile,
        beamHitType
    )
        if not shipManager
            or not projectile
            or beamHitType
                == Defines.BeamHit.SAME_TILE then

            return Defines.Chain.CONTINUE,
                beamHitType
        end

        local blueprintName =
            get_erosion_blueprint_name(
                projectile
            )

        if blueprintName then
            spawn_erosion_impact(
                shipManager,
                projectile,
                location,
                blueprintName
            )
        end

        return Defines.Chain.CONTINUE,
            beamHitType
    end
)
