mods.sc_debug = mods.sc_debug or {}
mods.sc_debug.lastAccuracyMod = mods.sc_debug.lastAccuracyMod or {
    [0] = {0, 0, 0},
    [1] = {0, 0, 0}
}
mods.sc_debug.lastRadius = mods.sc_debug.lastRadius or {
    [0] = {0, 0, 0},
    [1] = {0, 0, 0}
}
mods.sc_debug.lastDodge = mods.sc_debug.lastDodge or {
    [0] = 0,
    [1] = 0
}

local DEBUG_AUG_1 = "TERRAN_HIDDEN_FIRE_EXTINGUISHERS_1"
local DEBUG_AUG_2 = "TERRAN_HIDDEN_FIRE_EXTINGUISHERS_2"
local DEBUG_AUG_3 = "TERRAN_HIDDEN_FIRE_EXTINGUISHERS_3"
--local DEBUG_AUG_2 = "TERRAN_HIDDEN_FTL_BOOSTER"
--local DEBUG_AUG_3 = "TERRAN_SHIP_ARMOR_LIGHT"

local function has_debug_augment(ship, augName)
    return ship
        and ship:HasAugmentation(augName) > 0
end

local function push_accuracy_value(shipId, value)
    local history = mods.sc_debug.lastAccuracyMod[shipId]
    if not history then
        history = {0, 0, 0}
        mods.sc_debug.lastAccuracyMod[shipId] = history
    end

    table.remove(history, 1)
    table.insert(history, value or 0)
end

local function push_radius_value(shipId, value)
    local history = mods.sc_debug.lastRadius[shipId]
    if not history then
        history = {0, 0, 0}
        mods.sc_debug.lastRadius[shipId] = history
    end

    table.remove(history, 1)
    table.insert(history, value or 0)
end

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    if not projectile then return end

    local shipId = projectile.ownerId or 0

    if projectile.extend and projectile.extend.customDamage then
        push_accuracy_value(shipId, projectile.extend.customDamage.accuracyMod or 0)
    else
        push_accuracy_value(shipId, 0)
    end

    local radius = 0
    if weapon then
        local wdata = mods.multiverse.userdata_table(weapon, "mods.sc.weaponStuff")
        if wdata.fireRadiusOverride ~= nil then
            radius = wdata.fireRadiusOverride
        else
            radius = weapon.radius or 0
        end
    end

    push_radius_value(shipId, radius)
end)

script.on_internal_event(Defines.InternalEvents.GET_DODGE_FACTOR, function(shipMgr, dodge)
    if not shipMgr then
        return Defines.Chain.CONTINUE, dodge
    end

    local shipId = shipMgr.iShipId or 0
    mods.sc_debug.lastDodge[shipId] = dodge

    return Defines.Chain.CONTINUE, dodge
end)

script.on_render_event(
    Defines.RenderEvents.SHIP_STATUS,
    function() return Defines.Chain.CONTINUE end,
    function()
        local shipMgr = Hyperspace.ships.player
        if not shipMgr then return end

        local shipId = shipMgr.iShipId or 0
        local accHistory = mods.sc_debug.lastAccuracyMod[shipId] or {0, 0, 0}
        local radiusHistory = mods.sc_debug.lastRadius[shipId] or {0, 0, 0}
        local dodge = mods.sc_debug.lastDodge[shipId] or 0

        local accText = table.concat(accHistory, " / ")
        local radiusText = table.concat(radiusHistory, " / ")

        local hasAug1 = has_debug_augment(shipMgr, DEBUG_AUG_1)
        local hasAug2 = has_debug_augment(shipMgr, DEBUG_AUG_2)
        local hasAug3 = has_debug_augment(shipMgr, DEBUG_AUG_3)

        Graphics.freetype.easy_print(0, 10, 300, "AccuracyMod: " .. accText)
        Graphics.freetype.easy_print(0, 10, 325, "Radius: " .. radiusText)
        --Graphics.freetype.easy_print(0, 10, 350, "Dodge Bonus: " .. tostring(dodge))
        Graphics.freetype.easy_print(0, 10, 375, DEBUG_AUG_1 .. ": " .. (hasAug1 and "YES" or "NO"))
        Graphics.freetype.easy_print(0, 10, 400, DEBUG_AUG_2 .. ": " .. (hasAug2 and "YES" or "NO"))
        Graphics.freetype.easy_print(0, 10, 425, DEBUG_AUG_3 .. ": " .. (hasAug3 and "YES" or "NO"))
    end
)