local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local resourceRoot = scriptDir .. '../../'
local koraLibTestRoot = resourceRoot .. '../kora_lib/test/'
package.path = koraLibTestRoot .. '?.lua;' .. package.path

local harness = require('harness')

local now, canInteractCalls, boneReads = 0, 0, 0
local commands = {}
local raycastResponses, raycastFlags, raycastProbes = {}, {}, {}
local zoneHandles, zoneCalls = {}, {}
local frozenEntities = {}
local configBindings = {}

-- Mirrors kora_lib's own zone handle shape (client/state.lua only relies on
-- .remove and .contains) without pulling in kora_lib's real box/sphere/poly
-- geometry -- each test controls containment directly by overriding the
-- handle's .contains after registering, so this stays a test of kora_target's
-- own resolver wiring, not kora_lib's zone math (which has its own coverage).
local function makeZoneHandle(options)
    zoneCalls[#zoneCalls + 1] = options
    local handle = { remove = function() end, contains = function() return false end }
    zoneHandles[#zoneHandles + 1] = handle
    return handle
end

-- Records calls rather than doing anything real (like makeZoneHandle above) --
-- the qbtarget_debug command test only needs to prove client/loop.lua calls
-- through to Kora.zones.setDebug with the right (id, enabled) pair, not kora_lib's
-- own runtime toggle behaviour (covered separately in kora_lib's own test suite).
local setDebugCalls = {}

_G.Kora = {
    resources = {},
    util = { isCallable = function(value)
        if type(value) == 'function' then return true end
        local mt = type(value) == 'table' and getmetatable(value) or nil
        return mt ~= nil and mt.__call ~= nil
    end },
    compat = { isCallable = function(value) return Kora.util.isCallable(value) end },
    zones = {
        box = makeZoneHandle,
        sphere = makeZoneHandle,
        poly = makeZoneHandle,
        setDebug = function(id, enabled) setDebugCalls[#setDebugCalls + 1] = { id, enabled } end,
    },
    drawing = { text3d = function() end },
    -- The stub models kora_lib's asynchronous ray handle: flags are recorded at
    -- start time and the queued response is claimed before it is awaited.
    raycast = {
        start = function(_, _, flags)
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
        close = function() end,
    },
    callback = { trigger = function() end },
    config = {
        bind = function(resource, path, handler)
            configBindings[resource] = { path = path, handler = handler }
        end,
    },
    keybind = {
        add = function(options)
            commands[options.name] = options.onPressed
            commands['-' .. options.name] = options.onReleased
            return { remove = function() return true end }
        end,
    },
}

_G.GetCurrentResourceName = function() return 'kora_target' end
_G.GetInvokingResource = function() return nil end
_G.AddEventHandler = function() end
_G.CreateThread = function() end
_G.RegisterCommand = function(name, fn) commands[name] = fn end
_G.RegisterKeyMapping = function() end
_G.GetGameTimer = function() return now end
_G.PlayerPedId = function() return 1 end
_G.IsEntityPositionFrozen = function(entity) return frozenEntities[entity] == true end
_G.FreezeEntityPosition = function(entity, frozen) frozenEntities[entity] = frozen end
local entityCoords = { x = 0, y = 0, z = 0 }
local helpMessages, helpCleared = 0, 0
_G.GetEntityCoords = function() return entityCoords end
-- Ground state of the local ped; tests flip fields to simulate falling etc.
local pedState = {}
_G.IsPedFalling = function() return pedState.falling == true end
_G.IsPedJumping = function() return pedState.jumping == true end
_G.IsPedRagdoll = function() return pedState.ragdoll == true end
_G.IsPedInParachuteFreeFall = function() return pedState.freefall == true end
_G.IsPedClimbing = function() return pedState.climbing == true end
_G.IsPedVaulting = function() return pedState.vaulting == true end
_G.IsEntityInAir = function() return pedState.inAir == true end
_G.GetPedParachuteState = function() return pedState.chute or 0 end
_G.BeginTextCommandDisplayHelp = function() end
_G.AddTextComponentSubstringPlayerName = function() end
_G.EndTextCommandDisplayHelp = function() helpMessages = helpMessages + 1 end
_G.ClearAllHelpMessages = function() helpCleared = helpCleared + 1 end
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
dofile(resourceRoot .. '../kora_lib/local/resources/client.lua')
dofile(resourceRoot .. 'client/state.lua')
dofile(resourceRoot .. 'client/sprites.lua')
dofile(resourceRoot .. 'client/loop.lua')

local runtime = Target._testRuntime
local sprites = Target._testSprites

harness.test('multiple target options open kora_lib interact and dispatch the selected action', function()
    Config.target.freezeOnMenu = true -- the shipped default is false; the freeze is opt-in
    local selected = false
    runtime.selectCandidates({
        { option = { label = 'First', icon = 'one', onSelect = function() selected = true end } },
        { option = { label = 'Second', icon = 'two', onSelect = function() end } },
    })

    harness.assertEqual(#interactItems, 2, 'multiple candidates must use the interact selector')
    harness.assertTrue(frozenEntities[1], 'the player must stay in place while choosing from a target snapshot')
    harness.assertEqual(interactItems[1].label, 'First', 'the interact selector must preserve option labels')
    harness.assertTrue(type(interactItems[1].action) == 'function', 'each interact entry must dispatch its candidate')
    interactItems[1].action()
    harness.assertTrue(selected, 'the selected interact entry must run its target action')
    runtime.closeTargetMenu()
    harness.assertFalse(frozenEntities[1], 'closing the selector must restore player movement')
end)

harness.test('disabling targeting closes a target selector and restores player movement', function()
    Config.target.freezeOnMenu = true
    runtime.selectCandidates({
        { option = { label = 'First', onSelect = function() end } },
        { option = { label = 'Second', onSelect = function() end } },
    })

    harness.assertTrue(frozenEntities[1], 'opening a target selector must freeze the player')
    Target.setEnabled(false)
    harness.assertFalse(frozenEntities[1], 'disabling targeting must not leave the player frozen')
    Target.setEnabled(true)
    Config.target.freezeOnMenu = false
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

harness.test('a live kora_lib config update invalidates target resolver caches', function()
    local binding = configBindings.kora_target
    harness.assertTrue(binding ~= nil, 'qbtarget must bind its active config through kora_lib')
    harness.assertEqual(binding.path[1], 'target', 'the binding should receive only qbtarget settings')

    local revision = Target.registrationRevision
    local settings = {}
    for key, value in pairs(Config.target) do settings[key] = value end
    settings.defaultOptionDistance = 4.0
    binding.handler(settings)
    harness.assertEqual(Config.target.defaultOptionDistance, 4.0,
        'the active default distance should replace the previous runtime value')
    harness.assertTrue(Target.registrationRevision > revision,
        'a changed distance must invalidate the resolver broad-phase cache')
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
    Config.target.canInteractCacheMs = 0
    runtime.resetRuntimeState()
end)

harness.test('failed canInteract checks use a bounded cooldown', function()
    local calls = 0
    local registration = { id = 1000 }
    local option = { label = 'Unavailable', canInteract = function() calls = calls + 1; return false end }

    now = 0
    harness.assertFalse(runtime.optionAllowed(registration, 1, option, 99, 1.0, now),
        'the first failed check should reject the option')
    now = Config.target.canInteractFailureCacheMs - 1
    harness.assertFalse(runtime.optionAllowed(registration, 1, option, 99, 1.0, now),
        'the failed result should remain unavailable during its cooldown')
    harness.assertEqual(calls, 1, 'a failed check must not run on every resolver pass')

    now = Config.target.canInteractFailureCacheMs
    runtime.optionAllowed(registration, 1, option, 99, 1.0, now)
    harness.assertEqual(calls, 2, 'a failed check must be retried after the bounded cooldown')
    runtime.resetRuntimeState()
end)

harness.test('resolver waits longer when no entity or zone option was hit', function()
    harness.assertEqual(runtime.resolverWait({}, nil), Config.target.tickMiss,
        'an empty world hit should use the low-frequency miss cadence')
    harness.assertEqual(runtime.resolverWait({}, 99), Config.target.tickAcquire,
        'an aimed entity should retain the normal acquisition cadence')
    harness.assertEqual(runtime.resolverWait({ true }, nil), Config.target.tickActive,
        'an available zone option should retain the active cadence without an entity')
    runtime.resetRuntimeState()
end)

harness.test('entity-scoped custom zones skip containment for unrelated raycast hits', function()
    local calls = 0
    local id = Target._addCustomZone(function() calls = calls + 1; return true end,
        {{ label = 'Entity zone', onSelect = function() end }}, 10, nil, false, nil, 99)

    local point = { x = 0, y = 0, z = 0 }
    harness.assertEqual(#runtime.zoneRegistrationsAt(point, point, 42), 0,
        'an unrelated entity hit must reject the entity zone before containment')
    harness.assertEqual(calls, 0, 'an unrelated entity must not run the moving-zone predicate')
    harness.assertEqual(#runtime.zoneRegistrationsAt(point, point, 99), 1,
        'the entity zone must remain available when its own entity is hit')
    harness.assertEqual(calls, 1, 'the matching entity should run containment once')
    Target.destroyRegistration(id)
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

harness.test('freezeOnMenu=false (the default) never freezes the ped, and true does', function()
    local candidates = {
        { option = { label = 'A', onSelect = function() end }, registration = {}, anchorCoords = entityCoords },
        { option = { label = 'B', onSelect = function() end }, registration = {}, anchorCoords = entityCoords },
    }
    harness.assertEqual(Config.target.freezeOnMenu, false, 'the shipped default lets the player move while the menu is open')
    runtime.closeTargetMenu()
    frozenEntities[1] = nil
    Config.target.freezeOnMenu = false
    runtime.selectCandidates(candidates)
    harness.assertTrue(not frozenEntities[1], 'freezeOnMenu=false must not freeze the ped')
    runtime.closeTargetMenu()

    Config.target.freezeOnMenu = true
    runtime.selectCandidates(candidates)
    harness.assertTrue(frozenEntities[1], 'freezeOnMenu=true restores the freeze')
    runtime.closeTargetMenu()
    harness.assertTrue(not frozenEntities[1], 'closing the menu always unfreezes')
    harness.assertEqual(helpMessages, 0, 'showCloseHint defaults to false, so no help message is shown')
    harness.assertEqual(Config.target.showCloseHint, false, 'the shipped default hides the close hint')

    Config.target.showCloseHint = true
    runtime.selectCandidates(candidates)
    runtime.closeTargetMenu()
    Config.target.showCloseHint = false
    harness.assertTrue(helpMessages > 0 and helpCleared > 0, 'showCloseHint=true shows the hint and clears it with the menu')
end)

harness.test('menu range check fails once every target is out of reach', function()
    local candidate = { option = { label = 'A', distance = 2.0 }, registration = {}, anchorCoords = { x = 1, y = 0, z = 0 } }
    harness.assertTrue(runtime.menuTargetInRange({ candidate }), 'target within distance keeps the menu open')
    candidate.anchorCoords = { x = 10, y = 0, z = 0 }
    harness.assertTrue(not runtime.menuTargetInRange({ candidate }), 'target beyond distance closes the menu')
    local savedDoes = _G.DoesEntityExist
    _G.DoesEntityExist = function() return false end
    candidate.anchorCoords, candidate.entity = { x = 1, y = 0, z = 0 }, 77
    harness.assertTrue(not runtime.menuTargetInRange({ candidate }), 'a vanished entity closes the menu')
    _G.DoesEntityExist = savedDoes
end)

harness.test('menu range check anchors zone options on the hit point, not the incidental aimed entity', function()
    local savedCoords, savedDoes = _G.GetEntityCoords, _G.DoesEntityExist
    _G.GetEntityCoords = function(entity)
        if entity == 77 then return { x = 40, y = 0, z = 0 } end
        return savedCoords(entity)
    end
    _G.DoesEntityExist = function() return true end
    local hit = { x = 1, y = 0, z = 0 }
    local zone = { option = { label = 'Z', distance = 2.0 }, registration = { kind = 'zone' }, entity = 77, anchorCoords = hit }
    harness.assertTrue(runtime.menuTargetInRange({ zone }), 'a zone option stays in range while the hit point is near, however far the door prop origin is')
    local bound = { option = { label = 'B', distance = 2.0 }, registration = { kind = 'zone', targetEntity = 77 }, entity = 77, anchorCoords = hit }
    harness.assertTrue(not runtime.menuTargetInRange({ bound }), 'an entity-bound zone still follows its entity')
    local entityOption = { option = { label = 'E', distance = 2.0 }, registration = { kind = 'entity' }, entity = 77, anchorCoords = hit }
    harness.assertTrue(not runtime.menuTargetInRange({ entityOption }), 'entity options still follow the entity')
    _G.GetEntityCoords, _G.DoesEntityExist = savedCoords, savedDoes
end)

harness.test('menu range check measures entity options to the aimed point, carried with the entity', function()
    local savedCoords, savedDoes = _G.GetEntityCoords, _G.DoesEntityExist
    local savedToLocal, savedToWorld = _G.GetOffsetFromEntityGivenWorldCoords, _G.GetOffsetFromEntityInWorldCoords
    -- A long vehicle: its origin is 4 m from the player, its trunk lid 1 m.
    local origin = { x = 4, y = 0, z = 0 }
    _G.GetEntityCoords = function(entity)
        if entity == 88 then return origin end
        return savedCoords(entity)
    end
    _G.DoesEntityExist = function() return true end
    _G.GetOffsetFromEntityGivenWorldCoords = function(_, x, y, z)
        return { x = x - origin.x, y = y - origin.y, z = z - origin.z }
    end
    _G.GetOffsetFromEntityInWorldCoords = function(_, x, y, z)
        return { x = origin.x + x, y = origin.y + y, z = origin.z + z }
    end

    local function trunkOption(label)
        return { option = { label = label, distance = 3.0, onSelect = function() end },
            registration = { kind = 'globalType' }, entity = 88, anchorCoords = { x = 1, y = 0, z = 0 } }
    end
    local candidates = { trunkOption('Open trunk'), trunkOption('Trunk storage') }
    runtime.closeTargetMenu()
    runtime.selectCandidates(candidates)
    harness.assertTrue(runtime.menuTargetInRange(candidates),
        'the menu stays open while the aimed trunk is in reach, however far the vehicle origin is')
    origin = { x = 40, y = 0, z = 0 }
    harness.assertTrue(not runtime.menuTargetInRange(candidates), 'the anchor still moves with the vehicle')
    runtime.closeTargetMenu()

    _G.GetEntityCoords, _G.DoesEntityExist = savedCoords, savedDoes
    _G.GetOffsetFromEntityGivenWorldCoords, _G.GetOffsetFromEntityInWorldCoords = savedToLocal, savedToWorld
end)

harness.test('sprite visibility honours global switch, per-zone override and allowPerZoneOverride', function()
    local settings = Config.target.sprites
    local saved = { settings.enabled, settings.allowPerZoneOverride }
    local near = { x = 0, y = 0, z = 0 }
    local function zone(drawSprite)
        local id = Target.addSphereZone({
            coords = { x = 0, y = 0, z = 0 }, radius = 1.0, drawSprite = drawSprite,
            options = {{ label = 'S', onSelect = function() end }},
        })
        return Target.registrations[id]
    end
    local unset, forced, hidden = zone(nil), zone(true), zone(false)

    for _, enabled in ipairs({ true, false }) do
        for _, allow in ipairs({ true, false }) do
            settings.enabled, settings.allowPerZoneOverride = enabled, allow
            local label = ('enabled=%s allow=%s'):format(enabled, allow)
            harness.assertEqual(sprites.canDraw(unset, near, settings), enabled, 'unset zone follows global: ' .. label)
            harness.assertEqual(sprites.canDraw(forced, near, settings), enabled or allow, 'forced zone: ' .. label)
            harness.assertEqual(sprites.canDraw(hidden, near, settings), false, 'opted-out zone never draws: ' .. label)
        end
    end

    settings.enabled = false
    settings.allowPerZoneOverride = false
    harness.assertTrue(not sprites.hasEnabledZone(), 'override ignored when not allowed')
    settings.allowPerZoneOverride = true
    harness.assertTrue(sprites.hasEnabledZone(), 'override zone keeps a worker eligible when allowed')

    settings.enabled, settings.allowPerZoneOverride = saved[1], saved[2]
    Target.removeZone(unset.id); Target.removeZone(forced.id); Target.removeZone(hidden.id)
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
    harness.assertTrue(zoneCalls[#zoneCalls].debug, 'Config.target.debug must enable kora_lib zone outlines globally')
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
    local reused = runtime.resolveCandidates(false, nil, nil, now + 1)
    harness.assertTrue(reused == candidates, 'resolver passes in one hold should reuse their candidate array')
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

harness.test('entity-focused fallback raycasts are rate limited', function()
    now = now + 1
    raycastFlags, raycastProbes, raycastResponses = {}, {}, {
        { false, nil, nil },
        { true, { x = 1, y = 0, z = 0 }, 99 },
    }

    local hit = runtime.raycastTarget()
    harness.assertFalse(hit, 'the broad miss should be returned while fallback is cooling down')
    harness.assertEqual(#raycastFlags, 1, 'the fallback shape test must not run on every broad miss')
    raycastResponses = {}
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
    -- native API takes a bare dense array -- kora_police shipped 13 registrations
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

harness.test('qbtarget_debug command toggles every target zone through Kora.zones.setDebug(nil, ...)', function()
    -- client/loop.lua's own module chunk (loaded via dofile below, alongside
    -- state.lua) registers this -- Config.target.debug/zoneDebugEnabled stay
    -- the creation-time default; this command is the runtime override layered
    -- on top of kora_lib's Kora.zones.setDebug, so it must reach Kora.zones.setDebug
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

-- Resolver broad phase. Every test below starts from a clean zone fixture:
-- the tests above leave zones registered, and these assert on exactly which
-- `contains` predicates the resolver reaches.
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

    now = 1020 + Config.target.staticMissRefresh
    harness.assertFalse(runtime.aimIsStatic(now),
        'staticMissRefresh caps how long a frozen empty aim can go without a real scan')

    local previous = Config.target.staticMissRefresh
    Config.target.staticMissRefresh = 0
    now = now + 1
    harness.assertFalse(runtime.aimIsStatic(now), 'staticMissRefresh = 0 disables miss reuse entirely')
    Config.target.staticMissRefresh = previous
end)

local disabledControls, pressedControls, controlNormals = {}, {}, {}
_G.DisableControlAction = function(_, control, disabled) if disabled then disabledControls[control] = true end end
_G.IsControlPressed = function(_, control) return pressedControls[control] == true end
_G.GetControlNormal = function(_, control) return controlNormals[control] or 0.0 end

-- The pause controls (199/200/322) are disabled by design while a menu is open; these
-- checks are about movement and camera controls only.
local function onlyPauseControlsDisabled()
    for control in pairs(disabledControls) do
        if control ~= 199 and control ~= 200 and control ~= 322 then return false end
    end
    return true
end

local function resetMenuInput()
    disabledControls, pressedControls, controlNormals = {}, {}, {}
    Config.target.menuMovement, Config.target.freezeOnMenu, Config.target.lockCameraOnMenu = nil, false, false
    runtime.closeTargetMenu()
    frozenEntities[1] = nil
end

local menuCandidates = {
    { option = { label = 'A', onSelect = function() end }, registration = {}, anchorCoords = entityCoords },
    { option = { label = 'B', onSelect = function() end }, registration = {}, anchorCoords = entityCoords },
}

harness.test('menuMovement defaults to allow and maps legacy freezeOnMenu when unset', function()
    resetMenuInput()
    harness.assertEqual(runtime.menuMovementMode(), 'allow', 'default must allow free movement')
    Config.target.freezeOnMenu = true
    harness.assertEqual(runtime.menuMovementMode(), 'freeze', 'freezeOnMenu=true with no menuMovement behaves as freeze')
    Config.target.menuMovement = 'close'
    harness.assertEqual(runtime.menuMovementMode(), 'close', 'an explicit menuMovement wins over freezeOnMenu')
    Config.target.menuMovement = 'allow'
    harness.assertEqual(runtime.menuMovementMode(), 'allow', 'explicit allow wins over freezeOnMenu')
    Config.target.menuMovement = 'bogus'
    harness.assertEqual(runtime.menuMovementMode(), 'freeze', 'an unknown value falls back to the legacy mapping')
    resetMenuInput()
end)

harness.test('menuMovement=freeze freezes the ped and disables movement controls each frame', function()
    resetMenuInput()
    Config.target.menuMovement = 'freeze'
    runtime.selectCandidates(menuCandidates)
    harness.assertTrue(frozenEntities[1], 'freeze mode freezes the ped')
    local state = {}
    harness.assertFalse(runtime.menuInputFrame('freeze', state), 'freeze mode never closes on input')
    for _, control in ipairs({ 21, 22, 30, 31, 32, 33, 34, 35, 36, 44 }) do
        harness.assertTrue(disabledControls[control], 'movement control ' .. control .. ' must be disabled')
    end
    harness.assertTrue(not disabledControls[1] and not disabledControls[2], 'camera stays free unless lockCameraOnMenu')
    runtime.closeTargetMenu()
    harness.assertFalse(frozenEntities[1], 'closing releases the freeze')
    resetMenuInput()
end)

harness.test('menuMovement=allow neither freezes nor disables controls nor closes', function()
    resetMenuInput()
    Config.target.menuMovement = 'allow'
    runtime.selectCandidates(menuCandidates)
    harness.assertTrue(not frozenEntities[1], 'allow mode must not freeze')
    pressedControls[32] = true
    harness.assertFalse(runtime.menuInputFrame('allow', {}), 'movement does not close in allow mode')
    harness.assertTrue(onlyPauseControlsDisabled(), 'allow mode disables no movement or camera controls')
    resetMenuInput()
end)

harness.test('menuMovement=close closes on a new movement press but not on movement held at open', function()
    resetMenuInput()
    Config.target.menuMovement = 'close'
    runtime.selectCandidates(menuCandidates)
    harness.assertTrue(not frozenEntities[1], 'close mode must not freeze')
    local state = { moving = false }
    harness.assertFalse(runtime.menuInputFrame('close', state), 'no input keeps the menu open')
    pressedControls[32] = true
    harness.assertTrue(runtime.menuInputFrame('close', state), 'pressing W closes the menu')
    resetMenuInput()
    pressedControls[21] = true
    local held = { moving = true }
    harness.assertFalse(runtime.menuInputFrame('close', held), 'movement held since before opening does not close')
    pressedControls[21] = nil
    runtime.menuInputFrame('close', held)
    controlNormals[31] = -1.0
    harness.assertTrue(runtime.menuInputFrame('close', held), 'analogue stick movement after release closes')
    harness.assertTrue(onlyPauseControlsDisabled(), 'close mode disables no movement or camera controls')
    resetMenuInput()
end)

harness.test('lockCameraOnMenu disables look controls only when enabled', function()
    resetMenuInput()
    runtime.menuInputFrame('allow', {})
    harness.assertTrue(not disabledControls[1] and not disabledControls[2], 'default leaves the camera free')
    Config.target.lockCameraOnMenu = true
    runtime.menuInputFrame('allow', {})
    harness.assertTrue(disabledControls[1] and disabledControls[2], 'lockCameraOnMenu disables LookLR and LookUD')
    harness.assertTrue(not disabledControls[32], 'camera lock alone leaves movement enabled')
    resetMenuInput()
end)

harness.test('every close path releases the freeze', function()
    resetMenuInput()
    Config.target.menuMovement = 'freeze'
    runtime.selectCandidates(menuCandidates)
    harness.assertTrue(frozenEntities[1], 'frozen while open')
    Target._cancelCurrentTargeting()
    harness.assertFalse(frozenEntities[1], 'cancelling targeting (also the path taken on resource stop) releases the freeze')
    resetMenuInput()
end)

local pauseActive, pauseClosed, frontendClosed = false, 0, 0
_G.IsPauseMenuActive = function() return pauseActive end
_G.SetPauseMenuActive = function(active) if not active then pauseClosed = pauseClosed + 1; pauseActive = false end end
_G.SetFrontendActive = function(active) if not active then frontendClosed = frontendClosed + 1 end end

harness.test('pause menu suppression defaults on with a 250ms window', function()
    harness.assertTrue(Config.target.suppressPauseOnClose == true, 'suppressPauseOnClose defaults on')
    harness.assertEqual(Config.target.pauseSuppressMs, 250, 'pauseSuppressMs default')
end)

harness.test('open menu disables the pause controls every frame without touching movement', function()
    resetMenuInput()
    runtime.resetPauseSuppression()
    runtime.menuInputFrame('allow', {})
    for _, control in ipairs({ 199, 200, 322 }) do
        harness.assertTrue(disabledControls[control], 'pause control ' .. control .. ' must be disabled while the menu is open')
    end
    harness.assertTrue(not disabledControls[32] and not disabledControls[1], 'movement and camera stay as configured')
    resetMenuInput()
end)

harness.test('suppressPauseOnClose=false leaves the pause controls alone', function()
    resetMenuInput()
    runtime.resetPauseSuppression()
    Config.target.suppressPauseOnClose = false
    runtime.menuInputFrame('allow', {})
    harness.assertTrue(next(disabledControls) == nil, 'no controls disabled when the option is off')
    runtime.selectCandidates(menuCandidates)
    runtime.closeTargetMenu()
    harness.assertEqual(runtime.pauseSuppressUntil(), 0, 'no suppression window when off')
    Config.target.suppressPauseOnClose = true
    resetMenuInput()
end)

harness.test('closing an open menu starts a bounded suppression window; closing nothing does not', function()
    resetMenuInput()
    runtime.resetPauseSuppression()
    now = 7000
    runtime.closeTargetMenu()
    harness.assertEqual(runtime.pauseSuppressUntil(), 0, 'closing when no menu was open starts no window')
    runtime.selectCandidates(menuCandidates)
    runtime.closeTargetMenu()
    harness.assertEqual(runtime.pauseSuppressUntil(), 7250, 'window ends pauseSuppressMs after the close')
    Config.target.pauseSuppressMs = 99999
    runtime.resetPauseSuppression()
    runtime.selectCandidates(menuCandidates)
    runtime.closeTargetMenu()
    harness.assertEqual(runtime.pauseSuppressUntil(), 9000, 'window is capped at 2000ms so the pause menu is never blocked for long')
    Config.target.pauseSuppressMs = 250
    runtime.resetPauseSuppression()
    resetMenuInput()
end)

harness.test('a pause menu that still opened is closed only when forced', function()
    resetMenuInput()
    pauseActive, pauseClosed, frontendClosed = true, 0, 0
    runtime.suppressPauseFrame(false)
    harness.assertTrue(pauseActive and pauseClosed == 0, 'open menu frames do not force-close the pause menu')
    runtime.suppressPauseFrame(true)
    harness.assertFalse(pauseActive, 'post-close frame closes the pause menu')
    harness.assertEqual(frontendClosed, 1, 'frontend deactivated too')
    resetMenuInput()
end)

harness.test('forceRelease cancels the session, skips the release selection and re-sends the key release', function()
    local sent = {}
    _G.ExecuteCommand = function(command) sent[#sent + 1] = command end
    local released = 0
    local previous = Target._releaseLegacyFocus
    Target._releaseLegacyFocus = function() released = released + 1 end
    runtime.setHolding(true)
    Target.active = true
    runtime.forceRelease()
    harness.assertFalse(runtime.isHolding(), 'holding is cleared')
    harness.assertFalse(Target.active, 'targeting is inactive')
    harness.assertEqual(released, 1, 'legacy NUI focus is released')
    harness.assertEqual(sent[1], '-' .. Config.target.keybind.command, 'the keybind release is re-sent')
    harness.assertTrue(Config.target.recovery.enabled, 'recovery is on by default')
    harness.assertEqual(Config.target.recovery.resetCommand, 'target-reset', 'reset command default')
    Target._releaseLegacyFocus = previous
end)

harness.test('recovery defaults cover focus loss, Alt fallback and menu idle', function()
    local recovery = Config.target.recovery
    harness.assertTrue(recovery.cancelOnFocusLoss, 'focus loss cancels')
    harness.assertEqual(recovery.focusReleaseIgnoreMs, 1500, 'post-focus key-up ignore window')
    harness.assertTrue(recovery.altControlFallback, 'Alt control fallback on')
    harness.assertEqual(recovery.menuIdleTimeoutMs, 30000, 'menu idle timeout')
    harness.assertTrue(recovery.nuiListener, 'NUI listener on')
end)

harness.test('+playerTarget/-playerTarget alias the target keybind press and release', function()
    harness.assertTrue(type(commands['+playerTarget']) == 'function', '+playerTarget must be registered')
    harness.assertTrue(type(commands['-playerTarget']) == 'function', '-playerTarget must be registered')
    commands['+playerTarget']()
    harness.assertTrue(Target.active, '+playerTarget must start targeting like the keybind press')
    commands['-playerTarget']()
    harness.assertFalse(Target.active, '-playerTarget must end targeting like the keybind release')
end)

harness.test('dead / last stand players cannot target or run options; disableWhileDead and allowWhileDead opt out', function()
    harness.assertTrue(Config.target.disableWhileDead, 'on by default')
    harness.assertEqual(#Config.target.allowWhileDead, 0, 'empty whitelist by default')
    local metadata = { isdead = false, inlaststand = false }
    local previousExports = _G.exports
    _G.exports = { kora_core = { getPlayerData = function() return { metadata = metadata } end } }
    local ran = 0
    local candidate = { entity = 1, option = { name = 'cuff', label = 'Cuff', onSelect = function() ran = ran + 1 end } }

    Target._testRuntime.selectCandidates({ candidate })
    harness.assertEqual(ran, 1, 'alive player runs the option')

    metadata.inlaststand = true
    Target._testRuntime.selectCandidates({ candidate })
    harness.assertEqual(ran, 1, 'last stand blocks the action even with a stale poll cache')
    commands['+playerTarget']()
    harness.assertFalse(Target.active, 'targeting does not start while downed')
    commands['-playerTarget']()

    metadata.inlaststand, metadata.isdead = false, true
    harness.assertTrue(Target.isDowned(true), 'isdead blocks too')

    Config.target.allowWhileDead = { 'cuff' }
    Target._testRuntime.selectCandidates({ candidate })
    harness.assertEqual(ran, 2, 'whitelisted option name still runs while down')
    Config.target.allowWhileDead = {}

    Config.target.disableWhileDead = false
    Target._testRuntime.selectCandidates({ candidate })
    harness.assertEqual(ran, 3, 'option off restores old behaviour')
    Config.target.disableWhileDead = true

    metadata.isdead = false
    harness.assertFalse(Target.isDowned(true))
    _G.exports = previousExports
end)

harness.test('the option menu never freezes an airborne ped and releases the freeze on leaving the ground', function()
    resetMenuInput()
    Config.target.menuMovement = 'freeze'
    Config.target.closeWhenAirborne = true
    for _, state in ipairs({ 'falling', 'jumping', 'ragdoll', 'freefall', 'climbing', 'vaulting', 'inAir' }) do
        pedState = { [state] = true }
        runtime.selectCandidates(menuCandidates)
        harness.assertFalse(frozenEntities[1], 'a ped that is ' .. state .. ' must not be frozen')
        harness.assertFalse(runtime.isMenuOpen(), 'the menu must not open while ' .. state)
        runtime.closeTargetMenu()
    end
    pedState = { chute = 2 }
    harness.assertTrue(runtime.pedAirborne(), 'an open parachute counts as airborne')
    pedState = {}

    runtime.selectCandidates(menuCandidates)
    harness.assertTrue(frozenEntities[1], 'a grounded ped is frozen in freeze mode')
    pedState = { falling = true }
    -- the menu loop calls closeTargetMenu when it sees the ped leave the ground
    runtime.closeTargetMenu()
    harness.assertFalse(frozenEntities[1], 'closing the menu restores movement')
    pedState = {}
    Config.target.closeWhenAirborne = false
    resetMenuInput()
end)

harness.test('closeWhenAirborne=false keeps the previous behaviour', function()
    resetMenuInput()
    Config.target.menuMovement = 'allow'
    pedState = { falling = true }
    Config.target.closeWhenAirborne = false
    local opened = false
    runtime.selectCandidates(menuCandidates)
    harness.assertTrue(runtime.isMenuOpen(), 'with the option off the menu still opens in the air')
    Config.target.closeWhenAirborne = false
    pedState = {}
    resetMenuInput()
end)

harness.test('releasing the key while airborne does not run a single option', function()
    local ran = 0
    local candidate = { option = { label = 'One', onSelect = function() ran = ran + 1 end }, registration = {}, anchorCoords = entityCoords }
    Config.target.closeWhenAirborne = true
    pedState = { jumping = true }
    runtime.selectCandidates({ candidate })
    harness.assertEqual(ran, 0, 'no option may run mid-jump')
    Config.target.closeWhenAirborne = false
    pedState = { jumping = true }
    runtime.selectCandidates({ candidate })
    harness.assertEqual(ran, 1, 'with closeWhenAirborne off an option still runs mid-jump')
    ran = 0
    pedState = {}
    runtime.selectCandidates({ candidate })
    harness.assertEqual(ran, 1, 'the same option runs once grounded')
end)

harness.test('a single option whose target is out of range does not run', function()
    local ran = 0
    local candidate = { option = { label = 'One', distance = 2.0, onSelect = function() ran = ran + 1 end },
        registration = {}, anchorCoords = { x = 2.3, y = 0, z = 0 } }
    runtime.selectCandidates({ candidate })
    harness.assertEqual(ran, 1, 'within distance plus rangeTolerance still runs')
    candidate.anchorCoords = { x = 9, y = 0, z = 0 }
    runtime.selectCandidates({ candidate })
    harness.assertEqual(ran, 1, 'beyond distance plus rangeTolerance must not run')
    Config.target.rangeTolerance = 0
    candidate.anchorCoords = { x = 2.3, y = 0, z = 0 }
    runtime.selectCandidates({ candidate })
    harness.assertEqual(ran, 1, 'rangeTolerance = 0 is strict')
    Config.target.rangeTolerance = 0.5
end)

harness.test('the menu range check honours rangeTolerance', function()
    local candidate = { option = { label = 'A', distance = 2.0 }, registration = {}, anchorCoords = { x = 2.4, y = 0, z = 0 } }
    harness.assertTrue(runtime.menuTargetInRange({ candidate }), 'inside distance + tolerance stays open')
    candidate.anchorCoords = { x = 2.6, y = 0, z = 0 }
    harness.assertFalse(runtime.menuTargetInRange({ candidate }), 'outside distance + tolerance closes the menu')
end)

harness.test('the shipped defaults never freeze or interrupt the player', function()
    harness.assertEqual(Config.target.closeWhenAirborne, false, 'closeWhenAirborne defaults to off')
    harness.assertEqual(Config.target.menuMovement, nil, 'menuMovement is unset, so the legacy flag (off) resolves it to allow')
    harness.assertEqual(Config.target.freezeOnMenu, false, 'freezeOnMenu defaults to off')
    harness.assertEqual(Config.target.closeMenuOutOfRange, true, 'the menu still closes once out of range')
    harness.assertEqual(Config.target.rangeTolerance, 0.5, 'rangeTolerance default')
end)

harness.report('qbtarget runtime')
