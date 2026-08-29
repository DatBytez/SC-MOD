--[[
DESCRIPTION: Shared state for the immediate-hidden Terran Boarding Pod transport.
        - Keeps the actual CrewMember object; no snapshot/recreate path.
        - Hides arbitrary crew by temporarily replacing every live animation
          texture strip with a transparent texture.
        - While hidden, the passenger is rooted, non-combatant, non-targetable,
          AI-disabled, silenced, and protected from damage.
        - Once native teleport-out has begun, hidden passengers can be temporarily
          mind controlled so the destination ship's AI treats them as allied.
        - The crew's species, room/slot ownership data, health, skills, powers,
          appearance choices, and userdata are not recreated.
DEPENDENCIES: Multiverse userdata_table
]]

local userdata_table = mods.multiverse.userdata_table

mods.sc_drone_pod = mods.sc_drone_pod or {}
local pod = mods.sc_drone_pod

local POD_USERDATA = "mods.sc.dronePod"
local BLANK_TEXTURE_PATH = "people/sc_pod_hidden.png"

pod.nextTransportId = pod.nextTransportId or 0
pod.activeTransports = pod.activeTransports or {}
pod.returnableBoarders = pod.returnableBoarders or {}
pod.debugLines = pod.debugLines or {}
pod.blankCrewTexture =
    pod.blankCrewTexture
    or Hyperspace.Resources:GetImageId(BLANK_TEXTURE_PATH)

