local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local resourceRoot = scriptDir .. '../../'
local qblibTestRoot = resourceRoot .. '../qblib/test/'
package.path = qblibTestRoot .. '?.lua;' .. package.path

local harness = require('harness')

local now, canInteractCalls, boneReads = 0, 0, 0
local commands = {}
local raycastResponses, raycastFlags, raycastProbes = {}, {}, {}
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
    -- client/loop.lua starts both probes before awaiting either (so the
    -- engine settles them in the same frame), so the stub has to model a
    -- handle: flags are recorded at START time and the queued response is
    -- claimed then, not when the caller gets round to awaiting it.
    raycast = {
        startFromCamera = function(_, flags)
            raycastFlags[#raycastFlags + 1] = flags
            raycastProbes[#raycastProbes + 1] = table.remove(raycastResponses, 1) or { false }
            return #raycastProbes
        end,
        await = function(handle)
            return table.unpack(raycastProbes[handle])
        end,
    },
    nui = { send = function() end },
    interact = {
        open = function(items)
            _G.interactItems = items
            return true
        end,
        isActive = function() return false end,
    },
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
_G.GetGameplayCamCoord = function() return { x = 0, y = 0, z = 0 } end
_G.GetGameplayCamRot = function() return { x = 0, y = 0, z = 0 } end
_G.GetScreenCoordFromWorldCoord = function() return false, 0, 0 end
_G.DrawSprite = function() end
_G.RequestStreamedTextureDict = function() end
_G.HasStreamedTextureDictLoaded = function() return true end
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

harness.test('multiple target options open qblib interact and dispatch the selected action', function()
    local selected = false
    runtime.selectCandidates({
        { option = { label = 'First', icon = 'one', onSelect = function() selected = true end } },
        { option = { label = 'Second', icon = 'two', onSelect = function() end } },
    })

    harness.assertEqual(#interactItems, 2, 'multiple candidates must use the interact selector')
    harness.assertEqual(interactItems[1].label, 'First', 'the interact selector must preserve option labels')
    harness.assertTrue(type(interactItems[1].action) == 'function', 'each interact entry must dispatch its candidate')
    interactItems[1].action()
    harness.assertTrue(selected, 'the selected interact entry must run its target action')
end)

harness.test('sprite worker is lazy and requires a sprite-enabled zone', function()
    harness.assertTrue(not sprites.isRunning(), 'loading qbtarget with no zones must not create a sprite worker')

    local previousEnabled = Config.target.sprites.enabled
    Config.target.sprites.enabled = false
    local disabledId = Target.addSphereZone({
        coords = { x = 1, y = 1, z = 1 }, radius = 1.0,
        options = {{ label = 'Disabled sprite', onSelect = function() end }},
    })
    harness.assertTrue(not sprites.isRunning(), 'globally disabled sprites must not create a worker')
    Target.removeZone(disabledId)

    Config.target.sprites.enabled = true
    local optedOutId = Target.addSphereZone({
        coords = { x = 1, y = 1, z = 1 }, radius = 1.0, drawSprite = false,
        options = {{ label = 'Opted-out sprite', onSelect = function() end }},
    })
    harness.assertTrue(not sprites.isRunning(), 'zones that opt out must not create a worker')
    Target.removeZone(optedOutId)

    local enabledId = Target.addSphereZone({
        coords = { x = 1, y = 1, z = 1 }, radius = 1.0,
        options = {{ label = 'Enabled sprite', onSelect = function() end }},
    })
    harness.assertTrue(sprites.isRunning(), 'the first sprite-enabled zone should start the worker')
    Target.removeZone(enabledId)
    harness.assertTrue(not sprites.hasEnabledZone(), 'removing the last enabled zone should make the worker terminate')
    Config.target.sprites.enabled = previousEnabled
end)

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
    local priorSpriteEnabled = Config.target.sprites.enabled
    Config.target.sprites.enabled = true

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

    Config.target.sprites.enabled = priorSpriteEnabled
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
    raycastFlags, raycastProbes, raycastResponses = {}, {}, {
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

-- ---------------------------------------------------------------------------
-- Resolver broad phase. Every test below starts from a clean zone fixture:
-- the tests above leave zones registered, and these assert on exactly which
-- `contains` predicates the resolver reaches.
-- ---------------------------------------------------------------------------
local function clearZones()
    local ids = {}
    for id in pairs(Target.byZone) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do Target.destroyRegistration(id) end
end

local function trackedZone(coords, size, distance, result, rotation)
    local calls = 0
    local id = Target.addBoxZone({
        coords = coords, size = size, distance = distance, rotation = rotation,
        options = {{ label = 'Tracked', onSelect = function() end }},
    })
    zoneHandles[#zoneHandles].contains = function() calls = calls + 1; return result end
    return id, function() return calls end
end

harness.test('the aim-point grid keeps far zones away from their contains predicate', function()
    clearZones()
    local _, farCalls = trackedZone({ x = 500, y = 500, z = 0 }, { x = 2, y = 2, z = 2 }, 10, true)
    local _, nearCalls = trackedZone({ x = 3, y = 0, z = 0 }, { x = 2, y = 2, z = 2 }, 10, true)

    local matched = runtime.zoneRegistrationsAt({ x = 3, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
    harness.assertEqual(#matched, 1, 'only the zone whose bounds contain the aim point should match')
    harness.assertEqual(nearCalls(), 1, 'the zone under the crosshair must still be tested exactly')
    harness.assertEqual(farCalls(), 0, 'a zone 700m away must never reach its contains predicate')
end)

harness.test('a rotated box is bounded by its circumradius, not its axis-aligned size', function()
    clearZones()
    -- Rotated 45 degrees, a 4x1 box reaches ~1.77m along both axes -- the
    -- unrotated AABB would stop at 0.5m on Y and wrongly reject this point.
    local _, calls = trackedZone({ x = 0, y = 0, z = 0 }, { x = 4, y = 1, z = 2 }, 10, true, 45)

    local matched = runtime.zoneRegistrationsAt({ x = 1.2, y = 1.2, z = 0 }, { x = 0, y = 0, z = 0 })
    harness.assertEqual(calls(), 1, 'a point inside the rotation-safe bound must reach the real predicate')
    harness.assertEqual(#matched, 1, 'and be reported as a candidate')
end)

harness.test('an aim point beyond every zone option distance skips the zone pass entirely', function()
    clearZones()
    local _, calls = trackedZone({ x = 9, y = 0, z = 0 }, { x = 2, y = 2, z = 2 }, 2.5, true)

    -- Zone candidates anchor on the raycast hit, so ped->hit distance is the
    -- distance appendCandidates would test for EVERY zone -- 9m against a
    -- 2.5m option can never produce a candidate, whatever contains says.
    harness.assertEqual(#runtime.zoneRegistrationsAt({ x = 9, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }), 0,
        'an out-of-reach aim point must produce no zone candidates')
    harness.assertEqual(calls(), 0, 'and must not run a single contains predicate to find that out')

    harness.assertEqual(#runtime.zoneRegistrationsAt({ x = 9, y = 0, z = 0 }), 1,
        'without a ped position there is nothing to measure reach against, so the pass still runs')
    harness.assertEqual(calls(), 1, 'the exact predicate runs once in that case')
end)

harness.test('a custom zone with no derivable bounds is always scanned', function()
    clearZones()
    local calls = 0
    Target._addCustomZone(function() calls = calls + 1; return true end,
        {{ label = 'Combo-like', onSelect = function() end }}, 10)

    local matched = runtime.zoneRegistrationsAt({ x = 4000, y = -4000, z = 0 }, { x = 4000, y = -4000, z = 0 })
    harness.assertEqual(calls, 1, 'an unbounded predicate must still be consulted wherever the player aims')
    harness.assertEqual(#matched, 1, 'and must still be able to match')
end)

harness.test('compat bounds cover a scaled qb-target box', function()
    clearZones()
    local calls = 0
    -- Mirrors client/compat/qb-target.lua's scaled-box branch: the predicate
    -- covers the SCALED rectangle, so the bound it registers must too.
    Target._addCustomZone(function() calls = calls + 1; return true end,
        {{ label = 'Scaled', onSelect = function() end }}, 10, nil, false,
        Target._zoneBounds(0, 0, 5, 5))

    harness.assertEqual(#runtime.zoneRegistrationsAt({ x = 4.5, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }), 1,
        'a point inside the declared bound must reach the predicate')
    harness.assertEqual(#runtime.zoneRegistrationsAt({ x = 5.5, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }), 0,
        'a point outside it must be rejected without calling the predicate')
    harness.assertEqual(calls, 1, 'exactly one predicate call across both queries')
end)

harness.test('sprite-enabled zones are counted rather than re-walked', function()
    clearZones()
    harness.assertFalse(Target.hasSpriteZone(), 'no zones means no sprite work')

    local first = Target.addSphereZone({ coords = { x = 0, y = 0, z = 0 }, radius = 1.0,
        options = {{ label = 'Sprite', onSelect = function() end }} })
    local second = Target.addSphereZone({ coords = { x = 0, y = 0, z = 0 }, radius = 1.0, drawSprite = false,
        options = {{ label = 'No sprite', onSelect = function() end }} })

    harness.assertTrue(Target.hasSpriteZone(), 'a drawing zone should register in the counter')
    Target.destroyRegistration(second)
    harness.assertTrue(Target.hasSpriteZone(), 'removing an opted-out zone must not decrement it')
    Target.destroyRegistration(first)
    harness.assertFalse(Target.hasSpriteZone(), 'removing the last drawing zone should clear it')
end)

harness.test('a motionless camera and ped let a tick reuse the previous resolve, but only briefly', function()
    local camX, pitch = 0.0, 0.0
    _G.GetGameplayCamCoord = function() return { x = camX, y = 0, z = 0 } end
    _G.GetGameplayCamRot = function() return { x = pitch, y = 0, z = 0 } end

    runtime.resetRuntimeState()
    now = 1000
    harness.assertFalse(runtime.aimIsStatic(now), 'the first tick of a hold has nothing to reuse')
    runtime.resolveCandidates(false, nil, nil, now)

    now = 1010
    harness.assertTrue(runtime.aimIsStatic(now), 'an unchanged camera and ped can reuse the last scan')

    pitch = 0.0001
    now = 1020
    harness.assertFalse(runtime.aimIsStatic(now), 'the smallest aim change must resolve immediately')
    runtime.resolveCandidates(false, nil, nil, now)

    now = 1030
    harness.assertTrue(runtime.aimIsStatic(now), 'holding still again resumes reuse')

    now = 1020 + Config.target.staticRefresh
    harness.assertFalse(runtime.aimIsStatic(now),
        'staticRefresh caps how long a frozen crosshair can go without a real scan')

    local previous = Config.target.staticRefresh
    Config.target.staticRefresh = 0
    now = now + 1
    harness.assertFalse(runtime.aimIsStatic(now), 'staticRefresh = 0 disables reuse entirely')
    Config.target.staticRefresh = previous
end)

harness.report('qbtarget runtime')
