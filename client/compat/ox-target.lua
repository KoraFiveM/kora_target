-- Drop-in compatibility bridge: translates the real, public ox_target API
-- into calls against Target.* directly (same resource -- no exports.kora_target:
-- round trip needed). Scripts written against exports.ox_target:... keep
-- working unmodified even though this resource is literally named
-- "qbtarget", not "ox_target" -- see provideExport below.
--
-- See ../../AGENTS.md for the full function-by-function mapping table and
-- the explicitly flagged public-knowledge assumptions (getState()'s exact
-- return shape, isActive). canInteract receives ox_target's
-- (entity, distance, coords, name, bone) -- bone is always nil -- and
-- `groups` is enforced against kora_core job/gang data (see makeCanInteract).

Target = Target or {}

-- See client/compat/qb-target.lua's identical copy of this helper for why
-- it's needed (kora_target doesn't `provide 'ox_target'`, and even
-- `provide` alone wouldn't make exports.ox_target:Fn() resolve here -- only registering the underlying
-- __cfx_export_ox_target_<name> event does). Duplicated rather than shared:
-- kora_lib publishes the identity bridge for compatibility providers in either realm.
local provideExport = Kora.compat.provideExport

-- A callback passed through an FXServer export boundary is represented as a
-- table with an __call metamethod, not a Lua value whose type is "function"
-- -- see client/compat/qb-target.lua's identical copy of this helper (and
-- comment) for the concrete failure this fixes: a cross-resource
-- `onSelect`/`action` reaching this bridge in that shape used to silently
-- fall through to serverEvent/event/nothing, since `type(x) == 'function'`
-- is false for it. Duplicated rather than shared for the same reason
-- kora_lib also centralizes callable funcref detection across export boundaries.
local isCallable = Kora.util.isCallable

-- The compat response uses the captured hit, while native Kora callbacks keep their arguments.
local function responseFor(entity, context, server)
    local coords = context and context.anchorCoords
    local response = {
        entity = entity or 0,
        coords = coords and vector3(coords.x, coords.y, coords.z) or nil,
        distance = context and context.distance or nil,
        zone = context and context.registration.kind == 'zone' and context.registration.id or nil,
    }
    if server then
        response.entity = entity and entity ~= 0 and NetworkGetEntityIsNetworked(entity)
            and NetworkGetNetworkIdFromEntity(entity) or 0
    end
    return response
end

local function dispatchLegacy(option, entity, context)
    if isCallable(option.onSelect) then
        option.onSelect(responseFor(entity, context))
    elseif isCallable(option.action) then
        option.action(entity)
    elseif option.serverEvent then
        TriggerServerEvent(option.serverEvent, responseFor(entity, context, true))
    elseif option.event then
        TriggerEvent(option.event, responseFor(entity, context))
    end
end

-- `groups` enforcement (ox_target form: 'name' | {'a','b'} | {a = minGrade}),
-- checked against the same kora_core PlayerData the qb-target bridge tracks
-- (job and gang). Set convar `kora_target:oxGroups 0` to restore the previous
-- behaviour of passing `groups` through unenforced. If no kora_core identity is
-- running the check never denies (graceful degradation, warned at registration).
local function groupsEnforced()
    return type(GetConvarInt) ~= 'function' or GetConvarInt('kora_target:oxGroups', 1) ~= 0
end

local function groupGrade(entry, name)
    return entry and entry.name == name and entry.grade and (entry.grade.level or entry.grade) or nil
end

local function hasGroup(groups)
    if not Target._playerData then return true end
    local available, data = Target._playerData()
    if not available then return true end
    if not data then return false end

    local function satisfied(name, minGrade)
        local grade = groupGrade(data.job, name) or groupGrade(data.gang, name)
        return grade ~= nil and grade >= (tonumber(minGrade) or 0)
    end

    if type(groups) == 'string' then return satisfied(groups, 0) end
    if type(groups) ~= 'table' then return true end
    for key, value in pairs(groups) do
        if type(key) == 'number' then
            if satisfied(value, 0) then return true end
        elseif satisfied(key, value) then
            return true
        end
    end
    return next(groups) == nil
end

