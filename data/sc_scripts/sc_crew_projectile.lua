--[[
DESCRIPTION: Uses race-specific crew projectile animations when available.
        - Looks for <animation race>_crewLaser for each crew member.
        - Falls back to species/type prefixes if needed.
        - If no matching _crewLaser animation exists, leaves FTL's existing
          crew projectile behavior unchanged.
]]

local animationAvailability = {}

local function valid_animation(animation)
    return animation
        and animation.info
        and animation.info.frameWidth > 0
        and animation.info.frameHeight > 0
end

local function animation_exists(animationName)
    local cached = animationAvailability[animationName]

    if cached ~= nil then
        return cached
    end

    local success, animation = pcall(function()
        return Hyperspace.Animations:GetAnimation(animationName)
    end)

    local exists = success and valid_animation(animation)
    animationAvailability[animationName] = exists

    return exists
end

local function find_crew_projectile_animation(crew)
    local prefixes = {}
    local seen = {}

    local function add_prefix(prefix)
        if prefix and prefix ~= "" and not seen[prefix] then
            seen[prefix] = true
            table.insert(prefixes, prefix)
        end
    end

    add_prefix(crew.crewAnim.race)
    add_prefix(crew.species)
    add_prefix(crew.type)

    for _, prefix in ipairs(prefixes) do
        local animationName = prefix .. "_crewLaser"

        if animation_exists(animationName) then
            return animationName
        end
    end

    return nil
end

script.on_internal_event(Defines.InternalEvents.CREW_LOOP, function(crew)
    if not crew.crewAnim then
        return
    end

    local animationName = find_crew_projectile_animation(crew)

    if not animationName then
        return
    end

    local currentProjectile = crew.crewAnim.projectile

    if currentProjectile
        and currentProjectile.animName == animationName then
        return
    end

    local success, replacement = pcall(function()
        return Hyperspace.Animations:GetAnimation(animationName)
    end)

    if not success or not valid_animation(replacement) then
        return
    end

    pcall(function()
        crew.crewAnim.projectile = replacement
    end)
end)
