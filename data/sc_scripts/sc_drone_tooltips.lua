--[[
DESCRIPTION: Adds custom drone information to drone descriptions.
        - Displays Defense Matrix shield layers using existing drone tags.
TAGS: <sc-active-shield value="#"/>
DEPENDENCIES: sc_tag.lua
]]

local function get_text(textId, ...)
    local text = Hyperspace.Text:GetText(textId)

    for index, value in ipairs({...}) do
        text = text:gsub("\\" .. index, function()
            return tostring(value)
        end)
    end

    return text
end

-- DEFENSE MATRIX

local activeShieldDrones = {}

mods.sc.tag.register("drone", "sc-active-shield", activeShieldDrones,
    function(tagNode, blueprintNode)
        local value = tagNode:first_attribute("value")
        local shieldLevels = value and tonumber(value:value()) or 1

        shieldLevels = math.max(1, math.floor(shieldLevels))

        local weaponName = blueprintNode:first_attribute("name"):value()
        local blueprint = Hyperspace.Blueprints:GetDroneBlueprint(weaponName)

        if blueprint then
            local descNode = blueprintNode:first_node("desc")
            local descId = descNode and descNode:first_attribute("id")

            local description = descId
                and get_text(descId:value())
                or blueprint.desc.description:GetText()

            blueprint.desc.description.data = description
                .. "\n\n"
                .. get_text("stat_sc_active_shield_layers", shieldLevels)

            blueprint.desc.description.isLiteral = true
        end

        return shieldLevels
    end
)