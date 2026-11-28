--[[
DESCRIPTION: Adds custom weapon information to blueprint descriptions,
             weapon stat boxes, and live weapon cooldown displays.
        - Displays Chainstep mechanics using existing scaling tags.
        - Displays additional information for tagged Halo weapons.
TAGS: <sc-chainstep stat="..." value="#"/>
      <sc-halo/>
DEPENDENCIES: sc_tag.lua, sc_weapon_scaling.lua, sc_weapon_chainstep.lua
]]

local scaling = mods.sc.scaling

local haloWeapons = {}

mods.sc.tag.register("weapon", "sc-halo", haloWeapons)

local function get_chainstep_value(weaponName, statName)
    local entry = scaling.get_source_stat_entry("chainstep", weaponName, statName)
    return entry and entry.value
end

local function get_chainstep_max(blueprint)
    local fireThreshold = get_chainstep_value(blueprint.name, "fireThreshold")
    local chainStep = get_chainstep_value(blueprint.name, "chainStep")

    if not fireThreshold or not chainStep or chainStep <= 0 then return end

    return math.max(0, math.ceil((blueprint.cooldown - fireThreshold) / chainStep))
end

local function get_text(textId, ...)
    local text = Hyperspace.Text:GetText(textId)

    for index, value in ipairs({...}) do
        text = text:gsub("\\" .. index, function()
            return tostring(value)
        end)
    end

    return text
end

-- WEAPON DESCRIPTION

script.on_internal_event(Defines.InternalEvents.WEAPON_DESCBOX, function(blueprint, desc)
    if not haloWeapons[blueprint.name] then return end

    desc = desc .. "\n\n" .. get_text("desc_sc_halo")

    return Defines.Chain.CONTINUE, desc
end)

-- WEAPON STAT BOX

script.on_internal_event(Defines.InternalEvents.WEAPON_STATBOX, function(blueprint, stats)
    if not haloWeapons[blueprint.name] then return end

    local maxSteps = get_chainstep_max(blueprint)
    if not maxSteps then return end

    local fireThreshold = get_chainstep_value(blueprint.name, "fireThreshold")
    local chainStep = get_chainstep_value(blueprint.name, "chainStep")
    local radius = get_chainstep_value(blueprint.name, "radius")

    local lines = {
        get_text("stat_sc_chainstep_header"),
        get_text("stat_sc_chainstep_threshold", fireThreshold),
        get_text("stat_sc_chainstep_interval", chainStep),
        get_text("stat_sc_chainstep_max", maxSteps)
    }

    if radius then
        table.insert(lines, get_text("stat_sc_chainstep_radius", string.format("%+g", radius)))
    end

    table.insert(lines, "")
    table.insert(lines, get_text("stat_sc_halo_header"))
    table.insert(lines, get_text("stat_sc_halo_decoys"))

    stats = stats .. "\n\n" .. table.concat(lines, "\n")

    return Defines.Chain.CONTINUE, stats
end)

-- LIVE WEAPON DISPLAY

script.on_internal_event(Defines.InternalEvents.WEAPON_RENDERBOX, function(weapon, _, _, firstLine, secondLine, thirdLine)
    if not haloWeapons[weapon.blueprint.name] then
        return Defines.Chain.CONTINUE, firstLine, secondLine, thirdLine
    end

    local maxSteps = get_chainstep_max(weapon.blueprint)

    if maxSteps then
        thirdLine = get_text("render_sc_halo_step_radius",
            weapon.boostLevel,
            maxSteps,
            string.format("%.0f", weapon.radius))
    end

    return Defines.Chain.CONTINUE, firstLine, secondLine, thirdLine
end)