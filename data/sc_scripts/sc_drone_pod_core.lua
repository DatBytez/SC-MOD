--[[
DESCRIPTION: Shared state and crew transport utilities for the Terran Drop Pod drone.
        - Snapshots transported crew state before the original CrewMember is retired.
        - Recreates transported crew while preserving name, health, appearance, skills, and power state.
DEPENDENCIES: Multiverse userdata_table
]]

local userdata_table = mods.multiverse.userdata_table

mods.sc_drone_pod = mods.sc_drone_pod or {}
local pod = mods.sc_drone_pod

local POD_USERDATA = "mods.sc.dronePod"

pod.nextTransportId = pod.nextTransportId or 0
pod.activeTransports = pod.activeTransports or {}
pod.returnableBoarders = pod.returnableBoarders or {}

local function snapshot_crew_powers(crew)
    local snapshots = {}
    local powers = crew and crew.extend and crew.extend.crewPowers

    if not powers then return snapshots end

    for i = 0, powers:size() - 1 do
        local power = powers[i]

        if power then
            local cooldownCurrent = power.powerCooldown and power.powerCooldown.first or 0
            local cooldownTotal = power.powerCooldown and power.powerCooldown.second or 0
            local cooldownFraction = 1

            if cooldownTotal > 0 then
                cooldownFraction = math.max(0, math.min(1, cooldownCurrent / cooldownTotal))
            end

            snapshots[#snapshots + 1] = {
                index = i,
                name = power.def and power.def.name or nil,
                cooldownCurrent = cooldownCurrent,
                cooldownFraction = cooldownFraction,
                chargesCurrent = power.powerCharges and power.powerCharges.first or nil
            }
        end
    end

    return snapshots
end

local function find_matching_power(crew, savedPower)
    local powers = crew and crew.extend and crew.extend.crewPowers
    if not powers or not savedPower then return nil end

    if savedPower.index ~= nil
        and savedPower.index >= 0
        and savedPower.index < powers:size() then

        local indexedPower = powers[savedPower.index]

        if indexedPower then
            local indexedName = indexedPower.def and indexedPower.def.name or nil

            if savedPower.name == nil or savedPower.name == indexedName then
                return indexedPower
            end
        end
    end

    if savedPower.name ~= nil then
        for i = 0, powers:size() - 1 do
            local power = powers[i]

            if power and power.def and power.def.name == savedPower.name then
                return power
            end
        end
    end

    return nil
end

local function restore_crew_powers(crew, savedPowers)
    if not crew or not savedPowers then return end

    for _, savedPower in ipairs(savedPowers) do
        local power = find_matching_power(crew, savedPower)

        if power then
            pcall(function()
                local newCooldownTotal = power.powerCooldown.second

                if newCooldownTotal and newCooldownTotal > 0 then
                    power.powerCooldown.first = newCooldownTotal * savedPower.cooldownFraction
                elseif savedPower.cooldownCurrent ~= nil then
                    power.powerCooldown.first = savedPower.cooldownCurrent
                end

                if savedPower.chargesCurrent ~= nil and power.powerCharges then
                    local newChargesTotal = power.powerCharges.second

                    if newChargesTotal ~= nil and newChargesTotal >= 0 then
                        power.powerCharges.first = math.max(
                            0,
                            math.min(savedPower.chargesCurrent, newChargesTotal)
                        )
                    else
                        power.powerCharges.first = savedPower.chargesCurrent
                    end
                end
            end)
        end
    end
end

