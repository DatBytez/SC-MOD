--[[
DESCRIPTION: Adds custom weapon information to weapon stat boxes
             and live weapon cooldown displays.
        - Displays Charge, Chainstep, and Chain mechanics using existing scaling tags.
        - Calculates stat ranges from blueprint values and scaling modifiers.
        - Groups accuracy, targeting radius, and shots together.
        - Removes redundant native charge and chain information.
        - Displays pairing compatibility and paired secondary information.
TAGS: <sc-charge stat="..." value="#"/>
      <sc-chainstep stat="..." value="#"/>
      <sc-chain stat="..." value="#"/>
      <sc_paired group="GROUP"/>
DEPENDENCIES: sc_weapon_scaling.lua, sc_weapon_charge.lua,
              sc_weapon_chainstep.lua, sc_weapon_chain.lua,
              sc_weapon_paired_core.lua
]]

local scaling = mods.sc.scaling
local paired = mods.sc.paired

local function get_scaling_value(source, weaponName, statName)
    local entry = scaling.get_source_stat_entry(source, weaponName, statName)
    return entry and entry.value
end

local function get_chainstep_max(blueprint)
    local fireThreshold = get_scaling_value("chainstep", blueprint.name, "fireThreshold")
    local chainStep = get_scaling_value("chainstep", blueprint.name, "chainStep")

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

local function format_number(value)
    local text = string.format("%.2f", value)
    text = text:gsub("0+$", ""):gsub("%.$", "")
    return text
end

local function format_accuracy(value)
    return value > 0 and "+" .. tostring(value) or tostring(value)
end

local function get_stat_prefix(textId)
    local text = Hyperspace.Text:GetText(textId)
    local position = text:find("\\1", 1, true)

    return position and text:sub(1, position - 1) or text
end

