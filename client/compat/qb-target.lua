-- Drop-in compatibility bridge: translates the real, public qb-target API
-- into calls against Target.* directly (same resource -- no exports.kora_target:
-- round trip needed). Scripts written against exports['qb-target']:... keep
-- working unmodified even though this resource is literally named
-- "qbtarget", not "qb-target" -- see provideExport below.
--
-- The compatibility contracts in this file are audited against current
-- qbcore-framework/qb-target, including label-addressed mutation, PolyZone
-- object inputs, moving EntityZone containment, raycast return order, and the
-- distinct AllowTargeting/DisableTarget semantics.

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
local provideExport = Kora.compat.provideExport

-- A callback passed through an FXServer export boundary is represented as a
-- table with an __call metamethod, not a Lua value whose type is "function".
-- Banking's `action = function() OpenBank() end` reaches this bridge in that
-- form, so accepting only plain functions made its visible target option a
-- silent no-op when selected.
local isCallable = Kora.util.isCallable

local function dispatchLegacy(option, entity)
    local data = {}
    for k, v in pairs(option) do data[k] = v end
    data.entity = entity
    if entity and entity ~= 0 then data.coords = GetEntityCoords(entity) end

    if isCallable(option.action) then
        option.action(entity)
    elseif option.event then
        if option.type == 'server' then
            TriggerServerEvent(option.event, data)
        elseif option.type == 'command' then
            ExecuteCommand(option.event)
        elseif option.type == 'qbcommand' then
            TriggerServerEvent('QBCore:CallCommand', option.event, data)
        else
            TriggerEvent(option.event, data)
        end
    else
        error(('No trigger setup for qb-target option %q'):format(tostring(option.label)))
    end
end