-- ox_target accepts either an array of options or one bare option table.
local function optionList(options)
    assert(type(options) == 'table', 'ox_target options must be a table.')
    if options[1] == nil and next(options) ~= nil then return { options } end
    return options
end

-- Translates ox_target's option shape ({name?, icon, label, distance?,
-- bones?, canInteract?, onSelect?, action?, event?, serverEvent?, groups?,
-- items?}) into kora_target's own QBTargetOption shape. `distance`/`bones` map
-- 1:1 -- ox_target already stores these per-option, unlike qb-target.
-- `items` is passed through UNENFORCED; `groups` is enforced via makeCanInteract.
-- `offset`/`offsetAbsolute`/`offsetSize` (model/entity aim offsets) are not
-- supported and are ignored.
local function makeCanInteract(option)
    local userCheck, groups = option.canInteract, option.groups
    local enforce = groups ~= nil and groupsEnforced()
    if not userCheck and not enforce then return nil end

    if enforce then
        local available = Target._playerData and (Target._playerData())
        if not available then
            print(('[ox_target-bridge] WARNING: option %q sets groups but no kora_core identity is running '
                .. '-- groups cannot be checked and the option will be shown to everyone.')
                :format(tostring(option.label)))
        end
    end

    -- kora_target calls canInteract(entity, distance, data, anchorCoords); ox_target's
    -- contract is (entity, distance, coords, name, bone). Zones pass entity 0 in ox_target.
    -- `bone` is not tracked by the resolver and is always nil.
    return function(entity, distance, _, anchorCoords)
        if enforce and not hasGroup(groups) then return false end
        if userCheck then
            local coords = anchorCoords and vector3(anchorCoords.x, anchorCoords.y, anchorCoords.z) or nil
            return userCheck(entity or 0, distance, coords, option.name, nil)
        end
        return true
    end
end

local function translateOxOptions(options)
    options = optionList(options)

    local translated = {}

    for i, option in ipairs(options) do
        if option.items then
            print(('[ox_target-bridge] WARNING: option %q sets items but this compat shim does NOT '
                .. 'enforce item filters -- supply your own canInteract.'):format(tostring(option.label)))
        end

        local bones = option.bones
        if type(bones) == 'string' then bones = { bones } end

        translated[i] = {
            name = option.name,
            label = option.label or option.name or 'Interact',
            icon = option.icon,
            iconColor = option.iconColor,
            distance = option.distance,
            bones = bones,
            canInteract = makeCanInteract(option),
            groups = option.groups,
            items = option.items,
            onSelect = function(entity)
                dispatchLegacy(option, entity)
            end,
            _onSelectContext = function(context)
                dispatchLegacy(option, context.entity, context)
            end,
            _oxCompat = true,
        }
    end

    return translated
end

local function addLocalEntity(entities, options)
    return Target.addEntity(entities, translateOxOptions(options))
end

local function addModel(models, options)
    return Target.addModel(models, translateOxOptions(options))
end

local zonesByName = {}

local function addBoxZone(zoneOpts)
    assert(type(zoneOpts) == 'table', 'addBoxZone requires an options table.')

    local id = Target.addBoxZone({
        coords = zoneOpts.coords,
        size = zoneOpts.size or vector3(2.0, 2.0, 2.0),
        rotation = zoneOpts.rotation or 0.0,
        debug = zoneOpts.debug,
        drawSprite = zoneOpts.drawSprite,
        options = translateOxOptions(zoneOpts.options),
    })
    if zoneOpts.name then zonesByName[zoneOpts.name] = id end
    return id
end

local function addSphereZone(zoneOpts)
    assert(type(zoneOpts) == 'table', 'addSphereZone requires an options table.')

    return Target.addSphereZone({
        coords = zoneOpts.coords,
        radius = zoneOpts.radius,
        debug = zoneOpts.debug,
        drawSprite = zoneOpts.drawSprite,
        options = translateOxOptions(zoneOpts.options),
    })
end

local function addPolyZone(zoneOpts)
    assert(type(zoneOpts) == 'table', 'addPolyZone requires an options table.')

    return Target.addPolyZone({
        points = zoneOpts.points,
        thickness = zoneOpts.thickness,
        debug = zoneOpts.debug,
        drawSprite = zoneOpts.drawSprite,
        options = translateOxOptions(zoneOpts.options),
    })
