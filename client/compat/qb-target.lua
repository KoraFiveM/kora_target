-- Drop-in compatibility bridge: translates the real, public qb-target API
-- into calls against Target.* directly (same resource -- no exports.qbtarget:
-- round trip needed). Scripts written against exports['qb-target']:... keep
-- working unmodified even though this resource is literally named
-- "qbtarget", not "qb-target" -- see provideExport below.
--
-- See ../../AGENTS.md for the full function-by-function mapping table and
-- the explicitly flagged public-knowledge assumptions (AddTargetBone's
-- scope, RemoveTargetEntity/RemoveTargetModel's optional second argument,
-- AddBoxZone's length/width axis convention, canInteract arity,
-- AddComboZone's zone-definition shape, AddEntityZone's static-snapshot
-- semantics, RaycastCamera's return order, AllowTargeting/DisableTarget's
-- boolean polarities).

Target = Target or {}

-- `exports('name', fn)` only ever wires up the event FiveM's own export
-- resolution queries for THIS resource's real name (GetCurrentResourceName())
-- -- `provide 'qb-target'` in fxmanifest.lua only satisfies OTHER resources'
-- `dependency 'qb-target'` checks, it does NOT make exports['qb-target']:Fn()
-- resolve here. That resolution is, under the hood, itself just an event:
-- exports('name', fn) is sugar for registering
-- `__cfx_export_<resource>_<name>` with a callback that hands `fn` to the
-- caller-supplied setter. Registering that same event under the STRING
-- "qb-target" instead of this resource's real name is what actually makes
-- exports['qb-target']:Fn() reach code running here.
local function provideExport(providedResource, exportName, func)
    AddEventHandler(('__cfx_export_%s_%s'):format(providedResource, exportName), function(setCB)
        setCB(func)
    end)
end

-- A callback passed through an FXServer export boundary is represented as a
-- table with an __call metamethod, not a Lua value whose type is "function".
-- Banking's `action = function() OpenBank() end` reaches this bridge in that
-- form, so accepting only plain functions made its visible target option a
-- silent no-op when selected.
local function isCallable(value)
    if type(value) == 'function' then return true end
    local mt = type(value) == 'table' and getmetatable(value) or nil
    return mt ~= nil and mt.__call ~= nil
end

local function dispatchLegacy(option, entity)
    if isCallable(option.action) then
        option.action(entity)
    elseif option.event then
        if option.type == 'server' then
            TriggerServerEvent(option.event, entity)
        else
            TriggerEvent(option.event, entity)
        end
    end
end

