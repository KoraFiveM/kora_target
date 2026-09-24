local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local resourceRoot = scriptDir .. '../../'
local qblibTestRoot = resourceRoot .. '../qblib/test/'
package.path = qblibTestRoot .. '?.lua;' .. package.path

local harness = require('harness')
local exportsByEvent = {}

_G.Config = { target = { debug = false, maxDistance = 10.0 } }

_G.QB = {
    resources = {},
    util = { isCallable = function(value)
        if type(value) == 'function' then return true end
        local mt = type(value) == 'table' and getmetatable(value) or nil
        return mt ~= nil and mt.__call ~= nil
    end },
    compat = { isCallable = function(value) return QB.util.isCallable(value) end, provideExport = function(identity, name, fn)
        AddEventHandler(('__cfx_export_%s_%s'):format(identity, name), function(setCB) setCB(fn) end)
    end },
    zones = {
        box = function() return { remove = function() end, contains = function() return false end } end,
        sphere = function() return { remove = function() end, contains = function() return false end } end,
        poly = function() return { remove = function() end, contains = function() return false end } end,
    },
}
_G.GetCurrentResourceName = function() return 'qbtarget' end
_G.GetInvokingResource = function() return 'ox-doorlock' end
_G.AddEventHandler = function(name, handler) exportsByEvent[name] = handler end
_G.joaat = function(value) return value end
_G.vector3 = function(x, y, z) return { x = x, y = y, z = z } end

local networkEntities = {}
_G.NetworkGetEntityFromNetworkId = function(netId) return networkEntities[netId] end

dofile(resourceRoot .. '../qblib/local/resources/client.lua')
dofile(resourceRoot .. 'client/state.lua')
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
    local onSelectProxy = setmetatable({}, {
        __call = function(_, entity)
            calls = calls + 1
            harness.assertEqual(entity, 7, 'the entity handle must reach the proxied onSelect')
        end,
    })

    local id = addLocalEntity(7, { { label = 'Search', onSelect = onSelectProxy } })
    Target.registrations[id].options[1].onSelect(7)

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

harness.report('qbtarget ox_target compatibility')
