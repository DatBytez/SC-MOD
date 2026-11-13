-- Check all weapons, drones, augments, powers, crew, and events for custom tags on game load
script.on_load(function()
    -- Make tag tables local
    local weaponTagParsers = mods.multiverse.weaponTagParsers
    local droneTagParsers = mods.multiverse.droneTagParsers
    local augmentTagParsers = mods.multiverse.augmentTagParsers
    local powerTagParsers = mods.multiverse.powerTagParsers
    local crewTagParsers = mods.multiverse.crewTagParsers
    local eventTagParsers = mods.multiverse.eventTagParsers

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

    local eventFiles = {}
    local seenFiles = {}

    local doc = RapidXML.xml_document("data/hyperspace.xml")
    local root = doc:first_node("FTL")

    while root do
        local eventsNode = root:first_node("events")

        while eventsNode do
            local fileNode = eventsNode:first_node("eventFile")

            while fileNode do
                local file = "data/events_" .. fileNode:value() .. ".xml"

                if not seenFiles[file] then
                    seenFiles[file] = true
                    table.insert(eventFiles, file)
                end

                fileNode = fileNode:next_sibling("eventFile")
            end

            eventsNode = eventsNode:next_sibling("events")
        end

        root = root:next_sibling("FTL")
    end

    doc:clear()

    for _, file in ipairs(eventFiles) do
        local ok, doc = pcall(RapidXML.xml_document, file)

        if ok and doc then
            local root = doc:first_node("FTL") or doc

            local eventNode = root:first_node("event")
            while eventNode do
                for _, eventTagParser in ipairs(eventTagParsers) do
                    eventTagParser(eventNode)
                end
                eventNode = eventNode:next_sibling("event")
            end

            doc:clear()
        end
    end

    local doc = RapidXML.xml_document("data/hyperspace.xml")
    local root = doc:first_node("FTL") or doc

    local crewNode = root:first_node("crew")
    while crewNode do
        local raceNode = crewNode:first_node("race")

        while raceNode do
            for _, crewTagParser in ipairs(crewTagParsers) do
                crewTagParser(raceNode)
            end

            local powerNode = raceNode:first_node("powerEffect")

            while powerNode do
                for _, powerTagParser in ipairs(powerTagParsers) do
                    powerTagParser(powerNode)
                end

                powerNode = powerNode:next_sibling("powerEffect")
            end

            raceNode = raceNode:next_sibling("race")
        end

        crewNode = crewNode:next_sibling("crew")
    end

    doc:clear()
end)