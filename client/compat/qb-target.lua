-- Drop-in compatibility bridge: translates the real, public qb-target API
-- into calls against Target.* directly (same resource -- no exports.qbtarget:
-- round trip needed). Scripts written against exports['qb-target']:... keep
-- working unmodified even though this resource is literally named
-- "qbtarget", not "qb-target" -- see provideExport below.
--
-- See ../../AGENTS.md for the full function-by-function mapping table and
-- the explicitly flagged public-knowledge assumptions (AddTargetBone's
-- scope, RemoveTargetEntity/RemoveTargetModel's optional second argument,
-- AddBoxZone's length/width axis convention, canInteract arity).

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

local function dispatchLegacy(option, entity)
    if type(option.action) == 'function' then
        option.action(entity)
    elseif option.event then
        if option.type == 'server' then
            TriggerServerEvent(option.event, entity)
        else
            TriggerEvent(option.event, entity)
        end
    end
end

-- Translates qb-target's option shape ({type?, event?, icon, label, action?,
-- canInteract?, item?, job?, gang?, distance?}) into qbtarget's own
-- QBTargetOption shape. job/gang/item are passed through UNENFORCED -- see
-- ../../docs.md's "Opaque fields" section: no qb-core exists in this repo to
-- check a player's job/gang against, so a ported script's job/gang
-- restriction shows to everyone unless it supplies its own canInteract.
local function translateOptions(options)
    assert(type(options) == 'table', 'qb-target target options must be a table.')

    local translated = {}

    for i, option in ipairs(options) do
        translated[i] = {
            label = option.label,
            icon = option.icon,
            distance = option.distance,
            canInteract = option.canInteract,
            item = option.item,
            job = option.job,
            gang = option.gang,
            onSelect = function(entity)
                dispatchLegacy(option, entity)
            end,
        }
    end

    return translated
end

local zonesByName = {}

local function AddBoxZone(name, coords, length, width, boxOpts, targetOptions)
    boxOpts = boxOpts or {}
    targetOptions = targetOptions or {}

    local minZ = boxOpts.minZ or (coords.z - 2.0)
    local maxZ = boxOpts.maxZ or (coords.z + 2.0)

    local id = Target.addBoxZone({
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
    })

    zonesByName[name] = id
    return id
end

local function AddCircleZone(name, coords, radius, boxOpts, targetOptions)
    boxOpts = boxOpts or {}
    targetOptions = targetOptions or {}

    local id = Target.addSphereZone({
        coords = coords,
        radius = radius,
        options = translateOptions(targetOptions.options),
        distance = targetOptions.distance,
        debug = boxOpts.debugPoly,
    })

    zonesByName[name] = id
    return id
end

local function AddPolyZone(name, points, boxOpts, targetOptions)
    boxOpts = boxOpts or {}
    targetOptions = targetOptions or {}

    local id = Target.addPolyZone({
        points = points,
        minZ = boxOpts.minZ,
        maxZ = boxOpts.maxZ,
        thickness = boxOpts.thickness,
        options = translateOptions(targetOptions.options),
        distance = targetOptions.distance,
        debug = boxOpts.debugPoly,
    })

    zonesByName[name] = id
    return id
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
-- is this bridge's own translation state between the two.
local function RemoveZone(name)
    local id = zonesByName[name]
    if not id then return false end

    zonesByName[name] = nil
    return Target.removeZone(id)
end

for exportName, func in pairs({
    AddBoxZone = AddBoxZone,
    AddCircleZone = AddCircleZone,
    AddPolyZone = AddPolyZone,
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
}) do
    provideExport('qb-target', exportName, func)
end
