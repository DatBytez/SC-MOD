--[[
DESCRIPTION: Applies additional Irradiate effects to each newly struck beam tile.
        - Hits applies bonus erosion and crew damage effects from hidden blueprints.
TAG: <sc-irradiate/>
DEPENDENCIES: sc_tag.lua, sc_projectile_scaling.lua
]]

local scaling = mods.sc.scaling
local irradiateWeapons = {}

mods.sc.tag.register("weapon", "sc-irradiate", irradiateWeapons)

local function get_room_center(shipId, location)
    if Hyperspace.ShipGraph.GetShipInfo(shipId):GetSelectedRoom(location.x, location.y, true) == -1 then
        return nil
    end

    return Hyperspace.Pointf(
        math.floor(location.x / 35) * 35 + 17.5,
        math.floor(location.y / 35) * 35 + 17.5
    )
end

local function get_irradiate_blueprint_name(projectile)
    if not irradiateWeapons[projectile.extend.name] then return nil end

    local level = math.min(scaling.get_level(projectile, "chainstep"), 4)
    return "SC_IRRADIATE_EROSION_BONUS_" .. level + 1
end

local function spawn_irradiate_impact(shipManager, projectile, location, blueprintName)
    local target = get_room_center(shipManager.iShipId, location)
    if not target then return end

    local blueprint = Hyperspace.Blueprints:GetWeaponBlueprint(blueprintName)
    local spaceManager = Hyperspace.Global.GetInstance():GetCApp().world.space

    spaceManager:CreateLaserBlast(blueprint, target, shipManager.iShipId, projectile.ownerId, target, shipManager.iShipId, 0)
end

script.on_internal_event(Defines.InternalEvents.DAMAGE_BEAM, function(shipManager, projectile, location, _damage, _realNewTile, beamHitType)
    if beamHitType == Defines.BeamHit.SAME_TILE then
        return Defines.Chain.CONTINUE, beamHitType
    end

    local blueprintName = get_irradiate_blueprint_name(projectile)

    if blueprintName then
        spawn_irradiate_impact(shipManager, projectile, location, blueprintName)
    end

    return Defines.Chain.CONTINUE, beamHitType
end)