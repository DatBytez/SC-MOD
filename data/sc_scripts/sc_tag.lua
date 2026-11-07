--[[
DESCRIPTION: Registers reusable SC XML tag parsers and named power activation handlers.
        - "value" stores a single numeric or string value.
        - "stat" stores repeated {stat, value} entries.
        - "system" stores repeated {system, value} entries.
        - A function may be supplied for tags that need a custom data structure.
DEPENDENCIES: Multiverse tag-data-init.lua loads before this file; tag-data-read.lua loads after it.
]]

mods.sc = mods.sc or {}
mods.sc.tag = {}

local tag = mods.sc.tag

mods.multiverse.augmentTagParsers = {}
mods.multiverse.powerTagParsers = {}
mods.multiverse.crewTagParsers = {}
mods.multiverse.eventTagParsers = {}

local parserLists = {
    weapon = mods.multiverse.weaponTagParsers,
    drone = mods.multiverse.droneTagParsers,
    augment = mods.multiverse.augmentTagParsers,
    power = mods.multiverse.powerTagParsers,
    crew = mods.multiverse.crewTagParsers,
    event = mods.multiverse.eventTagParsers
}

local function get_value(tagNode)
    local rawValue = tagNode:first_attribute("value"):value()
    return tonumber(rawValue) or rawValue
end

function tag.register(blueprintType, tagName, targetTable, dataType)
    table.insert(parserLists[blueprintType], function(blueprintNode)
        local tagNode = blueprintNode:first_node(tagName)
        if not tagNode then return end

        local nameAttribute = blueprintNode:first_attribute("name")
        if not nameAttribute then return end

        local blueprintName = nameAttribute:value()

        if type(dataType) == "function" then
            local data = dataType(tagNode, blueprintNode)

            if data ~= nil then
                targetTable[blueprintName] = data
            end

            return
        end

        if not dataType then
            targetTable[blueprintName] = true
            return
        end

        if dataType == "value" then
            targetTable[blueprintName] = get_value(tagNode)
            return
        end

        local entries = {}

        while tagNode do
            local entry = { value = get_value(tagNode) }

            entry[dataType] = tagNode:first_attribute(dataType):value()

            table.insert(entries, entry)
            tagNode = tagNode:next_sibling(tagName)
        end

        targetTable[blueprintName] = entries
    end)
end

function tag.on_power_activate(powerName, callback)
    script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power, ship)
        if not power.def or power.def.name ~= powerName then
            return Defines.Chain.CONTINUE
        end

        return callback(power, ship) or Defines.Chain.CONTINUE
    end)
end