mods.multiverse.weaponTagParsers = mods.multiverse.weaponTagParsers or {}
mods.multiverse.augmentTagParsers = mods.multiverse.augmentTagParsers or {}

mods.sc = mods.sc or {}
mods.sc.tag = mods.sc.tag or {}

local weaponTagParsers = mods.multiverse.weaponTagParsers
local augmentTagParsers = mods.multiverse.augmentTagParsers

function mods.sc.tag.register_tag(tagName, targetTable)
    table.insert(weaponTagParsers, function(weaponNode)
        local nameAttr = weaponNode:first_attribute("name")
        if not nameAttr then return end
        local weaponName = nameAttr:value()

        local entries = {}

        local tagNode = weaponNode:first_node(tagName)
        while tagNode do
            local statAttr = tagNode:first_attribute("stat")
            local amountAttr = tagNode:first_attribute("amount")

            if statAttr then
                table.insert(entries, {
                    stat = statAttr:value(),
                    amount = amountAttr and tonumber(amountAttr:value()) or 1
                })
            end

            tagNode = tagNode:next_sibling(tagName)
        end

        if #entries > 0 then
            targetTable[weaponName] = entries
        end
    end)
end

function mods.sc.tag.register_flag_tag(tagName, targetTable)
    table.insert(weaponTagParsers, function(weaponNode)
        local nameAttr = weaponNode:first_attribute("name")
        if not nameAttr then return end
        local weaponName = nameAttr:value()

        local tagNode = weaponNode:first_node(tagName)
        if tagNode then
            targetTable[weaponName] = true
        end
    end)
end

function mods.sc.tag.register_augment_tag(tagName, targetTable)
    table.insert(augmentTagParsers, function(augNode)
        local nameAttr = augNode:first_attribute("name")
        if not nameAttr then return end
        local augmentName = nameAttr:value()

        local tagNode = augNode:first_node(tagName)
        if not tagNode then return end

        if not tagNode:first_attribute("system") and not tagNode:first_attribute("amount") then
            targetTable[augmentName] = true
            return
        end

        local entries = {}

        while tagNode do
            local systemAttr = tagNode:first_attribute("system")
            local amountAttr = tagNode:first_attribute("amount")

            if systemAttr then
                table.insert(entries, {
                    system = systemAttr:value(),
                    amount = amountAttr and tonumber(amountAttr:value()) or 1
                })
            end

            tagNode = tagNode:next_sibling(tagName)
        end

        if #entries > 0 then
            targetTable[augmentName] = entries
        end
    end)
end

mods.sc.tag.register_augment_flag_tag = mods.sc.tag.register_augment_tag

function mods.sc.tag.register_augment_amount_tag(tagName, targetTable)
    table.insert(augmentTagParsers, function(augNode)
        local nameAttr = augNode:first_attribute("name")
        if not nameAttr then return end
        local augmentName = nameAttr:value()

        local entries = {}

        local tagNode = augNode:first_node(tagName)
        while tagNode do
            local amountAttr = tagNode:first_attribute("amount")

            table.insert(entries, {
                amount = amountAttr and tonumber(amountAttr:value()) or 1
            })

            tagNode = tagNode:next_sibling(tagName)
        end

        if #entries > 0 then
            targetTable[augmentName] = entries
        end
    end)
end
