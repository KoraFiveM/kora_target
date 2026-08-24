local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local resourceRoot = scriptDir .. '../../'
local qblibTestRoot = resourceRoot .. '../qblib/test/'
package.path = qblibTestRoot .. '?.lua;' .. package.path

local harness = require('harness')

local now, canInteractCalls, boneReads = 0, 0, 0
local commands = {}
local raycastResponses, raycastFlags = {}, {}
local zoneHandles = {}

-- Mirrors qblib's own zone handle shape (client/state.lua only relies on
-- .remove and .contains) without pulling in qblib's real box/sphere/poly
-- geometry -- each test controls containment directly by overriding the
-- handle's .contains after registering, so this stays a test of qbtarget's
-- own resolver wiring, not qblib's zone math (which has its own coverage).
local function makeZoneHandle()
    local handle = { remove = function() end, contains = function() return false end }
    zoneHandles[#zoneHandles + 1] = handle
    return handle
end

_G.QB = {
    zones = {
        box = makeZoneHandle,
        sphere = makeZoneHandle,
        poly = makeZoneHandle,
    },
    drawing = { text3d = function() end },
    raycast = { fromCamera = function(_, flags)
        raycastFlags[#raycastFlags + 1] = flags
        local response = table.remove(raycastResponses, 1) or { false }
        return table.unpack(response)
    end },
    nui = { send = function() end },
    callback = { trigger = function() end },
}

_G.GetCurrentResourceName = function() return 'qbtarget' end
_G.GetInvokingResource = function() return nil end
_G.AddEventHandler = function() end
_G.CreateThread = function() end
_G.RegisterCommand = function(name, fn) commands[name] = fn end
_G.RegisterKeyMapping = function() end
_G.GetGameTimer = function() return now end
_G.PlayerPedId = function() return 1 end
_G.GetEntityCoords = function() return { x = 0, y = 0, z = 0 } end
_G.GetEntityModel = function() return 123 end
_G.DoesEntityExist = function() return true end
_G.IsEntityAPed = function() return true end
_G.IsPedAPlayer = function() return false end
_G.IsEntityAVehicle = function() return false end
_G.GetEntityBoneIndexByName = function() boneReads = boneReads + 1; return 0 end
_G.GetWorldPositionOfEntityBone = function() return { x = 0, y = 0, z = 0 } end
_G.joaat = function(value) return value end
_G.NetworkGetEntityIsNetworked = function() return true end
_G.NetworkGetNetworkIdFromEntity = function() return 1 end

dofile(resourceRoot .. 'config.lua')
Config.target.testMode = true
dofile(resourceRoot .. 'client/state.lua')
dofile(resourceRoot .. 'client/loop.lua')

local runtime = Target._testRuntime

harness.test('target registration mutations invalidate the aim cache', function()
    local first = runtime.entityRegistrations(99)
    local revision = Target.registrationRevision
    Target.addModel(123, {{ label = 'Inspect', onSelect = function() end }})
    harness.assertTrue(Target.registrationRevision > revision, 'adding a target should bump the resolver generation')
    local second = runtime.entityRegistrations(99)
    harness.assertTrue(first ~= second, 'registration generation must invalidate a stable aim cache')
end)

harness.test('canInteract results are cached only for the short configured window', function()
    local registration = { id = 999 }
    local option = { label = 'Cached', canInteract = function() canInteractCalls = canInteractCalls + 1; return true end }
    -- Production defaults to no cache for correctness; opt into a tiny cache
    -- here to exercise the optional performance path.
    Config.target.canInteractCacheMs = 75
    now = 0
    harness.assertTrue(runtime.optionAllowed(registration, 1, option, 99, 1.0, now), 'first evaluation should succeed')
    now = Config.target.canInteractCacheMs - 1
    runtime.optionAllowed(registration, 1, option, 99, 1.0, now)
    harness.assertEqual(canInteractCalls, 1, 'stable option should reuse its short-lived result')
    now = Config.target.canInteractCacheMs
    runtime.optionAllowed(registration, 1, option, 99, 1.0, now)
    harness.assertEqual(canInteractCalls, 2, 'expired result must be re-evaluated')
end)

harness.test('zone candidates are matched against the aim point, not the player position', function()
    Target.addBoxZone({
        coords = { x = 5, y = 0, z = 0 },
        size = { x = 2, y = 2, z = 2 },
        distance = 10, -- ped stays at {0,0,0} throughout; only the aim point should decide containment
        options = {{ label = 'Zone', onSelect = function() end }},
    })
    local handle = zoneHandles[#zoneHandles]
    handle.contains = function(point) return point.x == 5 end

    harness.assertEqual(#runtime.zoneRegistrationsAt({ x = 0, y = 0, z = 0 }), 0,
        'an aim point outside the zone must not surface it, even with the ped well within its configured distance')
    harness.assertEqual(#runtime.zoneRegistrationsAt({ x = 5, y = 0, z = 0 }), 1,
        'an aim point inside the zone must surface it regardless of where the ped is standing')
end)

harness.test('zone candidates require an actual raycast hit', function()
    local candidates = runtime.resolveCandidates(false, nil, nil, now)
    harness.assertEqual(#candidates, 0, 'no raycast hit means no aim point to test zones against')
end)

harness.test('bone lookups are memoized within one resolver pass', function()
    Target.addGlobalBone('door_dside_f', {{ label = 'Door', onSelect = function() end }}, 3.0)
    boneReads = 0
    now = 200
    runtime.resolveCandidates(true, 99, { x = 0, y = 0, z = 0 }, now)
    harness.assertEqual(boneReads, 1, 'one bone should be read once even when candidate filtering reuses it')
end)

harness.test('reset clears stale hover and candidates before a menu or stop', function()
    Target.hovering = { id = 123 }
    runtime.resetRuntimeState()
    harness.assertTrue(Target.hovering == nil, 'hover must be cleared')
    harness.assertEqual(runtime.candidateCount(), 0, 'candidate list must be cleared')
end)

harness.test('entity-focused fallback raycast finds a target when the broad cast misses', function()
    raycastFlags, raycastResponses = {}, {
        { false, nil, nil },
        { true, { x = 1, y = 0, z = 0 }, 99 },
    }
    local hit, coords, entity = runtime.raycastTarget()
    harness.assertTrue(hit, 'fallback entity hit should be returned')
    harness.assertEqual(entity, 99, 'fallback entity should be targetable')
    harness.assertEqual(raycastFlags[1], 511, 'broad raycast should use the world mask first')
    harness.assertEqual(raycastFlags[2], 26, 'entity-focused mask should be attempted second')
    harness.assertEqual(coords.x, 1, 'fallback hit coordinates should be preserved')
end)

harness.test('a stale raycast entity is ignored instead of reaching GetEntityModel', function()
    local originalExists, originalModel = DoesEntityExist, GetEntityModel
    _G.DoesEntityExist = function() return false end
    _G.GetEntityModel = function() error('stale entity must not be queried') end
    local registrations = runtime.entityRegistrations(99)
    harness.assertEqual(#registrations, 0, 'invalid entity should have no registrations')
    _G.DoesEntityExist, _G.GetEntityModel = originalExists, originalModel
end)

harness.report('qbtarget runtime')
