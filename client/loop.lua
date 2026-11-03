Target = Target or {}

local holding, holdingThread, menuOpen = false, false, false
local currentCandidates = {}
local candidatePool = {}
local currentRaycastEntity
local menuHintShown = false
local startWatchdog

-- Runtime-only cache; never authoritative.
local entityRegistrationCache = { entity = nil, model = nil, entityType = nil, revision = nil, registrations = {} }
local canInteractCache = {}
local emptyRegistrations = {}
local syncTargetHud
local diagnostics = { scans = 0, skipped = 0, raycasts = 0, options = 0, canInteract = 0, elapsed = 0, lastReport = 0 }

-- The last snapshot syncTargetHud pushed to the NUI. See syncTargetHud below.
local hudActive, hudRegistrationId, hudEntity, hudOption, hudOptionCount = false, nil, nil, nil, 0

-- Reused scratch. Candidate objects are stable for the lifetime of one target
-- hold; resetRuntimeState swaps them out before a captured release selection
-- can overlap a later hold.
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
    canInteractCache = {}
    candidatePool = {}
    lastResolveAt, lastResolveRevision = 0, nil
    lastCamX, lastCamY, lastCamZ, lastCamPitch, lastCamYaw = nil, nil, nil, nil, nil
    lastPedX, lastPedY, lastPedZ = nil, nil, nil
    if syncTargetHud then syncTargetHud(false) end
end

-- The candidate list is captured when Alt is released. It must remain valid
-- until the compact selector is dismissed, so do not let the player walk out
-- of a target zone and select an option from that stale snapshot.
-- Local copies of the kora_lib cache values this file needs, kept current by
-- onChange so no cross-resource export call runs in a loop. They fall back to
-- natives when the cache is unavailable.
local cachedPed, cachedInVehicle = nil, false
local vehicleBlocked
if Kora.cache and Kora.cache.onChange then
    pcall(function()
        cachedPed, cachedInVehicle = Kora.cache.ped(), Kora.cache.vehicle() and true or false
    end)
    Kora.cache.onChange('ped', function(ped) cachedPed = ped end)
    Kora.cache.onChange('vehicle', function(vehicle)
        cachedInVehicle = vehicle and true or false
        -- Getting into a vehicle (driver or passenger) ends targeting and closes any open menu.
        if cachedInVehicle and (holding or menuOpen) and vehicleBlocked() and Target._forceRelease then
            Target._forceRelease()
        end
    end)
end

local function localPed()
    if cachedPed and cachedPed ~= 0 then return cachedPed end
    return PlayerPedId()
end

-- Config.target.disableInVehicle: no targeting while seated in a vehicle. Reads
-- the kora_lib cache copy kept current by onChange, never a native.
vehicleBlocked = function()
    return cachedInVehicle and Config.target.disableInVehicle ~= false
end

local function nativeTrue(value)
    return value ~= nil and value ~= false and value ~= 0
end

-- True while the ped is falling, jumping, ragdolling, parachuting, climbing or
-- vaulting, i.e. anywhere its position must stay under the game's physics.
-- Seated in a vehicle never counts: the vehicle owns the movement there.
local function pedAirborne(ped)
    if cachedInVehicle then return false end
    ped = ped or localPed()
    if not ped or ped == 0 then return false end
    if nativeTrue(IsPedFalling(ped)) or nativeTrue(IsPedJumping(ped)) or nativeTrue(IsPedRagdoll(ped))
        or nativeTrue(IsPedInParachuteFreeFall(ped)) or nativeTrue(IsPedClimbing(ped))
        or nativeTrue(IsPedVaulting(ped)) or nativeTrue(IsEntityInAir(ped)) then
        return true
    end
    return (tonumber(GetPedParachuteState(ped)) or -1) > 0
end

local function closeWhenAirborne()
    return Config.target.closeWhenAirborne ~= false
end

-- Resolves how the open menu treats player movement. menuMovement wins when it
-- is a known mode; otherwise the legacy freezeOnMenu boolean maps onto it, so a
-- server that only ever set freezeOnMenu = true keeps its freeze.
local MENU_MOVEMENT_MODES = { freeze = true, close = true, allow = true }
local function menuMovementMode()
    local mode = Config.target.menuMovement
    if MENU_MOVEMENT_MODES[mode] then return mode end
    return Config.target.freezeOnMenu and 'freeze' or 'allow'
end

