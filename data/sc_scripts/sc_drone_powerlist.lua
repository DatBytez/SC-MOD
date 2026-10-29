--[[
DESCRIPTION: Adds crew powerList descriptions to crew drone blueprint descriptions.
DEPENDENCIES: Hyperspace Lua and RapidXML
]]

local associations

local function find_crew_drones(node, results)
    while node do
        if node:name() == "drones" then
            local droneNode = node:first_node("drone")

            while droneNode do
                local nameAttribute = droneNode:first_attribute("name")
                local crewNode = droneNode:first_node("crewBlueprint")

                if nameAttribute and crewNode and crewNode:value() ~= "" then
                    results[nameAttribute:value()] = crewNode:value()
                end

                droneNode = droneNode:next_sibling("drone")
            end
        else
            find_crew_drones(node:first_node(), results)
        end

        node = node:next_sibling()
    end
end

local function get_associations()
    if associations then return associations end

    local results = {}
    local doc = RapidXML.xml_document("data/hyperspace.xml")
    find_crew_drones(doc:first_node(), results)
    doc:clear()

    associations = results
    return associations
end

local function update_blueprint(droneName, crewName)
    local drone = Hyperspace.Blueprints:GetDroneBlueprint(droneName)
    local crew = Hyperspace.Blueprints:GetCrewBlueprint(crewName)
    if not drone or not crew or not crew.powers then return end

    local description = drone.desc.description
    local originalText = description:GetText() or ""
    local additions = {}
    local seen = {}

    for i = 0, crew.powers:size() - 1 do
        local power = crew.powers[i]
        if power.data ~= "DRONE" then
            local powerText = power:GetText()

            if powerText and powerText:find("%S") and not seen[powerText]
                and not originalText:find(powerText, 1, true) then
                seen[powerText] = true
                additions[#additions + 1] = powerText
            end
        end
    end

    if #additions == 0 then return end

    description.data = originalText .. "\n\n" .. table.concat(additions, "\n\n")
    description.isLiteral = true
end

script.on_init(function()
    local ok, list = pcall(get_associations)
    if not ok then
        print("[Drone PowerList] Unable to read hyperspace.xml: " .. tostring(list))
        return
    end

    for droneName, crewName in pairs(list) do
        local succeeded, err = pcall(update_blueprint, droneName, crewName)
        if not succeeded then
            print("[Drone PowerList] " .. droneName .. ": " .. tostring(err))
        end
    end
end)
