-- Make tag tables local
local weaponTagParsers = mods.multiverse.weaponTagParsers
local droneTagParsers = mods.multiverse.droneTagParsers
local augmentTagParsers = mods.multiverse.augmentTagParsers
local powerTagParsers = mods.multiverse.powerTagParsers

-- Check all weapons, drones, augments, and power for custom tags on game load
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

        local raceNode = root:first_node("race")
        while raceNode do
            local powerNode = raceNode:first_node("powerEffect")

            while powerNode do
                for _, powerTagParser in ipairs(powerTagParsers) do
                    powerTagParser(powerNode)
                end

                powerNode = powerNode:next_sibling("powerEffect")
            end

            raceNode = raceNode:next_sibling("race")
        end

        doc:clear()
    end
end)
