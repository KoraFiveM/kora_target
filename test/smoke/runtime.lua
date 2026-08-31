local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local resourceRoot = scriptDir .. '../../'
local qblibTestRoot = resourceRoot .. '../qblib/test/'
package.path = qblibTestRoot .. '?.lua;' .. package.path

local harness = require('harness')

local now, canInteractCalls, boneReads = 0, 0, 0
local commands = {}
local raycastResponses, raycastFlags = {}, {}
local zoneHandles, zoneCalls = {}, {}

-- Mirrors qblib's own zone handle shape (client/state.lua only relies on
-- .remove and .contains) without pulling in qblib's real box/sphere/poly
-- geometry -- each test controls containment directly by overriding the
-- handle's .contains after registering, so this stays a test of qbtarget's
-- own resolver wiring, not qblib's zone math (which has its own coverage).
local function makeZoneHandle(options)
    zoneCalls[#zoneCalls + 1] = options
    local handle = { remove = function() end, contains = function() return false end }
    zoneHandles[#zoneHandles + 1] = handle
    return handle
end

-- Records calls rather than doing anything real (like makeZoneHandle above) --
-- the qbtarget_debug command test only needs to prove client/loop.lua calls
-- through to QB.zones.setDebug with the right (id, enabled) pair, not qblib's
-- own runtime toggle behaviour (covered separately in qblib's own test suite).
local setDebugCalls = {}

_G.QB = {
    zones = {
        box = makeZoneHandle,
        sphere = makeZoneHandle,
        poly = makeZoneHandle,
        setDebug = function(id, enabled) setDebugCalls[#setDebugCalls + 1] = { id, enabled } end,
    },
    drawing = { text3d = function() end },
    raycast = { fromCamera = function(_, flags)
        raycastFlags[#raycastFlags + 1] = flags
        local response = table.remove(raycastResponses, 1) or { false }
        return table.unpack(response)
    end },
    nui = { send = function() end },
    callback = { trigger = function() end },
    keybind = {
        add = function(options)
            commands[options.name] = options.onPressed
            commands['-' .. options.name] = options.onReleased
            return { remove = function() return true end }
        end,
    },
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
_G.GetEntityType = function() return 1 end
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
dofile(resourceRoot .. 'client/sprites.lua')
dofile(resourceRoot .. 'client/loop.lua')

local runtime = Target._testRuntime
local sprites = Target._testSprites

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

harness.test('global zone debug and individual sprite visibility are retained on registrations', function()
    local priorDebug = Config.target.debug
    Config.target.debug = true

    local id = Target.addSphereZone({
        coords = { x = 12, y = 3, z = 4 },
        radius = 1.0,
        drawSprite = false,
        options = {{ label = 'Debug zone', onSelect = function() end }},
    })

    local registration = Target.registrations[id]
    harness.assertTrue(zoneCalls[#zoneCalls].debug, 'Config.target.debug must enable qblib zone outlines globally')
    harness.assertEqual(registration.spriteCoords.x, 12, 'a zone sprite should retain its world anchor')
    harness.assertTrue(registration.drawSprite == false, 'a zone must be able to opt out of configured sprites')
    harness.assertTrue(not sprites.canDraw(registration, { x = 12, y = 3, z = 4 }, Config.target.sprites),
        'per-zone sprite opt-out must be honoured')

    Config.target.debug = priorDebug
end)

harness.test('poly zones get a stable averaged sprite anchor and distance culling', function()
    local id = Target.addPolyZone({
        points = {
            { x = 0, y = 0, z = 10 },
            { x = 6, y = 0, z = 10 },
            { x = 3, y = 6, z = 10 },
        },
        options = {{ label = 'Poly sprite', onSelect = function() end }},
    })

    local registration = Target.registrations[id]
    harness.assertEqual(registration.spriteCoords.x, 3, 'poly sprite X should be the mean of its vertices')
    harness.assertEqual(registration.spriteCoords.y, 2, 'poly sprite Y should be the mean of its vertices')
    harness.assertTrue(sprites.canDraw(registration, { x = 3, y = 2, z = 10 }, Config.target.sprites),
        'nearby enabled zones should draw their sprite')
    harness.assertTrue(not sprites.canDraw(registration, { x = 1000, y = 2, z = 10 }, Config.target.sprites),
        'far-away zones must be rejected before any sprite native calls')
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

harness.test('an unresolved entity type is ignored before reaching GetEntityModel', function()
    local originalType, originalModel = GetEntityType, GetEntityModel
    _G.GetEntityType = function() return 0 end
    _G.GetEntityModel = function() error('an unresolved entity must not be queried') end

    local registrations = runtime.entityRegistrations(100)
    harness.assertEqual(#registrations, 0, 'an unresolved entity should have no registrations')

    _G.GetEntityType, _G.GetEntityModel = originalType, originalModel
end)

harness.test('addGlobalType takes the options array POSITIONALLY, not a { options = ... } envelope', function()
    -- The legacy qb-target shape ({ options = {...}, distance = n }) is only
    -- valid through the qb-target compat identity, which unwraps it. The
    -- native API takes a bare dense array -- qbpolice shipped 13 registrations
    -- using the envelope against the native export and every one of them
    -- failed validation at first client connect. Pin both directions.
    local id = Target.addGlobalType('player', {
        { label = 'Contract Check', onSelect = function() end },
    }, 2.0)
    harness.assertTrue(type(id) == 'number', 'a bare options array must register and return an id')
    Target.removeGlobalType('player', id)

    harness.assertThrows(function()
        Target.addGlobalType('player', {
            options = { { label = 'Enveloped', onSelect = function() end } },
        }, 2.0)
    end, 'the legacy { options = ... } envelope must be rejected by validation')
end)

harness.test('a faulting GetEntityModel handle is remembered and not re-invoked within the TTL', function()
    -- pcall stops the Lua error but CFX's native invoker logs
    -- `script error in native ...` BEFORE pcall catches it -- so re-invoking
    -- every 50ms tick spams the console. The failure cache must swallow
    -- repeat invocations for the same handle inside the TTL, re-probe after
    -- it, and never affect other handles.
    local originalModel = GetEntityModel
    local modelCalls = 0
    _G.GetEntityModel = function() modelCalls = modelCalls + 1; error('handle went stale mid-frame') end

    now = 100000
    harness.assertEqual(#runtime.entityRegistrations(501), 0, 'faulting handle yields no registrations')
    harness.assertEqual(modelCalls, 1, 'first probe reaches the native')
    now = now + 50
    runtime.entityRegistrations(501)
    harness.assertEqual(modelCalls, 1, 'same handle within the TTL must not re-invoke the native')
    runtime.entityRegistrations(502)
    harness.assertEqual(modelCalls, 2, 'a different handle is not blocked by 501\'s failure entry')
    now = now + 2000
    runtime.entityRegistrations(501)
    harness.assertEqual(modelCalls, 3, 'after the TTL the same handle is probed again')

    _G.GetEntityModel = originalModel
end)

harness.test('qbtarget_debug command toggles every target zone through QB.zones.setDebug(nil, ...)', function()
    -- client/loop.lua's own module chunk (loaded via dofile below, alongside
    -- state.lua) registers this -- Config.target.debug/zoneDebugEnabled stay
    -- the creation-time default; this command is the runtime override layered
    -- on top of qblib's QB.zones.setDebug, so it must reach QB.zones.setDebug
    -- with (nil, enabled) rather than touching any single zone's own handle.
    local handler = commands['qbtarget_debug']
    harness.assertTrue(handler ~= nil, 'client/loop.lua must register a qbtarget_debug command')

    setDebugCalls = {}
    Target.debugEnabled = false

    handler(nil, {})
    harness.assertEqual(#setDebugCalls, 1, 'a no-arg call should flip debug exactly once')
    harness.assertEqual(setDebugCalls[1][1], nil, 'the global toggle must pass a nil id, not a single zone id')
    harness.assertTrue(setDebugCalls[1][2], 'toggling from off should enable debug')
    harness.assertTrue(Target.debugEnabled, 'Target.debugEnabled should track the toggle so the next no-arg call reverses it')

    handler(nil, {})
    harness.assertEqual(#setDebugCalls, 2, 'a second no-arg call should flip debug again')
    harness.assertFalse(setDebugCalls[2][2], 'toggling from on should disable debug')
    harness.assertFalse(Target.debugEnabled, 'Target.debugEnabled should reflect the second toggle')

    handler(nil, { 'on' })
    harness.assertEqual(setDebugCalls[3][2], true, "'on' should enable debug regardless of the current state")

    handler(nil, { 'on' })
    harness.assertEqual(setDebugCalls[4][2], true, "'on' should enable debug again even though it was already on")

    handler(nil, { 'off' })
    harness.assertEqual(setDebugCalls[5][2], false, "'off' should disable debug regardless of the current state")

    Target.debugEnabled = false
end)

harness.report('qbtarget runtime')
