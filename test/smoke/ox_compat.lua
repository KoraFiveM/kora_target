local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local resourceRoot = scriptDir .. '../../'
local koraLibTestRoot = resourceRoot .. '../kora_lib/test/'
package.path = koraLibTestRoot .. '?.lua;' .. package.path

local harness = require('harness')
local exportsByEvent = {}



_G.Kora = {
    resources = {},
    util = { isCallable = function(value)
        if type(value) == 'function' then return true end
        local mt = type(value) == 'table' and getmetatable(value) or nil
        return mt ~= nil and mt.__call ~= nil
    end },
    compat = { isCallable = function(value) return Kora.util.isCallable(value) end, provideExport = function(identity, name, fn)
        AddEventHandler(('__cfx_export_%s_%s'):format(identity, name), function(setCB) setCB(fn) end)
    end },
    zones = {
        box = function() return { remove = function() end, contains = function() return false end } end,
        sphere = function() return { remove = function() end, contains = function() return false end } end,
        poly = function() return { remove = function() end, contains = function() return false end } end,
    },
}
_G.GetCurrentResourceName = function() return 'kora_target' end
local invokingResource = 'ox-doorlock'
_G.GetInvokingResource = function() return invokingResource end
local resourceStopHandlers = {}
_G.AddEventHandler = function(name, handler)
    exportsByEvent[name] = handler
    if name == 'onClientResourceStop' then resourceStopHandlers[#resourceStopHandlers + 1] = handler end
end
_G.joaat = function(value) return value end
local vectorCalls = {}
_G.vector3 = function(...)
    local args = table.pack(...)
    local value = { x = args[1], y = args[2], z = args[3] }
    vectorCalls[value] = args
    return value
end

local selectedItems, clientEvents, serverEvents = nil, {}, {}
Kora.keybind = { add = function() end }
Kora.nui = { send = function() end }
Kora.interact = {
    open = function(items) selectedItems = items; return true end,
    isActive = function() return false end,
    close = function() end,
}
_G.PlayerPedId = function() return 1 end
_G.IsEntityPositionFrozen = function() return false end
_G.FreezeEntityPosition = function() end
_G.BeginTextCommandDisplayHelp = function() end
_G.AddTextComponentSubstringPlayerName = function() end
_G.EndTextCommandDisplayHelp = function() end
_G.ClearAllHelpMessages = function() end
_G.CreateThread = function() end
_G.RegisterCommand = function() end
local clock = 0
_G.GetGameTimer = function() return clock end
_G.RegisterNetEvent = function(name, handler) netHandlers = netHandlers or {}; netHandlers[name] = handler end
_G.DoesEntityExist = function(entity) return entity ~= nil and entity ~= 0 end
_G.GetEntityType = function() return 3 end
_G.GetEntityModel = function() return 123 end
_G.LocalPlayer = { state = {} }
_G.TriggerEvent = function(name, ...) clientEvents[#clientEvents + 1] = { name = name, args = table.pack(...) } end
_G.TriggerServerEvent = function(name, ...) serverEvents[#serverEvents + 1] = { name = name, args = table.pack(...) } end
local networkIds = { [70] = 700 }
_G.NetworkGetEntityIsNetworked = function(entity) return networkIds[entity] ~= nil end
_G.NetworkGetNetworkIdFromEntity = function(entity) return assert(networkIds[entity], 'unnetworked handle conversion') end

local networkEntities = {}
_G.NetworkGetEntityFromNetworkId = function(netId) return networkEntities[netId] end

dofile(resourceRoot .. '../kora_lib/local/resources/client.lua')
dofile(resourceRoot .. 'config.lua')
Config.target.testMode = true
dofile(resourceRoot .. 'client/state.lua')
dofile(resourceRoot .. 'client/loop.lua')
dofile(resourceRoot .. 'client/compat/ox-target.lua')

local function getExport(name)
    local fn
    exportsByEvent[('__cfx_export_ox_target_%s'):format(name)](function(f) fn = f end)
    return fn
end

local addLocalEntity = getExport('addLocalEntity')
local addGlobalPed = getExport('addGlobalPed')
local removeGlobalPed = getExport('removeGlobalPed')
local removeGlobalVehicle = getExport('removeGlobalVehicle')
local removeGlobalObject = getExport('removeGlobalObject')
local removeGlobalPlayer = getExport('removeGlobalPlayer')
local addGlobalOption = getExport('addGlobalOption')
local removeGlobalOption = getExport('removeGlobalOption')
local addEntity = getExport('addEntity')
local removeEntity = getExport('removeEntity')
local isActive = getExport('isActive')
local getState = getExport('getState')

harness.test('a __call-metatable onSelect survives the FXServer export boundary (funcref tolerance)', function()
    local calls = 0
    local response
    local onSelectProxy = setmetatable({}, {
        __call = function(_, data)
            calls = calls + 1
            response = data
        end,
    })

    local id = addLocalEntity(7, { { label = 'Search', onSelect = onSelectProxy } })
    Target.registrations[id].options[1].onSelect(7)

    harness.assertEqual(type(response), 'table', 'compatibility onSelect receives a response table')
    harness.assertEqual(response.entity, 7, 'the local entity handle reaches the proxied onSelect')
    harness.assertEqual(response.coords, nil, 'direct legacy invocation retains absent hit coordinates')
    harness.assertEqual(calls, 1,
        'a __call-metatable table onSelect must be invoked, not silently fall through to serverEvent/event')
end)

harness.test('a __call-metatable action survives the FXServer export boundary (funcref tolerance)', function()
    local calls = 0
    local actionProxy = setmetatable({}, {
        __call = function(_, entity)
            calls = calls + 1
        end,
    })

    local id = addLocalEntity(8, { { label = 'Search', action = actionProxy } })
    Target.registrations[id].options[1].onSelect(8)

    harness.assertEqual(calls, 1,
        'a __call-metatable table action must be invoked, not silently fall through to serverEvent/event')
end)

harness.test('addGlobalPed/removeGlobalPed forward to Target.addGlobalType/removeGlobalType', function()
    local id = addGlobalPed({ { label = 'Frisk', onSelect = function() end } })
    harness.assertTrue(Target.registrations[id] ~= nil, 'addGlobalPed must register')
    harness.assertTrue(removeGlobalPed(), 'removeGlobalPed must remove the ped-type registration')
    harness.assertFalse(removeGlobalVehicle(), 'removeGlobalVehicle is a no-op with nothing registered')
    harness.assertFalse(removeGlobalObject(), 'removeGlobalObject is a no-op with nothing registered')
    harness.assertFalse(removeGlobalPlayer(), 'removeGlobalPlayer is a no-op with nothing registered')
end)

harness.test('addGlobalOption registers on every global type and removeGlobalOption undoes all of them', function()
    local groupId = addGlobalOption({ { label = 'Universal', onSelect = function() end } })

    local pedIds, vehicleIds, objectIds, playerIds =
        Target.byGlobalType.ped, Target.byGlobalType.vehicle, Target.byGlobalType.object, Target.byGlobalType.player
    harness.assertTrue(pedIds ~= nil and next(pedIds) ~= nil, 'addGlobalOption must register a ped-type option')
    harness.assertTrue(vehicleIds ~= nil and next(vehicleIds) ~= nil, 'addGlobalOption must register a vehicle-type option')
    harness.assertTrue(objectIds ~= nil and next(objectIds) ~= nil, 'addGlobalOption must register an object-type option')
    harness.assertTrue(playerIds ~= nil and next(playerIds) ~= nil, 'addGlobalOption must register a player-type option')

    harness.assertTrue(removeGlobalOption(groupId), 'removeGlobalOption must report success')
    harness.assertTrue(Target.byGlobalType.ped == nil, 'removeGlobalOption must clear the ped-type registration')
    harness.assertTrue(Target.byGlobalType.vehicle == nil, 'removeGlobalOption must clear the vehicle-type registration')
    harness.assertTrue(Target.byGlobalType.object == nil, 'removeGlobalOption must clear the object-type registration')
    harness.assertTrue(Target.byGlobalType.player == nil, 'removeGlobalOption must clear the player-type registration')
    harness.assertFalse(removeGlobalOption(groupId), 'removeGlobalOption must be a no-op the second time')
end)

harness.test('addEntity/removeEntity bridge network ids to local entity handles', function()
    networkEntities[555] = 21

    local id = addEntity(555, { { label = 'Loot', onSelect = function() end } })
    harness.assertTrue(Target.registrations[id] ~= nil, 'addEntity must register against the resolved local handle')
    harness.assertTrue(Target.byEntity[21] ~= nil, 'addEntity must index under the LOCAL handle, not the network id')

    harness.assertTrue(removeEntity(555), 'removeEntity must resolve the same network id back to the local handle')
    harness.assertTrue(Target.byEntity[21] == nil, 'removeEntity must clear the local-handle index')
end)

harness.test('addEntity/removeEntity accept an array of network ids', function()
    networkEntities[601] = 31
    networkEntities[602] = 32

    local id = addEntity({ 601, 602 }, { { label = 'Loot', onSelect = function() end } })
    harness.assertTrue(Target.byEntity[31] ~= nil, 'addEntity must resolve every network id in the array')
    harness.assertTrue(Target.byEntity[32] ~= nil, 'addEntity must resolve every network id in the array')

    harness.assertTrue(removeEntity({ 601, 602 }), 'removeEntity must remove every resolved entity')
    harness.assertTrue(Target.byEntity[31] == nil, 'removeEntity must clear all resolved local handles')
    harness.assertTrue(Target.byEntity[32] == nil, 'removeEntity must clear all resolved local handles')
end)

harness.test('isActive reflects the targeting session (Target.active), not what is hovered', function()
    Target.active, Target.hovering = false, nil
    harness.assertFalse(isActive(), 'isActive must be false when no targeting session is running')
    Target.hovering = { registrationId = 1 }
    harness.assertFalse(isActive(), 'hovering alone must not make isActive true')
    Target.hovering = nil
    Target.active = true
    harness.assertTrue(isActive(), 'isActive must be true for the whole session even with nothing under the reticle')
    Target.active = false
    harness.assertEqual(getState().active, false, 'getState exposes the same flag isActive reads')
end)


-- These invoke QBtarget's actual resolver/selector; native game and menu boundaries are inert.
local function clearRegistrations()
    local ids = {}
    for id in pairs(Target.registrations) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do Target.destroyRegistration(id) end
    Target._testRuntime.closeTargetMenu()
    Target._testRuntime.resetRuntimeState()
end

local function assertHitCoords(response, point)
    local args = vectorCalls[response.coords]
    harness.assertTrue(args ~= nil, 'compat coords must use the vector3 constructor')
    harness.assertTrue(response.coords ~= point, 'construct the vector at the compatibility boundary')
    harness.assertEqual(args.n, 3)
    harness.assertEqual(args[1], point.x)
    harness.assertEqual(args[2], point.y)
    harness.assertEqual(args[3], point.z)
end

local function resolve(entity, point)
    return Target._testRuntime.resolveCandidates(true, entity, point, 1, vector3(0, 0, 0))
end

harness.test('compat callbacks receive the captured hit, including delayed selection and zone identity', function()
    clearRegistrations()
    local response, calls = nil, 0
    local option = { label = 'Inspect', name = 'inspect', distance = 2,
        onSelect = function(data) response = data; calls = calls + 1 end }
    addLocalEntity(40, { option, { label = 'Other', onSelect = function() error('wrong choice') end } })
    local point = { x = 1.5, y = 0, z = 0 }
    local candidates = resolve(40, point)
    harness.assertEqual(#candidates, 2)
    Target._testRuntime.selectCandidates(candidates)
    local choose = selectedItems[1].action
    Target._testRuntime.resetRuntimeState()
    resolve(99, vector3(2, 0, 0))
    choose()
    harness.assertEqual(calls, 1)
    harness.assertEqual(type(response), 'table')
    harness.assertEqual(response.entity, 40)
    assertHitCoords(response, point)
    harness.assertEqual(response.distance, 1.5)
    harness.assertEqual(response.zone, nil)
    harness.assertEqual(option.entity, nil, 'selection must not alter caller options')
    harness.assertEqual(option.coords, nil)

    clearRegistrations()
    local oldSphere = Kora.zones.sphere
    Kora.zones.sphere = function() return { remove = function() end, contains = function() return true end } end
    local zone = getExport('addSphereZone')({ coords = point, radius = 1,
        options = { { label = 'Zone', onSelect = function(data) response = data end } } })
    Target._testRuntime.selectCandidates(resolve(0, point))
    harness.assertEqual(response.zone, zone)
    harness.assertEqual(response.entity, 0, 'world geometry uses the documented numeric no-entity value')
    assertHitCoords(response, point)
    harness.assertEqual(response.distance, 1.5)
    Kora.zones.sphere = oldSphere
    clearRegistrations()
end)

harness.test('compat client and server events receive one response; server entity uses network identity', function()
    clearRegistrations()
    local point = { x = 1, y = 0, z = 0 }
    addLocalEntity(70, { { label = 'Client', event = 'consumer:client' } })
    Target._testRuntime.selectCandidates(resolve(70, point))
    local client = clientEvents[#clientEvents]
    harness.assertEqual(client.name, 'consumer:client')
    harness.assertEqual(client.args.n, 1)
    harness.assertEqual(type(client.args[1]), 'table')
    harness.assertEqual(client.args[1].entity, 70)
    assertHitCoords(client.args[1], point)
    harness.assertEqual(client.args[1].distance, 1)
    clearRegistrations()

    local clientCount = #clientEvents
    addLocalEntity(70, { { label = 'Server', serverEvent = 'consumer:server' } })
    Target._testRuntime.selectCandidates(resolve(70, point))
    local server = serverEvents[#serverEvents]
    harness.assertEqual(server.name, 'consumer:server')
    harness.assertEqual(server.args.n, 1)
    harness.assertEqual(type(server.args[1]), 'table')
    harness.assertEqual(server.args[1].entity, 700, 'network ID, never the local handle')
    assertHitCoords(server.args[1], point)
    harness.assertEqual(server.args[1].distance, 1)
    harness.assertEqual(#clientEvents, clientCount, 'serverEvent alone triggers no client event')
    clearRegistrations()

    addLocalEntity(71, { { label = 'Local only', serverEvent = 'consumer:server' } })
    Target._testRuntime.selectCandidates(resolve(71, point))
    harness.assertEqual(serverEvents[#serverEvents].args[1].entity, 0, 'unnetworked entity is never exposed as a server handle')
    clearRegistrations()
end)

harness.test('native callback arity and legacy action handles remain unchanged', function()
    clearRegistrations()
    local args
    Target.addEntity(80, { { label = 'Native', data = false, onSelect = function(...) args = table.pack(...) end } })
    Target._testRuntime.selectCandidates(resolve(80, vector3(1, 0, 0)))
    harness.assertEqual(args.n, 2)
    harness.assertEqual(args[1], 80)
    harness.assertEqual(args[2], false)
    clearRegistrations()
    addLocalEntity(82, { { label = 'Compat callback', onSelect = function(...) args = table.pack(...) end } })
    Target._testRuntime.selectCandidates(resolve(82, vector3(1, 0, 0)))
    harness.assertEqual(args.n, 1)
    harness.assertEqual(type(args[1]), 'table')
    harness.assertEqual(args[1].entity, 82)
    clearRegistrations()
    addLocalEntity(81, { { label = 'Legacy action', action = function(...) args = table.pack(...) end } })
    Target._testRuntime.selectCandidates(resolve(81, vector3(1, 0, 0)))
    harness.assertEqual(args.n, 1)
    harness.assertEqual(args[1], 81)
    clearRegistrations()
end)

harness.test('named global type removal preserves other options, native registrations and universal entries', function()
    clearRegistrations()
    for _, entityType in ipairs({ 'Ped', 'Player', 'Vehicle', 'Object' }) do
        local add, remove = getExport('addGlobal' .. entityType), getExport('removeGlobal' .. entityType)
        local id = add({
            { name = 'first', label = 'First', onSelect = function() end },
            { name = 'keep', label = 'Keep', distance = 1.25, onSelect = function() end },
            { name = 'last', label = 'Last', onSelect = function() end },
        })
        local keep = Target.registrations[id].options[2]
        local native = Target.addGlobalType(entityType:lower(), { { name = 'first', label = 'Native', onSelect = function() end } })
        local universal = addGlobalOption({ { name = 'first', label = 'Universal', onSelect = function() end } })
        local revision = Target.registrationRevision
        harness.assertTrue(remove('first'))
        harness.assertEqual(#Target.registrations[id].options, 2, 'remove the option name, not a registration ID')
        harness.assertEqual(Target.registrations[id].options[1], keep)
        harness.assertEqual(keep.distance, 1.25)
        harness.assertTrue(Target.registrationRevision > revision, 'invalidate the resolver on option changes')
        harness.assertTrue(Target.registrations[native] ~= nil, 'native registrations remain outside named compatibility removal')
        local universalCount = 0
        for _, registration in pairs(Target.registrations) do
            if registration.options[1].label == 'Universal' then universalCount = universalCount + 1 end
        end
        harness.assertEqual(universalCount, 4, 'type-specific removal retains every universal entry')
        harness.assertFalse(remove('unknown'))
        harness.assertFalse(remove({}))
        harness.assertTrue(remove({ 'last', 'missing' }))
        harness.assertEqual(#Target.registrations[id].options, 1)
        harness.assertEqual(Target.registrations[id].options[1], keep)
        harness.assertTrue(remove({ 'keep' }))
        harness.assertEqual(Target.registrations[id], nil)
        harness.assertEqual(Target.ownership.owner(id), nil)
        harness.assertFalse(remove('keep'))
        harness.assertTrue(remove(id), 'numeric aliases retain the previous return behavior')
        harness.assertTrue(removeGlobalOption(universal), 'type-specific removal did not remove the universal group alias')
        Target.destroyRegistration(native)
    end
    clearRegistrations()
end)

harness.test('named universal removal updates every type while preserving type-specific and numeric aliases', function()
    clearRegistrations()
    local scoped = addGlobalPed({ { name = 'remove', label = 'Type-specific', onSelect = function() end } })
    local native = Target.addGlobalType('ped', { { name = 'remove', label = 'Native', onSelect = function() end } })
    local group = addGlobalOption({
        { name = 'remove', label = 'Remove', onSelect = function() end },
        { name = 'keep', label = 'Keep', onSelect = function() end },
    })
    local otherGroup = addGlobalOption({ { name = 'other', label = 'Other', onSelect = function() end } })
    harness.assertTrue(removeGlobalOption('remove'))
    for _, entityType in ipairs({ 'ped', 'player', 'vehicle', 'object' }) do
        local kept, other = 0, 0
        for id in pairs(Target.byGlobalType[entityType]) do
            if id ~= scoped and id ~= native then
                local options = Target.registrations[id].options
                harness.assertEqual(#options, 1)
                if options[1].name == 'keep' then kept = kept + 1 end
                if options[1].name == 'other' then other = other + 1 end
            end
        end
        harness.assertEqual(kept, 1)
        harness.assertEqual(other, 1)
    end
    harness.assertTrue(Target.registrations[scoped] ~= nil)
    harness.assertTrue(Target.registrations[native] ~= nil)
    harness.assertFalse(removeGlobalOption('unknown'))
    harness.assertFalse(removeGlobalOption({}))
    harness.assertTrue(removeGlobalOption({ 'keep', 'missing' }))
    harness.assertFalse(removeGlobalOption('keep'))
    harness.assertTrue(removeGlobalOption(group), 'keep the existing returned group ID removal alias')
    harness.assertFalse(removeGlobalOption(group))
    harness.assertTrue(removeGlobalOption(otherGroup))
    harness.assertFalse(removeGlobalOption(nil))
    harness.assertFalse(removeGlobalOption(false))
    clearRegistrations()
end)

harness.test('named removals skip retired owned registrations and preserve nil/false whole-type cleanup', function()
    clearRegistrations()
    invokingResource = 'retired-consumer'
    local retired = addGlobalPed({ { name = 'retired', label = 'Retired', onSelect = function() end } })
    addGlobalOption({ { name = 'retired-universal', label = 'Retired universal', onSelect = function() end } })
    invokingResource = 'live-consumer'
    local live = addGlobalPed({ { name = 'live', label = 'Live', onSelect = function() end } })
    for _, handler in ipairs(resourceStopHandlers) do handler('retired-consumer') end
    harness.assertEqual(Target.registrations[retired], nil)
    harness.assertFalse(removeGlobalPed('retired'))
    harness.assertFalse(removeGlobalOption('retired-universal'))
    harness.assertTrue(Target.registrations[live] ~= nil)
    harness.assertTrue(removeGlobalPed(false), 'false retains whole-type cleanup')
    harness.assertEqual(Target.registrations[live], nil)
    harness.assertFalse(removeGlobalPed())
    local numeric = addGlobalPed({ { name = 'numeric', label = 'Numeric', onSelect = function() end } })
    harness.assertTrue(removeGlobalPed(numeric))
    harness.assertEqual(Target.registrations[numeric], nil)
    invokingResource = 'ox-doorlock'
    clearRegistrations()
end)


-- ox_inventory 2.48.1-shaped payloads for the seven exports it uses.
local addModel, removeModel = getExport('addModel'), getExport('removeModel')
local addGlobalVehicle, removeLocalEntity = getExport('addGlobalVehicle'), getExport('removeLocalEntity')
local addBoxZone, removeZone = getExport('addBoxZone'), getExport('removeZone')

local function hashOf(name) return name end

harness.test('ox_inventory addModel with a single option table; removeModel(model, name) removes only that option', function()
    clearRegistrations()
    local id = addModel({ 'prop_dumpster_01a', 'prop_dumpster_02a' }, {
        icon = 'fas fa-dumpster', label = 'Search', onSelect = function() end, distance = 2,
    })
    harness.assertTrue(Target.registrations[id] ~= nil, 'a bare option table registers')
    harness.assertEqual(Target.registrations[id].options[1].distance, 2)
    harness.assertEqual(Target.registrations[id].options[1].icon, 'fas fa-dumpster')

    -- shop pattern: removeModel(model, shop.name) then addModel(model, { { name = ... } })
    local shop = addModel('s_m_y_shop_01', { { name = 'Shop A', label = 'Shop A', onSelect = function() end },
        { name = 'Shop B', label = 'Shop B', onSelect = function() end } })
    harness.assertFalse(removeModel('s_m_y_shop_01', 'nope'))
    harness.assertTrue(removeModel('s_m_y_shop_01', 'Shop A'))
    harness.assertEqual(#Target.registrations[shop].options, 1)
    harness.assertEqual(Target.registrations[shop].options[1].name, 'Shop B')
    harness.assertTrue(removeModel('s_m_y_shop_01', { 'Shop B' }))
    harness.assertEqual(Target.registrations[shop], nil, 'last named option removes the registration')
    harness.assertTrue(Target.registrations[id] ~= nil, 'unrelated models untouched')
    harness.assertTrue(removeModel({ 'prop_dumpster_01a', 'prop_dumpster_02a' }), 'no names removes everything')
    harness.assertEqual(Target.registrations[id], nil)
    clearRegistrations()
end)

harness.test('removeModel(model, names) leaves native registrations on the same model alone', function()
    clearRegistrations()
    local native = Target.addModel('prop_x', { { name = 'same', label = 'Native', onSelect = function() end } })
    addModel('prop_x', { { name = 'same', label = 'Ox', onSelect = function() end } })
    harness.assertTrue(removeModel('prop_x', 'same'))
    harness.assertTrue(Target.registrations[native] ~= nil)
    clearRegistrations()
end)

harness.test('ox_inventory addLocalEntity (shop ped) and removeLocalEntity(entity) / by name', function()
    clearRegistrations()
    addLocalEntity(90, { { icon = 'fas fa-shopping-basket', label = 'Open', groups = nil, iconColor = 'red',
        onSelect = function() end, distance = 2.0 } })
    harness.assertTrue(Target.byEntity[90] ~= nil)
    harness.assertEqual(Target.registrations[next(Target.byEntity[90])].options[1].iconColor, 'red')
    harness.assertTrue(removeLocalEntity(90))
    harness.assertTrue(Target.byEntity[90] == nil)
    harness.assertFalse(removeLocalEntity(90))

    addLocalEntity(91, { { name = 'a', label = 'A', onSelect = function() end }, { name = 'b', label = 'B', onSelect = function() end } })
    harness.assertTrue(removeLocalEntity(91, 'a'))
    harness.assertTrue(removeLocalEntity(91, { 'b' }))
    harness.assertTrue(Target.byEntity[91] == nil)
    clearRegistrations()
end)

harness.test('addGlobalVehicle: canInteract receives (entity, distance, coords, name, bone); returns id', function()
    clearRegistrations()
    local args
    local id = addGlobalVehicle({ {
        name = 'trunk', icon = 'fas fa-truck-ramp-box', label = 'Open storage', distance = 1.5,
        canInteract = function(...) args = table.pack(...); return true end,
        onSelect = function() end,
    } })
    harness.assertEqual(type(id), 'number')
    local candidates = Target._testRuntime.resolveCandidates(true, 12, vector3(1, 0, 0), 1, vector3(0, 0, 0))
    harness.assertEqual(#candidates, 0, 'vehicle global only matches vehicles (stub entity type is object)')
    local option = Target.registrations[id].options[1]
    harness.assertTrue(option.canInteract(12, 1.0, nil, { x = 1, y = 2, z = 3 }))
    harness.assertEqual(args.n, 5)
    harness.assertEqual(args[1], 12)
    harness.assertEqual(args[2], 1.0)
    harness.assertEqual(args[3].x, 1)
    harness.assertEqual(args[4], 'trunk')
    harness.assertEqual(args[5], nil)
    harness.assertTrue(removeGlobalVehicle(id) )
    clearRegistrations()
end)

local function withPlayer(job, gang, fn)
    local previous = Target._playerData
    Target._playerData = function() return true, { job = job, gang = gang } end
    fn()
    Target._playerData = previous
end

harness.test('groups: string, array and map forms are enforced against job/gang; canInteract ANDs', function()
    clearRegistrations()
    local police = { name = 'police', grade = { level = 2 } }
    local function allowed(groups, job, gang, userCheck)
        local ok
        withPlayer(job, gang or { name = 'none', grade = { level = 0 } }, function()
            local id = addGlobalVehicle({ { label = 'G', groups = groups, canInteract = userCheck, onSelect = function() end } })
            ok = Target.registrations[id].options[1].canInteract(1, 1.0)
            Target.destroyRegistration(id)
        end)
        return ok
    end
    harness.assertTrue(allowed('police', police))
    harness.assertFalse(allowed('ambulance', police))
    harness.assertTrue(allowed({ 'ambulance', 'police' }, police))
    harness.assertFalse(allowed({ 'ambulance', 'fire' }, police))
    harness.assertTrue(allowed({ police = 2 }, police))
    harness.assertFalse(allowed({ police = 3 }, police))
    harness.assertTrue(allowed({ ballas = 1 }, police, { name = 'ballas', grade = { level = 1 } }))
    harness.assertFalse(allowed('police', police, nil, function() return false end), 'own canInteract still applies')

    local noPlayer
    local previous = Target._playerData
    Target._playerData = function() return true, nil end
    local id = addGlobalVehicle({ { label = 'G', groups = 'police', onSelect = function() end } })
    noPlayer = Target.registrations[id].options[1].canInteract(1, 1.0)
    Target._playerData = previous
    harness.assertFalse(noPlayer, 'loaded identity layer but no player data denies')
    Target.destroyRegistration(id)

    -- no identity resource at all: never denies
    id = addGlobalVehicle({ { label = 'G', groups = 'police', onSelect = function() end } })
    harness.assertTrue(Target.registrations[id].options[1].canInteract(1, 1.0))
    clearRegistrations()
end)

harness.test('ox_inventory addBoxZone: returns an id removeZone accepts (crafting + evidence/stash shapes)', function()
    clearRegistrations()
    local crafted = addBoxZone({
        name = 'craftingbench_1:1', id = 1, index = 1,
        coords = vector3(10, 20, 30), size = vector3(1.5, 1.5, 2.0), rotation = 45, debug = false, drawSprite = false,
        options = { { label = 'Crafting', icon = 'fas fa-wrench', distance = 2.0,
            canInteract = function() return true end, onSelect = function() end } },
    })
    harness.assertEqual(type(crafted), 'number')
    harness.assertEqual(Target.registrations[crafted].kind, 'zone')

    -- Utils.CreateBoxZone: legacy data converted to coords/size/rotation, options attached after
    local stash = addBoxZone({ coords = vector3(1, 2, 3), size = vector3(2, 2, 2), rotation = 0.0,
        options = { { icon = 'fas fa-warehouse', label = 'Stash', groups = { police = 0 }, iconColor = 'blue',
            onSelect = function() end, distance = 2.0 } } })
    harness.assertTrue(removeZone(stash))
    harness.assertEqual(Target.registrations[stash], nil)
    harness.assertFalse(removeZone(stash), 'second removal is a no-op')
    harness.assertFalse(removeZone(nil))
    harness.assertFalse(removeZone(99999))

    harness.assertTrue(removeZone('craftingbench_1:1'), 'zones are also removable by their name')
    harness.assertEqual(Target.registrations[crafted], nil)

    local defaults = addBoxZone({ coords = vector3(0, 0, 0), options = { { label = 'x', onSelect = function() end } } })
    harness.assertTrue(Target.registrations[defaults] ~= nil, 'size and rotation default like ox_target')
    harness.assertTrue(removeZone(defaults))
    clearRegistrations()
end)

-- ---------------------------------------------------------------------------
-- Option fields: export, command, event/serverEvent order, response, items,
-- offset, menus, zone names.
-- ---------------------------------------------------------------------------
local executed, exportCalls, heldItems = {}, {}, {}
_G.ExecuteCommand = function(command) executed[#executed + 1] = command end
_G.exports = setmetatable({
    kora_inventory = { HasItem = function(_, name, amount)
        return (heldItems[name] or 0) >= (amount or 1)
    end },
}, { __index = function(_, resource)
    return setmetatable({}, { __index = function(_, fn)
        return function(...) exportCalls[#exportCalls + 1] = { resource = resource, fn = fn, args = table.pack(...) } end
    end })
end })

local function select1(entity, point)
    Target._testRuntime.selectCandidates(resolve(entity, point or vector3(1, 0, 0)))
end

harness.test('export option calls exports[resource][export](nil, response) on the registering resource', function()
    clearRegistrations()
    invokingResource = 'consumer-res'
    addLocalEntity(100, { { name = 'ex', label = 'Ex', icon = 'x', export = 'doThing', items = 'a', groups = 'g',
        custom = 7 } })
    invokingResource = 'ox-doorlock'
    heldItems.a = 1
    select1(100)
    local call = exportCalls[#exportCalls]
    harness.assertEqual(call.resource, 'consumer-res')
    harness.assertEqual(call.fn, 'doThing')
    harness.assertEqual(call.args.n, 2)
    harness.assertEqual(call.args[1], nil, 'upstream passes nil as the first argument')
    harness.assertEqual(call.args[2].entity, 100)
    harness.assertEqual(call.args[2].name, 'ex')
    harness.assertEqual(call.args[2].custom, 7, 'option fields flow through like upstream getResponse')
    harness.assertEqual(call.args[2].icon, nil)
    harness.assertEqual(call.args[2].items, nil)
    harness.assertEqual(call.args[2].groups, nil)
    harness.assertEqual(call.args[2].export, nil)
    heldItems.a = nil
    clearRegistrations()
end)

harness.test('command runs via ExecuteCommand; precedence is onSelect > export > event > serverEvent > command', function()
    clearRegistrations()
    addLocalEntity(101, { { label = 'Cmd', command = 'me waves' } })
    select1(101)
    harness.assertEqual(executed[#executed], 'me waves')
    clearRegistrations()

    local clientCount, serverCount, execCount, exportCount = #clientEvents, #serverEvents, #executed, #exportCalls
    addLocalEntity(101, { { label = 'Both', event = 'e:client', serverEvent = 'e:server', command = 'nope' } })
    select1(101)
    harness.assertEqual(#clientEvents, clientCount + 1, 'event wins over serverEvent like upstream')
    harness.assertEqual(#serverEvents, serverCount)
    harness.assertEqual(#executed, execCount, 'command not run when event handled')
    clearRegistrations()

    invokingResource = 'consumer-res'
    addLocalEntity(101, { { label = 'Exp', export = 'f', event = 'e:client2', command = 'nope' } })
    invokingResource = 'ox-doorlock'
    clientCount = #clientEvents
    select1(101)
    harness.assertEqual(#exportCalls, exportCount + 1, 'export wins over event')
    harness.assertEqual(#clientEvents, clientCount)
    clearRegistrations()
end)

harness.test('items / anyItem are checked through kora_inventory HasItem', function()
    clearRegistrations()
    local function visible(items, anyItem)
        clock = clock + 1000 -- step past the HasItem cache
        clearRegistrations()
        addLocalEntity(110, { { label = 'I', items = items, anyItem = anyItem, onSelect = function() end } })
        return #resolve(110, vector3(1, 0, 0)) == 1
    end
    heldItems = {}
    harness.assertFalse(visible('lockpick'))
    heldItems = { lockpick = 1 }
    harness.assertTrue(visible('lockpick'))
    harness.assertFalse(visible({ 'lockpick', 'screwdriver' }), 'array form requires all')
    harness.assertTrue(visible({ 'lockpick', 'screwdriver' }, true), 'anyItem needs one')
    heldItems = { lockpick = 1, screwdriver = 1 }
    harness.assertTrue(visible({ 'lockpick', 'screwdriver' }))
    heldItems = { money = 50 }
    harness.assertTrue(visible({ money = 50 }))
    harness.assertFalse(visible({ money = 51 }))
    harness.assertFalse(visible({ money = 51, lockpick = 1 }, true))
    harness.assertTrue(visible({ money = 50, lockpick = 1 }, true))
    heldItems = {}
    clearRegistrations()
end)

harness.test('offset / offsetSize / absoluteOffset gate on the aim point', function()
    clearRegistrations()
    _G.GetModelDimensions = function() return vector3(-1, -2, 0), vector3(1, 2, 2) end
    _G.GetOffsetFromEntityInWorldCoords = function(_, x, y, z) return { x = 10 + x, y = y, z = z } end
    local function visible(option)
        clearRegistrations()
        option.label, option.onSelect, option.distance = 'O', function() end, 20
        addLocalEntity(120, { option })
        return #resolve(120, { x = 11, y = 2, z = 2 }) == 1
    end
    -- relative (0.5,..) of dims: min + (max-min)*offset = (0, 0, 1) -> world (10,0,1); aim (11,2,2) is 2.45 away
    harness.assertFalse(visible({ offset = vector3(0.5, 0.5, 0.5) }))
    harness.assertTrue(visible({ offset = vector3(0.5, 0.5, 0.5), offsetSize = 3 }))
    -- absolute offset (1,2,2) -> world (11,2,2): exact hit
    harness.assertTrue(visible({ offset = vector3(1, 2, 2), absoluteOffset = true }))
    harness.assertTrue(visible({ offset = vector3(1, 2, 2), offsetAbsolute = true }))
    harness.assertFalse(visible({ offset = vector3(-1, 2, 2), absoluteOffset = true }))
    -- zones ignore offset (upstream applies it to model/entity hits only)
    clearRegistrations()
    local oldSphere = Kora.zones.sphere
    Kora.zones.sphere = function() return { remove = function() end, contains = function() return true end } end
    getExport('addSphereZone')({ coords = vector3(11, 2, 2), radius = 1, options = {
        { label = 'Z', distance = 20, offset = vector3(0, 0, 0), onSelect = function() end } } })
    harness.assertEqual(#resolve(0, { x = 11, y = 2, z = 2 }), 1)
    Kora.zones.sphere = oldSphere
    _G.GetModelDimensions, _G.GetOffsetFromEntityInWorldCoords = nil, nil
    clearRegistrations()
end)

harness.test('distance is honoured per option', function()
    clearRegistrations()
    addLocalEntity(130, { { label = 'Near', distance = 1, onSelect = function() end },
        { label = 'Far', distance = 5, onSelect = function() end } })
    harness.assertEqual(#resolve(130, vector3(3, 0, 0)), 1)
    harness.assertEqual(#resolve(130, vector3(0.5, 0, 0)), 2)
    clearRegistrations()
end)

harness.test('HasItem results are cached ~300ms and dropped on inventory events', function()
    local calls = 0
    local realHas = _G.exports.kora_inventory.HasItem
    _G.exports.kora_inventory.HasItem = function(self, name, amount) calls = calls + 1; return realHas(self, name, amount) end
    local function visible()
        clearRegistrations()
        addLocalEntity(115, { { label = 'C', items = 'cachey', onSelect = function() end } })
        return #resolve(115, vector3(1, 0, 0)) == 1
    end
    clock = clock + 1000
    heldItems = { cachey = 1 }
    harness.assertTrue(visible())
    local first = calls
    harness.assertTrue(visible())
    harness.assertEqual(calls, first, 'second pass inside 300 ms is served from cache')
    heldItems = {}
    harness.assertTrue(visible(), 'stale until expiry')
    clock = clock + 301
    harness.assertFalse(visible(), 'refreshed after 300 ms')
    heldItems = { cachey = 1 }
    harness.assertFalse(visible())
    harness.assertTrue(netHandlers['qb-inventory:client:updateInventory'] ~= nil, 'inventory event handler registered')
    netHandlers['qb-inventory:client:updateInventory']()
    harness.assertTrue(visible(), 'inventory event invalidates cache')
    _G.exports.kora_inventory.HasItem = realHas
    heldItems = {}
    clearRegistrations()
end)

harness.test('openMenu / menuName sub-menus with go-back', function()
    clearRegistrations()
    local now = 0
    _G.GetGameTimer = function() return now end
    local ran = {}
    addLocalEntity(140, {
        { name = 'root', label = 'Root', openMenu = 'sub', onSelect = function() ran[#ran + 1] = 'root' end },
        { name = 'home', label = 'Home only', onSelect = function() ran[#ran + 1] = 'home' end },
        { name = 'child', label = 'Child', menuName = 'sub', onSelect = function() ran[#ran + 1] = 'child' end },
        { name = 'deep', label = 'Deep', menuName = 'sub', openMenu = 'sub2' },
        { name = 'leaf', label = 'Leaf', menuName = 'sub2', onSelect = function() ran[#ran + 1] = 'leaf' end },
    })
    local function names()
        Target._testRuntime.resetRuntimeState()
        local out = {}
        for _, c in ipairs(resolve(140, vector3(1, 0, 0))) do out[#out + 1] = c.option.name end
        table.sort(out)
        return table.concat(out, ',')
    end
    harness.assertEqual(names(), 'home,root')
    Target._testRuntime.selectCandidates(resolve(140, vector3(1, 0, 0))) -- menu of 2: opens selector
    selectedItems[1].action() -- first sorted by candidate order = root
    harness.assertEqual(ran[#ran], 'root', 'the openMenu option still runs its handler')
    Target._testRuntime.resetRuntimeState()
    harness.assertEqual(names(), 'builtin:goback,child,deep', 'sub-menu shows its options plus go-back (stub entity is an object)')

    -- go deeper, then back twice
    for _, c in ipairs(resolve(140, vector3(1, 0, 0))) do
        if c.option.name == 'deep' then c.option._onSelectContext(c) end
    end
    harness.assertEqual(names(), 'builtin:goback,leaf')
    for _, c in ipairs(resolve(140, vector3(1, 0, 0))) do
        if c.option.name == 'builtin:goback' then c.option._onSelectContext(c) end
    end
    harness.assertEqual(names(), 'builtin:goback,child,deep', 'go-back returns to the parent menu')
    for _, c in ipairs(resolve(140, vector3(1, 0, 0))) do
        if c.option.name == 'builtin:goback' then c.option._onSelectContext(c) end
    end
    harness.assertEqual(names(), 'home,root', 'go-back from the first level returns home and removes go-back')

    -- timeout resets a forgotten sub-menu
    for _, c in ipairs(resolve(140, vector3(1, 0, 0))) do
        if c.option.name == 'root' then c.option._onSelectContext(c) end
    end
    harness.assertEqual(names(), 'builtin:goback,child,deep')
    now = 20000
    harness.assertEqual(names(), 'home,root', 'menu expires after kora_target:oxMenuTimeoutMs')
    clearRegistrations()
    _G.GetGameTimer = function() return clock end
end)

harness.test('zone sub-menus get their own go-back', function()
    clearRegistrations()
    _G.GetGameTimer = function() return clock end
    local id = addBoxZone({ coords = vector3(0, 0, 0), size = vector3(2, 2, 2), options = {
        { name = 'zroot', label = 'Z', openMenu = 'zsub', onSelect = function() end },
        { name = 'zchild', label = 'ZC', menuName = 'zsub', onSelect = function() end },
    } })
    local function names()
        local out = {}
        for _, opt in ipairs(Target.registrations[id].options) do
            if opt.canInteract(0, 1, nil, nil) then out[#out + 1] = opt.name end
        end
        table.sort(out)
        return table.concat(out, ',')
    end
    harness.assertEqual(names(), 'zroot')
    for _, opt in ipairs(Target.registrations[id].options) do
        if opt.name == 'zroot' then opt._onSelectContext({ entity = 0, registration = Target.registrations[id] }) end
    end
    harness.assertEqual(names(), 'builtin:goback,zchild')
    for _, opt in ipairs(Target.registrations[id].options) do
        if opt.name == 'builtin:goback' then opt._onSelectContext({ entity = 0, registration = Target.registrations[id] }) end
    end
    harness.assertEqual(names(), 'zroot', 'go-back from a zone returns home')
    removeZone(id)
    clearRegistrations()
end)

harness.test('sphere and poly zones are removable by name', function()
    clearRegistrations()
    local oldSphere, oldPoly = Kora.zones.sphere, Kora.zones.poly
    local removed = 0
    local function handle() return { remove = function() removed = removed + 1 end, contains = function() return false end } end
    Kora.zones.sphere, Kora.zones.poly = handle, handle
    local s = getExport('addSphereZone')({ name = 'my-sphere', coords = vector3(0, 0, 0), radius = 1,
        options = { { label = 'S', onSelect = function() end } } })
    local p = getExport('addPolyZone')({ name = 'my-poly',
        points = { vector3(0, 0, 0), vector3(1, 0, 0), vector3(1, 1, 0) }, thickness = 2,
        options = { { label = 'P', onSelect = function() end } } })
    harness.assertTrue(removeZone('my-sphere'))
    harness.assertEqual(Target.registrations[s], nil)
    harness.assertTrue(Target.registrations[p] ~= nil)
    harness.assertTrue(removeZone('my-poly'))
    harness.assertEqual(Target.registrations[p], nil)
    harness.assertFalse(removeZone('my-poly'))
    Kora.zones.sphere, Kora.zones.poly = oldSphere, oldPoly
    clearRegistrations()
end)

harness.test('manifest does not claim the ox_target name', function()
    local file = assert(io.open(resourceRoot .. 'fxmanifest.lua', 'r'))
    local manifest = file:read('*a')
    file:close()
    harness.assertTrue(not manifest:find("^%s*provide%s+['\"]ox_target['\"]") and not manifest:find("\n%s*provide%s+['\"]ox_target['\"]"), "kora_target must not provide 'ox_target'")
    harness.assertTrue(manifest:find("provide 'qb-target'", 1, true) ~= nil, "still provides 'qb-target'")
    harness.assertTrue(manifest:find("provide 'qbtarget'", 1, true) ~= nil, "still provides 'qbtarget'")
end)

harness.report('qbtarget ox_target compatibility')
