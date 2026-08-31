Target = Target or {}

local holding, holdingThread, menuOpen = false, false, false
local currentCandidates = {}

-- Runtime-only resolver state. This cache never decides authority; it simply
-- avoids resolving the same world/registration combination more often than a
-- player can perceive it.
local entityRegistrationCache = { key = nil, revision = nil, registrations = {} }
local canInteractCache = {}
local emptyRegistrations = {}
local targetHudKey
local syncTargetHud
local diagnostics = { scans = 0, raycasts = 0, options = 0, canInteract = 0, elapsed = 0, lastReport = 0 }

local function distanceSq(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

local function resetRuntimeState()
    currentCandidates, Target.hovering = {}, nil
    entityRegistrationCache.key, entityRegistrationCache.revision, entityRegistrationCache.registrations = nil, nil, {}
    canInteractCache = {}
    if syncTargetHud then syncTargetHud(false) end
end

local function classifyEntity(entity)
    -- GetEntityType returns 0 for a handle that no longer resolves. This is a
    -- stronger preflight than treating "not a ped and not a vehicle" as an
    -- object: that old fallback also classified invalid handles as objects,
    -- allowing them to reach GetEntityModel and fault in the native invoker.
    local ok, entityType = pcall(GetEntityType, entity)
    if not ok or entityType == 0 then return nil end
    if entityType == 1 then
        local playerOk, isPlayer = pcall(IsPedAPlayer, entity)
        if not playerOk then return nil end
        return isPlayer and 'player' or 'ped'
    end
    if entityType == 2 then return 'vehicle' end
    if entityType == 3 then return 'object' end
    return nil
end

local function cachedBoneCoords(entity, boneName, cache)
    local entityBones = cache[entity]
    if not entityBones then entityBones = {}; cache[entity] = entityBones end
    local cached = entityBones[boneName]
    if cached ~= nil then return cached or nil end

    local indexOk, boneIndex = pcall(GetEntityBoneIndexByName, entity, boneName)
    if not indexOk then entityBones[boneName] = false; return nil end
    if boneIndex == -1 then entityBones[boneName] = false; return nil end
    local coordsOk, coords = pcall(GetWorldPositionOfEntityBone, entity, boneIndex)
    if not coordsOk then entityBones[boneName] = false; return nil end
    entityBones[boneName] = coords
    return coords
end

local function boneMatches(entity, boneNames, anchorCoords, toleranceSq, boneCache)
    if not boneNames then return true end
    if not (entity and anchorCoords) then return false end
    for _, boneName in ipairs(boneNames) do
        local boneCoords = cachedBoneCoords(entity, boneName, boneCache)
        if boneCoords and distanceSq(boneCoords, anchorCoords) <= toleranceSq then return true end
    end
    return false
end

local function addRegistrations(out, seen, set)
    if not set then return end
    for id in pairs(set) do
        if not seen[id] then
            local registration = Target.registrations[id]
            if registration then seen[id] = true; out[#out + 1] = registration end
        end
    end
end

-- The pcall around GetEntityModel below stops the LUA error, but CFX's native
-- invoker prints `script error in native ...` from inside the invoke layer
-- BEFORE the error surfaces to pcall -- so a persistently-faulting handle
-- aimed at every tick (50ms) still spams the console 20x/sec. Remember the
-- failing handle for a short window and skip re-invoking the native for it.
-- Failures ONLY: caching successful models across ticks would risk returning
-- a stale model when the engine recycles a freed handle for a new entity;
-- a failure entry's worst case is one extra empty-registration second.
local FAILED_MODEL_TTL_MS = 1000
local failedModelEntity, failedModelUntil = nil, 0

-- Registration mutations increment Target.registrationRevision in state.lua,
-- making additions/removals visible without waiting for the player to aim away.
local function entityRegistrations(entity)
    local existsOk, exists = pcall(DoesEntityExist, entity)
    if not existsOk or not exists then return emptyRegistrations end

    local entityType = classifyEntity(entity)
    if not entityType then return emptyRegistrations end

    if entity == failedModelEntity and GetGameTimer() < failedModelUntil then
        return emptyRegistrations
    end

    -- A raycast handle can go stale when an entity despawns in the same frame.
    -- GetEntityModel is one of the natives that can throw on that race, so it
    -- must be guarded even after DoesEntityExist succeeds.
    local modelOk, model = pcall(GetEntityModel, entity)
    if not modelOk then
        failedModelEntity, failedModelUntil = entity, GetGameTimer() + FAILED_MODEL_TTL_MS
        return emptyRegistrations
    end
    local key, revision = ('%s:%s:%s'):format(entity, model, entityType), Target.registrationRevision or 0
    if entityRegistrationCache.key == key and entityRegistrationCache.revision == revision then
        return entityRegistrationCache.registrations
    end

    local registrations, seen = {}, {}
    addRegistrations(registrations, seen, Target.byEntity[entity])
    addRegistrations(registrations, seen, Target.byModel[model])
    addRegistrations(registrations, seen, Target.byGlobalType[entityType])
    if next(Target.byGlobalBone) then addRegistrations(registrations, seen, Target.byGlobalBone) end
    entityRegistrationCache.key, entityRegistrationCache.revision, entityRegistrationCache.registrations = key, revision, registrations
    return registrations
end

-- Zone candidates are matched against where the player is AIMING (the
-- raycast collision point), not where the player's own ped is standing --
-- deliberately not QB.zones.getInside(), which answers "is the ped inside
-- this zone" and would require walking into a zone to target it. Every
-- zone-kind registration's own qblib zoneHandle already exposes a `contains`
-- test (client/state.lua tracks these in Target.byZone), so this is a plain
-- linear scan -- cheap enough to run every resolve given qbtarget's expected
-- zone counts, unlike the position-tracking machinery getInside relies on.
local function zoneRegistrationsAt(point)
    local registrations = {}
    for id in pairs(Target.byZone) do
        local registration = Target.registrations[id]
        if registration and registration.zoneHandle.contains(point) then
            registrations[#registrations + 1] = registration
        end
    end
    return registrations
end

local function optionAllowed(registration, optionIndex, option, entity, distance, now)
    if not option.canInteract then return true end
    local key = ('%s:%s:%s:%s'):format(registration.id, optionIndex, entity or 0, math.floor(distance * 10))
    local cached = canInteractCache[key]
    if cached and now < cached.expiresAt then return cached.allowed end

    diagnostics.canInteract = diagnostics.canInteract + 1
    local ok, result = pcall(option.canInteract, entity, distance, option.data)
    local allowed = ok and result ~= false
    if not ok then print(("[qbtarget] canInteract for option '%s' errored: %s"):format(option.label, tostring(result))) end
    canInteractCache[key] = { allowed = allowed, expiresAt = now + Config.target.canInteractCacheMs }
    return allowed
end

local function appendCandidates(candidates, nearestIndex, registration, entity, anchorCoords, pedCoords, now, boneCache)
    local registrationBones = registration.kind == 'globalBone' and Target.byGlobalBone[registration.id] or nil
    local distSq, toleranceSq = distanceSq(pedCoords, anchorCoords), Config.target.boneTolerance * Config.target.boneTolerance

    for index, option in ipairs(registration.options) do
        diagnostics.options = diagnostics.options + 1
        local maxDistance = option.distance or registration.distance or Config.target.defaultOptionDistance
        if distSq <= maxDistance * maxDistance and boneMatches(entity, option.bones or registrationBones, anchorCoords, toleranceSq, boneCache) then
            -- canInteract receives distance for compatibility; pay the sqrt only
            -- after all cheap rejections have passed.
            local distance = math.sqrt(distSq)
            if optionAllowed(registration, index, option, entity, distance, now) then
                candidates[#candidates + 1] = { registration = registration, option = option, entity = entity, anchorCoords = anchorCoords, distance = distance, distanceSq = distSq }
                local candidateIndex = #candidates
                if not nearestIndex or distSq < candidates[nearestIndex].distanceSq then nearestIndex = candidateIndex end
            end
        end
    end
    return nearestIndex
end

local function resolveCandidates(hit, entity, hitCoords, now)
    diagnostics.scans = diagnostics.scans + 1
    local pedCoords, candidates, nearestIndex, boneCache = GetEntityCoords(PlayerPedId()), {}, nil, {}
    if hit and entity and entity ~= 0 then
        for _, registration in ipairs(entityRegistrations(entity)) do
            nearestIndex = appendCandidates(candidates, nearestIndex, registration, entity, hitCoords, pedCoords, now, boneCache)
        end
    end
    if hit and hitCoords then
        for _, registration in ipairs(zoneRegistrationsAt(hitCoords)) do
            nearestIndex = appendCandidates(candidates, nearestIndex, registration, nil, hitCoords, pedCoords, now, boneCache)
        end
    end
    -- Keep the closest candidate first without sorting every option.
    if nearestIndex and nearestIndex ~= 1 then candidates[1], candidates[nearestIndex] = candidates[nearestIndex], candidates[1] end
    return candidates
end

-- Mirrors ox_target's two-pass idea: the broad mask sees normal world
-- geometry, then an entity-focused mask gets a chance when that first cast
-- reports no entity. The closer hit always wins, so this never targets through
-- a nearer obstruction.
local function raycastTarget()
    local hit, hitCoords, entity = QB.raycast.fromCamera(Config.target.maxDistance, 511)
    if entity and entity ~= 0 then return hit, hitCoords, entity end

    local entityHit, entityCoords, entityHandle = QB.raycast.fromCamera(Config.target.maxDistance, 26)
    if not (entityHit and entityHandle and entityHandle ~= 0) then return hit, hitCoords, entity end
    if not hit or not hitCoords then return entityHit, entityCoords, entityHandle end

    local pedCoords = GetEntityCoords(PlayerPedId())
    if not hitCoords or distanceSq(pedCoords, entityCoords) <= distanceSq(pedCoords, hitCoords) then
        return entityHit, entityCoords, entityHandle
    end

    return hit, hitCoords, entity
end

local function updateHoveringState(candidates)
    local top = candidates[1]
    if not top then Target.hovering = nil; return end
    local previous = Target.hovering
    if previous and previous.id == top.registration.id and previous.entity == top.entity and previous.option == top.option then return end
    Target.hovering = { kind = top.registration.kind, id = top.registration.id, entity = top.entity, zoneId = top.registration.kind == 'zone' and top.registration.id or nil, option = top.option, optionCount = #candidates }
end

-- qblib owns the transparent NUI root. Targeting remains game-input driven;
-- this is only a compact visual snapshot, never a focus-taking UI.
syncTargetHud = function(active, candidates)
    local top = candidates and candidates[1]
    local label = top and (#candidates == 1 and top.option.label or ('%d options'):format(#candidates)) or nil
    local key = active and ('%s:%s:%s'):format(label or '', top and top.registration.id or '', top and top.entity or '') or 'hidden'
    if key == targetHudKey then return end

    targetHudKey = key
    QB.nui.send('qbtarget:target', active and {
        active = true,
        label = label,
        optionCount = candidates and #candidates or 0,
    } or { active = false })
end

local function reportDiagnostics(now)
    if not Config.target.diagnostics or now - diagnostics.lastReport < Config.target.diagnosticsInterval then return end
    local scans = math.max(diagnostics.scans, 1)
    print(('[qbtarget] %d scans, %d raycasts, %d options, %d canInteract calls, %.2fms average resolve')
        :format(diagnostics.scans, diagnostics.raycasts, diagnostics.options, diagnostics.canInteract, diagnostics.elapsed / scans))
    diagnostics = { scans = 0, raycasts = 0, options = 0, canInteract = 0, elapsed = 0, lastReport = now }
end

local function runOption(candidate)
    local ok, err = pcall(candidate.option.onSelect, candidate.entity, candidate.option.data)
    if not ok then print(("[qbtarget] onSelect for option '%s' errored: %s"):format(candidate.option.label, tostring(err))) end
end

---Resolves the candidates captured at Alt release. One option is immediate;
---multiple options deliberately use qblib's regular menu, which takes focus
---only after targeting has ended and supports both mouse and keyboard input.
local function selectCandidates(candidates)
    if #candidates == 0 then return end
    if #candidates == 1 then return runOption(candidates[1]) end

    menuOpen = true
    local items, byId = {}, {}
    for index, candidate in ipairs(candidates) do
        local id = tostring(index)
        items[index] = {
            id = id,
            label = candidate.option.label,
            icon = candidate.option.icon,
        }
        byId[id] = candidate
    end

    CreateThread(function()
        local result = QB.nui.openMenu(items, 'Select action')
        menuOpen = false
        if result and not result.cancelled then
            local selected = byId[result.selectedId]
            if selected then runOption(selected) end
        end
    end)
end

local function startTargeting()
    if holdingThread then return end
    holdingThread = true
    resetRuntimeState()
    syncTargetHud(true, currentCandidates)
    diagnostics.lastReport = GetGameTimer()

    CreateThread(function()
        while holding do
            local now = GetGameTimer()
            if not Target.enabled or menuOpen then
                resetRuntimeState()
                Wait(Config.target.tickIdle)
            else
                local startedAt = now
                diagnostics.raycasts = diagnostics.raycasts + 1
                local hit, hitCoords, entity = raycastTarget()
                currentCandidates = resolveCandidates(hit, entity, hitCoords, now)
                diagnostics.elapsed = diagnostics.elapsed + GetGameTimer() - startedAt
                updateHoveringState(currentCandidates)
                local hasCandidate = currentCandidates[1] ~= nil
                syncTargetHud(true, currentCandidates)
                reportDiagnostics(now)
                Wait(hasCandidate and Config.target.tickActive or Config.target.tickAcquire)
            end
        end
        resetRuntimeState()
        holdingThread = false
    end)
end

QB.keybind.add({
    name = Config.target.keybind.command,
    description = Config.target.keybind.label,
    defaultMapper = 'keyboard',
    defaultKey = Config.target.keybind.defaultKey,
    onPressed = function()
        if not Config.target.toggle then
            holding = true
            startTargeting()
            return
        end

        holding = not holding
        if holding then
            startTargeting()
        else
            local candidates = currentCandidates
            resetRuntimeState()
            selectCandidates(candidates)
        end
    end,
    onReleased = function()
        if Config.target.toggle then return end
        holding = false
        local candidates = currentCandidates
        resetRuntimeState()
        selectCandidates(candidates)
    end,
})

-- Config.target.debug/zoneDebugEnabled (client/state.lua) only ever get read
-- once, at zone registration time -- flipping the config afterward does
-- nothing to zones already created. This command is a runtime override layered
-- on top via qblib's own QB.zones.setDebug(nil, ...) (added specifically for
-- this), not a replacement for the config default: it lets a developer outline
-- every already-registered target zone live, without editing config.lua and
-- restarting the resource. `[on|off]`, or no argument to toggle.
RegisterCommand('qbtarget_debug', function(_, args)
    local arg = args[1] and tostring(args[1]):lower() or nil
    local enabled

    if arg == 'on' then
        enabled = true
    elseif arg == 'off' then
        enabled = false
    elseif arg == nil then
        enabled = not Target.debugEnabled
    else
        print(("[qbtarget] qbtarget_debug: unrecognised argument '%s' -- use 'on', 'off', or no argument to toggle."):format(arg))
        return
    end

    Target.debugEnabled = enabled
    QB.zones.setDebug(nil, enabled)
    print(("[qbtarget] target zone debug drawing %s."):format(enabled and 'enabled' or 'disabled'))
end, false)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        holding, menuOpen = false, false
        resetRuntimeState()
    end
end)

-- Deliberately absent in production. The standalone smoke suite sets this
-- before loading the file so it can exercise resolver behaviour without a
-- running FiveM client or exporting private implementation details.
if Config.target.testMode then
    Target._testRuntime = {
        entityRegistrations = entityRegistrations,
        optionAllowed = optionAllowed,
        zoneRegistrationsAt = zoneRegistrationsAt,
        raycastTarget = raycastTarget,
        resetRuntimeState = resetRuntimeState,
        resolveCandidates = resolveCandidates,
        candidateCount = function() return #currentCandidates end,
    }
end

if Config.target.demo then
    Target.addGlobalType('ped', {{ label = 'Inspect ped (demo)', icon = 'eye', onSelect = function(entity)
        print(('[qbtarget] demo: inspected ped %s (model %s)'):format(tostring(entity), tostring(GetEntityModel(entity))))
    end }}, 3.0)
    Target.addGlobalType('vehicle', {{ label = 'Inspect vehicle (demo)', icon = 'car', onSelect = function(entity)
        print(('[qbtarget] demo: inspected vehicle %s'):format(tostring(entity)))
    end }}, 3.0)
end
