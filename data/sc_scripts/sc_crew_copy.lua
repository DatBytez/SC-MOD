--[[
DESCRIPTION: Provides reusable helpers for copying and moving crew between ships.
        - Snapshots crew identity, sex, ownership, location, health, death count, appearance, skills, and power state.
        - Recreates a new CrewMember from a saved snapshot.
DEPENDENCIES: None
]]

mods.sc = mods.sc or {}
mods.sc.crew_copy = mods.sc.crew_copy or {}

local crew_copy = mods.sc.crew_copy

local function snapshot_crew_powers(crew)
    local snapshots = {}
    local powers = crew.extend and crew.extend.crewPowers

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
    local powers = crew.extend and crew.extend.crewPowers
    if not powers then return nil end

    if savedPower.index ~= nil
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
    for _, savedPower in ipairs(savedPowers) do
        local power = find_matching_power(crew, savedPower)

        if power then
            pcall(function()
                local newCooldownTotal = power.powerCooldown.second

                if newCooldownTotal and newCooldownTotal > 0 then
                    power.powerCooldown.first = newCooldownTotal * savedPower.cooldownFraction
                else
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
    pcall(function()
        if crew.blueprint and crew.blueprint.colorChoices then
            crew.blueprint.colorChoices:clear()

            for _, choice in ipairs(appearance.colorChoices) do
                crew.blueprint.colorChoices:push_back(choice)
            end
        end

        if crew.crewAnim and crew.crewAnim.layerColors then
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
    local skillLevels = crew.blueprint and crew.blueprint.skillLevel

    if not skillLevels then return skills end

    pcall(function()
        for skillId = 0, math.min(6, skillLevels:size()) - 1 do
            skills[#skills + 1] = {
                id = skillId,
                progress = skillLevels[skillId].first
            }
        end
    end)

    return skills
end

local function restore_crew_skills(crew, savedSkills)
    pcall(function()
        for _, savedSkill in ipairs(savedSkills) do
            crew:SetSkillProgress(savedSkill.id, savedSkill.progress)
        end
    end)
end

function crew_copy.snapshot(crew)
    if not crew then return nil end

    local male = nil
    if crew.blueprint then
        male = crew.blueprint.male
    end

    return {
        name = crew:GetName(),
        species = crew:GetSpecies(),
        male = male,
        ownerShipId = crew.iShipId,
        currentShipId = crew.currentShipId,
        roomId = crew.iRoomId,
        health = crew.health and crew.health.first or nil,
        deathNumber = crew.iDeathNumber,
        powers = snapshot_crew_powers(crew),
        appearance = snapshot_crew_appearance(crew),
        skills = snapshot_crew_skills(crew)
    }
end

function crew_copy.recreate(snapshot, shipManager, roomId)
    if not snapshot or not shipManager then return nil end

    local intruder = snapshot.ownerShipId ~= shipManager.iShipId

    local spawnOk, newCrew = pcall(function()
        return shipManager:AddCrewMemberFromString(
            snapshot.name,
            snapshot.species,
            intruder,
            roomId,
            true,
            false
        )
    end)

    if not spawnOk or not newCrew then return nil end

    if snapshot.male ~= nil then
        pcall(function()
            newCrew:SetSex(snapshot.male)
        end)
    end

    restore_crew_appearance(newCrew, snapshot.appearance)
    restore_crew_skills(newCrew, snapshot.skills)
    restore_crew_powers(newCrew, snapshot.powers)

    if snapshot.deathNumber ~= nil then
        pcall(function()
            newCrew:SetDeathNumber(snapshot.deathNumber)
        end)
    end

    if snapshot.health ~= nil then
        pcall(function()
            local healthDelta = math.max(1, snapshot.health) - newCrew:GetIntegerHealth()

            if math.abs(healthDelta) > 0.001 then
                newCrew:DirectModifyHealth(healthDelta)
            end
        end)
    end

    return newCrew
end

function crew_copy.retire(crew)
    local emptySlotOk = pcall(function()
        crew:EmptySlot()
    end)

    if not emptySlotOk then return false end

    crew:SetCloneReady(false)
    crew:SetOutOfGame()

    return true
end

function crew_copy.copy(crew, shipManager, roomId)
    local snapshot = crew_copy.snapshot(crew)

    return crew_copy.recreate(snapshot, shipManager, roomId)
end

function crew_copy.move(crew, shipManager, roomId)
    local snapshot = crew_copy.snapshot(crew)
    if not snapshot then return nil end

    local sourceShip = Hyperspace.Global.GetInstance():GetShipManager(snapshot.currentShipId)

    if not crew_copy.retire(crew) then return nil end

    local movedCrew = crew_copy.recreate(snapshot, shipManager, roomId)
    if movedCrew then return movedCrew end

    if sourceShip and not sourceShip.bDestroyed then
        crew_copy.recreate(snapshot, sourceShip, snapshot.roomId)
    end

    return nil
end