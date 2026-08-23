-- Drop-in compatibility bridge: translates the real, public ox_target API
-- into calls against Target.* directly (same resource -- no exports.qbtarget:
-- round trip needed). Scripts written against exports.ox_target:... keep
-- working unmodified even though this resource is literally named
-- "qbtarget", not "ox_target" -- see provideExport below.
--
-- See ../../AGENTS.md for the full function-by-function mapping table and
-- the explicitly flagged public-knowledge assumptions (removeLocalEntity/
-- removeModel's optional `names` argument, canInteract arity -- qbtarget's
-- own canInteract only forwards (entity, distance, data), so a ported
-- script's canInteract does NOT receive ox_target's real (entity, distance,
-- coords, name, bone) -- and getState()'s exact return shape).

Target = Target or {}

-- See client/compat/qb-target.lua's identical copy of this helper for why
-- it's needed (`provide` in fxmanifest.lua alone doesn't make
-- exports.ox_target:Fn() resolve here -- only registering the underlying
-- __cfx_export_ox_target_<name> event does). Duplicated rather than shared:
-- separate Lua chunks can't share a local, same reasoning qblib's own
-- AGENTS.md gives for its small per-file helper duplicates.
local function provideExport(providedResource, exportName, func)
    AddEventHandler(('__cfx_export_%s_%s'):format(providedResource, exportName), function(setCB)
        setCB(func)
    end)
end

local function dispatchLegacy(option, entity)
    if type(option.onSelect) == 'function' then
        option.onSelect(entity)
    elseif type(option.action) == 'function' then
        option.action(entity)
    elseif option.serverEvent then
        TriggerServerEvent(option.serverEvent, entity)
    elseif option.event then
        TriggerEvent(option.event, entity)
    end
end

-- Translates ox_target's option shape ({name?, icon, label, distance?,
-- bones?, canInteract?, onSelect?, action?, event?, serverEvent?, groups?,
-- items?}) into qbtarget's own QBTargetOption shape. `distance`/`bones` map
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
            label = option.label,
            icon = option.icon,
            distance = option.distance,
            bones = option.bones,
            canInteract = option.canInteract,
            groups = option.groups,
            items = option.items,
            onSelect = function(entity)
                dispatchLegacy(option, entity)
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
        options = translateOxOptions(zoneOpts.options),
    })
end

local function addSphereZone(zoneOpts)
    assert(type(zoneOpts) == 'table', 'addSphereZone requires an options table.')

    return Target.addSphereZone({
        coords = zoneOpts.coords,
        radius = zoneOpts.radius,
        debug = zoneOpts.debug,
        options = translateOxOptions(zoneOpts.options),
    })
end

local function addPolyZone(zoneOpts)
    assert(type(zoneOpts) == 'table', 'addPolyZone requires an options table.')

    return Target.addPolyZone({
        points = zoneOpts.points,
        thickness = zoneOpts.thickness,
        debug = zoneOpts.debug,
        options = translateOxOptions(zoneOpts.options),
    })
end

local function addGlobal(entityType)
    return function(options)
        return Target.addGlobalType(entityType, translateOxOptions(options))
    end
end

local addGlobalPlayer = addGlobal('player')
local addGlobalPed = addGlobal('ped')
local addGlobalVehicle = addGlobal('vehicle')
local addGlobalObject = addGlobal('object')

-- ox_target zones are already id-based, same as qbtarget's own -- the
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
-- Returns qbtarget's own getState() shape as-is rather than guessing at a
-- reshape that could be wrong in a different way.
local function getState()
    return Target.getState()
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
    removeZone = removeZone,
    removeLocalEntity = removeLocalEntity,
    removeModel = removeModel,
    disableTargeting = disableTargeting,
    getState = getState,
}) do
    provideExport('ox_target', exportName, func)
end
