--[[
DESCRIPTION: Uses a crew race's _crewLaser animation when one is available.
]]

local missingAnimations = {}

script.on_internal_event(Defines.InternalEvents.CREW_LOOP, function(crew)
    local crewAnimation = crew.crewAnim
    local animationName = crewAnimation.race .. "_crewLaser"

    if crewAnimation.projectile.animName == animationName
        or missingAnimations[animationName] then
        return
    end

    local replacement =
        Hyperspace.Animations:GetAnimation(animationName)

    if not replacement.animationStrip then
        missingAnimations[animationName] = true
        return
    end

    crewAnimation.projectile = replacement
end)