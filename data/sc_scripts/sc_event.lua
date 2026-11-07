--[[
DESCRIPTION: Fully charges weapons for player or enemy ships through custom event tags.
        - Supports player and enemy targets.
        - Player weapons are charged when the event activates.
        - Enemy weapons are charged after the event's choice box is created.
        - Does not add or remove augments.
TAG: <ambush target="enemy"/>
DEPENDENCIES: sc_tag.lua, Multiverse vter, Hyperspace event hooks.
]]

mods.sc = mods.sc or {}
mods.sc.event = mods.sc.event or {}

local eventAmbushes = {}
local pendingEnemyAmbush = false

local function charge_weapons(ship)
    if not ship or not ship.weaponSystem then return end

    for weapon in mods.multiverse.vter(ship.weaponSystem.weapons) do
        if weapon.powered then
            weapon:ForceCoolup()
        end
    end
end

local function activate_event(eventName)
    local entries = eventAmbushes[eventName]
    if not entries then return end

    pendingEnemyAmbush = false

    for _, target in ipairs(entries) do
        if target == "player" then
            charge_weapons(Hyperspace.Global.GetInstance():GetShipManager(0))
        elseif target == "enemy" then
            pendingEnemyAmbush = true
        end
    end
end

mods.sc.tag.register("event", "ambush", eventAmbushes, function(tagNode, eventNode)
    local entries = {}

    while tagNode do
        local target = tagNode:first_attribute("target")

        if target then
            local targetName = target:value()

            if targetName == "player" or targetName == "enemy" then
                table.insert(entries, targetName)
            end
        end

        tagNode = tagNode:next_sibling("ambush")
    end

    if #entries == 0 then return nil end

    local eventName = eventNode:first_attribute("name"):value()

    script.on_game_event(eventName, false, function()
        activate_event(eventName)
    end)

    return entries
end)

script.on_internal_event(Defines.InternalEvents.POST_CREATE_CHOICEBOX, function()
    if not pendingEnemyAmbush then return end

    pendingEnemyAmbush = false
    charge_weapons(Hyperspace.Global.GetInstance():GetShipManager(1))
end)
