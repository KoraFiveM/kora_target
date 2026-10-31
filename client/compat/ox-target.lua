-- Drop-in compatibility bridge: translates the real, public ox_target API
-- into calls against Target.* directly (same resource -- no exports.kora_target:
-- round trip needed). Scripts written against exports.ox_target:... keep
-- working unmodified even though this resource is literally named
-- "qbtarget", not "ox_target" -- see provideExport below.
--
-- See ../../AGENTS.md for the full function-by-function mapping table and
-- the explicitly flagged public-knowledge assumptions (removeLocalEntity/
-- removeModel's optional `names` argument, canInteract arity -- kora_target's
-- own canInteract only forwards (entity, distance, data), so a ported
-- script's canInteract does NOT receive ox_target's real (entity, distance,
-- coords, name, bone) -- and getState()'s exact return shape).

Target = Target or {}

-- See client/compat/qb-target.lua's identical copy of this helper for why
-- it's needed (`provide` in fxmanifest.lua alone doesn't make
-- exports.ox_target:Fn() resolve here -- only registering the underlying
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

-- Translates ox_target's option shape ({name?, icon, label, distance?,
-- bones?, canInteract?, onSelect?, action?, event?, serverEvent?, groups?,
-- items?}) into kora_target's own QBTargetOption shape. `distance`/`bones` map
-- 1:1 -- ox_target already stores these per-option, unlike qb-target.
-- `groups`/`items` are passed through UNENFORCED -- see ../../docs.md's
-- "Opaque fields" section: no ox_core/qb-core exists in this repo to check a
-- player's group/inventory against.
local function translateOxOptions(options)
    assert(type(options) == 'table', 'ox_target options must be a table.')

    local translated = {}

    for i, option in ipairs(options) do
        -- Loud, once-per-option warning at REGISTRATION time (not per
        -- interaction/frame) for the exact gap the comment above describes:
        -- groups/items filter fields with no canInteract of the caller's
        -- own means this option shows to EVERYONE, silently.
        if (option.groups or option.items) and not option.canInteract then
            print(('[ox_target-bridge] WARNING: option %q sets groups/items but this compat shim does '
                .. 'NOT enforce those filters (no ox_core/qb-core in this repo to check against) -- the '
                .. 'option will be shown to EVERYONE unless you supply your own canInteract.')
                :format(tostring(option.label)))
        end

        translated[i] = {
            name = option.name,
            label = option.label,
            icon = option.icon,
            distance = option.distance,
            bones = option.bones,
            -- Passed through as-is, NOT re-wrapped to real ox_target's own
            -- contract: kora_target's resolver always calls this with
            -- (entity, distance, data), but real ox_target calls
            -- canInteract(entity, distance, coords, name, bone) -- five
            -- arguments. A ported canInteract reading coords/name/bone off
            -- its 3rd-5th parameters sees kora_target's shape instead. See this
            -- file's header and ../../AGENTS.md for why this divergence is
            -- intentionally NOT fixed here.
            canInteract = option.canInteract,
            groups = option.groups,
            items = option.items,
            onSelect = function(entity)
                dispatchLegacy(option, entity)
            end,
            _onSelectContext = function(context)
                dispatchLegacy(option, context.entity, context)
            end,
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

local function addBoxZone(zoneOpts)
    assert(type(zoneOpts) == 'table', 'addBoxZone requires an options table.')

    return Target.addBoxZone({
        coords = zoneOpts.coords,
        size = zoneOpts.size,
        rotation = zoneOpts.rotation,
        debug = zoneOpts.debug,
        drawSprite = zoneOpts.drawSprite,
        options = translateOxOptions(zoneOpts.options),
    })
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
    return Target.removeZone(id)
end

-- ox_target's exact semantics for the optional `names` (specific option
-- names to remove) argument aren't confidently known from public knowledge
-- alone (see AGENTS.md's assumptions list). Rather than guess and risk
-- silently removing the wrong option, this only supports the unambiguous
-- case (no `names` -- remove everything) and loudly refuses the rest.
local function removeLocalEntity(entities, names)
    if names then
        print(('[ox_target-bridge] removeLocalEntity(entities, names) with specific option names is not '
            .. 'supported -- call removeLocalEntity(entities) to remove everything on them. (names=%s)')
            :format(tostring(names)))
        return false
    end

    local removedAny = false
    for _, entity in ipairs(type(entities) == 'table' and entities or { entities }) do
        if Target.removeEntity(entity) then removedAny = true end
    end

    return removedAny
end

local function removeModel(models, names)
    if names then
        print(('[ox_target-bridge] removeModel(models, names) with specific option names is not supported '
            .. '-- call removeModel(models) to remove everything on them. (names=%s)'):format(tostring(names)))
        return false
    end

    return Target.removeModel(models)
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
