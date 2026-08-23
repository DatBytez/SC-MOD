--[[
DESCRIPTION: Registers reusable SC XML tag parsers for weapon and augment blueprints.
        - Omit dataType for boolean flag tags.
        - "stat" stores repeated {stat, amount} entries.
        - "system" stores repeated {system, amount} entries.
        - "amount" stores repeated {amount} entries.
DEPENDENCIES: Multiverse tag-data-init.lua loads before this file; tag-data-read.lua loads after it.
]]

mods.sc = mods.sc or {}
mods.sc.tag = mods.sc.tag or {}

local tag = mods.sc.tag

local parserLists = {
    weapon = mods.multiverse.weaponTagParsers,
    drone = mods.multiverse.droneTagParsers,
    augment = mods.multiverse.augmentTagParsers
}

local function get_value(tagNode)
    local rawValue =
        tagNode:first_attribute("value"):value()

    return tonumber(rawValue) or rawValue
end

function tag.register(blueprintType, tagName, targetTable, dataType)
    table.insert(parserLists[blueprintType], function(blueprintNode)
            local tagNode = blueprintNode:first_node(tagName)

            if not tagNode then return end

            local blueprintName = blueprintNode:first_attribute("name"):value()

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
                local entry = {value = get_value(tagNode)}

                entry[dataType] =tagNode:first_attribute(dataType):value()

                table.insert(entries, entry)

                tagNode =tagNode:next_sibling(tagName)
            end

            targetTable[blueprintName] = entries
        end
    )
end