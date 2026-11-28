
--[[
DESCRIPTION: Shows the weapon and drone lists before and after Cudgel runs.
        - Displays the current enemy ship's equipped drone blueprints and drone system power.
        - Checks eligible drones after generation for all four equipment flag values.
        - Keeps the last result visible on screen.
DEPENDENCIES: Hyperspace, load before sc_cudgel.lua
]]

local message = "[SC Weapon Swap] Waiting for ship generation"
local droneSwapMessage = "[SC Drone Swap] Waiting for ship generation"
local droneMessage = "[SC Drones] Waiting for enemy ship"
local dronePowerMessage = "[SC Drone Power] Waiting for enemy ship"
local eligibleMessage = "[SC Drone Eligible] Waiting for ship generation"
local originalList = nil
local originalDrones = nil

script.on_internal_event(Defines.InternalEvents.GENERATOR_CREATE_SHIP, function(name, sector, event, blueprint, ship)
    originalList = blueprint and blueprint.loadWeapons or "(nil)"
    originalDrones = blueprint and blueprint.loadDrones or "(nil)"
    message = "[SC Weapon Swap] " .. tostring(name) .. ": " .. tostring(originalList) .. " -> (waiting for POST)"
    droneSwapMessage = "[SC Drone Swap] " .. tostring(originalDrones) .. " -> (waiting for POST)"

    return Defines.Chain.CONTINUE, sector, event, blueprint, ship
end)

script.on_internal_event(Defines.InternalEvents.GENERATOR_CREATE_SHIP_POST, function(name, sector, event, blueprint, ship)
    local finalList = blueprint and blueprint.loadWeapons or "(nil)"
    local finalDrones = blueprint and blueprint.loadDrones or "(nil)"
    message = "[SC Weapon Swap] " .. tostring(name) .. ": " .. tostring(originalList) .. " -> " .. tostring(finalList)
    droneSwapMessage = "[SC Drone Swap] " .. tostring(originalDrones) .. " -> " .. tostring(finalDrones)

    if blueprint and ship then
        local counts = {}
        for flags = 0, 3 do
            local ok, candidates = pcall(Hyperspace.ShipGenerator.GetPossibleDroneList, ship, finalDrones, 0, flags, false)
            counts[#counts + 1] = ok and tostring(candidates:size()) or "ERR"
        end
        eligibleMessage = "[SC Drone Eligible] flags 0/1/2/3: " .. table.concat(counts, " / ")
    else
        eligibleMessage = "[SC Drone Eligible] No generated ship"
    end

    return Defines.Chain.CONTINUE
end)

script.on_render_event(Defines.RenderEvents.MOUSE_CONTROL, function()
    local enemy = Hyperspace.ships.enemy
    if enemy then
        dronePowerMessage = "[SC Drone Power] " .. (enemy:HasSystem(4) and tostring(enemy:GetSystemPowerMax(4)) or "(no system)")

        local drones = enemy:GetDroneList()
        local droneNames = {}

        for i = 0, drones:size() - 1 do
            local drone = drones[i]
            if drone and drone.blueprint then
                droneNames[#droneNames + 1] = drone.blueprint.name
            end
        end

        droneMessage = "[SC Drones] " .. (#droneNames > 0 and table.concat(droneNames, ", ") or "(none)")
    end

    local x, y = 16, 32
    local width = math.max(Graphics.freetype.easy_measureWidth(13, message), Graphics.freetype.easy_measureWidth(13, droneSwapMessage), Graphics.freetype.easy_measureWidth(13, dronePowerMessage), Graphics.freetype.easy_measureWidth(13, droneMessage), Graphics.freetype.easy_measureWidth(13, eligibleMessage))
    local oldColor = Graphics.CSurface.GL_GetColor()

    Graphics.CSurface.GL_DrawRect(x - 6, y - 17, width + 12, 106, Graphics.GL_Color(0, 0, 0, 0.85))
    Graphics.CSurface.GL_SetColor(Graphics.GL_Color(1, 1, 1, 1))
    Graphics.freetype.easy_print(13, x, y, message)
    Graphics.freetype.easy_print(13, x, y + 20, droneSwapMessage)
    Graphics.freetype.easy_print(13, x, y + 40, dronePowerMessage)
    Graphics.freetype.easy_print(13, x, y + 60, droneMessage)
    Graphics.freetype.easy_print(13, x, y + 80, eligibleMessage)
    Graphics.CSurface.GL_SetColor(oldColor)

    return Defines.Chain.CONTINUE
end, function() end)