-- job/gang/item/jobType enforcement -- qbtarget's own native resolver
-- deliberately never interprets these fields (framework-agnostic by design,
-- see ../../docs.md's "Opaque fields" section); this is the compat SHIM's
-- job, done here rather than in qbtarget's core. qb-core now exists in this
-- repo (resources/[test]/qbcore, `provide 'qb-core'`) -- pcall-guarded so
-- this shim still degrades to the old unenforced-with-warning behaviour if
-- it's ever dropped into a server with no qb-core identity running at all.
-- Semantics ported verbatim from real qb-target's JobCheck/JobTypeCheck/
-- GangCheck/CitizenCheck (client.lua's "QBCore init" CreateThread).
local QBCore, PlayerData

local function refreshPlayerData()
    if not QBCore then return end
    local ok, data = pcall(QBCore.Functions.GetPlayerData)
    if ok and data then PlayerData = data end
end

CreateThread(function()
    local ok, core = pcall(function() return exports['qb-core']:GetCoreObject({ 'Functions' }) end)
    if not ok or not core then return end
    QBCore = core
    refreshPlayerData()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', refreshPlayerData)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() PlayerData = nil end)
-- Real qb-target itself listens for this exact event the same way to keep its
-- own PlayerData in sync -- same reasoning modules/jobs/server.lua now fires
-- it (see that file's comment) for every legacy job/gang consumer.
RegisterNetEvent('QBCore:Client:OnPlayerUpdated', function(key, val)
    if not PlayerData then return end
    if key == 'job' then PlayerData.job = val
    elseif key == 'gang' then PlayerData.gang = val
    elseif key == 'all' then PlayerData = val end
end)

local function jobCheck(job)
    if not PlayerData then return false end
    if type(job) == 'table' then
        local required = job[PlayerData.job.name]
        return required ~= nil and PlayerData.job.grade.level >= required
    end
    return job == 'all' or job == PlayerData.job.name
end

local function jobTypeCheck(jobType)
    if not PlayerData then return false end
    if type(jobType) == 'table' then return jobType[PlayerData.job.type] ~= nil end
    return jobType == 'all' or jobType == PlayerData.job.type
end

local function gangCheck(gang)
    if not PlayerData then return false end
    if type(gang) == 'table' then
        local required = gang[PlayerData.gang.name]
        return required ~= nil and PlayerData.gang.grade.level >= required
    end
    return gang == 'all' or gang == PlayerData.gang.name
end

local function citizenCheck(citizenid)
    if not PlayerData then return false end
    if type(citizenid) == 'table' then return citizenid[PlayerData.citizenid] end
    return citizenid == PlayerData.citizenid
end

-- Wraps a translated option's canInteract with the enforcement chain above --
-- ALL supplied filters must pass, exactly like real qb-target's CheckOptions,
-- before falling through to the option's own canInteract (if any). If QBCore
-- never became available at all, every filter check is skipped (never denies)
-- so the option still shows -- same graceful, warned degradation as before.
local function makeCanInteract(option)
    local hasFilter = option.job or option.excludejob or option.jobType or option.excludejobType
        or option.gang or option.excludegang or option.item or option.citizenid

    if hasFilter and not QBCore then
        print(('[qb-target-bridge] WARNING: option %q sets a job/gang/item/jobType filter but no qb-core '
            .. 'identity resource is running -- the option will be shown to EVERYONE unless it supplies its '
            .. 'own canInteract.'):format(tostring(option.label)))
    end

    return function(entity, distance, data)
        if QBCore then
            if option.job and not jobCheck(option.job) then return false end
            if option.excludejob and jobCheck(option.excludejob) then return false end
            if option.jobType and not jobTypeCheck(option.jobType) then return false end
            if option.excludejobType and jobTypeCheck(option.excludejobType) then return false end
            if option.gang and not gangCheck(option.gang) then return false end
            if option.excludegang and gangCheck(option.excludegang) then return false end
            if option.item and not QBCore.Functions.HasItem(option.item) then return false end
            if option.citizenid and not citizenCheck(option.citizenid) then return false end
        end
        if isCallable(option.canInteract) then
            -- Passed through as-is, NOT re-wrapped to real qb-target's own
            -- contract: qbtarget's resolver always calls this with
            -- (entity, distance, data), but real qb-target only ever calls
            -- canInteract(entity) -- one argument. A ported canInteract that
            -- reads its 2nd/3rd parameter sees qbtarget's shape, not
            -- qb-target's. See this file's header and ../../AGENTS.md for
            -- why this divergence is intentionally NOT fixed here.
            return option.canInteract(entity, distance, data)
        end
        return true
    end
end

-- Translates qb-target's option shape ({type?, event?, icon, label, action?,
-- canInteract?, item?, job?, gang?, jobType?, distance?}) into qbtarget's own
-- QBTargetOption shape.
local function translateOptions(options)
    assert(type(options) == 'table', 'qb-target target options must be a table.')

    local translated = {}

    for i, option in ipairs(options) do
        translated[i] = {
            label = option.label,
            icon = option.icon,
            distance = option.distance,
            canInteract = makeCanInteract(option),
            onSelect = function(entity)
                dispatchLegacy(option, entity)
            end,
        }
    end

    return translated
end

local zonesByName = {}

-- Shared translation helpers, factored out of AddBoxZone/AddCircleZone/
-- AddPolyZone below so AddComboZone (a name-less, options-sharing group of
-- sub-zones) can reuse the exact same qb-target->qbtarget shape logic
-- instead of duplicating it. These do NOT touch zonesByName -- only the
-- public Add*Zone wrappers below do that, since a combo zone's bookkeeping
-- differs (one name maps to several ids, see AddComboZone).
local function makeBoxZone(coords, length, width, boxOpts, targetOptions)
    boxOpts = boxOpts or {}
    targetOptions = targetOptions or {}

    local minZ = boxOpts.minZ or (coords.z - 2.0)
    local maxZ = boxOpts.maxZ or (coords.z + 2.0)

    return Target.addBoxZone({
        -- The box's z-center is the midpoint of [minZ, maxZ], not coords.z
        -- itself -- an explicit boxOpts.minZ/maxZ can put that midpoint well
        -- above or below coords.z.
        coords = { x = coords.x, y = coords.y, z = (minZ + maxZ) / 2 },
        -- qb-target's "length" runs along the zone's heading, "width" across
        -- it (medium-confidence public-knowledge assumption, see AGENTS.md).
        size = vector3(width, length, maxZ - minZ),
        rotation = boxOpts.heading or 0.0,
        options = translateOptions(targetOptions.options),
        distance = targetOptions.distance,
        debug = boxOpts.debugPoly,
        drawSprite = boxOpts.drawSprite,
    })
end

local function makeCircleZone(coords, radius, boxOpts, targetOptions)
    boxOpts = boxOpts or {}
    targetOptions = targetOptions or {}

    return Target.addSphereZone({
        coords = coords,
        radius = radius,
        options = translateOptions(targetOptions.options),
        distance = targetOptions.distance,
        debug = boxOpts.debugPoly,
        drawSprite = boxOpts.drawSprite,
    })
end

local function makePolyZone(points, boxOpts, targetOptions)
    boxOpts = boxOpts or {}
    targetOptions = targetOptions or {}

    return Target.addPolyZone({
        points = points,
        minZ = boxOpts.minZ,
        maxZ = boxOpts.maxZ,
        thickness = boxOpts.thickness,
        options = translateOptions(targetOptions.options),
        distance = targetOptions.distance,
        debug = boxOpts.debugPoly,
        drawSprite = boxOpts.drawSprite,
    })
end

local function AddBoxZone(name, coords, length, width, boxOpts, targetOptions)
    local id = makeBoxZone(coords, length, width, boxOpts, targetOptions)
    zonesByName[name] = id
    return id
end

local function AddCircleZone(name, coords, radius, boxOpts, targetOptions)
    local id = makeCircleZone(coords, radius, boxOpts, targetOptions)
    zonesByName[name] = id
    return id
end

local function AddPolyZone(name, points, boxOpts, targetOptions)
    local id = makePolyZone(points, boxOpts, targetOptions)
    zonesByName[name] = id
    return id
end

-- AddComboZone: real qb-target combines several zone shape definitions
-- (Box/Circle/Poly) under one shared `targetOptions`, all filed under one
-- logical `name`. Public-knowledge assumption (medium confidence, see
-- AGENTS.md's assumptions list): each element of `zones` is a table shaped
-- like {type = "Box"|"Circle"|"Poly", coords, length?, width?, radius?,
-- points?, boxOpts?}, and every sub-zone shares the SAME `targetOptions`
-- (qb-target's combo zones exist to attach one option set to an irregular
-- area built from multiple primitive shapes, not to vary options per shape).
-- qbtarget has no native combo-zone concept, so this registers one qbtarget
-- zone per sub-zone definition (reusing makeBoxZone/makeCircleZone/
-- makePolyZone above) and returns an array of the resulting ids; `name`
-- is bookkept in zonesByName as that whole array so RemoveZone(name) tears
-- every sub-zone down together.
local function AddComboZone(name, zones, targetOptions)
    assert(type(zones) == 'table', 'AddComboZone requires an array of zone definitions.')

    local ids = {}
    for i, zoneDef in ipairs(zones) do
        local id
        if zoneDef.type == 'Circle' then
            id = makeCircleZone(zoneDef.coords, zoneDef.radius, zoneDef.boxOpts, targetOptions)
        elseif zoneDef.type == 'Poly' then
            id = makePolyZone(zoneDef.points, zoneDef.boxOpts, targetOptions)
        else
            -- Default/'Box' -- qb-target's most common combo-zone shape.
            id = makeBoxZone(zoneDef.coords, zoneDef.length, zoneDef.width, zoneDef.boxOpts, targetOptions)
        end
        ids[i] = id
    end

    zonesByName[name] = ids
    return ids
end

-- AddEntityZone: real qb-target's per-entity STATIC zone variant. Distinct
-- from AddTargetEntity (Target.addEntity, which attaches options directly to
-- the entity handle and therefore tracks it as it moves) -- AddEntityZone
-- instead snapshots the entity's position at registration time into a plain
-- box zone (public-knowledge assumption, medium confidence: qb-target's own
-- docs describe this as "target a zone around an entity's location", a
-- separate mechanism from AddTargetEntity). This is the intended home for
-- the functionality ../../PolyZone/EntityZone.lua deliberately left
-- unimplemented, per that file's own header comment. boxOpts may supply
-- length/width/heading exactly like AddBoxZone; absent length/width this
-- defaults to a small 1.5x1.5 box around the entity, matching qb-target's
-- typical "immediate vicinity of a static prop" usage.
local function AddEntityZone(name, entity, boxOpts, targetOptions)
    boxOpts = boxOpts or {}
    local coords = GetEntityCoords(entity)
    local length = boxOpts.length or 1.5
    local width = boxOpts.width or 1.5
    return AddBoxZone(name, coords, length, width, boxOpts, targetOptions)
end

local function AddTargetEntity(entity, targetOptions)
    targetOptions = targetOptions or {}
    return Target.addEntity(entity, translateOptions(targetOptions.options), targetOptions.distance)
end

local function AddTargetModel(models, targetOptions)
    targetOptions = targetOptions or {}
    return Target.addModel(models, translateOptions(targetOptions.options), targetOptions.distance)
end

-- Mapped as a GLOBAL bone match (any entity, any type, with a matching bone)
-- -- medium-confidence assumption, see ../../AGENTS.md.
local function AddTargetBone(bones, targetOptions)
    targetOptions = targetOptions or {}
    return Target.addGlobalBone(bones, translateOptions(targetOptions.options), targetOptions.distance)
end

local function addGlobal(entityType)
    return function(targetOptions)
        targetOptions = targetOptions or {}
        return Target.addGlobalType(entityType, translateOptions(targetOptions.options), targetOptions.distance)
    end
end

local AddGlobalPed = addGlobal('ped')
local AddGlobalVehicle = addGlobal('vehicle')
local AddGlobalObject = addGlobal('object')
local AddGlobalPlayer = addGlobal('player')

-- qb-target's exact semantics for the optional `target` (single-option
-- label) argument aren't confidently known from public knowledge alone (see
-- AGENTS.md's assumptions list). Rather than guess and risk silently
-- removing the wrong option, this only supports the unambiguous case (no
-- `target` -- remove everything on the entity) and loudly refuses the rest.
local function RemoveTargetEntity(entity, target)
    if not target then
        return Target.removeEntity(entity)
    end

    print(('[qb-target-bridge] RemoveTargetEntity(entity, target) with a specific target label is not '
        .. 'supported -- call RemoveTargetEntity(entity) to remove everything on this entity. (target=%s)')
        :format(tostring(target)))
    return false
end

local function RemoveTargetModel(models, target)
    if not target then
        return Target.removeModel(models)
    end

    print(('[qb-target-bridge] RemoveTargetModel(models, target) with a specific target label is not '
        .. 'supported -- call RemoveTargetModel(models) to remove everything on these models. (target=%s)')
        :format(tostring(target)))
    return false
end

-- qb-target zones are name-keyed; qbtarget's own are id-based -- zonesByName
-- is this bridge's own translation state between the two. A combo zone
-- (AddComboZone above) stores an ARRAY of ids under its name instead of a
-- single one, so this removes every id in that array together.
local function RemoveZone(name)
    local id = zonesByName[name]
    if not id then return false end

    zonesByName[name] = nil

    if type(id) == 'table' then
        local removedAny = false
        for _, zoneId in ipairs(id) do
            if Target.removeZone(zoneId) then removedAny = true end
        end
        return removedAny
    end

    return Target.removeZone(id)
end

local function removeGlobal(entityType)
    return function(id) return Target.removeGlobalType(entityType, id) end
end

local RemoveGlobalPed = removeGlobal('ped')
local RemoveGlobalVehicle = removeGlobal('vehicle')
local RemoveGlobalObject = removeGlobal('object')
local RemoveGlobalPlayer = removeGlobal('player')

-- Mirrors AddTargetBone's own "global bone match" mapping (Target.addGlobalBone
-- / removeGlobalBone), NOT Target.removeGlobalType -- "bone" here refers to
-- the bone-name registration, unrelated to the ped/vehicle/object/player
-- global-TYPE registrations above.
local function RemoveTargetBone(id)
    return Target.removeGlobalBone(id)
end

-- qb-target bundles a small ped spawner that resources such as qb-taxijob use
-- through exports['qb-target']:SpawnPed(...). Keep its state in this compat
-- layer rather than adding ped lifecycle concerns to qbtarget's native API.
-- Each spawned ped also remembers the exact target registration created for
-- it so explicit removal and resource-stop cleanup don't leave stale entity or
-- model registrations behind.
local spawnedPedConfigs = {}
local spawnedPedOwners = {}
local spawnedPedRecords = {}
local nextSpawnedPedConfig = 0

local function applyPedConfig(ped, data)
    if data.freeze then FreezeEntityPosition(ped, true) end
    if data.invincible then SetEntityInvincible(ped, true) end
    if data.blockevents then SetBlockingOfNonTemporaryEvents(ped, true) end

    if data.animDict and data.anim then
        RequestAnimDict(data.animDict)
        while not HasAnimDictLoaded(data.animDict) do Wait(0) end
        TaskPlayAnim(ped, data.animDict, data.anim, 8.0, 0, -1, data.flag or 1, 0, false, false, false)
    end

    if data.scenario then
        SetPedCanPlayAmbientAnims(ped, true)
        TaskStartScenarioInPlace(ped, data.scenario, 0, true)
    end

    if data.pedrelations then
        local relations = data.pedrelations
        assert(type(relations.groupname) == 'string', 'SpawnPed pedrelations.groupname must be a string.')

        local groupHash = joaat(relations.groupname)
        if not DoesRelationshipGroupExist(groupHash) then AddRelationshipGroup(relations.groupname) end
        SetPedRelationshipGroupHash(ped, groupHash)

        if relations.toplayer then
            SetRelationshipBetweenGroups(relations.toplayer, groupHash, joaat('PLAYER'))
        end
        if relations.toowngroup then
            SetRelationshipBetweenGroups(relations.toowngroup, groupHash, groupHash)
        end
    end

    if data.weapon then
        if type(data.weapon.name) == 'string' then data.weapon.name = joaat(data.weapon.name) end
        if IsWeaponValid(data.weapon.name) then
            SetCanPedEquipWeapon(ped, data.weapon.name, true)
            GiveWeaponToPed(ped, data.weapon.name, data.weapon.ammo, data.weapon.hidden or false, true)
            SetPedCurrentWeaponVisible(ped, not data.weapon.hidden or false, true)
        end
    end

    local targetRegistrationId
    if data.target then
        if data.target.useModel then
            targetRegistrationId = AddTargetModel(data.model, data.target)
        else
            targetRegistrationId = AddTargetEntity(ped, data.target)
        end
    end

    if isCallable(data.action) then data.action(data) end
    return targetRegistrationId
end

local function spawnOnePed(data, owner, configIndex)
    assert(type(data) == 'table', 'SpawnPed entries must be tables.')
    assert(data.model ~= nil, 'SpawnPed requires a model.')
    assert(data.coords ~= nil, 'SpawnPed requires coords.')

    if type(data.model) == 'string' then data.model = joaat(data.model) end
    RequestModel(data.model)
    while not HasModelLoaded(data.model) do Wait(0) end

    local z = data.minusOne and (data.coords.z - 1.0) or data.coords.z
    local ped = CreatePed(0, data.model, data.coords.x, data.coords.y, z, data.coords.w or 0.0,
        data.networked or false, true)
    local targetRegistrationId = applyPedConfig(ped, data)

    data.currentpednumber = ped
    spawnedPedRecords[ped] = {
        configIndex = configIndex,
        data = data,
        owner = owner,
        targetRegistrationId = targetRegistrationId,
        targetUsesModel = data.target and data.target.useModel == true,
    }
    return ped
end

local function addSpawnedPedConfig(data, owner)
    nextSpawnedPedConfig = nextSpawnedPedConfig + 1
    local configIndex = nextSpawnedPedConfig
    spawnedPedConfigs[configIndex] = data
    spawnedPedOwners[configIndex] = owner

    if data.spawnNow then spawnOnePed(data, owner, configIndex) end
end

local function SpawnPed(data)
    assert(type(data) == 'table', 'SpawnPed requires a ped config or array of ped configs.')
    local owner = GetInvokingResource() or GetCurrentResourceName()
    local key, value = next(data)

    -- Match qb-target's distinction between one string-keyed ped config and
    -- an array/map of numeric-keyed ped configs.
    if type(value) == 'table' and type(key) ~= 'string' then
        for _, pedConfig in pairs(data) do addSpawnedPedConfig(pedConfig, owner) end
    else
        addSpawnedPedConfig(data, owner)
    end
end

local function removeSpawnedPedEntity(ped)
    local record = spawnedPedRecords[ped]
    if record and record.targetRegistrationId then
        if record.targetUsesModel then
            Target.removeModel(record.data.model, record.targetRegistrationId)
        else
            Target.removeEntity(ped, record.targetRegistrationId)
        end
    end

    DeletePed(ped)
    if record then
        record.data.currentpednumber = 0
        spawnedPedRecords[ped] = nil
    end
end

local function RemoveSpawnedPed(peds)
    if type(peds) == 'table' then
        for configIndex, ped in pairs(peds) do
            removeSpawnedPedEntity(ped)
            if spawnedPedConfigs[configIndex] then
                spawnedPedConfigs[configIndex].currentpednumber = 0
            end
        end
    elseif type(peds) == 'number' then
        removeSpawnedPedEntity(peds)
    end
end

-- Real qb-target removes its configured peds when it stops. Because this
-- resource also serves other resources directly, additionally clean up only
-- the peds belonging to an individual caller when that caller stops.
AddEventHandler('onClientResourceStop', function(resource)
    local removeAll = resource == GetCurrentResourceName()
    local peds = {}
    for ped, record in pairs(spawnedPedRecords) do
        if removeAll or record.owner == resource then peds[#peds + 1] = ped end
    end
    for _, ped in ipairs(peds) do removeSpawnedPedEntity(ped) end

    for configIndex, owner in pairs(spawnedPedOwners) do
        if removeAll or owner == resource then
            spawnedPedConfigs[configIndex] = nil
            spawnedPedOwners[configIndex] = nil
        end
    end
end)

-- RaycastCamera: real qb-target's manual raycast-from-camera helper.
-- qbtarget's own primitive, QB.raycast.fromCamera (qblib), returns
-- (hit, coords, entityHit, surfaceNormal). Public-knowledge assumption
-- (medium confidence, see AGENTS.md): real qb-target's RaycastCamera instead
-- returns (entityHit, endCoords, hit, surfaceNormal) -- FiveM's own
-- GetShapeTestResult field order minus the leading status code -- so this
-- wrapper reorders qbtarget's own return values to match rather than
-- exposing qbtarget's shape under qb-target's name.
local function RaycastCamera()
    local hit, coords, entityHit, surfaceNormal = QB.raycast.fromCamera(Config.target.maxDistance)
    return entityHit, coords, hit, surfaceNormal
end

-- AllowTargeting(state): real qb-target's usual enable/disable export --
-- state == true enables targeting, a direct passthrough to Target.setEnabled.
local function AllowTargeting(state)
    return Target.setEnabled(state)
end

-- DisableTarget(state): alternate qb-target export name seen in some forks,
-- with INVERTED polarity vs AllowTargeting -- state == true means targeting
-- should be turned OFF (public-knowledge assumption, low confidence; kept as
-- the deliberate inverse of AllowTargeting so the two names can coexist
-- without one silently overriding the other's sense, mirroring how
-- ox-target.lua's disableTargeting inverts against Target.setEnabled).
local function DisableTarget(state)
    return Target.setEnabled(not state)
end

for exportName, func in pairs({
    AddBoxZone = AddBoxZone,
    AddCircleZone = AddCircleZone,
    AddPolyZone = AddPolyZone,
    AddComboZone = AddComboZone,
    AddEntityZone = AddEntityZone,
    AddTargetEntity = AddTargetEntity,
    AddTargetModel = AddTargetModel,
    AddTargetBone = AddTargetBone,
    AddGlobalPed = AddGlobalPed,
    AddGlobalVehicle = AddGlobalVehicle,
    AddGlobalObject = AddGlobalObject,
    AddGlobalPlayer = AddGlobalPlayer,
    RemoveTargetEntity = RemoveTargetEntity,
    RemoveTargetModel = RemoveTargetModel,
    RemoveZone = RemoveZone,
    RemoveGlobalPed = RemoveGlobalPed,
    RemoveGlobalVehicle = RemoveGlobalVehicle,
    RemoveGlobalObject = RemoveGlobalObject,
    RemoveGlobalPlayer = RemoveGlobalPlayer,
    RemoveTargetBone = RemoveTargetBone,
    SpawnPed = SpawnPed,
    RemoveSpawnedPed = RemoveSpawnedPed,
    RaycastCamera = RaycastCamera,
    AllowTargeting = AllowTargeting,
    DisableTarget = DisableTarget,
}) do
    provideExport('qb-target', exportName, func)
end