end

local function addGlobal(entityType)
    return function(options)
        local id = Target.addGlobalType(entityType, translateOxOptions(options))
        Target.registrations[id]._oxGlobal = true
        return id
    end
end

local addGlobalPlayer = addGlobal('player')
local addGlobalPed = addGlobal('ped')
local addGlobalVehicle = addGlobal('vehicle')
local addGlobalObject = addGlobal('object')

-- ox_target zones are already id-based, same as kora_target's own -- the
-- cleanest mapping in the suite, no translation table needed.
local function removeZone(id)
    if type(id) == 'string' then
        local named = zonesByName[id]
        zonesByName[id] = nil
        id = named
    end
    return id ~= nil and Target.removeZone(id) or false
end

local function optionNames(names)
    local wanted = {}
    for _, name in ipairs(type(names) == 'table' and names or { names }) do wanted[name] = true end
    return wanted
end

local function removeNamedOptions(id, wanted)
    local registration = Target.registrations[id]
    if not registration then return false end

    local remaining = {}
    for _, option in ipairs(registration.options) do
        if not wanted[option.name] then remaining[#remaining + 1] = option end
    end
    if #remaining == #registration.options then return false end

    if #remaining == 0 then
        Target.destroyRegistration(id)
    else
        Target._replaceOptions(id, remaining, registration.distance)
    end
    return true
end

-- Removes the named options from bridge-created registrations indexed under
-- `key` in `index` (Target.byEntity / Target.byModel). Native and qb-target
-- registrations on the same key are left alone.
local function removeNamedFromIndex(index, key, wanted)
    local ids = {}
    for id in pairs(index[key] or {}) do ids[#ids + 1] = id end
    local removed = false
    for _, id in ipairs(ids) do
        local registration = Target.registrations[id]
        local first = registration and registration.options[1]
        if first and first._oxCompat and removeNamedOptions(id, wanted) then removed = true end
    end
    return removed
end

-- removeLocalEntity(entities, names?): without `names` every registration on the
-- entities goes; with a name or array of names only those options do.
local function removeLocalEntity(entities, names)
    local wanted = names ~= nil and optionNames(names) or nil
    local removedAny = false
    for _, entity in ipairs(type(entities) == 'table' and entities or { entities }) do
        if wanted then
            if removeNamedFromIndex(Target.byEntity, entity, wanted) then removedAny = true end
        elseif Target.removeEntity(entity) then
            removedAny = true
        end
    end

    return removedAny
end

local function removeModel(models, names)
    if names == nil then return Target.removeModel(models) end

    local wanted, removedAny = optionNames(names), false
    for _, model in ipairs(type(models) == 'table' and models or { models }) do
        local hash = type(model) == 'string' and joaat(model) or model
        if removeNamedFromIndex(Target.byModel, hash, wanted) then removedAny = true end
    end
    return removedAny
end

-- Note the INVERTED boolean sense: ox_target's disableTargeting(true) turns
-- targeting OFF. A naive passthrough to setEnabled would silently invert
-- behavior.
local function disableTargeting(state)
    return Target.setEnabled(not state)
end

-- Best-effort: ox_target's exact getState() return shape isn't confidently
-- known from public knowledge alone (see AGENTS.md's assumptions list).
-- Returns kora_target's own getState() shape as-is rather than guessing at a
-- reshape that could be wrong in a different way.
local function getState()
    return Target.getState()
end

local function removeGlobal(entityType)
    return function(names)
        if type(names) ~= 'string' and type(names) ~= 'table' then
            return Target.removeGlobalType(entityType, names)
        end

        local ids = {}
        for id in pairs(Target.byGlobalType[entityType] or {}) do
            if Target.registrations[id]._oxGlobal then ids[#ids + 1] = id end
        end
        local wanted, removed = optionNames(names), false
        for _, id in ipairs(ids) do
            if removeNamedOptions(id, wanted) then removed = true end
        end
        return removed
    end
end

local removeGlobalPlayer = removeGlobal('player')
local removeGlobalPed = removeGlobal('ped')
local removeGlobalVehicle = removeGlobal('vehicle')
local removeGlobalObject = removeGlobal('object')

-- Universal registrations remain grouped so the existing numeric removal alias
-- still works alongside the documented option-name removal.
local globalOptionGroups = {}
local nextGlobalOptionId = 0

local function addGlobalOption(options)
    nextGlobalOptionId = nextGlobalOptionId + 1
    local groupId = nextGlobalOptionId

    local entries = {}
    for _, entityType in ipairs({ 'ped', 'vehicle', 'object', 'player' }) do
        entries[#entries + 1] = { entityType = entityType, id = Target.addGlobalType(entityType, translateOxOptions(options)) }
    end

    globalOptionGroups[groupId] = entries
    return groupId
end

local function removeGlobalOption(groupId)
    if type(groupId) == 'string' or type(groupId) == 'table' then
        local wanted, removed = optionNames(groupId), false
        for _, entries in pairs(globalOptionGroups) do
            for _, entry in ipairs(entries) do
                if removeNamedOptions(entry.id, wanted) then removed = true end
            end
        end
        return removed
    end

    local entries = globalOptionGroups[groupId]
    if not entries then return false end

    globalOptionGroups[groupId] = nil

    local removedAny = false
    for _, entry in ipairs(entries) do
        if Target.removeGlobalType(entry.entityType, entry.id) then removedAny = true end
    end

    return removedAny
end

---A bare network id or an array of network ids is normalised to an array,
---mirroring client/state.lua's own toArray for the same single-vs-array
---convenience.
---@param value any
---@return table
local function toArray(value)
    if type(value) == 'table' then return value end
    return { value }
end

-- addEntity/removeEntity: real ox_target's NETWORK-id scoped entity API --
-- different from addLocalEntity/removeLocalEntity above, which already take
-- local entity handles valid on this client directly. ox_target's addEntity
-- takes a network id (or array of them), letting a caller target something
-- it only knows the netId for (e.g. received over an event); bridged here to
-- Target.addEntity/removeEntity (both LOCAL-handle scoped) via
-- NetworkGetEntityFromNetworkId, FiveM's standard netId->handle native.
local function addEntity(netIds, options)
    local entities = {}
    for i, netId in ipairs(toArray(netIds)) do
        entities[i] = NetworkGetEntityFromNetworkId(netId)
    end

    return Target.addEntity(entities, translateOxOptions(options))
end

local function removeEntity(netIds)
    local removedAny = false
    for _, netId in ipairs(toArray(netIds)) do
        local entity = NetworkGetEntityFromNetworkId(netId)
        if Target.removeEntity(entity) then removedAny = true end
    end

    return removedAny
end

-- isActive: real ox_target's "is targeting currently active" query.
-- Public-knowledge assumption (low confidence, see AGENTS.md): interpreted
-- here as "is a target option currently resolved/visible under the
-- reticle" -- Target.getState().hovering ~= nil -- rather than "is
-- targeting enabled at all" (Target.getState().enabled), since ox_target's
-- own isActive is commonly used to guard UI/animation logic that only makes
-- sense while something is actually being aimed at.
local function isActive()
    local state = Target.getState()
    return state.hovering ~= nil
end

for exportName, func in pairs({
    addLocalEntity = addLocalEntity,
    addModel = addModel,
    addBoxZone = addBoxZone,
    addSphereZone = addSphereZone,
    addPolyZone = addPolyZone,
    addGlobalPlayer = addGlobalPlayer,
    addGlobalPed = addGlobalPed,
    addGlobalVehicle = addGlobalVehicle,
    addGlobalObject = addGlobalObject,
    addGlobalOption = addGlobalOption,
    addEntity = addEntity,
    removeZone = removeZone,
    removeLocalEntity = removeLocalEntity,
    removeModel = removeModel,
    removeGlobalPlayer = removeGlobalPlayer,
    removeGlobalPed = removeGlobalPed,
    removeGlobalVehicle = removeGlobalVehicle,
    removeGlobalObject = removeGlobalObject,
    removeGlobalOption = removeGlobalOption,
    removeEntity = removeEntity,
    disableTargeting = disableTargeting,
    getState = getState,
    isActive = isActive,
}) do
    provideExport('ox_target', exportName, func)
end
