
--[[
DESCRIPTION: Adds hidden augments to ships through custom event tags.
        - Supports player and enemy targets.
        - Enemy augments are added during ship generation.
        - All added augments are hidden and do not occupy normal augment slots.
TAG: <addAugment value="AUGMENT_NAME" target="enemy"/>
DEPENDENCIES: sc_tag.lua, Hyperspace event and ship generation hooks.
]]

mods.sc = mods.sc or {}
mods.sc.event = mods.sc.event or {}

local eventAugments = {}
local pendingEnemyAugments = nil

local function add_hidden_augment(ship, augmentName)
    if not ship or ship:HasAugmentation(augmentName) > 0 then return end

    ship:AddAugmentation("HIDDEN " .. augmentName)
end

local function activate_event(eventName)
    local entries = eventAugments[eventName]
    if not entries then return end

    pendingEnemyAugments = nil

    local player = Hyperspace.Global.GetInstance():GetShipManager(0)

    for _, entry in ipairs(entries) do

        if entry.target == "player" then
            local hadAugment = player and player:HasAugmentation(entry.value) > 0

            add_hidden_augment(player, entry.value)

            if player and not hadAugment and entry.value == "WEAPON_PREIGNITE" and player.weaponSystem then
                for weapon in mods.multiverse.vter(player.weaponSystem.weapons) do
                    if weapon.powered then
                        weapon:ForceCoolup()
                    end
                end
            end
        elseif entry.target == "enemy" then
            pendingEnemyAugments = pendingEnemyAugments or {}
            table.insert(pendingEnemyAugments, entry.value)
        end
    end
end

mods.sc.tag.register("event", "addAugment", eventAugments, function(tagNode, eventNode)
    local entries = {}

    while tagNode do
        local value = tagNode:first_attribute("value")
        local target = tagNode:first_attribute("target")

        if value and target then
            local targetName = target:value()

            if targetName == "player" or targetName == "enemy" then
                table.insert(entries, {
                    value = value:value(),
                    target = targetName
                })
            end
        end

        tagNode = tagNode:next_sibling("addAugment")
    end

    if #entries == 0 then return nil end

    local eventName = eventNode:first_attribute("name"):value()

    script.on_game_event(eventName, false, function()
        activate_event(eventName)
    end)

    return entries
end)

script.on_internal_event(Defines.InternalEvents.GENERATOR_CREATE_SHIP_POST,
    function(name, sector, event, bp, ship)
        if not pendingEnemyAugments or not ship then
            return Defines.Chain.CONTINUE
        end

        for _, augmentName in ipairs(pendingEnemyAugments) do
            add_hidden_augment(ship, augmentName)
        end

        pendingEnemyAugments = nil

        return Defines.Chain.CONTINUE
    end
)

script.on_internal_event(Defines.InternalEvents.POST_CREATE_CHOICEBOX, function()
    pendingEnemyAugments = nil
end)
