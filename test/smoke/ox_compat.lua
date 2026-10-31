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
_G.GetGameTimer = function() return 0 end
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

harness.test('isActive reflects Target.getState().hovering', function()
    harness.assertFalse(isActive(), 'isActive must be false with nothing hovered')
    Target.hovering = { registrationId = 1 }
    harness.assertTrue(isActive(), 'isActive must be true once Target.hovering is set')
    harness.assertEqual(getState().hovering, Target.hovering, 'getState must expose the same hovering value isActive reads')
    Target.hovering = nil
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
    addLocalEntity(70, { { label = 'Server', serverEvent = 'consumer:server', event = 'unused:client' } })
    Target._testRuntime.selectCandidates(resolve(70, point))
    local server = serverEvents[#serverEvents]
    harness.assertEqual(server.name, 'consumer:server')
    harness.assertEqual(server.args.n, 1)
    harness.assertEqual(type(server.args[1]), 'table')
    harness.assertEqual(server.args[1].entity, 700, 'network ID, never the local handle')
    assertHitCoords(server.args[1], point)
    harness.assertEqual(server.args[1].distance, 1)
    harness.assertEqual(#clientEvents, clientCount, 'retain existing bridge action priority')
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

harness.report('qbtarget ox_target compatibility')
