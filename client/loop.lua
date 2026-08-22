Target = Target or {}

local holding = false
local currentCandidates = {}

local function distanceBetween(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---@param entity number
---@return "ped"|"vehicle"|"object"|"player"
local function classifyEntity(entity)
    if IsEntityAPed(entity) then
        return IsPedAPlayer(entity) and "player" or "ped"
    end
    if IsEntityAVehicle(entity) then return "vehicle" end
    return "object"
end

---`nil` bones (no filter set) always matches. A bone-scoped option needs a
---real aim point to test against, so it never matches a zone-only candidate
---(entity/anchorCoords are nil there).
---@param entity number?
---@param boneNames string[]?
---@param anchorCoords table?
---@param tolerance number
---@return boolean
local function boneMatches(entity, boneNames, anchorCoords, tolerance)
    if not boneNames then return true end
    if not (entity and anchorCoords) then return false end

    for _, boneName in ipairs(boneNames) do
        local boneIndex = GetEntityBoneIndexByName(entity, boneName)

        if boneIndex ~= -1 then
            local boneCoords = GetWorldPositionOfEntityBone(entity, boneIndex)
            if distanceBetween(boneCoords, anchorCoords) <= tolerance then return true end
        end
    end

    return false
end

---Filters `registration`'s options against one already-matched candidate
---(an aimed-at entity, or the anchor point of a zone the player is standing
---in) and appends whichever survive to `candidates`. Shared by every
---resolution path in resolveCandidates below.
---@param candidates table[]
---@param registration table
---@param entity number?
---@param anchorCoords table
---@param pedCoords table
local function pushOptionCandidates(candidates, registration, entity, anchorCoords, pedCoords)
    local registrationBones = registration.kind == "globalBone" and Target.byGlobalBone[registration.id] or nil
    local distance = distanceBetween(pedCoords, anchorCoords)

    for _, option in ipairs(registration.options) do
        local bones = option.bones or registrationBones

        if boneMatches(entity, bones, anchorCoords, Config.target.boneTolerance) then
            local maxDistance = option.distance or registration.distance or Config.target.defaultOptionDistance

            if distance <= maxDistance then
                local allowed = true

                if option.canInteract then
                    local ok, result = pcall(option.canInteract, entity, distance, option.data)
                    if not ok then
                        print(("[qbtarget] canInteract for option '%s' errored: %s"):format(option.label, tostring(result)))
                        allowed = false
                    else
                        allowed = result ~= false
                    end
                end

                if allowed then
                    candidates[#candidates + 1] = {
                        registration = registration,
                        option = option,
                        entity = entity,
                        anchorCoords = anchorCoords,
                        distance = distance,
                    }
                end
            end
        end
    end
end

---Resolves every option currently available: from the raycast hit (entity/
---model/global-type/global-bone registrations) and, independently of aim,
---from every qbtarget-owned zone the player is standing in -- matching both
---real qb-target and ox_target's behavior of not requiring an aim for
---zone-based targets.
---@param hit boolean
---@param entity number?
---@param hitCoords table?
---@return table[] candidates Sorted ascending by distance.
local function resolveCandidates(hit, entity, hitCoords)
    local candidates = {}
    local pedCoords = GetEntityCoords(PlayerPedId())

    if hit and entity and entity ~= 0 then
        local seen = {}

        local function pushRegistrations(set)
            if not set then return end
            for regId in pairs(set) do
                if not seen[regId] then
                    seen[regId] = true
                    local registration = Target.registrations[regId]
                    if registration then
                        pushOptionCandidates(candidates, registration, entity, hitCoords, pedCoords)
                    end
                end
            end
        end

        pushRegistrations(Target.byEntity[entity])
        pushRegistrations(Target.byModel[GetEntityModel(entity)])
        pushRegistrations(Target.byGlobalType[classifyEntity(entity)])

        for regId in pairs(Target.byGlobalBone) do
            if not seen[regId] then
                seen[regId] = true
                local registration = Target.registrations[regId]
                if registration then
                    pushOptionCandidates(candidates, registration, entity, hitCoords, pedCoords)
                end
            end
        end
    end

    for _, zoneHandle in ipairs(QB.zones.getInside(GetCurrentResourceName())) do
        local qbtargetId = zoneHandle.data and zoneHandle.data.qbtargetId
        local registration = qbtargetId and Target.registrations[qbtargetId]

        if registration and registration.kind == "zone" then
            pushOptionCandidates(candidates, registration, nil, registration.promptCoords, pedCoords)
        end
    end

    table.sort(candidates, function(a, b) return a.distance < b.distance end)

    return candidates
end

local function updateHoveringState(candidates)
    if #candidates == 0 then
        Target.hovering = nil
        return
    end

    local top = candidates[1]
    Target.hovering = {
        kind = top.registration.kind,
        id = top.registration.id,
        entity = top.entity,
        zoneId = top.registration.kind == "zone" and top.registration.id or nil,
        optionCount = #candidates,
    }
end

local function drawPrompt(candidates)
    if #candidates == 0 then return end

    local label = #candidates == 1 and candidates[1].option.label or ("%d options"):format(#candidates)
    QB.drawing.text3d(candidates[1].anchorCoords, label)
end

local function runOption(candidate)
    local ok, err = pcall(candidate.option.onSelect, candidate.entity, candidate.option.data)
    if not ok then
        print(("[qbtarget] onSelect for option '%s' errored: %s"):format(candidate.option.label, tostring(err)))
    end
end

CreateThread(function()
    while true do
        if Target.enabled and holding then
            local hit, hitCoords, entity = QB.raycast.fromCamera(Config.target.maxDistance)

            currentCandidates = resolveCandidates(hit, entity, hitCoords)
            updateHoveringState(currentCandidates)
            drawPrompt(currentCandidates)

            Wait(Config.target.tickWhileHeld)
        else
            if #currentCandidates > 0 then
                currentCandidates = {}
                Target.hovering = nil
            end

            Wait(Config.target.tickIdle)
        end
    end
end)

RegisterCommand('+' .. Config.target.keybind.command, function() holding = true end, false)
RegisterCommand('-' .. Config.target.keybind.command, function() holding = false end, false)
RegisterKeyMapping('+' .. Config.target.keybind.command, Config.target.keybind.label, 'keyboard', Config.target.keybind.defaultKey)

RegisterCommand(Config.target.selectKeybind.command, function()
    if not (Target.enabled and holding) or #currentCandidates == 0 then return end

    if #currentCandidates == 1 then
        runOption(currentCandidates[1])
        return
    end

    -- QB.nui.openContextMenu auto-awaits internally for a cross-resource
    -- caller (qbtarget calling into qblib), but that auto-await still needs a
    -- running coroutine to suspend into -- same reason every QB.nui.* call
    -- site in qblib-playground wraps itself in CreateThread.
    CreateThread(function()
        local menuCandidates = currentCandidates
        local items = {}

        for i, candidate in ipairs(menuCandidates) do
            items[i] = { id = tostring(i), label = candidate.option.label, icon = candidate.option.icon }
        end

        local result = QB.nui.openContextMenu(items)
        if not result or result.cancelled then return end

        local selected = menuCandidates[tonumber(result.selectedId)]
        if selected then runOption(selected) end
    end)
end, false)
RegisterKeyMapping(Config.target.selectKeybind.command, Config.target.selectKeybind.label, 'keyboard', Config.target.selectKeybind.defaultKey)