-- Move LR/UD, sprint, jump, cover, stealth and the directional keys. menuMovement
-- = 'freeze' only ignores these keys: the ped's position is never frozen, so a
-- walking ped slows to a natural stop and gravity keeps working mid-air.
local MENU_MOVE_CONTROLS = { 21, 22, 30, 31, 32, 33, 34, 35, 36, 44 }
local MENU_LOOK_CONTROLS = { 1, 2 }

-- Escape closes the option menu, and the same key press then reaches the game
-- and opens the pause menu. While the menu is open, and for a short window
-- after it closes, the pause controls are disabled (and a pause menu that still
-- opened is shut again) so closing the menu never leaves the player in it.
-- INPUT_FRONTEND_PAUSE, INPUT_FRONTEND_PAUSE_ALTERNATE, INPUT_FRONTEND_CANCEL-ESC
local PAUSE_CONTROLS = { 199, 200, 322 }
local pauseSuppressUntil, pauseSuppressRunning = 0, false

local function pauseSuppressEnabled()
    return Config.target.suppressPauseOnClose == true
end

local function pauseSuppressWindow()
    local ms = tonumber(Config.target.pauseSuppressMs) or 250
    if ms < 0 then return 0 end
    if ms > 2000 then return 2000 end
    return ms
end

local function suppressPauseFrame(forceClose)
    for _, control in ipairs(PAUSE_CONTROLS) do DisableControlAction(0, control, true) end
    if forceClose and IsPauseMenuActive() then
        SetPauseMenuActive(false)
        SetFrontendActive(false)
    end
end

-- Starts (or extends) the short post-close suppression window. It always ends,
-- so the pause menu is never blocked permanently.
local function startPauseSuppression()
    if not pauseSuppressEnabled() then return end
    local window = pauseSuppressWindow()
    if window <= 0 then return end
    pauseSuppressUntil = GetGameTimer() + window
    if pauseSuppressRunning then return end
    pauseSuppressRunning = true
    CreateThread(function()
        while GetGameTimer() < pauseSuppressUntil do
            suppressPauseFrame(true)
            Wait(0)
        end
        pauseSuppressRunning = false
    end)
end

local function menuMovementPressed()
    if math.abs(GetControlNormal(0, 30)) > 0.1 or math.abs(GetControlNormal(0, 31)) > 0.1 then return true end
    for _, control in ipairs(MENU_MOVE_CONTROLS) do
        if IsControlPressed(0, control) then return true end
    end
    return false
end

-- One frame of menu input policy, run from the menu-open loop. Returns true
-- when the menu should close (menuMovement = 'close' and a movement key went
-- down). Movement already held when the menu opened does not count until it is
-- released and pressed again, so releasing Alt mid-stride does not dismiss it.
local function menuInputFrame(mode, state)
    if pauseSuppressEnabled() then suppressPauseFrame(false) end
    if mode == 'freeze' then
        for _, control in ipairs(MENU_MOVE_CONTROLS) do DisableControlAction(0, control, true) end
    end
    if Config.target.lockCameraOnMenu then
        for _, control in ipairs(MENU_LOOK_CONTROLS) do DisableControlAction(0, control, true) end
    end
    if mode == 'close' then
        local moving = menuMovementPressed()
        local started = moving and not state.moving
        state.moving = moving
        return started
    end
    return false
end

local function closeTargetMenu()
    local wasOpen = menuOpen
    if menuOpen then Kora.interact.close() end
    menuOpen = false
    if wasOpen then startPauseSuppression() end
    if menuHintShown then ClearAllHelpMessages() end
    menuHintShown = false
end

-- Close an open menu if this resource stops.
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then closeTargetMenu() end
end)

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

-- Dead / last stand / downed gate (Config.target.disableWhileDead). The Kora
-- stack records death as kora_core player metadata (isdead / inlaststand, set by
-- kora_ambulance); the native fatal-injury flag (Kora.cache.isDead) covers the
-- gap before the metadata lands. The metadata export is polled at most every
-- downedPollMs; runOption passes fresh = true to bypass that cache.
local downedCache, downedCheckedAt = false, -math.huge

local function readDowned()
    local ok, data = pcall(function() return exports.kora_core:getPlayerData() end)
    local metadata = ok and type(data) == "table" and data.metadata or nil
    if type(metadata) == "table" and (metadata.isdead == true or metadata.inlaststand == true) then return true end
    local state = LocalPlayer and LocalPlayer.state
    if state and (state.isDead == true or state.inLastStand == true or state.isDowned == true) then return true end
    return Kora.cache ~= nil and Kora.cache.isDead ~= nil and Kora.cache.isDead() == true