local function snapshot_crew_appearance(crew)
    local appearance = {
        colorChoices = {},
        layerColors = {}
    }

    if not crew then return appearance end

    pcall(function()
        if crew.blueprint and crew.blueprint.colorChoices then
            for i = 0, crew.blueprint.colorChoices:size() - 1 do
                appearance.colorChoices[#appearance.colorChoices + 1] = crew.blueprint.colorChoices[i]
            end
        end

        if crew.crewAnim and crew.crewAnim.layerColors then
            for i = 0, crew.crewAnim.layerColors:size() - 1 do
                local color = crew.crewAnim.layerColors[i]

                appearance.layerColors[#appearance.layerColors + 1] = {
                    r = color.r,
                    g = color.g,
                    b = color.b,
                    a = color.a
                }
            end
        end
    end)

    return appearance
end

local function restore_crew_appearance(crew, appearance)
    if not crew or not appearance then return end

    pcall(function()
        if crew.blueprint
            and crew.blueprint.colorChoices
            and appearance.colorChoices then

            crew.blueprint.colorChoices:clear()

            for _, choice in ipairs(appearance.colorChoices) do
                crew.blueprint.colorChoices:push_back(choice)
            end
        end

        if crew.crewAnim
            and crew.crewAnim.layerColors
            and appearance.layerColors then

            crew.crewAnim.layerColors:clear()

            for _, color in ipairs(appearance.layerColors) do
                crew.crewAnim.layerColors:push_back(
                    Graphics.GL_Color(color.r, color.g, color.b, color.a)
                )
            end
        end
    end)
end

local function snapshot_crew_skills(crew)
    local skills = {}

    if not crew or not crew.blueprint or not crew.blueprint.skillLevel then
        return skills
    end

    pcall(function()
        local skillCount = math.min(6, crew.blueprint.skillLevel:size())

        for skillId = 0, skillCount - 1 do
            local skillPair = crew.blueprint.skillLevel[skillId]

            skills[#skills + 1] = {
                id = skillId,
                progress = skillPair.first
            }
        end
    end)

    return skills
end

local function restore_crew_skills(crew, savedSkills)
    if not crew or not savedSkills then return end

    pcall(function()
        for _, savedSkill in ipairs(savedSkills) do
            crew:SetSkillProgress(savedSkill.id, savedSkill.progress)
        end
    end)
end

function pod.snapshot_crew(crew)
    if not crew then return nil end

    local health = crew.health

    return {
        name = crew:GetName(),
        species = crew:GetSpecies(),
        health = health and health.first or nil,
        powers = snapshot_crew_powers(crew),
        appearance = snapshot_crew_appearance(crew),
        skills = snapshot_crew_skills(crew)
    }
end

function pod.create_transport_payload(crew, sourceShipId, targetShipId)
    pod.nextTransportId = pod.nextTransportId + 1

    local payload = {
        transportId = pod.nextTransportId,
        sourceShipId = sourceShipId,
        sourceRoomId = crew.iRoomId,
        targetShipId = targetShipId,
        snapshot = pod.snapshot_crew(crew)
    }

    pod.activeTransports[payload.transportId] = payload
    return payload
end

function pod.remove_original_crew(crew, transportId)
    if not crew then return false end

    local crewData = userdata_table(crew, POD_USERDATA)
    crewData.inTransit = true
    crewData.transportId = transportId

    local emptySlotOk = pcall(function()
        crew:EmptySlot()
    end)

    if not emptySlotOk then
        crewData.inTransit = false
        crewData.transportId = nil
        return false
    end

    crew:SetCloneReady(false)
    crew:SetOutOfGame()

    return true
end

function pod.recreate_crew(payload, shipManager, roomId)
    if not payload or not payload.snapshot or not shipManager then return nil end

    local snapshot = payload.snapshot
    local intruder = payload.sourceShipId ~= shipManager.iShipId

    local spawnOk, spawnResult = pcall(function()
        return shipManager:AddCrewMemberFromString(
            snapshot.name,
            snapshot.species,
            intruder,
            roomId,
            true,
            false
        )
    end)

    if not spawnOk then return nil end

    local newCrew = spawnResult
    if not newCrew then return nil end

    restore_crew_appearance(newCrew, snapshot.appearance)
    restore_crew_skills(newCrew, snapshot.skills)
    restore_crew_powers(newCrew, snapshot.powers)

    if snapshot.health ~= nil then
        pcall(function()
            local currentHealth = newCrew:GetIntegerHealth()
            local targetHealth = math.max(1, snapshot.health)
            local healthDelta = targetHealth - currentHealth

            if math.abs(healthDelta) > 0.001 then
                newCrew:DirectModifyHealth(healthDelta)
            end
        end)
    end

    return newCrew
end

function pod.return_transport_to_source(transportId)
    local payload = pod.activeTransports[transportId]
    if not payload then return end

    local sourceShip = Hyperspace.Global.GetInstance():GetShipManager(payload.sourceShipId)

    if sourceShip then
        pod.recreate_crew(payload, sourceShip, payload.sourceRoomId)
    end

    pod.activeTransports[transportId] = nil
end