local function find_stat_line(lines, textId)
    local prefix = get_stat_prefix(textId)

    if prefix == "" then return end

    for index, line in ipairs(lines) do
        if line:sub(1, #prefix) == prefix then
            return index
        end
    end
end

local function remove_stat_line(lines, textId)
    local index = find_stat_line(lines, textId)

    if index then
        return table.remove(lines, index)
    end
end

local function get_total_charge_time(blueprint)
    local cooldown = blueprint.cooldown
    local modifier = get_scaling_value("charge", blueprint.name, "cooldown") or 0
    local totalTime = cooldown

    for level = 1, blueprint.chargeLevels - 1 do
        if modifier > 0 then
            totalTime = totalTime + cooldown / (1 + level * modifier)
        else
            totalTime = totalTime + cooldown * (1 + level * math.abs(modifier))
        end
    end

    return totalTime
end

local function get_weapon_scaling(blueprint)
    local weaponName = blueprint.name

    if scaling.get_source_stat_entries("chainstep", weaponName) then
        local maxSteps = get_chainstep_max(blueprint)

        if maxSteps then
            return "chainstep", maxSteps
        end

    elseif scaling.get_source_stat_entries("charge", weaponName) then
        return "charge", math.max(0, blueprint.chargeLevels - 1)

    elseif scaling.get_source_stat_entries("chain", weaponName) then
        return "chain", math.max(0, blueprint.boostPower.count)
    end
end

-- PAIRED WEAPON STAT BOX

script.on_internal_event(Defines.InternalEvents.WEAPON_STATBOX, function(blueprint, stats)
    local weaponName = blueprint.name

    if weaponName == paired.GENERIC_SECONDARY_BLUEPRINT then
        return Defines.Chain.CONTINUE, get_text("stat_sc_paired_secondary")
    end

    local group = paired.groups[weaponName]
    if not group then return end

    local groupName = get_text("stat_sc_paired_group_" .. group)

    if groupName == "" or groupName == "stat_sc_paired_group_" .. group then
        groupName = group
    end

    local pairingText = get_text("stat_sc_paired_group", groupName)

    local lines = {}

    for line in (stats .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end

    local insertIndex = find_stat_line(lines, "stat_resources_missiles")
        or find_stat_line(lines, "ammo_consumption")
        or find_stat_line(lines, "charge_time")

    if insertIndex then
        table.insert(lines, insertIndex + 1, pairingText)
    else
        table.insert(lines, 1, pairingText)
    end

    return Defines.Chain.CONTINUE, table.concat(lines, "\n")
end)

-- WEAPON STAT BOX

script.on_internal_event(Defines.InternalEvents.WEAPON_STATBOX, function(blueprint, stats)
    local weaponName = blueprint.name
    local source, maxLevel = get_weapon_scaling(blueprint)

    if not source then return end

    local lines = {}

    for line in (stats .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end

    -- CHARGE TIME AND LEVELS

    local minimumTime
    local maximumTime
    local levelText

    if source == "charge" then
        minimumTime = blueprint.cooldown
        maximumTime = get_total_charge_time(blueprint)

        levelText = get_text("stat_sc_charge_levels", blueprint.chargeLevels)

        local nativeChargeText = get_text("charge", blueprint.chargeLevels)

        for index = #lines, 1, -1 do
            if lines[index] == nativeChargeText then
                table.remove(lines, index)
            end
        end

    elseif source == "chainstep" then
        minimumTime = get_scaling_value(source, weaponName, "fireThreshold")
        maximumTime = blueprint.cooldown

        levelText = get_text("stat_sc_chainstep_max", maxLevel)

        if blueprint.boostPower.amount == 0 then
            remove_stat_line(lines, "redesigned_boost_power_speed_positive")
            remove_stat_line(lines, "redesigned_boost_power_speed_negative")
            remove_stat_line(lines, "redesigned_speed_cap")
        end

    elseif source == "chain" then
        minimumTime = blueprint.cooldown
        maximumTime = math.max(0,
            blueprint.cooldown - maxLevel * blueprint.boostPower.amount)

        levelText = get_text("stat_sc_chain_levels", maxLevel)

        remove_stat_line(lines, "redesigned_boost_power_speed_positive")
        remove_stat_line(lines, "redesigned_boost_power_speed_negative")
        remove_stat_line(lines, "redesigned_speed_cap")
    end

    local cooldownIndex = find_stat_line(lines, "charge_time")

    if cooldownIndex then
        lines[cooldownIndex] = get_text("charge_time",
            format_number(minimumTime) .. " - " .. format_number(maximumTime))

        table.insert(lines, cooldownIndex + 1, levelText)
    end

    -- ACCURACY

    local accuracyLine = remove_stat_line(lines, "accuracy_modifier")
    local accuracyBoost = get_scaling_value(source, weaponName, "accuracyMod")

    if accuracyBoost then
        local baseAccuracy = 0

        if accuracyLine then
            local prefix = get_stat_prefix("accuracy_modifier")

            baseAccuracy = tonumber(
                accuracyLine:sub(#prefix + 1):match("[-+]?%d+")
            ) or 0
        end

        local finalAccuracy = baseAccuracy + maxLevel * accuracyBoost

        accuracyLine = get_text("stat_sc_accuracy_range",
            format_accuracy(baseAccuracy),
            format_accuracy(finalAccuracy))
    end

    -- TARGETING RADIUS

    local radiusBoost = get_scaling_value(source, weaponName, "radius")
    local radiusIndex = find_stat_line(lines, "shot_radius")

    if radiusBoost then
        local baseRadius = blueprint.radius
        local finalRadius = math.max(0, baseRadius + maxLevel * radiusBoost)

        local radiusText = get_text("shot_radius",
            format_number(baseRadius) .. " - " .. format_number(finalRadius))

        if radiusIndex then
            lines[radiusIndex] = radiusText
        else
            local shotsIndex = find_stat_line(lines, "shots")

            if shotsIndex then
                table.insert(lines, shotsIndex, radiusText)
            end
        end
    end

    -- GROUP ACCURACY, RADIUS, AND SHOTS

    if accuracyLine then
        local insertIndex = find_stat_line(lines, "shot_radius")
            or find_stat_line(lines, "shots")
            or find_stat_line(lines, "beam_length")

        if insertIndex then
            table.insert(lines, insertIndex, accuracyLine)
        elseif cooldownIndex then
            table.insert(lines, cooldownIndex + 2, accuracyLine)
        end
    end

    -- SHOT COUNT

    local shotBoost = get_scaling_value(source, weaponName, "shots")

    if source == "chain" and shotBoost then
        local baseShots = math.max(1,
            math.min(blueprint.shots, shotBoost - 1))

        local finalShots = math.max(1,
            math.min(blueprint.shots, shotBoost - 1 + maxLevel))

        local shotsIndex = find_stat_line(lines, "shots")

        if shotsIndex then
            lines[shotsIndex] = get_text("shots",
                format_number(baseShots) .. " - " .. format_number(finalShots))
        end
    end

    -- BREACH CHANCE

    local breachBoost = get_scaling_value(source, weaponName, "breachChance")

    if breachBoost then
        local baseBreach = math.max(0, math.min(100,
            blueprint.damage.breachChance * 10))

        local finalBreach = math.max(0, math.min(100,
            (blueprint.damage.breachChance + maxLevel * breachBoost) * 10))

        local breachText = get_text("stat_sc_breach_range",
            baseBreach, finalBreach)

        local breachIndex = find_stat_line(lines, "breach_chance")

        if breachIndex then
            lines[breachIndex] = breachText
        else
            while lines[#lines] == "" do
                table.remove(lines)
            end

            table.insert(lines, "")
            table.insert(lines, breachText)
        end
    end

    -- STUN CHANCE

    local stunBoost = get_scaling_value(source, weaponName, "stunChance")

    if stunBoost then
        local baseStun = math.max(0, math.min(100,
            blueprint.damage.stunChance * 10))

        local finalStun = math.max(0, math.min(100,
            (blueprint.damage.stunChance + maxLevel * stunBoost) * 10))

        local stunText = get_text("stat_sc_stun_range",
            baseStun, finalStun)

        local stunIndex = find_stat_line(lines, "stun_chance")

        if stunIndex then
            lines[stunIndex] = stunText
        else
            local fireIndex = find_stat_line(lines, "fire_chance")
            local breachIndex = find_stat_line(lines, "breach_chance")

            local insertIndex = breachIndex or fireIndex

            if insertIndex then
                table.insert(lines, insertIndex + 1, stunText)
            else
                table.insert(lines, "")
                table.insert(lines, stunText)
            end
        end
    end

    -- REMOVE REDUNDANT LINE BREAKS

    stats = table.concat(lines, "\n")
    stats = stats:gsub("\n\n\n+", "\n\n")

    return Defines.Chain.CONTINUE, stats
end)

-- LIVE WEAPON DISPLAY

script.on_internal_event(Defines.InternalEvents.WEAPON_RENDERBOX, function(weapon, _, _, firstLine, secondLine, thirdLine)
    local blueprint = weapon.blueprint
    local source, maxLevel = get_weapon_scaling(blueprint)

    if source == "charge" then
        thirdLine = get_text("render_sc_charge_level_radius",
            weapon.chargeLevel,
            blueprint.chargeLevels,
            string.format("%.0f", weapon.radius))

    elseif source == "chainstep" then
        thirdLine = get_text("render_sc_halo_step_radius",
            weapon.boostLevel,
            maxLevel,
            string.format("%.0f", weapon.radius))

    elseif source == "chain" then
        thirdLine = get_text("render_sc_chain_level_radius",
            weapon.boostLevel,
            maxLevel,
            string.format("%.0f", weapon.radius))
    end

    -- PAIRED WEAPON DISPLAY

    if blueprint.name == paired.GENERIC_SECONDARY_BLUEPRINT
        or paired.groups[blueprint.name] then

        local ship = Hyperspace.ships(weapon.iShipId)
        local slot = paired.get_weapon_slot(weapon)

        if weapon.iShipId == 0 and ship and slot ~= nil then
            local pairData = paired.build_valid_pair_slots(ship)[slot]

            if pairData then
                if pairData.primarySlot == slot then
                    thirdLine = get_text("render_sc_paired_primary")
                else
                    thirdLine = get_text("render_sc_paired_secondary")
                end
            end
        end
    end

    return Defines.Chain.CONTINUE, firstLine, secondLine, thirdLine
end)