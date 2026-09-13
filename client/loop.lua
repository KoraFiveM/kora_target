Target = Target or {}

local holding, holdingThread, menuOpen = false, false, false
local currentCandidates = {}
local currentRaycastEntity
local menuPed, menuPedWasFrozen

-- Runtime-only resolver state. This cache never decides authority; it simply
-- avoids resolving the same world/registration combination more often than a
-- player can perceive it.
local entityRegistrationCache = { entity = nil, model = nil, entityType = nil, revision = nil, registrations = {} }
local canInteractCache, canInteractCacheCount = {}, 0
local emptyRegistrations = {}
local syncTargetHud
local diagnostics = { scans = 0, skipped = 0, raycasts = 0, options = 0, canInteract = 0, elapsed = 0, lastReport = 0 }

-- The last snapshot syncTargetHud pushed to the NUI. See syncTargetHud below.
local hudActive, hudRegistrationId, hudEntity, hudOption, hudOptionCount = false, nil, nil, nil, 0

-- Reused scratch. resolveCandidates deliberately still allocates its own
-- `candidates` array per pass: the release handler captures that exact table
-- and hands it to an async menu, so it must not be written to again.
local zoneCandidateIds = {}
local zoneCandidates = {}
local boneCache = {}

local function distanceSq(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

local lastResolveAt, lastCamX, lastCamY, lastCamZ, lastCamPitch, lastCamYaw = 0, nil, nil, nil, nil, nil
local lastPedX, lastPedY, lastPedZ, lastResolveRevision

local function resetRuntimeState()
    currentCandidates, currentRaycastEntity, Target.hovering = {}, nil, nil
    Target.success = false
    entityRegistrationCache.entity, entityRegistrationCache.model = nil, nil
    entityRegistrationCache.entityType, entityRegistrationCache.revision = nil, nil
    entityRegistrationCache.registrations = {}
    canInteractCache, canInteractCacheCount = {}, 0
    lastResolveAt, lastResolveRevision = 0, nil
    lastCamX, lastCamY, lastCamZ, lastCamPitch, lastCamYaw = nil, nil, nil, nil, nil
    lastPedX, lastPedY, lastPedZ = nil, nil, nil
    if syncTargetHud then syncTargetHud(false) end
end

-- The candidate list is captured when Alt is released. It must remain valid
-- until the compact selector is dismissed, so do not let the player walk out
-- of a target zone and select an option from that stale snapshot.
local function setMenuPositionFrozen(frozen)
    if frozen then
        local ped = PlayerPedId()
        if not ped or ped == 0 then return end

        menuPed = ped
        menuPedWasFrozen = IsEntityPositionFrozen(ped)
        if not menuPedWasFrozen then FreezeEntityPosition(ped, true) end
        return
    end

    if menuPed and not menuPedWasFrozen then FreezeEntityPosition(menuPed, false) end
    menuPed, menuPedWasFrozen = nil, nil
end

local function closeTargetMenu()
    if menuOpen then QB.interact.close() end
    menuOpen = false
    setMenuPositionFrozen(false)
end

-- Internal compatibility hook for qb-target's DisableTarget(true). That
-- export cancels only the current targeting session; it does not change the
-- persistent AllowTargeting gate. Keeping this separate from setEnabled is
-- what lets the next key press start a fresh session, as upstream does.
function Target._cancelCurrentTargeting()
    holding = false
    closeTargetMenu()
    resetRuntimeState()
    Target.active = false
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
    -- Compared field by field instead of against a formatted "entity:model:type"
    -- key. The key was rebuilt on every tick of every hold purely to be thrown
    -- away on a cache hit; three equality tests answer the same question with
    -- no allocation.
    local revision = Target.registrationRevision or 0
    if entityRegistrationCache.entity == entity
        and entityRegistrationCache.model == model
        and entityRegistrationCache.entityType == entityType
        and entityRegistrationCache.revision == revision then
        return entityRegistrationCache.registrations
    end

    local registrations, seen = {}, {}
    addRegistrations(registrations, seen, Target.byEntity[entity])
    addRegistrations(registrations, seen, Target.byModel[model])
    addRegistrations(registrations, seen, Target.byGlobalType[entityType])
    if next(Target.byGlobalBone) then addRegistrations(registrations, seen, Target.byGlobalBone) end
    entityRegistrationCache.entity, entityRegistrationCache.model = entity, model
    entityRegistrationCache.entityType, entityRegistrationCache.revision = entityType, revision
    entityRegistrationCache.registrations = registrations
    return registrations
end

-- Zone candidates are matched against where the player is AIMING (the
-- raycast collision point), not where the player's own ped is standing --
-- deliberately not QB.zones.getInside(), which answers "is the ped inside
-- this zone" and would require walking into a zone to target it.
--
-- This used to be a plain linear scan over every zone-kind registration,
-- calling each one's `contains` predicate. That is the resolver's worst
-- scaling behaviour on a real server: a qb-target-compatible install
-- registers hundreds-to-thousands of zones, and this ran 20x/second for the
-- whole hold. Two exact filters now sit in front of it, neither of which can
-- change which zones match:
--
--  1. Every zone candidate anchors on the raycast hit itself, so the
--     ped->anchor distance appendCandidates tests is IDENTICAL for all of
--     them. One comparison against the largest interact distance any zone
--     option uses therefore rejects the whole pass -- aiming across a room at
--     something 8m away can never produce a 2.5m zone candidate.
--  2. Target.zonesNear (client/state.lua) is an AABB grid keyed on the aim
--     point, so only zones whose bounding box actually contains that point
--     reach their real `contains` predicate. Zones with an underivable extent
--     (the qb-target ComboZone/EntityZone bridges) stay in the scan.
---@param point table Raycast hit coordinates.
---@param pedCoords table? Player position; omit to skip filter 1.
local function zoneRegistrationsAt(point, pedCoords)
    if next(Target.byZone) == nil then return emptyRegistrations end

    if pedCoords then
        local reach = Target.maxZoneOptionDistance()
        if distanceSq(pedCoords, point) > reach * reach then return emptyRegistrations end
    end

    local ids = zoneCandidateIds
    for i = #ids, 1, -1 do ids[i] = nil end
    Target.zonesNear(point, ids)

    local registrations = zoneCandidates
    for i = #registrations, 1, -1 do registrations[i] = nil end

    for i = 1, #ids do
        local registration = Target.registrations[ids[i]]
        if registration and registration.zoneHandle.contains(point) then
            registrations[#registrations + 1] = registration
        end
    end

    return registrations
end

-- Entries are keyed partly on a distance bucket, so simply walking towards a
-- target mints a fresh key every tenth of a metre. Left unbounded the cache
-- grew for the entire hold -- pure garbage behind a lookup that can never hit
-- again. Sweep the expired entries once it gets large instead.
local CAN_INTERACT_CACHE_LIMIT = 256

local function pruneCanInteractCache(now)
    local remaining = 0
    for key, entry in pairs(canInteractCache) do
        if now >= entry.expiresAt then
            canInteractCache[key] = nil
        else
            remaining = remaining + 1
        end
    end
    canInteractCacheCount = remaining
end

local function optionAllowed(registration, optionIndex, option, entity, distance, now)
    if not option.canInteract then return true end

    -- Successful checks remain uncached by default because third-party
    -- callbacks often read rapidly-changing local state. Failed checks get a
    -- short, separate cooldown: an unavailable option should not invoke the
    -- same callback on every resolver pass, but it must still become available
    -- while the player continues aiming when that external state changes.
    local successCacheMs = Config.target.canInteractCacheMs or 0
    local failureCacheMs = Config.target.canInteractFailureCacheMs or 0
    local key

    if successCacheMs > 0 or failureCacheMs > 0 then
        key = ('%s:%s:%s:%s'):format(registration.id, optionIndex, entity or 0, math.floor(distance * 10))
        local cached = canInteractCache[key]
        if cached and now < cached.expiresAt then return cached.allowed end
    end

    diagnostics.canInteract = diagnostics.canInteract + 1
    local ok, result = pcall(option.canInteract, entity, distance, option.data)
    local allowed = ok and result ~= false
    if not ok then print(("[qbtarget] canInteract for option '%s' errored: %s"):format(option.label, tostring(result))) end

    local cacheMs = allowed and successCacheMs or failureCacheMs
    if key and cacheMs > 0 then
        if canInteractCache[key] == nil then canInteractCacheCount = canInteractCacheCount + 1 end
        canInteractCache[key] = { allowed = allowed, expiresAt = now + cacheMs }
        if canInteractCacheCount > CAN_INTERACT_CACHE_LIMIT then pruneCanInteractCache(now) end
    elseif key and canInteractCache[key] then
        canInteractCache[key] = nil
        canInteractCacheCount = canInteractCacheCount - 1
    end

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
    -- Stamped here rather than at the call site so aimIsStatic's staleness cap
    -- is anchored to the resolve that actually happened.
    lastResolveAt = now
    -- The bone cache is scoped to one resolver pass (a bone moves between
    -- passes) but reused across them: a fresh table per tick was garbage for
    -- the whole hold, and clearing the handful of keys it holds is cheaper
    -- than allocating.
    for cachedEntity in pairs(boneCache) do boneCache[cachedEntity] = nil end
    local pedCoords, candidates, nearestIndex = GetEntityCoords(PlayerPedId()), {}, nil
    if hit and entity and entity ~= 0 then
        for _, registration in ipairs(entityRegistrations(entity)) do
            nearestIndex = appendCandidates(candidates, nearestIndex, registration, entity, hitCoords, pedCoords, now, boneCache)
        end
    end
    if hit and hitCoords then
        for _, registration in ipairs(zoneRegistrationsAt(hitCoords, pedCoords)) do
            -- qb-target passes the raycast entity through zone canInteract /
            -- action payloads as well; it may be nil/0 when the zone point is
            -- world geometry.
            nearestIndex = appendCandidates(candidates, nearestIndex, registration,
                entity and entity ~= 0 and entity or nil, hitCoords, pedCoords, now, boneCache)
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
--
-- Both probes are STARTED before either is awaited (QB.raycast.startFromCamera
-- was added to qblib for exactly this). The engine settles shape tests once
-- per frame, so the previous await-then-fire ordering spent two frames -- and
-- two thread wake-ups -- per tick to learn what one frame already knew.
-- Starting them together halves both. The second probe is started
-- unconditionally rather than only when the first reports no entity: a shape
-- test costs far less than the extra frame that deciding first would cost,
-- and when the broad probe does find an entity the second result is simply
-- never read.
local function raycastTarget()
    local broadProbe = QB.raycast.startFromCamera(Config.target.maxDistance, 511)
    local entityProbe = QB.raycast.startFromCamera(Config.target.maxDistance, 26)

    local hit, hitCoords, entity = QB.raycast.await(broadProbe)
    if entity and entity ~= 0 then return hit, hitCoords, entity end

    -- Already settled -- it was started in the same frame the await above
    -- waited out -- so this second await never yields.
    local entityHit, entityCoords, entityHandle = QB.raycast.await(entityProbe)
    if not (entityHit and entityHandle and entityHandle ~= 0) then return hit, hitCoords, entity end
    if not hit or not hitCoords then return entityHit, entityCoords, entityHandle end

    local pedCoords = GetEntityCoords(PlayerPedId())
    if distanceSq(pedCoords, entityCoords) <= distanceSq(pedCoords, hitCoords) then
        return entityHit, entityCoords, entityHandle
    end

    return hit, hitCoords, entity
end

local function updateHoveringState(candidates)
    local top = candidates[1]
    Target.success = top ~= nil
    if not top then Target.hovering = nil; return end
    local previous = Target.hovering
    if previous and previous.id == top.registration.id and previous.entity == top.entity and previous.option == top.option then return end
    Target.hovering = { kind = top.registration.kind, id = top.registration.id, entity = top.entity, zoneId = top.registration.kind == 'zone' and top.registration.id or nil, option = top.option, optionCount = #candidates }
end

-- qblib owns the transparent NUI root. Targeting remains game-input driven;
-- this is only a compact visual snapshot, never a focus-taking UI.
-- The snapshot is compared field by field against what was last sent, rather
-- than against a formatted key string. The old key was rebuilt (and the label
-- with it) on every tick of every hold purely to be compared and dropped;
-- the identity of the top candidate's registration, entity and option table,
-- plus the option count, decide the same thing exactly and allocate nothing.
-- The label is only formatted once something has actually changed.
syncTargetHud = function(active, candidates)
    if not active then
        if not hudActive then return end
        hudActive, hudRegistrationId, hudEntity, hudOption, hudOptionCount = false, nil, nil, nil, 0
        QB.nui.send('qbtarget:target', { active = false })
        return
    end

    local top = candidates and candidates[1]
    local registrationId = top and top.registration.id or nil
    local entity = top and top.entity or nil
    local option = top and top.option or nil
    local optionCount = candidates and #candidates or 0

    if hudActive and hudRegistrationId == registrationId and hudEntity == entity
        and hudOption == option and hudOptionCount == optionCount then
        return
    end

    hudActive, hudRegistrationId, hudEntity = true, registrationId, entity
    hudOption, hudOptionCount = option, optionCount

    QB.nui.send('qbtarget:target', {
        active = true,
        label = top and (optionCount == 1 and option.label or ('%d options'):format(optionCount)) or nil,
        optionCount = optionCount,
    })
end

-- The single most expensive thing a resolver tick does is fire two shape
-- tests and yield a frame waiting for the engine to settle them. None of that
-- can tell us anything new while the camera and the player are both perfectly
-- still: the ray is the same ray, so it lands on the same point.
--
-- "Perfectly still" is deliberately exact equality, not an epsilon. Any real
-- aim adjustment -- the smallest mouse movement, a controller stick, the ped
-- drifting -- changes these floats and resolves immediately, so this can only
-- ever engage while the player is genuinely holding still. What it cannot see
-- is the world moving under a static crosshair (a ped walking into it), which
-- is why it is capped: Config.target.staticRefresh is the longest a held aim
-- can go without a real scan regardless.
---@return boolean skip True when this tick can reuse the previous resolve.
local function aimIsStatic(now)
    local staticRefresh = Config.target.staticRefresh
    if not staticRefresh or staticRefresh <= 0 then return false end

    local cam, rot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local ped = GetEntityCoords(PlayerPedId())
    local revision = Target.registrationRevision

    local unchanged = lastCamX == cam.x and lastCamY == cam.y and lastCamZ == cam.z
        and lastCamPitch == rot.x and lastCamYaw == rot.z
        and lastPedX == ped.x and lastPedY == ped.y and lastPedZ == ped.z
        and lastResolveRevision == revision

    lastCamX, lastCamY, lastCamZ = cam.x, cam.y, cam.z
    lastCamPitch, lastCamYaw = rot.x, rot.z
    lastPedX, lastPedY, lastPedZ = ped.x, ped.y, ped.z
    lastResolveRevision = revision

    return unchanged and (now - lastResolveAt) < staticRefresh
end

local function reportDiagnostics(now)
    if not Config.target.diagnostics or now - diagnostics.lastReport < Config.target.diagnosticsInterval then return end
    local scans = math.max(diagnostics.scans, 1)
    print(('[qbtarget] %d scans (%d ticks skipped as static), %d raycasts, %d options, %d canInteract calls, %.2fms average resolve')
        :format(diagnostics.scans, diagnostics.skipped, diagnostics.raycasts, diagnostics.options, diagnostics.canInteract, diagnostics.elapsed / scans))
    diagnostics = { scans = 0, skipped = 0, raycasts = 0, options = 0, canInteract = 0, elapsed = 0, lastReport = now }
end

local function resolverWait()
    if currentCandidates[1] then return Config.target.tickActive end
    if currentRaycastEntity and currentRaycastEntity ~= 0 then return Config.target.tickAcquire end
    return Config.target.tickMiss
end

local function runOption(candidate)
    local ok, err = pcall(candidate.option.onSelect, candidate.entity, candidate.option.data)
    if not ok then print(("[qbtarget] onSelect for option '%s' errored: %s"):format(candidate.option.label, tostring(err))) end
end

---Resolves the candidates captured at Alt release. One option is immediate;
---multiple options use qblib's game-input-driven interact selector, so the
---player can keep camera control and choose with scroll/arrows plus E.
local function selectCandidates(candidates)
    if #candidates == 0 then return end
    if #candidates == 1 then return runOption(candidates[1]) end

    local items = {}
    for index, candidate in ipairs(candidates) do
        items[index] = {
            label = candidate.option.label,
            icon = candidate.option.icon,
            action = function() runOption(candidate) end,
        }
    end

    menuOpen = QB.interact.open(items)
    if not menuOpen then return end
    setMenuPositionFrozen(true)

    CreateThread(function()
        while QB.interact.isActive() do
            Wait(0)
        end
        closeTargetMenu()
    end)
end

local function startTargeting()
    if holdingThread or Target.interactionsLocked() then
        holding = false
        Target.active = false
        resetRuntimeState()
        return
    end
    holdingThread = true
    Target.active = Target.enabled
    resetRuntimeState()
    syncTargetHud(true, currentCandidates)
    diagnostics.lastReport = GetGameTimer()

    CreateThread(function()
        while holding do
            local now = GetGameTimer()
            if not Target.enabled or menuOpen or Target.interactionsLocked() then
                if Target.interactionsLocked() then
                    holding = false
                    closeTargetMenu()
                end
                Target.active = false
                resetRuntimeState()
                Wait(Config.target.tickIdle)
            elseif aimIsStatic(now) then
                Target.active = true
                diagnostics.skipped = diagnostics.skipped + 1
                reportDiagnostics(now)
                Wait(resolverWait())
            else
                Target.active = true
                local startedAt = now
                diagnostics.raycasts = diagnostics.raycasts + 1
                local hit, hitCoords, entity = raycastTarget()
                currentRaycastEntity = entity
                currentCandidates = resolveCandidates(hit, entity, hitCoords, now)
                diagnostics.elapsed = diagnostics.elapsed + GetGameTimer() - startedAt
                updateHoveringState(currentCandidates)
                syncTargetHud(true, currentCandidates)
                reportDiagnostics(now)
                Wait(resolverWait())
            end
        end
        resetRuntimeState()
        Target.active = false
        holdingThread = false
    end)
end

QB.keybind.add({
    name = Config.target.keybind.command,
    description = Config.target.keybind.label,
    defaultMapper = 'keyboard',
    defaultKey = Config.target.keybind.defaultKey,
    onPressed = function()
        if Target.interactionsLocked() then
            holding = false
            Target.active = false
            resetRuntimeState()
            return
        end
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
            Target.active = false
            selectCandidates(candidates)
        end
    end,
    onReleased = function()
        if Target.interactionsLocked() then
            holding = false
            Target.active = false
            resetRuntimeState()
            return
        end
        if Config.target.toggle then return end
        holding = false
        local candidates = currentCandidates
        resetRuntimeState()
        Target.active = false
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
        holding = false
        closeTargetMenu()
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
        aimIsStatic = aimIsStatic,
        resetRuntimeState = resetRuntimeState,
        selectCandidates = selectCandidates,
        closeTargetMenu = closeTargetMenu,
        resolveCandidates = resolveCandidates,
        resolverWait = function(candidates, entity)
            currentCandidates, currentRaycastEntity = candidates, entity
            return resolverWait()
        end,
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
