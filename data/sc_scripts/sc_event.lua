
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

mods.sc.tag.register("event", "addAugment", eventAugments, function(tagNode)
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

    return #entries > 0 and entries or nil
end)

local function walk_nodes(node, callback)
    while node do
        callback(node)
        walk_nodes(node:first_node(), callback)
        node = node:next_sibling()
    end
end

local function read_event_file(file)
    local doc = RapidXML.xml_document(file)

    walk_nodes(doc:first_node(), function(node)
        if node:name() ~= "event" then return end

        local name = node:first_attribute("name")
        if not name then return end

        for _, parser in ipairs(mods.sc.tag.eventTagParsers) do
            parser(node)
        end
    end)

    doc:clear()
end

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
            add_hidden_augment(player, entry.value)
        elseif entry.target == "enemy" then
            pendingEnemyAugments = pendingEnemyAugments or {}
            table.insert(pendingEnemyAugments, entry.value)
        end
    end
end

script.on_load(function()
    local eventFiles = {}
    local seenFiles = {}

    local doc = RapidXML.xml_document("data/hyperspace.xml")

    walk_nodes(doc:first_node(), function(node)
        if node:name() ~= "eventFile" then return end

        local fileName = "data/events_" .. node:value() .. ".xml"

        if not seenFiles[fileName] then
            seenFiles[fileName] = true
            table.insert(eventFiles, fileName)
        end
    end)

    doc:clear()

    for _, fileName in ipairs(eventFiles) do
        read_event_file(fileName)
    end

    for eventName in pairs(eventAugments) do
        script.on_game_event(eventName, false, function()
            activate_event(eventName)
        end)
    end
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