function pod.debug_line(text)
    pod.debugLines[#pod.debugLines + 1] = tostring(text)

    while #pod.debugLines > 22 do
        table.remove(pod.debugLines, 1)
    end
end

local function slot_text(crew)
    local result = "?"

    pcall(function()
        result =
            tostring(crew.currentSlot.roomId)
            .. ":"
            .. tostring(crew.currentSlot.slotId)
    end)

    return result
end

function pod.describe_crew(prefix, crew)
    if not crew then
        pod.debug_line(prefix .. " crew=nil")
        return
    end

    local data = userdata_table(crew, POD_USERDATA)
    local customTele =
        crew.extend
        and crew.extend.customTele
        or nil

    pod.debug_line(
        prefix
        .. " cur=" .. tostring(crew.currentShipId)
        .. " room=" .. tostring(crew.iRoomId)
        .. " slot=" .. slot_text(crew)
        .. " hidden=" .. tostring(data.podHidden == true)
        .. " mc=" .. tostring(crew.bMindControlled == true)
        .. " tele="
        .. tostring(customTele and customTele.shipId or "nil")
        .. "/"
        .. tostring(customTele and customTele.teleporting or "nil")
    )
end

local function save_visual_state(crew, data)
    if not crew
        or not crew.crewAnim
        or data.visualSaved then
        return
    end

    data.savedBaseStrip = crew.crewAnim.baseStrip
    data.savedColorStrip = crew.crewAnim.colorStrip
    data.savedLayerStrips = {}

    if crew.crewAnim.layerStrips then
        for i = 0, crew.crewAnim.layerStrips:size() - 1 do
            data.savedLayerStrips[#data.savedLayerStrips + 1] =
                crew.crewAnim.layerStrips[i]
        end
    end

    data.visualSaved = true
end

local function set_blank_layer_strips(crew, data)
    if not crew
        or not crew.crewAnim
        or not crew.crewAnim.layerStrips then
        return
    end

    local count =
        data.savedLayerStrips
        and #data.savedLayerStrips
        or crew.crewAnim.layerStrips:size()

    crew.crewAnim.layerStrips:clear()

    for _ = 1, count do
        crew.crewAnim.layerStrips:push_back(
            pod.blankCrewTexture
        )
    end
end

function pod.apply_hidden_visual(crew)
    if not crew
        or not crew.crewAnim
        or not pod.blankCrewTexture then
        return false
    end

    local data = userdata_table(crew, POD_USERDATA)

    save_visual_state(crew, data)

    crew.crewAnim.baseStrip =
        pod.blankCrewTexture

    crew.crewAnim.colorStrip =
        pod.blankCrewTexture

    set_blank_layer_strips(crew, data)

    return true
end

function pod.restore_visual(crew)
    if not crew
        or not crew.crewAnim then
        return
    end

    local data = userdata_table(crew, POD_USERDATA)

    if not data.visualSaved then
        return
    end

    crew.crewAnim.baseStrip =
        data.savedBaseStrip

    crew.crewAnim.colorStrip =
        data.savedColorStrip

    if crew.crewAnim.layerStrips then
        crew.crewAnim.layerStrips:clear()

        for _, texture in ipairs(
            data.savedLayerStrips or {}
        ) do
            crew.crewAnim.layerStrips:push_back(
                texture
            )
        end
    end

    data.savedBaseStrip = nil
    data.savedColorStrip = nil
    data.savedLayerStrips = nil
    data.visualSaved = false
end

local function hide_mind_control_icon(crew, data)
    if not crew
        or not crew.mindControlled
        or not pod.blankCrewTexture then
        return
    end

    if not data.mindControlIconSaved then
        data.savedMindControlAnimationStrip =
            crew.mindControlled.animationStrip

        data.mindControlIconSaved = true
    end

    crew.mindControlled.animationStrip =
        pod.blankCrewTexture
end

local function restore_mind_control_icon(crew, data)
    if not crew
        or not crew.mindControlled
        or not data.mindControlIconSaved then
        return
    end

    crew.mindControlled.animationStrip =
        data.savedMindControlAnimationStrip

    data.savedMindControlAnimationStrip = nil
    data.mindControlIconSaved = false
end

function pod.set_hidden_mind_control(crew, enabled)
    if not crew then
        return
    end

    local data =
        userdata_table(
            crew,
            POD_USERDATA
        )

    if enabled then
        if not data.podMindControlSaved then
            data.originalMindControlled =
                crew.bMindControlled == true

            data.podMindControlSaved = true
        end

        crew.bMindControlled = true
        data.podMindControlled = true

        -- The mind-control status icon is a separate CrewMember Animation
        -- rather than part of crew.crewAnim. Blank that animation's texture
        -- while the hidden passenger is temporarily mind controlled.
        hide_mind_control_icon(
            crew,
            data
        )

    else
        restore_mind_control_icon(
            crew,
            data
        )

        if data.podMindControlSaved then
            crew.bMindControlled =
                data.originalMindControlled == true
        end

        data.originalMindControlled = nil
        data.podMindControlSaved = false
        data.podMindControlled = false
    end
end

function pod.set_hidden(crew, hidden, transportId)
    if not crew then
        return
    end

    local data = userdata_table(crew, POD_USERDATA)

    data.podHidden = hidden == true

    if hidden then
        data.transportId = transportId
        pod.apply_hidden_visual(crew)
    else
        pod.set_hidden_mind_control(
            crew,
            false
        )

        pod.restore_visual(crew)
        data.transportId = nil
    end
end

function pod.create_transport_payload(
    crew,
    projectile,
    sourceShipId,
    sourceRoomId,
    targetShipId,
    targetRoomId,
    targetPosition
)
    pod.nextTransportId =
        pod.nextTransportId + 1

    local payload = {
        transportId = pod.nextTransportId,
        crew = crew,
        projectile = projectile,

        sourceShipId = sourceShipId,
        sourceRoomId = sourceRoomId,

        targetShipId = targetShipId,
        targetRoomId = targetRoomId,
        targetPosition = targetPosition,

        state = "outbound",
        impact = false,
        actualImpactRoomId = nil,
        cancelRequested = false,
        outboundLimboLogged = false
    }

    pod.activeTransports[payload.transportId] =
        payload

    return payload
end

function pod.ship_contains_reference(shipId, crew)
    local shipManager =
        Hyperspace.Global.GetInstance()
            :GetShipManager(shipId)

    if not shipManager
        or not shipManager.vCrewList
        or not crew then
        return false
    end

    for i = 0, shipManager.vCrewList:size() - 1 do
        if shipManager.vCrewList[i] == crew then
            return true
        end
    end

    return false
end

function pod.returned_vector_contains(returned, crew)
    if not returned or not crew then
        return false
    end

    for i = 0, returned:size() - 1 do
        if returned[i] == crew then
            return true
        end
    end

    return false
end

-- Keep the visual blank even if another crew animation update rebuilds its
-- texture strips while the passenger is waiting inside the pod.
script.on_render_event(
    Defines.RenderEvents.CREW_MEMBER_HEALTH,

    function(crew)
        if not crew then
            return
        end

        local data = userdata_table(crew, POD_USERDATA)

        if data.podHidden then
            pod.apply_hidden_visual(crew)

            if data.podMindControlled then
                hide_mind_control_icon(
                    crew,
                    data
                )
            end
        elseif data.visualSaved then
            pod.restore_visual(crew)
        end
    end,

    function()
    end
)

-- A hidden passenger is logically inside the boarding pod rather than actively
-- occupying either ship. Keep the actual CrewMember registered on the target
-- ship, but disable gameplay interactions until its missile arrives.
script.on_internal_event(
    Defines.InternalEvents.CALCULATE_STAT_POST,
    function(crew, stat, def, amount, value)
        if not crew then
            return Defines.Chain.CONTINUE,
                amount,
                value
        end

        local data = userdata_table(crew, POD_USERDATA)

        if not data.podHidden then
            return Defines.Chain.CONTINUE,
                amount,
                value
        end

        if stat == Hyperspace.CrewStat.CAN_MOVE
            or stat == Hyperspace.CrewStat.CAN_FIGHT
            or stat == Hyperspace.CrewStat.CAN_REPAIR
            or stat == Hyperspace.CrewStat.CAN_SABOTAGE
            or stat == Hyperspace.CrewStat.CAN_MAN
            or stat == Hyperspace.CrewStat.VALID_TARGET
            or stat == Hyperspace.CrewStat.CAN_SUFFOCATE
            or stat == Hyperspace.CrewStat.CAN_BURN then

            value = false

        elseif stat == Hyperspace.CrewStat.NO_AI
            or stat == Hyperspace.CrewStat.SILENCED then

            value = true

        elseif stat == Hyperspace.CrewStat.ALL_DAMAGE_TAKEN_MULTIPLIER
            or stat == Hyperspace.CrewStat.DAMAGE_ENEMIES_AMOUNT
            or stat == Hyperspace.CrewStat.HEAL_CREW_AMOUNT
            or stat == Hyperspace.CrewStat.BONUS_POWER
            or stat == Hyperspace.CrewStat.POWER_DRAIN then

            amount = 0
        end

        return Defines.Chain.CONTINUE,
            amount,
            value
    end
)