-- job/gang/item/jobType enforcement -- kora_target's own native resolver
-- deliberately never interprets these fields (framework-agnostic by design,
-- see ../../docs.md's "Opaque fields" section); this is the compat SHIM's
-- job, done here rather than in kora_target's core. Read kora_core directly, while
-- retaining the optional-framework behavior and legacy zero-based grades.
-- Semantics ported verbatim from real qb-target's JobCheck/JobTypeCheck/
-- GangCheck/CitizenCheck (client.lua's "QBCore init" CreateThread).
local coreAvailable, PlayerData

local function refreshPlayerData()
    local ok, data = pcall(function()
        return exports.kora_core:toLegacyPlayerData(exports.kora_core:getPlayerData())
    end)
    if ok then
        coreAvailable = true
        PlayerData = data
    end
end

CreateThread(refreshPlayerData)

-- Read-only accessor for client/compat/ox-target.lua's `groups` check, which
-- shares this file's kora_core PlayerData tracking instead of duplicating it.
function Target._playerData()
    return coreAvailable, PlayerData
end

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

    if hasFilter and not coreAvailable then
        print(('[qb-target-bridge] WARNING: option %q sets a job/gang/item/jobType filter but no qbcore '
            .. 'identity resource is running -- the option will be shown to EVERYONE unless it supplies its '
            .. 'own canInteract.'):format(tostring(option.label)))
    end

    return function(entity, distance, data)
        if coreAvailable then
            if option.job and not jobCheck(option.job) then return false end
            if option.excludejob and jobCheck(option.excludejob) then return false end
            if option.jobType and not jobTypeCheck(option.jobType) then return false end
            if option.excludejobType and jobTypeCheck(option.excludejobType) then return false end
            if option.gang and not gangCheck(option.gang) then return false end
            if option.excludegang and gangCheck(option.excludegang) then return false end
            if option.item and not exports.kora_inventory:HasItem(option.item) then return false end
            if option.citizenid and not citizenCheck(option.citizenid) then return false end
        end
        if isCallable(option.canInteract) then
            -- Current qb-target passes this exact three-argument tuple.
            return option.canInteract(entity, distance, data)
        end
        return true
    end
end

-- Translates qb-target's option shape ({type?, event?, icon, label, action?,
-- canInteract?, item?, job?, gang?, jobType?, distance?}) into kora_target's own
-- QBTargetOption shape.
local function translateOptions(options)
    assert(type(options) == 'table', 'qb-target target options must be a table.')

    local translated = {}

    local ordered = {}
    for _, option in pairs(options) do ordered[#ordered + 1] = option end
    table.sort(ordered, function(a, b)
        if a.num and b.num then return a.num < b.num end
        if a.num then return true end
        if b.num then return false end
        return tostring(a.label) < tostring(b.label)
    end)

    for i, option in ipairs(ordered) do
        if option.required_item and not option.item then option.item = option.required_item end
        translated[i] = {
            label = option.label,
            icon = option.icon,
            bones = option.bones,
            distance = option.distance,
            canInteract = makeCanInteract(option),
            onSelect = function(entity)
                dispatchLegacy(option, entity)
            end,
            data = option,
        }
    end

    return translated
end

local function toArray(value)
    if type(value) == 'table' then return value end
    return { value }
end

local function labelSet(labels)
    if labels == nil then return nil end
    if type(labels) == 'table' then
        local set = {}
        for _, label in pairs(labels) do set[label] = true end
        return set
    end
    return { [labels] = true }
end

-- qb-target stores one option map per entity/model/bone/global type and merges
-- repeated Add* calls by label. kora_target's native model stores immutable
-- registration groups instead. This ledger recreates the label-addressable
-- view and uses Target._replaceOptions for exact remove/update behavior.
local legacyRecords = {}
local legacyIndex = {
    entity = {}, model = {}, bone = {}, globalType = {}, globalPlayer = {},
}

local function indexKey(kind, key)
    local index = legacyIndex[kind]
    local set = index[key]
    if not set then set = {}; index[key] = set end
    return set
end

local function unindexRecord(record)
    local index = legacyIndex[record.kind]
    local set = index and index[record.key]
    if set then
        set[record.id] = nil
        if next(set) == nil then index[record.key] = nil end
    end
    legacyRecords[record.id] = nil
end

local function destroyRecord(record)
    if not record then return end
    unindexRecord(record)
    Target.destroyRegistration(record.id)
end

local function optionsMap(options, defaultDistance)
    local map = {}
    for _, option in pairs(options or {}) do
        if option.required_item and not option.item then option.item = option.required_item end
        if not option.distance or (defaultDistance and option.distance > defaultDistance) then
            option.distance = defaultDistance or Config.target.defaultOptionDistance
        end
        map[option.label] = option
    end
    return map
end

local function legacyDistance(value)
    return value or Config.target.legacyMaxDistance or 7.0
end

local function refreshRecord(record)
    if not Target.registrations[record.id] then unindexRecord(record); return false end
    if next(record.options) == nil then destroyRecord(record); return false end
    return Target._replaceOptions(record.id, translateOptions(record.options), record.distance)
end

local function removeIndexed(kind, key, labels)
    local set = legacyIndex[kind][key]
    if not set then return false end
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    local wanted, removed = labelSet(labels), false
    for _, id in ipairs(ids) do
        local record = legacyRecords[id]
        if record then
            if not wanted then
                destroyRecord(record)
                removed = true
            else
                for label in pairs(wanted) do
                    if record.options[label] ~= nil then record.options[label] = nil; removed = true end
                end
                refreshRecord(record)
            end
        end
    end
    return removed
end

local function addIndexed(kind, key, id, options, distance)
    local mapped = optionsMap(options, distance)
    -- Upstream's label map overwrites an earlier option with the same label.
    for label in pairs(mapped) do removeIndexed(kind, key, label) end
    local record = {
        id = id, kind = kind, key = key, options = mapped, distance = distance,
        owner = GetInvokingResource() or GetCurrentResourceName(),
    }
    legacyRecords[id] = record
    indexKey(kind, key)[id] = true
    return record
end

local function getIndexed(kind, key, label)
    local set = legacyIndex[kind][key]
    if not set then return nil end
    for id in pairs(set) do
        local record = legacyRecords[id]
        if record and record.options[label] then return record.options[label] end
    end
end

local function updateIndexed(kind, key, label, data)
    local set = legacyIndex[kind][key]
    if not set then return false end
    local fallback
    for id in pairs(set) do
        local record = legacyRecords[id]
        if record then
            fallback = fallback or record
            if record.options[label] then
                record.options[label] = data
                refreshRecord(record)
                return true
            end
        end
    end
    -- Upstream setters are direct map assignments and therefore also add a
    -- previously absent label when the target entry already exists.
    if not fallback then return false end
    fallback.options[label] = data
    refreshRecord(fallback)
    return true
end

local function entityKey(entity)
    if NetworkGetEntityIsNetworked and NetworkGetEntityIsNetworked(entity) then
        return NetworkGetNetworkIdFromEntity(entity)
    end
    return entity
end

local function modelKey(model)
    return type(model) == 'string' and joaat(model) or model
end

local zonesByName = {}
local RemoveZone

-- qb-target returns/stores PolyZone objects, while kora_target's native zone API
-- returns registration ids. This lightweight object preserves the observable
-- qb-target contract (`isPointInside`, `destroy`, `targetoptions`, shape data)
-- and owns the native registrations behind it.
local function legacyZone(name, kind, ids, targetOptions, fields)
    local zone = fields or {}
    zone.name, zone.kind, zone.ids = name, kind, ids
    zone.targetoptions = targetOptions
    zone.owner = GetInvokingResource() or GetCurrentResourceName()
    zone.destroyed = false
    function zone:isPointInside(point)
        if self.destroyed then return false end
        for _, id in ipairs(self.ids) do
            local registration = Target.registrations[id]
            if registration and registration.zoneHandle.contains(point) then return true end
        end
        return false
    end
    zone.contains = function(point) return zone:isPointInside(point) end
    function zone:destroy()
        if self.destroyed then return end
        self.destroyed = true
        if zonesByName[self.name] == self then zonesByName[self.name] = nil end
        for _, id in ipairs(self.ids) do Target.destroyRegistration(id) end
    end
    zonesByName[name] = zone
    return zone
end

-- In a real server the manifest loads the same PolyZone classes upstream
-- qb-target loads. Preserve those actual returned objects (and therefore all
-- of their public methods) while attaching kora_target registration lifecycle.
-- The plain-Lua smoke harness has no PolyZone globals and exercises the exact
-- standalone predicates below instead.
local function trackPolyZoneObject(name, kind, zone, targetOptions, distance, spriteCoords, drawSprite, bounds, targetEntity)
    local id = Target._addCustomZone(function(point) return zone:isPointInside(point) end,
        translateOptions(optionsMap(targetOptions.options, distance)), distance, spriteCoords, drawSprite, bounds, targetEntity)
    local shapeDestroy = zone.destroy
    zone.name, zone.kind, zone.ids = name, kind, { id }
    zone.targetoptions = targetOptions
    zone.owner = GetInvokingResource() or GetCurrentResourceName()
    zone._qbtargetDestroyed = false
    zone.destroy = function(self)
        if self._qbtargetDestroyed then return end
        self._qbtargetDestroyed = true
        if zonesByName[self.name] == self then zonesByName[self.name] = nil end
        if Target.registrations[id] then Target.destroyRegistration(id) end
        if isCallable(shapeDestroy) then shapeDestroy(self) end
    end
    zonesByName[name] = zone
    return zone
end

-- Shared translation helpers, factored out of AddBoxZone/AddCircleZone/
-- AddPolyZone below so AddComboZone (a name-less, options-sharing group of
-- sub-zones) can reuse the exact same qb-target->kora_target shape logic
-- instead of duplicating it. These do NOT touch zonesByName -- only the
-- public Add*Zone wrappers below do that, since a combo zone's bookkeeping
-- differs (one name maps to several ids, see AddComboZone).
-- Broad-phase bounds for the PolyZone-object path (trackPolyZoneObject).
-- Derived from the CALLER'S OWN arguments rather than read back off the
-- constructed PolyZone object: PolyZone's `scale`/`offset` grow a box beyond
-- the length/width it was created with, and an AABB that missed that growth
-- would silently hide the zone from the resolver. When those are present the
-- bound is simply not derived and the zone stays in the unindexed scan --
-- slower, never wrong. See Target._zoneBounds in client/state.lua.
local function legacyBoxBounds(center, length, width, boxOpts)
    if boxOpts.scale or boxOpts.offset then return nil end
    -- A heading rotates the rectangle in place, so the circumradius of its
    -- half-extents encloses it at ANY heading without needing to know one.
    local halfLength, halfWidth = length / 2, width / 2
    local extent = math.sqrt(halfLength * halfLength + halfWidth * halfWidth)

    return Target._zoneBounds(center.x, center.y, extent, extent, boxOpts.minZ, boxOpts.maxZ)
end

local function legacyCircleBounds(center, radius, boxOpts)
    -- PolyZone's CircleZone is an infinite vertical cylinder unless useZ.
    local minZ, maxZ
    if boxOpts.useZ == true then minZ, maxZ = center.z - radius, center.z + radius end

    return Target._zoneBounds(center.x, center.y, radius, radius, minZ, maxZ)
end

local function legacyPolyBounds(points, boxOpts)
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    for i = 1, #points do
        local point = points[i]
        if point.x < minX then minX = point.x end
        if point.x > maxX then maxX = point.x end
        if point.y < minY then minY = point.y end
        if point.y > maxY then maxY = point.y end
    end
    if minX > maxX then return nil end

    return Target._zoneBounds((minX + maxX) / 2, (minY + maxY) / 2,
        (maxX - minX) / 2, (maxY - minY) / 2, boxOpts.minZ, boxOpts.maxZ)
end

local function comboChildBounds(zone)
    if zone.type == 'box' and zone.coords and zone.length and zone.width then
        return legacyBoxBounds(zone.coords, zone.length, zone.width, zone.options or {})
    end
    if zone.type == 'poly' and zone.points then
        return legacyPolyBounds(zone.points, { minZ = zone.minZ, maxZ = zone.maxZ })
    end
    -- CircleZone exposes live setCenter/setRadius methods, so indexing its
    -- current extent would become stale after a mutation. Keep it unbounded.
    return nil
end

local function boxScaleOffset(boxOpts)
    local scale = boxOpts.scale or { 1.0, 1.0, 1.0 }
    local offset = boxOpts.offset or { 0.0, 0.0, 0.0 }
    assert(#scale == 3 or #scale == 6, 'BoxZone scale must contain 3 or 6 values')
    assert(#offset == 3 or #offset == 6, 'BoxZone offset must contain 3 or 6 values')
    if #scale == 3 then scale = { scale[1], scale[1], scale[2], scale[2], scale[3], scale[3] } end
    if #offset == 3 then offset = { offset[1], offset[1], offset[2], offset[2], offset[3], offset[3] } end
    return scale, offset
end

local function makeBoxZone(coords, length, width, boxOpts, targetOptions)
    boxOpts = boxOpts or {}
    targetOptions = targetOptions or {}
    local distance = legacyDistance(targetOptions.distance)
    local mapped = optionsMap(targetOptions.options, distance)

    -- PolyZone boxes are 2D when minZ/maxZ are absent. Scale/offset may also
    -- make the two horizontal halves asymmetric, which a centre/size-only
    -- kora_lib box cannot express, so use the exact PolyZone predicate there.
    if (boxOpts.minZ == nil and boxOpts.maxZ == nil) or boxOpts.scale or boxOpts.offset then
        local scale, offset = boxScaleOffset(boxOpts)
        local radians = math.rad(boxOpts.heading or 0.0)
        local cosR, sinR = math.cos(radians), math.sin(radians)
        local halfX, halfY = width / 2, length / 2
        local minX, maxX = -halfX * scale[3] - offset[3], halfX * scale[4] + offset[4]
        local minY, maxY = -halfY * scale[2] - offset[2], halfY * scale[1] + offset[1]
        local minZ, maxZ = boxOpts.minZ, boxOpts.maxZ
        if minZ ~= nil and maxZ ~= nil and (scale[5] ~= 1.0 or scale[6] ~= 1.0) then
            local halfZ = (maxZ - minZ) / 2
            local centerZ = minZ + halfZ
            minZ, maxZ = centerZ - halfZ * scale[6], centerZ + halfZ * scale[5]
        end
        if minZ ~= nil then minZ = minZ - offset[6] end
        if maxZ ~= nil then maxZ = maxZ + offset[5] end
        -- The predicate below tests the SCALED/OFFSET local rectangle, so its
        -- broad-phase bound has to come from those same numbers rather than
        -- from the caller's width/length. Asymmetric scale/offset can push the
        -- rectangle off `coords`, and a heading rotates it, so take the
        -- circumradius of the furthest corner about coords -- conservative at
        -- every heading. See Target._zoneBounds in client/state.lua.
        local reachX, reachY = math.max(-minX, maxX), math.max(-minY, maxY)
        local extent = math.sqrt(reachX * reachX + reachY * reachY)
        return Target._addCustomZone(function(point)
            local dx, dy = point.x - coords.x, point.y - coords.y
            local localX = dx * cosR + dy * sinR
            local localY = -dx * sinR + dy * cosR
            if localX < minX or localX > maxX or localY < minY or localY > maxY then return false end
            return (minZ == nil or point.z >= minZ) and (maxZ == nil or point.z <= maxZ)
        end, translateOptions(mapped), distance, coords, boxOpts.drawSprite,
        Target._zoneBounds(coords.x, coords.y, extent, extent, minZ, maxZ))
    end

    local minZ = boxOpts.minZ or -2000.0
    local maxZ = boxOpts.maxZ or 2000.0

    return Target.addBoxZone({
        -- The box's z-center is the midpoint of [minZ, maxZ], not coords.z
        -- itself -- an explicit boxOpts.minZ/maxZ can put that midpoint well
        -- above or below coords.z.
        coords = { x = coords.x, y = coords.y, z = (minZ + maxZ) / 2 },
        -- BoxZone's length runs along the zone heading and width across it.
        size = vector3(width, length, maxZ - minZ),
        rotation = boxOpts.heading or 0.0,
        options = translateOptions(mapped),
        distance = distance,
        debug = boxOpts.debugPoly,
        drawSprite = boxOpts.drawSprite,
    })
end

local function makeCircleZone(coords, radius, boxOpts, targetOptions)
    boxOpts = boxOpts or {}
    targetOptions = targetOptions or {}
    local distance = legacyDistance(targetOptions.distance)
    local mapped = optionsMap(targetOptions.options, distance)

    if boxOpts.useZ then
        return Target.addSphereZone({
            coords = coords,
            radius = radius,
            options = translateOptions(mapped),
            distance = distance,
            debug = boxOpts.debugPoly,
            drawSprite = boxOpts.drawSprite,
        })
    end

    local radiusSq = radius * radius
    return Target._addCustomZone(function(point)
        local dx, dy = point.x - coords.x, point.y - coords.y
        return dx * dx + dy * dy < radiusSq
    end, translateOptions(mapped), distance, coords, boxOpts.drawSprite,
    Target._zoneBounds(coords.x, coords.y, radius, radius))
end

local function makePolyZone(points, boxOpts, targetOptions)
    boxOpts = boxOpts or {}
    targetOptions = targetOptions or {}
    local distance = legacyDistance(targetOptions.distance)
    local mapped = optionsMap(targetOptions.options, distance)

    -- qb-target/PolyZone accepts vec2 vertices and treats a poly without
    -- minZ/maxZ as a 2D footprint. Convert to kora_lib's vec3 input and use an
    -- effectively unbounded world-height band for that case.
    local converted = {}
    local anchorZ = boxOpts.minZ and boxOpts.maxZ and (boxOpts.minZ + boxOpts.maxZ) / 2 or 0.0
    for i, point in ipairs(points) do
        converted[i] = { x = point.x, y = point.y, z = point.z or anchorZ }
    end
    local minZ = boxOpts.minZ or -2000.0
    local maxZ = boxOpts.maxZ or 2000.0

    return Target.addPolyZone({
        points = converted,
        minZ = minZ,
        maxZ = maxZ,
        options = translateOptions(mapped),
        distance = distance,
        debug = boxOpts.debugPoly,
        drawSprite = boxOpts.drawSprite,
    })
end

local function AddBoxZone(name, coords, length, width, boxOpts, targetOptions)
    if zonesByName[name] then RemoveZone(name) end
    targetOptions = targetOptions or {}
    boxOpts = boxOpts or {}
    if BoxZone and isCallable(BoxZone.Create) then
        local centerType = type(coords)
        local center = (centerType == 'table' or centerType == 'vector4')
            and vector3(coords.x, coords.y, coords.z) or coords
        local distance = legacyDistance(targetOptions.distance)
        targetOptions.distance = distance
        return trackPolyZoneObject(name, 'box', BoxZone:Create(center, length, width, boxOpts),
            targetOptions, distance, center, boxOpts.drawSprite,
            legacyBoxBounds(center, length, width, boxOpts))
    end
    local id = makeBoxZone(coords, length, width, boxOpts, targetOptions)
    return legacyZone(name, 'box', { id }, targetOptions, {
        center = coords, length = length, width = width, minZ = boxOpts.minZ, maxZ = boxOpts.maxZ,
        heading = boxOpts.heading or 0.0, isBoxZone = true,
    })
end

local function AddCircleZone(name, coords, radius, boxOpts, targetOptions)
    if zonesByName[name] then RemoveZone(name) end
    targetOptions = targetOptions or {}
    boxOpts = boxOpts or {}
    if CircleZone and isCallable(CircleZone.Create) then
        local centerType = type(coords)
        local center = (centerType == 'table' or centerType == 'vector4')
            and vector3(coords.x, coords.y, coords.z) or coords
        local distance = legacyDistance(targetOptions.distance)
        targetOptions.distance = distance
        return trackPolyZoneObject(name, 'circle', CircleZone:Create(center, radius, boxOpts),
            targetOptions, distance, center, boxOpts.drawSprite,
            legacyCircleBounds(center, radius, boxOpts))
    end
    local id = makeCircleZone(coords, radius, boxOpts, targetOptions)
    return legacyZone(name, 'circle', { id }, targetOptions, {
        center = coords, radius = radius, useZ = boxOpts.useZ == true, isCircleZone = true,
    })
end

local function AddPolyZone(name, points, boxOpts, targetOptions)
    if zonesByName[name] then RemoveZone(name) end
    targetOptions = targetOptions or {}
    boxOpts = boxOpts or {}
    if PolyZone and isCallable(PolyZone.Create) then
        local converted = {}
        for i = 1, #points do converted[i] = vector2(points[i].x, points[i].y) end
        local distance = legacyDistance(targetOptions.distance)
        targetOptions.distance = distance
        local zone = PolyZone:Create(converted, boxOpts)
        local anchorZ = boxOpts.minZ and boxOpts.maxZ and (boxOpts.minZ + boxOpts.maxZ) / 2
            or points[1].z or 0.0
        local spriteCoords = { x = zone.center.x, y = zone.center.y, z = anchorZ }
        return trackPolyZoneObject(name, 'poly', zone, targetOptions, distance, spriteCoords, boxOpts.drawSprite,
            legacyPolyBounds(points, boxOpts))
    end
    local id = makePolyZone(points, boxOpts, targetOptions)
    return legacyZone(name, 'poly', { id }, targetOptions, {
        points = points, minZ = boxOpts.minZ, maxZ = boxOpts.maxZ, isPolyZone = true,
    })
end

-- AddComboZone receives the already-created PolyZone objects that upstream
-- passes directly to ComboZone:Create. Mirror the combo with one internal
-- predicate per object while keeping one name-keyed, zone-compatible result.
local function AddComboZone(zones, options, targetOptions)
    assert(type(zones) == 'table', 'AddComboZone requires an array of zone definitions.')
    options = options or {}
    local name = assert(options.name, 'AddComboZone options.name is required.')
    if zonesByName[name] then RemoveZone(name) end
    targetOptions = targetOptions or {}
    local distance = legacyDistance(targetOptions.distance)
    targetOptions.distance = distance
    if ComboZone and isCallable(ComboZone.Create) then
        local combo = ComboZone:Create(zones, options)
        local mapped = optionsMap(targetOptions.options, distance)
        local ids = {}
        for i, zone in ipairs(zones) do
            ids[i] = Target._addCustomZone(function(point) return zone:isPointInside(point) end,
                translateOptions(mapped), distance, nil, false, comboChildBounds(zone))
        end

        local shapeDestroy = combo.destroy
        combo.name, combo.kind, combo.ids = name, 'combo', ids
        combo.targetoptions = targetOptions
        combo.owner = GetInvokingResource() or GetCurrentResourceName()
        combo._qbtargetDestroyed = false
        combo.destroy = function(self)
            if self._qbtargetDestroyed then return end
            self._qbtargetDestroyed = true
            if zonesByName[self.name] == self then zonesByName[self.name] = nil end
            for _, id in ipairs(ids) do
                if Target.registrations[id] then Target.destroyRegistration(id) end
            end
            if isCallable(shapeDestroy) then shapeDestroy(self) end
        end
        zonesByName[name] = combo
        return combo
    end
    local mapped = optionsMap(targetOptions.options, distance)

    local ids = {}
    for i, zone in ipairs(zones) do
        local contains
        if isCallable(zone.isPointInside) then
            contains = function(point) return zone:isPointInside(point) end
        elseif isCallable(zone.contains) then
            contains = function(point) return zone.contains(point) end
        else
            error(('AddComboZone zones[%d] must expose isPointInside/contains.'):format(i))
        end
        ids[i] = Target._addCustomZone(contains, translateOptions(mapped), distance)
    end

    return legacyZone(name, 'combo', ids, targetOptions, { zones = zones, isComboZone = true })
end

-- EntityZone is a moving, rotated box derived from the entity model bounds.
-- PolyZone's scale/offset order is {forward, back, left, right, up, down}; a
-- three-value form applies symmetrically to each axis.
local function AddEntityZone(name, entity, boxOpts, targetOptions)
    boxOpts = boxOpts or {}
    targetOptions = targetOptions or {}
    if zonesByName[name] then RemoveZone(name) end
    assert(DoesEntityExist(entity), 'Entity does not exist')
    local distance = legacyDistance(targetOptions.distance)
    targetOptions.distance = distance
    if EntityZone and isCallable(EntityZone.Create) then
        return trackPolyZoneObject(name, 'entity', EntityZone:Create(entity, boxOpts),
            targetOptions, distance, nil, false, nil, entity)
    end
    local mapped = optionsMap(targetOptions.options, distance)

    local minimum, maximum = GetModelDimensions(GetEntityModel(entity))
    local scale = boxOpts.scale or { 1.0, 1.0, 1.0 }
    local offset = boxOpts.offset or { 0.0, 0.0, 0.0 }
    assert(#scale == 3 or #scale == 6, 'EntityZone scale must contain 3 or 6 values')
    assert(#offset == 3 or #offset == 6, 'EntityZone offset must contain 3 or 6 values')
    if #scale == 3 then scale = { scale[1], scale[1], scale[2], scale[2], scale[3], scale[3] } end
    if #offset == 3 then offset = { offset[1], offset[1], offset[2], offset[2], offset[3], offset[3] } end

    local halfX = (maximum.x - minimum.x) / 2
    local halfY = (maximum.y - minimum.y) / 2
    local minX, maxX = -halfX * scale[3] - offset[3], halfX * scale[4] + offset[4]
    local minY, maxY = -halfY * scale[2] - offset[2], halfY * scale[1] + offset[1]

    local function entityZBounds()
        if not GetOffsetFromEntityInWorldCoords then
            local pos = GetEntityCoords(entity)
            local half = (maximum.z - minimum.z) / 2
            local center = minimum.z + half + pos.z
            return center - half * scale[6] - offset[6], center + half * scale[5] + offset[5]
        end
        local minZ, maxZ = math.huge, -math.huge
        for _, x in ipairs({ minimum.x, maximum.x }) do
            for _, y in ipairs({ minimum.y, maximum.y }) do
                for _, z in ipairs({ minimum.z, maximum.z }) do
                    local world = GetOffsetFromEntityInWorldCoords(entity, x, y, z)
                    minZ, maxZ = math.min(minZ, world.z), math.max(maxZ, world.z)
                end
            end
        end
        local half = (maxZ - minZ) / 2
        local center = minZ + half
        return center - half * scale[6] - offset[6], center + half * scale[5] + offset[5]
    end

    local contains = function(point)
        if not DoesEntityExist(entity) then return false end
        local localPoint = GetOffsetFromEntityGivenWorldCoords(entity, point.x, point.y, point.z)
        if localPoint.x < minX or localPoint.x > maxX or localPoint.y < minY or localPoint.y > maxY then
            return false
        end
        if boxOpts.useZ ~= true then return true end
        local worldMinZ, worldMaxZ = entityZBounds()
        return point.z >= worldMinZ and point.z <= worldMaxZ
    end
    local id = Target._addCustomZone(contains, translateOptions(mapped), distance,
        GetEntityCoords(entity), false, nil, entity)
    return legacyZone(name, 'entity', { id }, targetOptions, {
        entity = entity, dimensions = { minimum, maximum }, useZ = boxOpts.useZ == true, isEntityZone = true,
    })
end

local function AddTargetEntity(entity, targetOptions)
    targetOptions = targetOptions or {}
    local distance = legacyDistance(targetOptions.distance)
    local ids = {}
    for _, value in pairs(toArray(entity)) do
        local mapped = optionsMap(targetOptions.options, distance)
        local id = Target.addEntity(value, translateOptions(mapped), distance)
        addIndexed('entity', entityKey(value), id, mapped, distance)
        ids[#ids + 1] = id
    end
    return #ids == 1 and ids[1] or ids
end

local function AddTargetModel(models, targetOptions)
    targetOptions = targetOptions or {}
    local distance = legacyDistance(targetOptions.distance)
    local ids = {}
    for _, model in pairs(toArray(models)) do
        local mapped = optionsMap(targetOptions.options, distance)
        local id = Target.addModel(model, translateOptions(mapped), distance)
        addIndexed('model', modelKey(model), id, mapped, distance)
        ids[#ids + 1] = id
    end
    return #ids == 1 and ids[1] or ids
end

-- Upstream stores bone targets globally by bone name: any entity with a
-- matching bone can resolve these options.
local function AddTargetBone(bones, targetOptions)
    targetOptions = targetOptions or {}
    local distance = legacyDistance(targetOptions.distance)
    local ids = {}
    for _, bone in pairs(toArray(bones)) do
        local mapped = optionsMap(targetOptions.options, distance)
        local id = Target.addGlobalBone(bone, translateOptions(mapped), distance)
        addIndexed('bone', bone, id, mapped, distance)
        ids[#ids + 1] = id
    end
    return #ids == 1 and ids[1] or ids
end

local function addGlobal(entityType)
    return function(targetOptions)
        targetOptions = targetOptions or {}
        local distance = legacyDistance(targetOptions.distance)
        local mapped = optionsMap(targetOptions.options, distance)
        local id = Target.addGlobalType(entityType, translateOptions(mapped), distance)
        addIndexed(entityType == 'player' and 'globalPlayer' or 'globalType', entityType, id, mapped,
            distance)
        return id
    end
end

local AddGlobalPed = addGlobal('ped')
local AddGlobalVehicle = addGlobal('vehicle')
local AddGlobalObject = addGlobal('object')
local AddGlobalPlayer = addGlobal('player')

-- Upstream's optional labels argument removes only matching options; omitting
-- it removes the full entity entry. removeIndexed preserves those semantics.
local function RemoveTargetEntity(entities, labels)
    local removed = false
    for _, entity in pairs(toArray(entities)) do
        if removeIndexed('entity', entityKey(entity), labels) then removed = true end
    end
    return removed
end

local function RemoveTargetModel(models, labels)
    local removed = false
    for _, model in pairs(toArray(models)) do
        if removeIndexed('model', modelKey(model), labels) then removed = true end
    end
    return removed
end

-- qb-target zones are name-keyed; kora_target's own are id-based -- zonesByName
-- is this bridge's own translation state between the two. A combo zone
-- (AddComboZone above) stores an ARRAY of ids under its name instead of a
-- single one, so this removes every id in that array together.
RemoveZone = function(name)
    local descriptor = zonesByName[name]
    if not descriptor then return false end
    local removedAny = false
    for _, id in ipairs(descriptor.ids) do
        if Target.registrations[id] then removedAny = true end
    end
    descriptor:destroy()
    if zonesByName[name] == descriptor then zonesByName[name] = nil end
    return removedAny
end

local function removeGlobal(entityType)
    return function(labels)
        return removeIndexed(entityType == 'player' and 'globalPlayer' or 'globalType', entityType, labels)
    end
end

local RemoveGlobalPed = removeGlobal('ped')
local RemoveGlobalVehicle = removeGlobal('vehicle')
local RemoveGlobalObject = removeGlobal('object')
local RemoveGlobalPlayer = removeGlobal('player')

-- Mirrors AddTargetBone's own "global bone match" mapping (Target.addGlobalBone
-- / removeGlobalBone), NOT Target.removeGlobalType -- "bone" here refers to
-- the bone-name registration, unrelated to the ped/vehicle/object/player
-- global-TYPE registrations above.
local function RemoveTargetBone(bones, labels)
    local removed = false
    for _, bone in pairs(toArray(bones)) do
        if removeIndexed('bone', bone, labels) then removed = true end
    end
    return removed
end

-- qb-target bundles a small ped spawner that resources such as qb-taxijob use
-- through exports['qb-target']:SpawnPed(...). Keep its state in this compat
-- layer rather than adding ped lifecycle concerns to kora_target's native API.
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
        local loaded, err = Kora.stream.loadAnimDict(data.animDict, function(dict)
            TaskPlayAnim(ped, dict, data.anim, 8.0, 0, -1, data.flag or 1, 0, false, false, false)
        end)
        if not loaded then error(('SpawnPed animation failed: %s'):format(err), 2) end
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

    return targetRegistrationId
end

local function removePedTarget(ped, data, registrationId)
    if not registrationId then return end
    if data.target and data.target.useModel then
        Target.removeModel(data.model, registrationId)
    else
        Target.removeEntity(ped, registrationId)
    end
end

local function spawnOnePed(data, owner, configIndex)
    assert(type(data) == 'table', 'SpawnPed entries must be tables.')
    assert(data.model ~= nil, 'SpawnPed requires a model.')
    assert(data.coords ~= nil, 'SpawnPed requires coords.')

    local ped
    local model, err = Kora.stream.loadModel(data.model, function(loadedModel)
        local z = data.minusOne and (data.coords.z - 1.0) or data.coords.z
        -- SpawnPed is a client compatibility helper and has no server authority
        -- capable of approving shared world state. Keep its configured peds local
        -- even when an older consumer asks for `networked = true`; shared peds must
        -- be created by their owning server resource under strict lockdown.
        ped = CreatePed(0, loadedModel, data.coords.x, data.coords.y, z, data.coords.w or 0.0, false, true)
    end)
    if not model then error(('SpawnPed model failed: %s'):format(err), 2) end
    if not ped or ped == 0 then error('SpawnPed failed to create the configured ped.', 2) end
    data.model = model

    local ok, targetRegistrationId = pcall(applyPedConfig, ped, data)
    if not ok then
        DeletePed(ped)
        error(targetRegistrationId, 2)
    end
    if isCallable(data.action) then
        local actionOk, actionErr = pcall(data.action, data)
        if not actionOk then
            removePedTarget(ped, data, targetRegistrationId)
            DeletePed(ped)
            error(actionErr, 2)
        end
    end

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

    if data.spawnNow then
        local ok, err = pcall(spawnOnePed, data, owner, configIndex)
        if not ok then
            spawnedPedConfigs[configIndex] = nil
            spawnedPedOwners[configIndex] = nil
            error(err, 2)
        end
    end
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
    if record then removePedTarget(ped, record.data, record.targetRegistrationId) end

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

    local records = {}
    for _, record in pairs(legacyRecords) do
        if removeAll or record.owner == resource or not Target.registrations[record.id] then
            records[#records + 1] = record
        end
    end
    for _, record in ipairs(records) do destroyRecord(record) end

    local zoneNames = {}
    for name, zone in pairs(zonesByName) do
        if removeAll or zone.owner == resource then zoneNames[#zoneNames + 1] = name end
    end
    for _, name in ipairs(zoneNames) do RemoveZone(name) end
end)

-- Upstream returns coords, distance, entity, entityType. kora_lib's raycast
-- primitive supplies hit, coords, entity, so compute the two remaining values.
local function RaycastCamera(flag, playerCoords)
    local hit, coords, entityHit = Kora.raycast.fromCamera(16.0, flag or -1)
    local ped = PlayerPedId and PlayerPedId() or 0
    playerCoords = playerCoords or GetEntityCoords(ped)
    local dx, dy, dz = coords.x - playerCoords.x, coords.y - playerCoords.y, coords.z - playerCoords.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if flag == 30 and entityHit and entityHit ~= 0 and HasEntityClearLosToEntity then
        entityHit = HasEntityClearLosToEntity(entityHit, ped, 7) and entityHit or nil
    end
    local entityType = entityHit and entityHit ~= 0 and GetEntityType(entityHit) or 0
    if entityType == 0 and entityHit and entityHit ~= 0 and pcall(GetEntityModel, entityHit) then entityType = 3 end
    return coords, distance, entityHit, entityType
end

-- AllowTargeting(state): real qb-target's usual enable/disable export --
-- state == true enables targeting, a direct passthrough to Target.setEnabled.
local DisableNUI

local function AllowTargeting(state)
    Target.setEnabled(state)
    if not state and Target._cancelCurrentTargeting then Target._cancelCurrentTargeting() end
end

-- Upstream DisableTarget(true) closes only the active target session. Its
-- persistent allowTarget gate is controlled separately by AllowTargeting.
local function DisableTarget(state)
    if not state then return end
    DisableNUI()
    Wait(100)
    if Target._cancelCurrentTargeting then Target._cancelCurrentTargeting() end
    Target.success = false
    SendNUIMessage({ response = 'closeTarget' })
end

local function AddGlobalType(entityType, targetOptions)
    local map = { [1] = 'ped', [2] = 'vehicle', [3] = 'object', ped = 'ped', vehicle = 'vehicle', object = 'object' }
    local name = assert(map[entityType], 'AddGlobalType type must be 1, 2, 3, ped, vehicle, or object')
    return addGlobal(name)(targetOptions)
end

local function RemoveGlobalType(entityType, labels)
    local map = { [1] = 'ped', [2] = 'vehicle', [3] = 'object', ped = 'ped', vehicle = 'vehicle', object = 'object' }
    local name = assert(map[entityType], 'RemoveGlobalType type must be 1, 2, 3, ped, vehicle, or object')
    return removeIndexed('globalType', name, labels)
end

local function GetGlobalTypeData(entityType, label)
    local map = { [1] = 'ped', [2] = 'vehicle', [3] = 'object', ped = 'ped', vehicle = 'vehicle', object = 'object' }
    return map[entityType] and getIndexed('globalType', map[entityType], label) or nil
end

local function GetZoneData(name) return zonesByName[name] end
local function GetTargetBoneData(bone, label) return getIndexed('bone', bone, label) end
local function GetTargetEntityData(entity, label) return getIndexed('entity', entityKey(entity), label) end
local function GetTargetModelData(model, label) return getIndexed('model', modelKey(model), label) end
local function GetGlobalPedData(label) return getIndexed('globalType', 'ped', label) end
local function GetGlobalVehicleData(label) return getIndexed('globalType', 'vehicle', label) end
local function GetGlobalObjectData(label) return getIndexed('globalType', 'object', label) end
local function GetGlobalPlayerData(label) return getIndexed('globalPlayer', 'player', label) end

local function UpdateGlobalTypeData(entityType, label, data)
    local map = { [1] = 'ped', [2] = 'vehicle', [3] = 'object', ped = 'ped', vehicle = 'vehicle', object = 'object' }
    return map[entityType] and updateIndexed('globalType', map[entityType], label, data) or false
end

local function UpdateZoneData(name, data)
    local descriptor = zonesByName[name]
    if not descriptor then return false end
    data.distance = legacyDistance(data.distance)
    descriptor.targetoptions = data
    local mapped = optionsMap(data.options, data.distance)
    for _, id in ipairs(descriptor.ids) do
        Target._replaceOptions(id, translateOptions(mapped), data.distance)
    end
    return true
end

local function UpdateTargetBoneData(bone, label, data) return updateIndexed('bone', bone, label, data) end
local function UpdateTargetEntityData(entity, label, data)
    return updateIndexed('entity', entityKey(entity), label, data)
end
local function UpdateTargetModelData(model, label, data)
    return updateIndexed('model', modelKey(model), label, data)
end
local function UpdateGlobalPedData(label, data) return updateIndexed('globalType', 'ped', label, data) end
local function UpdateGlobalVehicleData(label, data) return updateIndexed('globalType', 'vehicle', label, data) end
local function UpdateGlobalObjectData(label, data) return updateIndexed('globalType', 'object', label, data) end
local function UpdateGlobalPlayerData(label, data) return updateIndexed('globalPlayer', 'player', label, data) end

local legacyHasFocus = false

DisableNUI = function()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    legacyHasFocus = false
end

local function EnableNUI(options)
    if not Target.active or legacyHasFocus then return end
    SetCursorLocation(0.5, 0.5)
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    legacyHasFocus = true
    SendNUIMessage({ response = 'validTarget', data = options })
end

local function LeftTarget()
    DisableNUI()
    Target.success = false
    Target.hovering = nil
    SendNUIMessage({ response = 'leftTarget' })
end

local function DrawOutlineEntity(entity, enabled)
    local outline = Config.target.legacyOutline or {}
    if not outline.enabled or IsEntityAPed(entity) then return end
    SetEntityDrawOutline(entity, enabled)
    local colour = outline.colour or { 255, 255, 255, 255 }
    SetEntityDrawOutlineColor(colour[1], colour[2], colour[3], colour[4])
end

local function CheckBones(coords, entity, bones)
    local closestBone, closestDistance, closestPos, closestName = -1, math.huge, nil, nil
    for _, bone in pairs(bones or {}) do
        if legacyIndex.bone[bone] then
            local index = GetEntityBoneIndexByName(entity, bone)
            local position = GetWorldPositionOfEntityBone(entity, index)
            local dx, dy, dz = coords.x - position.x, coords.y - position.y, coords.z - position.z
            local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
            if distance < closestDistance then
                closestBone, closestDistance, closestPos, closestName = index, distance, position, bone
            end
        end
    end
    if closestBone == -1 then return false end
    return closestBone, closestPos, closestName
end

local function CheckEntity(_flag, datatable, _entity, _distance)
    return type(datatable) == 'table' and next(datatable) ~= nil
end

local function IsTargetActive() return Target.active == true end
local function IsTargetSuccess() return Target.success == true end

local function GetPeds() return spawnedPedConfigs end

local function UpdatePedsData(index, data)
    spawnedPedConfigs[index] = data
    return true
end

local function DeletePeds()
    local peds = {}
    for ped in pairs(spawnedPedRecords) do peds[#peds + 1] = ped end
    for _, ped in ipairs(peds) do removeSpawnedPedEntity(ped) end
    return true
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
    AddGlobalType = AddGlobalType,
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
    RemoveGlobalType = RemoveGlobalType,
    GetGlobalTypeData = GetGlobalTypeData,
    GetZoneData = GetZoneData,
    GetTargetBoneData = GetTargetBoneData,
    GetTargetEntityData = GetTargetEntityData,
    GetTargetModelData = GetTargetModelData,
    GetGlobalPedData = GetGlobalPedData,
    GetGlobalVehicleData = GetGlobalVehicleData,
    GetGlobalObjectData = GetGlobalObjectData,
    GetGlobalPlayerData = GetGlobalPlayerData,
    UpdateGlobalTypeData = UpdateGlobalTypeData,
    UpdateZoneData = UpdateZoneData,
    UpdateTargetBoneData = UpdateTargetBoneData,
    UpdateTargetEntityData = UpdateTargetEntityData,
    UpdateTargetModelData = UpdateTargetModelData,
    UpdateGlobalPedData = UpdateGlobalPedData,
    UpdateGlobalVehicleData = UpdateGlobalVehicleData,
    UpdateGlobalObjectData = UpdateGlobalObjectData,
    UpdateGlobalPlayerData = UpdateGlobalPlayerData,
    SpawnPed = SpawnPed,
    RemoveSpawnedPed = RemoveSpawnedPed,
    DeletePeds = DeletePeds,
    GetPeds = GetPeds,
    UpdatePedsData = UpdatePedsData,
    RaycastCamera = RaycastCamera,
    DisableNUI = DisableNUI,
    EnableNUI = EnableNUI,
    LeftTarget = LeftTarget,
    DrawOutlineEntity = DrawOutlineEntity,
    CheckEntity = CheckEntity,
    CheckBones = CheckBones,
    AllowTargeting = AllowTargeting,
    DisableTarget = DisableTarget,
    IsTargetActive = IsTargetActive,
    IsTargetSuccess = IsTargetSuccess,
}) do
    provideExport('qb-target', exportName, func)
end
