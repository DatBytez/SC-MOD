--[[
DESCRIPTION: Implements reusable resource costs for crew abilities.
        - Powers with <sc-cost resource="..." amount="#"/> tags require the configured resources.
        - Multiple costs may be assigned to the same power.
        - Repeated costs for the same resource are combined when checking affordability.
        - Resources are reserved when the power activates.
        - Other ability scripts may commit or refund the reserved costs.
        - Supported resources are missiles, drones, fuel, and scrap.
TAG: <sc-cost resource="missiles" amount="#"/>
DEPENDENCIES: sc_tag.lua
]]

mods.sc.powerCosts = mods.sc.powerCosts or {}
mods.sc.cost = mods.sc.cost or {}

local powerCosts = mods.sc.powerCosts
local cost = mods.sc.cost
local reservations = {}

local POWER_READY = 1
local POWER_NOT_READY_CHARGES = 22

local function parse_power_cost(tagNode)
    local costs = {}

    while tagNode do
        local resourceAttr = tagNode:first_attribute("resource")
        local amountAttr = tagNode:first_attribute("amount")

        if resourceAttr and amountAttr then
            local amount = tonumber(amountAttr:value())

            if amount then
                table.insert(costs, {
                    resource = resourceAttr:value(),
                    amount = amount
                })
            end
        end

        tagNode = tagNode:next_sibling("sc-cost")
    end

    if #costs == 0 then return nil end

    return costs
end

mods.sc.tag.register(
    "power",
    "sc-cost",
    powerCosts,
    parse_power_cost
)

local function get_owner_ship(power)
    if not power.crew then return nil end

    if power.crew.iShipId == 0 then
        return Hyperspace.ships.player
    end

    return Hyperspace.ships.enemy
end

local function get_resource_count(ship, resourceName)
    if resourceName == "missiles" then
        return ship:GetMissileCount()
    end

    if resourceName == "drones" then
        return ship:GetDroneCount()
    end

    if resourceName == "fuel" then
        return ship.fuel_count
    end

    if resourceName == "scrap" then
        return ship.currentScrap
    end

    return nil
end

local function modify_resource_count(ship, resourceName, amount)
    if resourceName == "missiles" then
        ship:ModifyMissileCount(amount)
        return true
    end

    if resourceName == "drones" then
        ship:ModifyDroneCount(amount)
        return true
    end

    if resourceName == "fuel" then
        ship.fuel_count = ship.fuel_count + amount
        return true
    end

    if resourceName == "scrap" then
        ship:ModifyScrapCount(amount, false)
        return true
    end

    return false
end

local function get_total_costs(costData)
    local totals = {}

    for _, entry in ipairs(costData) do
        totals[entry.resource] =
            (totals[entry.resource] or 0) + entry.amount
    end

    return totals
end

function cost.can_pay(power)
    local costData = powerCosts[power.def.name]

    if not costData then
        return true
    end

    local ship = get_owner_ship(power)

    if not ship then
        return false
    end

    local totals = get_total_costs(costData)

    for resourceName, amount in pairs(totals) do
        local resourceCount = get_resource_count(
            ship,
            resourceName
        )

        if resourceCount == nil or resourceCount < amount then
            return false
        end
    end

    return true
end

function cost.reserve(power)
    local costData = powerCosts[power.def.name]

    if not costData then
        return true
    end

    if reservations[power] then
        return true
    end

    local ship = get_owner_ship(power)

    if not ship or not cost.can_pay(power) then
        return false
    end

    local totals = get_total_costs(costData)

    for resourceName, amount in pairs(totals) do
        if not modify_resource_count(
            ship,
            resourceName,
            -amount
        ) then
            return false
        end
    end

    reservations[power] = {
        ship = ship,
        costs = totals
    }

    return true
end

function cost.commit(power)
    reservations[power] = nil
end

function cost.refund(power)
    local reservation = reservations[power]

    if not reservation then return end

    for resourceName, amount in pairs(reservation.costs) do
        modify_resource_count(
            reservation.ship,
            resourceName,
            amount
        )
    end

    reservations[power] = nil
end

script.on_internal_event(Defines.InternalEvents.POWER_READY, function(power, powerState)
    if not powerCosts[power.def.name] then
        return Defines.Chain.CONTINUE, powerState
    end

    if powerState == POWER_READY and not cost.can_pay(power) then
        powerState = POWER_NOT_READY_CHARGES
    end

    return Defines.Chain.CONTINUE, powerState
end)

script.on_internal_event(Defines.InternalEvents.ACTIVATE_POWER, function(power)
    if not powerCosts[power.def.name] then
        return Defines.Chain.CONTINUE
    end

    if not cost.reserve(power) then
        power.powerCooldown.first = power.powerCooldown.second
        return Defines.Chain.PREEMPT
    end

    return Defines.Chain.CONTINUE
end)