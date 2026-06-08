-- Make tag tables local
local weaponTagParsers = mods.multiverse.weaponTagParsers
local droneTagParsers = mods.multiverse.droneTagParsers
local augmentTagParsers = mods.multiverse.augmentTagParsers

-- Check all weapons, drones, and augments for custom tags on game load
script.on_load(function()
    for _, file in ipairs(mods.multiverse.blueprintFiles) do
        local doc = RapidXML.xml_document(file)
        local root = doc:first_node("FTL") or doc

        local blueprintNode = root:first_node("weaponBlueprint")
        while blueprintNode do
            for _, weaponTagParser in ipairs(weaponTagParsers) do
                weaponTagParser(blueprintNode)
            end
            blueprintNode = blueprintNode:next_sibling("weaponBlueprint")
        end

        blueprintNode = root:first_node("droneBlueprint")
        while blueprintNode do
            for _, droneTagParser in ipairs(droneTagParsers) do
                droneTagParser(blueprintNode)
            end
            blueprintNode = blueprintNode:next_sibling("droneBlueprint")
        end

        blueprintNode = root:first_node("augBlueprint")
        while blueprintNode do
            for _, augmentTagParser in ipairs(augmentTagParsers) do
                augmentTagParser(blueprintNode)
            end
            blueprintNode = blueprintNode:next_sibling("augBlueprint")
        end

        doc:clear()
    end
end)