end

---True when the local player is dead, in last stand or downed and
---Config.target.disableWhileDead is on.
---@param fresh boolean|nil skip the poll cache (used right before an action fires)
---@return boolean
function Target.isDowned(fresh)
    if Config.target.disableWhileDead == false then return false end
    local now = GetGameTimer()
    if fresh or now - downedCheckedAt >= (tonumber(Config.target.downedPollMs) or 250) then
        downedCheckedAt = now
        downedCache = readDowned()
    end
    return downedCache
end

local function allowedWhileDown()
    local list = Config.target.allowWhileDead
    return type(list) == "table" and list or {}
end

local function optionAllowedWhileDown(option)
    if not option or option.name == nil then return false end
    for _, name in ipairs(allowedWhileDown()) do
        if name == option.name then return true end
    end
    return false
end

local function classifyEntity(entity)
    -- GetEntityType is 0 for a handle that no longer resolves; treating it as an object would let it reach GetEntityModel and fault.
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
    -- Field-wise compare instead of a formatted key string: no per-tick allocation.
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

-- Zones match against the aim point (raycast hit), not the ped's position, so standing inside isn't required.
-- Two exact filters precede the contains scan: one reach comparison (every zone anchors on the hit, so the
-- distance is identical for all), then the Target.zonesNear AABB grid. Zones with underivable extents stay in the scan.
---@param point table Raycast hit coordinates.
---@param pedCoords table? Player position; omit to skip filter 1.
local function zoneRegistrationsAt(point, pedCoords, aimedEntity)
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
        if registration and (not registration.targetEntity or registration.targetEntity == aimedEntity)
            and registration.zoneHandle.contains(point) then
            registrations[#registrations + 1] = registration
        end
    end

    return registrations
end

local function optionAllowed(registration, optionIndex, option, entity, distance, now, anchorCoords)
    if Target.isDowned() and not optionAllowedWhileDown(option) then return false end
    if not option.canInteract then return true end

    -- Successful checks remain uncached by default because third-party
    -- callbacks often read rapidly-changing local state. Failed checks get a
    -- short, separate cooldown: an unavailable option should not invoke the
    -- same callback on every resolver pass, but it must still become available
    -- while the player continues aiming when that external state changes.
    local successCacheMs = Config.target.canInteractCacheMs or 0
    local failureCacheMs = Config.target.canInteractFailureCacheMs or 0
    if successCacheMs > 0 or failureCacheMs > 0 then
        local cached = canInteractCache[option]
        local distanceBucket = math.floor(distance * 10)
        if cached and cached.registrationId == registration.id and cached.optionIndex == optionIndex
            and cached.entity == entity and cached.distanceBucket == distanceBucket
            and now < cached.expiresAt then
            return cached.allowed
        end
    end

    if Config.target.diagnostics then diagnostics.canInteract = diagnostics.canInteract + 1 end
    local ok, result = pcall(option.canInteract, entity, distance, option.data, anchorCoords)
    local allowed = ok and result ~= false
    if not ok then print(("[qbtarget] canInteract for option '%s' errored: %s"):format(option.label, tostring(result))) end

    local cacheMs = allowed and successCacheMs or failureCacheMs
    if cacheMs > 0 then
        canInteractCache[option] = {
            registrationId = registration.id,
            optionIndex = optionIndex,
            entity = entity,
            distanceBucket = math.floor(distance * 10),
            allowed = allowed,
            expiresAt = now + cacheMs,
        }
    else
        canInteractCache[option] = nil
    end

    return allowed
end

local function appendCandidates(candidates, nearestIndex, registration, entity, anchorCoords,
    distSq, toleranceSq, now, boneCache)
    local registrationBones = registration.kind == 'globalBone' and Target.byGlobalBone[registration.id] or nil
    local distance

    for index, option in ipairs(registration.options) do
        if Config.target.diagnostics then diagnostics.options = diagnostics.options + 1 end
        local maxDistance = option.distance or registration.distance or Config.target.defaultOptionDistance
        if distSq <= maxDistance * maxDistance and boneMatches(entity, option.bones or registrationBones, anchorCoords, toleranceSq, boneCache) then
            -- canInteract receives distance for compatibility; pay the sqrt only
            -- after all cheap rejections have passed.
            distance = distance or math.sqrt(distSq)
            if optionAllowed(registration, index, option, entity, distance, now, anchorCoords) then
                local candidateIndex = #candidates + 1
                local candidate = candidatePool[candidateIndex]
                if not candidate then
                    candidate = {}
                    candidatePool[candidateIndex] = candidate
                end
                candidate.registration, candidate.option, candidate.entity = registration, option, entity
                candidate.anchorCoords, candidate.distance, candidate.distanceSq = anchorCoords, distance, distSq
                candidates[candidateIndex] = candidate
                if not nearestIndex or distSq < candidates[nearestIndex].distanceSq then nearestIndex = candidateIndex end
            end
        end
    end
    return nearestIndex
end

local function resolveCandidates(hit, entity, hitCoords, now, pedCoords)
    if Config.target.diagnostics then diagnostics.scans = diagnostics.scans + 1 end
    -- Stamped here rather than at the call site so aimIsStatic's staleness cap
    -- is anchored to the resolve that actually happened.
    lastResolveAt = now
    -- Bone cache is per-pass but the table is reused; clearing beats reallocating.
    for cachedEntity in pairs(boneCache) do boneCache[cachedEntity] = nil end
    pedCoords = pedCoords or GetEntityCoords(PlayerPedId())
    local candidates, oldCount, nearestIndex = currentCandidates, #currentCandidates, nil
    for i = 1, oldCount do candidates[i] = nil end
    local hitDistanceSq = hitCoords and distanceSq(pedCoords, hitCoords) or 0.0
    local toleranceSq = Config.target.boneTolerance * Config.target.boneTolerance
    if hit and entity and entity ~= 0 then
        for _, registration in ipairs(entityRegistrations(entity)) do
            nearestIndex = appendCandidates(candidates, nearestIndex, registration, entity, hitCoords,
                hitDistanceSq, toleranceSq, now, boneCache)
        end
    end
    if hit and hitCoords then
        for _, registration in ipairs(zoneRegistrationsAt(hitCoords, pedCoords, entity)) do
            -- qb-target passes the raycast entity through zone canInteract /
            -- action payloads as well; it may be nil/0 when the zone point is
            -- world geometry.
            nearestIndex = appendCandidates(candidates, nearestIndex, registration,
                entity and entity ~= 0 and entity or nil, hitCoords, hitDistanceSq, toleranceSq, now, boneCache)
        end
    end
    -- Keep the closest candidate first without sorting every option.
    if nearestIndex and nearestIndex ~= 1 then candidates[1], candidates[nearestIndex] = candidates[nearestIndex], candidates[1] end
    return candidates
end

-- Mirrors ox_target: broad mask first, then an entity-focused mask when that reports no entity. The closer hit wins.
-- The fallback is rate limited and only starts after a broad miss on entities; both casts share one camera/ped snapshot.
local lastEntityProbeAt = -math.huge
local aimState = { destination = {} }

local function aimSnapshot()
    local ped = PlayerPedId()
    local cam, rot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local pitch, yaw = math.rad(rot.x), math.rad(rot.z)
    local flatLength = math.abs(math.cos(pitch))
    local distance = Config.target.maxDistance
    aimState.ped, aimState.pedCoords = ped, GetEntityCoords(ped)
    aimState.cam, aimState.rot = cam, rot
    aimState.destination.x = cam.x - math.sin(yaw) * flatLength * distance
    aimState.destination.y = cam.y + math.cos(yaw) * flatLength * distance
    aimState.destination.z = cam.z + math.sin(pitch) * distance
    return aimState
end

local function raycastTarget(snapshot, now)
    snapshot = snapshot or aimSnapshot()
    now = now or GetGameTimer()
    local broadProbe = Kora.raycast.start(snapshot.cam, snapshot.destination, 511, snapshot.ped)
    local hit, hitCoords, entity = Kora.raycast.await(broadProbe)
    if entity and entity ~= 0 then return hit, hitCoords, entity end

    local interval = Config.target.entityProbeInterval or 0
    if interval > 0 and now - lastEntityProbeAt < interval then return hit, hitCoords, entity end
    lastEntityProbeAt = now
    local entityProbe = Kora.raycast.start(snapshot.cam, snapshot.destination, 26, snapshot.ped)

    local entityHit, entityCoords, entityHandle = Kora.raycast.await(entityProbe)
    if not (entityHit and entityHandle and entityHandle ~= 0) then return hit, hitCoords, entity end
    if not hit or not hitCoords then return entityHit, entityCoords, entityHandle end

    if distanceSq(snapshot.pedCoords, entityCoords) <= distanceSq(snapshot.pedCoords, hitCoords) then
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

-- kora_lib owns the transparent NUI root; this is only a compact snapshot, never focus-taking.
-- Compared field by field against the last sent snapshot (no formatted key); the label is formatted only on change.
syncTargetHud = function(active, candidates)
    if not active then
        if not hudActive then return end
        hudActive, hudRegistrationId, hudEntity, hudOption, hudOptionCount = false, nil, nil, nil, 0
        Kora.nui.send('qbtarget:target', { active = false })
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

    Kora.nui.send('qbtarget:target', {
        active = true,
        label = top and (optionCount == 1 and option.label or ('%d options'):format(optionCount)) or nil,
        optionCount = optionCount,
    })
end

-- Reuses the previous resolve while camera and ped are exactly still (no epsilon: any real aim change resolves immediately).
-- Cannot see the world moving under a static crosshair, hence the refresh caps; empty misses use staticMissRefresh.
---@return boolean skip True when this tick can reuse the previous resolve.
local function aimIsStatic(now, snapshot)
    local hasAimTarget = currentCandidates[1] ~= nil
        or currentRaycastEntity ~= nil and currentRaycastEntity ~= 0
    local staticRefresh = hasAimTarget and Config.target.staticRefresh or Config.target.staticMissRefresh
    if not staticRefresh or staticRefresh <= 0 then return false end

    snapshot = snapshot or aimSnapshot()
    local cam, rot, ped = snapshot.cam, snapshot.rot, snapshot.pedCoords
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

-- A zone option is reached through the point the ray hit inside the zone. The entity the ray also
-- touched (a door or wall prop) is incidental and its origin can be many metres from that point, so
-- only zones bound to an entity (targetEntity) follow it.
local function followsEntity(registration)
    return registration.kind ~= 'zone' or registration.targetEntity ~= nil
end

-- The aimed point in the entity's own frame, so the menu range check can follow
-- a moving entity while still measuring to the spot the resolver measured to.
local function entityAnchorOffset(entity, point)
    if not (point and point.x) then return nil end
    local ok, offset = pcall(GetOffsetFromEntityGivenWorldCoords, entity, point.x, point.y, point.z)
    return ok and offset or nil
end

-- The menu works from the snapshot taken at release, so check that at least one
-- snapshotted option can still be reached from where the player is now. The
-- resolver accepted each option by its distance to the aimed point, so measure
-- to that same point. For an entity it is carried along with the entity
-- (anchorOffset, set when the menu opens); its origin is not used, because on a
-- long vehicle the origin is metres from the trunk or hood that was aimed at and
-- the menu would close on its first frame.
local function rangeTolerance()
    local tolerance = tonumber(Config.target.rangeTolerance) or 0.0
    return tolerance > 0 and tolerance or 0.0
end

-- true / false, or nil when the candidate has nothing to measure to.
local function candidateInRange(candidate, pedCoords)
    local registration = candidate.registration
    local entity = registration and followsEntity(registration) and candidate.entity or nil
    if entity and entity ~= 0 and not DoesEntityExist(entity) then return false end
    local anchor = candidate.anchorCoords
    if entity and entity ~= 0 then
        local offset = candidate.anchorOffset
        if offset then
            anchor = GetOffsetFromEntityInWorldCoords(entity, offset.x, offset.y, offset.z)
        else
            anchor = GetEntityCoords(entity)
        end
    end
    if not anchor then return nil end
    local maxDistance = (candidate.option.distance or (registration and registration.distance)
        or Config.target.defaultOptionDistance) + rangeTolerance()
    return distanceSq(pedCoords, anchor) <= maxDistance * maxDistance
end

local function menuTargetInRange(candidates)
    local pedCoords = GetEntityCoords(localPed())
    for _, candidate in ipairs(candidates) do
        if candidateInRange(candidate, pedCoords) then return true end
    end
    return false
end

local function runOption(candidate)
    if vehicleBlocked() then return end
    -- The snapshot may be older than the click: an option whose target has since
    -- gone out of reach (or vanished) must not run.
    if candidateInRange(candidate, GetEntityCoords(localPed())) == false then return end
    if Target.isDowned(true) and not optionAllowedWhileDown(candidate.option) then
        Target._cancelCurrentTargeting()
        return
    end
    local ok, err
    if candidate.option._onSelectContext then
        ok, err = pcall(candidate.option._onSelectContext, candidate)
    else
        ok, err = pcall(candidate.option.onSelect, candidate.entity, candidate.option.data)
    end
    if not ok then print(("[qbtarget] onSelect for option '%s' errored: %s"):format(candidate.option.label, tostring(err))) end
end

---Resolves the candidates captured at Alt release. One option is immediate;
---multiple options use kora_lib's game-input-driven interact selector, so the
---player can keep camera control and choose with scroll/arrows plus E.
local function selectCandidates(candidates)
    if #candidates == 0 or vehicleBlocked() then return end
    -- Releasing the key mid-fall or mid-jump neither opens the menu nor runs an option.
    if closeWhenAirborne() and pedAirborne() then return end

    for _, candidate in ipairs(candidates) do
        local entity = candidate.registration and followsEntity(candidate.registration) and candidate.entity or nil
        candidate.anchorOffset = entity and entity ~= 0 and entityAnchorOffset(entity, candidate.anchorCoords) or nil
    end
    if #candidates == 1 then return runOption(candidates[1]) end

    local items = {}
    for index, candidate in ipairs(candidates) do
        items[index] = {
            label = candidate.option.label,
            icon = candidate.option.icon,
            action = function() runOption(candidate) end,
        }
    end

    menuOpen = Kora.interact.open(items)
    if not menuOpen then return end
    startWatchdog()
    local movementMode = menuMovementMode()

    -- kora_lib's selector has no footer, so use a one-off native help message.
    if Config.target.showCloseHint then
        BeginTextCommandDisplayHelp('STRING')
        AddTextComponentSubstringPlayerName('Press ~INPUT_FRONTEND_PAUSE_ALTERNATE~ to close')
        EndTextCommandDisplayHelp(0, false, false, 5000)
        menuHintShown = true
    end

    -- Reuses the selector's existing per-frame wait; the range check is throttled.
    CreateThread(function()
        local nextRangeCheck = 0
        local inputState = { moving = movementMode == 'close' and menuMovementPressed() }
        while Kora.interact.isActive() do
            if menuInputFrame(movementMode, inputState) then break end
            if Target.isDowned() and #allowedWhileDown() == 0 then break end
            local now = GetGameTimer()
            if now >= nextRangeCheck then
                nextRangeCheck = now + Config.target.tickActive
                -- closeWhenAirborne: leaving the ground closes the menu.
                if closeWhenAirborne() and pedAirborne() then break end
                if Config.target.closeMenuOutOfRange then
                    if not menuTargetInRange(candidates) then break end
                end
            end
            Wait(0)
        end
        closeTargetMenu()
    end)
end

local releaseGuard = false

-- Cancels the current targeting session without running an option, clears any
-- legacy NUI focus, and re-sends -<command> so kora_lib's keybind drops its
-- own "pressed" flag (otherwise the next +<command> is ignored as a repeat).
local function forceRelease()
    holding = false
    closeTargetMenu()
    resetRuntimeState()
    Target.active = false
    if Target._releaseLegacyFocus then Target._releaseLegacyFocus() end
    releaseGuard = true
    pcall(ExecuteCommand, '-' .. Config.target.keybind.command)
    releaseGuard = false
end
Target._forceRelease = forceRelease

local function recoveryConfig()
    local recovery = Config.target.recovery
    if type(recovery) ~= 'table' or recovery.enabled == false then return nil end
    return recovery
end

local CANCEL_CONTROLS = { 200, 177, 25 } -- Escape, Backspace/right-click (cancel), aim
local MENU_ACTIVITY_CONTROLS = { 38, 24, 15, 14, 27, 173 } -- select, scroll, arrows
local ALT_CONTROL = 19 -- INPUT_CHARACTER_WHEEL, the default control behind Left Alt
local MENU_IDLE_DEFAULT_MS = 30000

local lastFocusLossAt = -1000000
local watchdogRunning = false

local function noteFocusLoss()
    lastFocusLossAt = GetGameTimer()
end

-- Unknown (older builds without the native) counts as focused.
local function windowFocused()
    local native = IsGameWindowFocused
    if type(native) ~= 'function' then return true end
    local ok, focused = pcall(native)
    return not ok or focused ~= false
end

local function legacyFocused()
    return Target._legacyFocused ~= nil and Target._legacyFocused() == true
end

local function sessionActive()
    return holding or menuOpen or legacyFocused()
end

-- The hold key is Left Alt by default, and the game reports it as INPUT_CHARACTER_WHEEL.
-- That is a real control, unlike the +command hash which is not reliably readable.
-- Skipped when the key was rebound to something other than Alt.
local function altFallbackActive(recovery)
    if recovery.altControlFallback == false then return false end
    if tostring(Config.target.keybind.defaultKey):upper() ~= 'LMENU' then return false end
    local ok, bound = pcall(GetControlInstructionalButton, 0, joaat('+' .. Config.target.keybind.command) | 0x80000000, true)
    if ok and type(bound) == 'string' and bound:sub(1, 2) == 't_' and bound:upper() ~= 't_LMENU' then return false end
    return true
end

local function anyPressed(controls)
    for _, control in ipairs(controls) do
        if IsDisabledControlJustPressed(0, control) or IsControlJustPressed(0, control) then return true end
    end
    return false
end

-- Alt+Tab swallows the key-up (hold mode) and can leave the selector or legacy
-- NUI focus open. While anything is active this thread cancels it when the
-- window loses focus, the pause menu opens, a cancel input is pressed, the hold
-- key reads "up", the selector sits idle too long, or legacy focus is orphaned.
startWatchdog = function()
    local recovery = recoveryConfig()
    if not recovery or watchdogRunning then return end
    watchdogRunning = true
    CreateThread(function()
        local cmd = Config.target.keybind.command
        local keyHash = joaat('+' .. cmd) | 0x80000000
        local useAlt = altFallbackActive(recovery)
        local seenDown, upSince, legacySince = false, nil, nil
        local menuWasOpen, lastActivity = false, GetGameTimer()
        while sessionActive() do
            local now = GetGameTimer()
            if not windowFocused() then
                noteFocusLoss()
                if recovery.cancelOnFocusLoss ~= false then forceRelease(); break end
            end
            if recovery.cancelOnPause ~= false and IsPauseMenuActive() then
                forceRelease()
                break
            end
            if holding and recovery.cancelControls ~= false then
                local cancelled = false
                for _, control in ipairs(CANCEL_CONTROLS) do
                    if IsDisabledControlJustPressed(0, control) then cancelled = true break end
                end
                if cancelled then
                    startPauseSuppression()
                    forceRelease()
                    break
                end
            end
            if holding and not Config.target.toggle then
                local down
                if useAlt then
                    down = IsControlPressed(0, ALT_CONTROL) or IsDisabledControlPressed(0, ALT_CONTROL)
                else
                    down = IsControlPressed(0, keyHash) or IsDisabledControlPressed(0, keyHash)
                end
                if down then
                    seenDown, upSince = true, nil
                elseif seenDown then
                    -- Only trusted after the key was seen down once, so a
                    -- control that cannot see the key can never cancel a hold.
                    upSince = upSince or now
                    if now - upSince >= (tonumber(recovery.releaseGraceMs) or 250) then
                        forceRelease()
                        break
                    end
                end
            end
            if menuOpen then
                if not menuWasOpen or anyPressed(MENU_ACTIVITY_CONTROLS) then lastActivity = now end
                local idle = tonumber(recovery.menuIdleTimeoutMs)
                if idle == nil then idle = MENU_IDLE_DEFAULT_MS end
                if idle > 0 and now - lastActivity >= idle then
                    startPauseSuppression()
                    forceRelease()
                    break
                end
            end
            menuWasOpen = menuOpen
            if not holding and not menuOpen then
                -- Orphaned cursor focus: the session ended but the legacy NUI kept focus.
                legacySince = legacySince or now
                if now - legacySince >= 1000 then forceRelease(); break end
            else
                legacySince = nil
            end
            Wait(0)
        end
        watchdogRunning = false
    end)
end

-- The NUI listener page (ui/focus.html) reports browser-side window blur and
-- cancel input, which is the only place Escape/right-click are visible while
-- NUI holds focus.
if RegisterNUICallback then
    RegisterNUICallback('targetFocus', function(data, cb)
        local recovery = recoveryConfig()
        local event = type(data) == 'table' and data.event or nil
        if recovery and recovery.nuiListener ~= false and sessionActive() then
            if event == 'blur' then
                noteFocusLoss()
                if recovery.cancelOnFocusLoss ~= false then forceRelease() end
            elseif event == 'cancel' and recovery.cancelControls ~= false then
                startPauseSuppression()
                forceRelease()
            end
        elseif event == 'blur' then
            noteFocusLoss()
        end
        cb('ok')
    end)
end

local function startTargeting()
    if holdingThread or vehicleBlocked() or Target.interactionsLocked() or (Target.isDowned(true) and #allowedWhileDown() == 0) then
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
    startWatchdog()

    CreateThread(function()
        while holding do
            local now = GetGameTimer()
            if Target.isDowned() and #allowedWhileDown() == 0 then
                holding = false
                closeTargetMenu()
            end
            -- Falling, jumping or climbing cancels targeting (hover prompt included).
            if holding and closeWhenAirborne() and pedAirborne() then forceRelease() end
            if not holding then
                Target.active = false
                resetRuntimeState()
                break
            end
            if not Target.enabled or menuOpen or Target.interactionsLocked() then
                if Target.interactionsLocked() then
                    holding = false
                    closeTargetMenu()
                end
                Target.active = false
                resetRuntimeState()
                Wait(Config.target.tickIdle)
            else
                local snapshot = aimSnapshot()
                Target.active = true
                if aimIsStatic(now, snapshot) then
                    if Config.target.diagnostics then diagnostics.skipped = diagnostics.skipped + 1 end
                    reportDiagnostics(now)
                    Wait(resolverWait())
                else
                    local startedAt = now
                    if Config.target.diagnostics then diagnostics.raycasts = diagnostics.raycasts + 1 end
                    local hit, hitCoords, entity = raycastTarget(snapshot, now)
                    currentRaycastEntity = entity
                    currentCandidates = resolveCandidates(hit, entity, hitCoords, now, snapshot.pedCoords)
                    if Config.target.diagnostics then
                        diagnostics.elapsed = diagnostics.elapsed + GetGameTimer() - startedAt
                    end
                    updateHoveringState(currentCandidates)
                    syncTargetHud(true, currentCandidates)
                    reportDiagnostics(now)
                    Wait(resolverWait())
                end
            end
        end
        resetRuntimeState()
        Target.active = false
        holdingThread = false
    end)
end

local targetKeybind = {
    name = Config.target.keybind.command,
    description = Config.target.keybind.label,
    defaultMapper = 'keyboard',
    defaultKey = Config.target.keybind.defaultKey,
    onPressed = function()
        if vehicleBlocked() or Target.interactionsLocked() or (Target.isDowned(true) and #allowedWhileDown() == 0) then
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
        if releaseGuard then return end
        if Target.interactionsLocked() then
            holding = false
            Target.active = false
            resetRuntimeState()
            return
        end
        if Config.target.toggle then return end
        local recovery = recoveryConfig()
        local ignoreMs = recovery and tonumber(recovery.focusReleaseIgnoreMs) or 0
        if ignoreMs > 0 and GetGameTimer() - lastFocusLossAt < ignoreMs then
            -- The key-up that follows an Alt+Tab round trip is not a selection.
            forceRelease()
            return
        end
        holding = false
        local candidates = currentCandidates
        resetRuntimeState()
        Target.active = false
        selectCandidates(candidates)
    end,
}
Kora.keybind.add(targetKeybind)

-- Stock qb-target names its hold commands +playerTarget/-playerTarget; scripts and keybind
-- configs that reference them keep working. Registered as plain commands (no key mapping),
-- so the player's own binding stays on Config.target.keybind.
RegisterCommand('+playerTarget', function() targetKeybind.onPressed() end, false)
RegisterCommand('-playerTarget', function() targetKeybind.onReleased() end, false)

-- Manual recovery if targeting ever sticks (e.g. after Alt+Tab).
do
    local recovery = recoveryConfig()
    local name = recovery and recovery.resetCommand
    if type(name) == 'string' and name ~= '' then
        RegisterCommand(name, function() forceRelease() end, false)
    end
end

-- Runtime override via Kora.zones.setDebug(nil, ...) for zones already created; config is only read at registration.
-- `[on|off]`, or no argument to toggle.
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
    Kora.zones.setDebug(nil, enabled)
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
        menuTargetInRange = menuTargetInRange,
        pedAirborne = pedAirborne,
        isMenuOpen = function() return menuOpen end,
        closeTargetMenu = closeTargetMenu,
        forceRelease = forceRelease,
        isHolding = function() return holding end,
        setHolding = function(value) holding = value end,
        menuMovementMode = menuMovementMode,
        setInVehicle = function(value) cachedInVehicle = value and true or false end,
        menuInputFrame = menuInputFrame,
        suppressPauseFrame = suppressPauseFrame,
        pauseSuppressUntil = function() return pauseSuppressUntil end,
        resetPauseSuppression = function() pauseSuppressUntil, pauseSuppressRunning = 0, false end,
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
