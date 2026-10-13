--[[
DESCRIPTION: Applies additional Irradiate effects to each newly struck beam tile.
        - Hits apply bonus erosion and crew damage effects from hidden blueprints.
        - Crew struck by Irradiate periodically apply additional erosion to their current room.
TAG: <sc-irradiate/>
DEPENDENCIES: sc_tag.lua, Multiverse userdata_table
]]

local userdata_table = mods.multiverse.userdata_table
local irradiateWeapons = {}

mods.sc.tag.register("weapon", "sc-irradiate", irradiateWeapons)

local IRRADIATE_DURATION = 25
local EROSION_PULSE_INTERVAL = 1

local function get_tile_center(shipId, location)
    if Hyperspace.ShipGraph.GetShipInfo(shipId):GetSelectedRoom(location.x, location.y, true) == -1 then
        return nil
    end

    return Hyperspace.Pointf(
        math.floor(location.x / 35) * 35 + 17.5,
        math.floor(location.y / 35) * 35 + 17.5
    )
end

local function get_irradiate_blueprint_name(projectile, damage)
    if not irradiateWeapons[projectile.extend.name] then return nil end
    if damage.iDamage <= 0 then return nil end

    local level = math.min(math.floor(damage.iDamage), 5)

    return "TERRAN_IRRADIATE_EROSION_" .. level
end

local function get_irradiate_level(projectile)
    if not projectile or not projectile.extend then return nil end

    local level =
        projectile.extend.name:match(
            "^TERRAN_IRRADIATE_EROSION_(%d+)$"
        )

    return level and tonumber(level)
end

local function spawn_irradiate_impact(shipManager, projectile, location, blueprintName)
    local target = get_tile_center(shipManager.iShipId, location)
    if not target then return end

    local blueprint = Hyperspace.Blueprints:GetWeaponBlueprint(blueprintName)
    local spaceManager = Hyperspace.Global.GetInstance():GetCApp().world.space

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

local function spawn_erosion_pulse(crew, data)
    local shipManager = Hyperspace.ships(crew.currentShipId)
    if not shipManager or crew.iRoomId < 0 then return end

    local target = shipManager:GetRoomCenter(crew.iRoomId)

    local blueprint =
        Hyperspace.Blueprints:GetWeaponBlueprint(
            "TERRAN_IRRADIATE_EROSION_PULSE_" .. data.level
        )

    local spaceManager = Hyperspace.Global.GetInstance():GetCApp().world.space

    spaceManager:CreateLaserBlast(
        blueprint,
        target,
        shipManager.iShipId,
        data.ownerId,
        target,
        shipManager.iShipId,
        0
    )
end

script.on_internal_event(Defines.InternalEvents.DAMAGE_BEAM, function(shipManager, projectile, location, damage, _realNewTile, beamHitType)
    if beamHitType == Defines.BeamHit.SAME_TILE then
        return Defines.Chain.CONTINUE, beamHitType
    end

    local blueprintName = get_irradiate_blueprint_name(projectile, damage)

    if blueprintName then
        spawn_irradiate_impact(
            shipManager,
            projectile,
            location,
            blueprintName
        )
    end

    return Defines.Chain.CONTINUE, beamHitType
end)

script.on_internal_event(Defines.InternalEvents.DAMAGE_AREA_HIT, function(shipManager, projectile, location)
    local level = get_irradiate_level(projectile)
    if not level then return end

    local x = math.floor(location.x)
    local y = math.floor(location.y)

    for i = 0, shipManager.vCrewList:size() - 1 do
        local crew = shipManager.vCrewList[i]

        if not crew.bDead
            and crew.currentShipId == shipManager.iShipId
            and crew:GetSpecies() ~= "terran_scv"
            and crew:ContainsPoint(x, y) then

            local data =
                userdata_table(
                    crew,
                    "mods.sc.irradiate"
                )

            data.level = math.max(
                data.level or 0,
                level
            )

            data.duration = IRRADIATE_DURATION
            data.pulseTimer = EROSION_PULSE_INTERVAL
            data.ownerId = projectile.ownerId
        end
    end
end)

script.on_internal_event(Defines.InternalEvents.CREW_LOOP, function(crew)
    local data =
        userdata_table(
            crew,
            "mods.sc.irradiate"
        )

    if not data.duration then return end

    if crew.bDead
        or crew.currentShipId < 0
        or crew.iRoomId < 0 then

        data.level = nil
        data.duration = nil
        data.pulseTimer = nil
        data.ownerId = nil
        return
    end

    local frameTime =
        Hyperspace.FPS.SpeedFactor / 16

    data.duration =
        data.duration - frameTime

    if data.duration <= 0 then
        data.level = nil
        data.duration = nil
        data.pulseTimer = nil
        data.ownerId = nil
        return
    end

    data.pulseTimer =
        data.pulseTimer - frameTime

    if data.pulseTimer <= 0 then
        spawn_erosion_pulse(crew, data)

        data.pulseTimer =
            data.pulseTimer + EROSION_PULSE_INTERVAL
    end
end)