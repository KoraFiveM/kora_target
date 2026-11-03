local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local resourceRoot = scriptDir .. '../../'
local koraLibTestRoot = resourceRoot .. '../kora_lib/test/'
package.path = koraLibTestRoot .. '?.lua;' .. package.path

local harness = require('harness')
local exportsByEvent = {}

-- The native resource always loads config.lua first. Keep this focused compat
-- harness self-contained while state.lua now also reads the global zone-debug
-- switch during zone registration.
_G.Config = { target = { debug = false, maxDistance = 10.0, defaultOptionDistance = 2.0, legacyMaxDistance = 7.0 } }

local zoneCalls = {}
local function makeZoneHandle(opts)
    zoneCalls[#zoneCalls + 1] = opts
    return { remove = function() end, contains = function() return false end }
end

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
        box = makeZoneHandle,
        sphere = makeZoneHandle,
        poly = makeZoneHandle,
    },
    raycast = {
        fromCamera = function(maxDistance)
            return true, { x = 1, y = 2, z = 3 }, 42, { x = 0, y = 0, z = 1 }
        end,
    },
}
_G.GetCurrentResourceName = function() return 'kora_target' end
_G.GetInvokingResource = function() return 'qb-banking' end
_G.AddEventHandler = function(name, handler) exportsByEvent[name] = handler end
_G.joaat = function(value) return value end
local entityCoords = { [99] = { x = 10, y = 20, z = 30 } }
_G.GetEntityCoords = function(entity) return entityCoords[entity] or { x = 10, y = 20, z = 30 } end
_G.DoesEntityExist = function() return true end
_G.NetworkGetEntityIsNetworked = function() return false end
_G.NetworkGetNetworkIdFromEntity = function(entity) return entity end
_G.PlayerPedId = function() return 1 end
_G.GetEntityType = function(entity) return entity == 42 and 3 or 0 end
_G.GetEntityModel = function() return 100 end
_G.GetModelDimensions = function()
    return { x = -1, y = -2, z = -0.5 }, { x = 1, y = 2, z = 1.5 }
end
_G.GetOffsetFromEntityGivenWorldCoords = function(entity, x, y, z)
    local coords = _G.GetEntityCoords(entity)
    return { x = x - coords.x, y = y - coords.y, z = z - coords.z }
end
_G.HasEntityClearLosToEntity = function() return true end
_G.SetNuiFocus = function() end
_G.SetNuiFocusKeepInput = function() end
_G.SetCursorLocation = function() end
_G.SendNUIMessage = function() end
_G.IsEntityAPed = function() return false end
_G.SetEntityDrawOutline = function() end

local requestedModels = {}
local createdPeds = {}
local deletedPeds = {}
local frozenPeds = {}
local invinciblePeds = {}
local blockedPeds = {}
_G.Wait = function() end
_G.RequestModel = function(model) requestedModels[#requestedModels + 1] = model end
_G.HasModelLoaded = function() return true end
_G.CreatePed = function(pedType, model, x, y, z, heading, networked, missionPed)
    local ped = 500 + #createdPeds + 1
    createdPeds[#createdPeds + 1] = {
        ped = ped,
        pedType = pedType,
        model = model,
        x = x,
        y = y,
        z = z,
        heading = heading,
        networked = networked,
        missionPed = missionPed,
    }
    return ped
end
_G.DeletePed = function(ped) deletedPeds[#deletedPeds + 1] = ped end
_G.FreezeEntityPosition = function(ped, state) frozenPeds[ped] = state end
_G.IsPedFalling, _G.IsPedJumping, _G.IsPedRagdoll = function() return false end, function() return false end, function() return false end
_G.IsPedInParachuteFreeFall, _G.IsPedClimbing, _G.IsPedVaulting = function() return false end, function() return false end, function() return false end
_G.IsEntityInAir, _G.GetPedParachuteState = function() return false end, function() return 0 end
_G.BeginTextCommandDisplayHelp = function() end
_G.AddTextComponentSubstringPlayerName = function() end
_G.EndTextCommandDisplayHelp = function() end
_G.ClearAllHelpMessages = function() end
_G.SetEntityInvincible = function(ped, state) invinciblePeds[ped] = state end
_G.SetBlockingOfNonTemporaryEvents = function(ped, state) blockedPeds[ped] = state end
_G.RequestAnimDict = function() end
_G.HasAnimDictLoaded = function() return true end
_G.TaskPlayAnim = function() end
_G.SetPedCanPlayAmbientAnims = function() end
_G.TaskStartScenarioInPlace = function() end
_G.DoesRelationshipGroupExist = function() return true end
_G.AddRelationshipGroup = function() end
_G.SetPedRelationshipGroupHash = function() end
_G.SetRelationshipBetweenGroups = function() end
_G.IsWeaponValid = function() return false end
_G.SetCanPedEquipWeapon = function() end
_G.GiveWeaponToPed = function() end
_G.SetPedCurrentWeaponVisible = function() end

Kora.stream = {
    loadModel = function(model, callback)
        RequestModel(model)
        if not HasModelLoaded(model) then return false, 'model timeout' end
        callback(model)
        return model
    end,
    loadAnimDict = function(dict, callback)
        RequestAnimDict(dict)
        if not HasAnimDictLoaded(dict) then return false, 'animation timeout' end
        callback(dict)
        return dict
    end,
}

-- The qb-target compat now fetches qb-core once at load time (job/gang/item
-- enforcement, see AGENTS.md's "Job/gang/item enforcement") -- CreateThread
-- runs synchronously here (same idiom kora_core's own legacy_callback_wire.lua
-- test uses) so that fetch completes before any test below runs.
_G.CreateThread = function(fn) fn() end
local netHandlers = {}
_G.RegisterNetEvent = function(name, handler) netHandlers[name] = handler end

-- Mutable so individual tests can reassign job/gang/citizenid/items and see
-- the compat shim's checks react -- GetPlayerData returns this SAME table by
-- reference every call, matching real QBCore.Functions.GetPlayerData().
local qbCorePlayerData = {
    job = { name = 'unemployed', type = 'none', grade = { level = 0 } },
    gang = { name = 'none', grade = { level = 0 } },
    citizenid = 'CID1',
}
local heldItems = {}
_G.exports = {
    kora_core = {
        getPlayerData = function() return qbCorePlayerData end,
        toLegacyPlayerData = function(_, data) return data end,
    },
    kora_inventory = { HasItem = function(_, item) return heldItems[item] == true end },
}
-- Real FiveM builds vector3 as an engine-provided constructor; the
-- standalone lua interpreter has no such global, so AddBoxZone's (and
-- therefore AddComboZone/AddEntityZone's) size = vector3(width, length, ...)
-- call needs a plain-table stand-in.
_G.vector3 = function(x, y, z) return { x = x, y = y, z = z } end

dofile(resourceRoot .. '../kora_lib/local/resources/client.lua')
dofile(resourceRoot .. 'client/state.lua')
dofile(resourceRoot .. 'client/compat/qb-target.lua')

local function getExport(name)
    local fn
    exportsByEvent[('__cfx_export_qb-target_%s'):format(name)](function(f) fn = f end)
    return fn
end

local addCircleZone = getExport('AddCircleZone')
local addBoxZone = getExport('AddBoxZone')
local addPolyZone = getExport('AddPolyZone')
local addComboZone = getExport('AddComboZone')
local addEntityZone = getExport('AddEntityZone')
local removeZone = getExport('RemoveZone')
local addGlobalPed = getExport('AddGlobalPed')
local removeGlobalPed = getExport('RemoveGlobalPed')
local removeGlobalVehicle = getExport('RemoveGlobalVehicle')
local removeGlobalObject = getExport('RemoveGlobalObject')
local removeGlobalPlayer = getExport('RemoveGlobalPlayer')
local addTargetBone = getExport('AddTargetBone')
local removeTargetBone = getExport('RemoveTargetBone')
local spawnPed = getExport('SpawnPed')
local removeSpawnedPed = getExport('RemoveSpawnedPed')
local raycastCamera = getExport('RaycastCamera')
local allowTargeting = getExport('AllowTargeting')
local disableTarget = getExport('DisableTarget')

harness.test('every current qb-target export is provided', function()
    for _, name in ipairs({
        'AddCircleZone', 'AddBoxZone', 'AddPolyZone', 'AddComboZone', 'AddEntityZone', 'RemoveZone',
        'AddTargetBone', 'RemoveTargetBone', 'AddTargetEntity', 'RemoveTargetEntity',
        'AddTargetModel', 'RemoveTargetModel', 'AddGlobalType', 'AddGlobalPed', 'AddGlobalVehicle',
        'AddGlobalObject', 'AddGlobalPlayer', 'RemoveGlobalType', 'RemoveGlobalPed',
        'RemoveGlobalVehicle', 'RemoveGlobalObject', 'RemoveGlobalPlayer', 'GetGlobalTypeData',
        'GetZoneData', 'GetTargetBoneData', 'GetTargetEntityData', 'GetTargetModelData',
        'GetGlobalPedData', 'GetGlobalVehicleData', 'GetGlobalObjectData', 'GetGlobalPlayerData',
        'UpdateGlobalTypeData', 'UpdateZoneData', 'UpdateTargetBoneData', 'UpdateTargetEntityData',
        'UpdateTargetModelData', 'UpdateGlobalPedData', 'UpdateGlobalVehicleData',
        'UpdateGlobalObjectData', 'UpdateGlobalPlayerData', 'DeletePeds', 'SpawnPed',
        'RemoveSpawnedPed', 'GetPeds', 'UpdatePedsData', 'RaycastCamera', 'DisableNUI', 'EnableNUI',
        'LeftTarget', 'DisableTarget', 'DrawOutlineEntity', 'CheckEntity', 'CheckBones',
        'AllowTargeting', 'IsTargetActive', 'IsTargetSuccess',
    }) do
        harness.assertTrue(getExport(name) ~= nil, 'missing qb-target export ' .. name)
    end
end)

local function opts(label)
    return { options = { { label = label, action = function() end } } }
end

harness.test('legacy action callbacks survive the FXServer export boundary', function()
    local calls = 0
    local bankAction = setmetatable({}, {
        __call = function(_, entity)
            calls = calls + 1
            harness.assertEqual(entity, nil, 'bank zones do not supply an entity handle')
        end,
    })

    local zone = addCircleZone('bank-smoke', { x = 0, y = 0, z = 0 }, 1.0, { drawSprite = false }, {
        options = { { label = 'Open Bank', action = bankAction } },
        distance = 1.5,
    })

    local registration = Target.registrations[zone.ids[1]]
    registration.options[1].onSelect(nil)
    harness.assertEqual(calls, 1, 'the callable export proxy must dispatch the legacy action')
    harness.assertTrue(registration.drawSprite == false,
        'legacy zones must be able to opt out of the configured location sprite')
end)

harness.test('legacy zones return PolyZone-compatible objects and vec2 polygons retain unbounded Z', function()
    local zone = addPolyZone('poly-smoke', {
        { x = 0, y = 0 }, { x = 2, y = 0 }, { x = 2, y = 2 },
    }, {}, opts('Poly Option'))
    local registration = Target.registrations[zone.ids[1]]
    harness.assertTrue(zone.isPolyZone, 'AddPolyZone must return a zone-compatible object')
    harness.assertEqual(getExport('GetZoneData')('poly-smoke'), zone, 'GetZoneData must return the same object')
    harness.assertEqual(registration.distance, 7.0, 'qb-target calls must use its 7m default distance')
    local nativeOptions = zoneCalls[#zoneCalls]
    harness.assertEqual(nativeOptions.points[1].z, 0.0, 'vec2 points must be accepted and converted safely')
    harness.assertEqual(nativeOptions.minZ, -2000.0, 'a poly without minZ must not gain a narrow height limit')
    harness.assertEqual(nativeOptions.maxZ, 2000.0, 'a poly without maxZ must not gain a narrow height limit')

    getExport('UpdateZoneData')('poly-smoke', opts('Updated Poly Option'))
    harness.assertEqual(Target.registrations[zone.ids[1]].options[1].label, 'Updated Poly Option',
        'UpdateZoneData must update live resolver options')
end)

harness.test('runtime PolyZone objects retain their public methods and own target cleanup', function()
    local shapeDestroyed = false
    _G.BoxZone = {
        Create = function(_, center)
            return {
                center = center,
                isBoxZone = true,
                isPointInside = function() return true end,
                getHeading = function() return 123 end,
                destroy = function(self) shapeDestroyed = true; self.destroyed = true end,
            }
        end,
    }

    local zone = addBoxZone('real-polyzone-smoke', { x = 1, y = 2, z = 3 }, 2, 2, {}, opts('Real Zone'))
    _G.BoxZone = nil
    harness.assertEqual(zone:getHeading(), 123, 'the real PolyZone object method must survive wrapping')
    harness.assertEqual(getExport('GetZoneData')('real-polyzone-smoke'), zone)
    local id = zone.ids[1]
    harness.assertTrue(Target.registrations[id].zoneHandle.contains({ x = 0, y = 0, z = 0 }))
    zone:destroy()
    harness.assertTrue(shapeDestroyed, 'destroy must reach the underlying PolyZone object')
    harness.assertTrue(Target.registrations[id] == nil, 'destroy must also remove the target registration')
end)

harness.test('AddComboZone registers one qbtarget zone per sub-zone definition', function()
    local zone = { isPointInside = function() return false end }
    local combo = addComboZone({ zone, zone }, { name = 'combo-smoke' }, opts('Combo Option'))

    harness.assertTrue(combo.isComboZone, 'AddComboZone must return a zone-compatible object')
    harness.assertEqual(#combo.ids, 2, 'AddComboZone must retain one id per sub-zone')
    harness.assertTrue(Target.registrations[combo.ids[1]] ~= nil, 'first combo sub-zone must be registered')
    harness.assertTrue(Target.registrations[combo.ids[2]] ~= nil, 'second combo sub-zone must be registered')
end)

harness.test('stable combo children are indexed instead of scanned globally', function()
    _G.ComboZone = {
        Create = function(_, zones)
            return { zones = zones, destroy = function() end }
        end,
    }
    local child = {
        type = 'box',
        coords = { x = 10, y = 20, z = 30 },
        length = 2,
        width = 2,
        options = { minZ = 29, maxZ = 31 },
        isPointInside = function() return false end,
    }
    local combo = addComboZone({ child }, { name = 'bounded-combo' }, opts('Bounded Combo'))
    _G.ComboZone = nil

    local nearby = {}
    Target.zonesNear({ x = 1000, y = 1000, z = 30 }, nearby)
    for _, id in ipairs(nearby) do
        harness.assertTrue(id ~= combo.ids[1], 'a far stable combo child must be excluded by the spatial grid')
    end
    combo:destroy()
end)

harness.test('RemoveZone tears down every sub-zone of a combo registration', function()
    local zone = { isPointInside = function() return false end }
    local combo = addComboZone({ zone, zone }, { name = 'combo-remove' }, opts('Combo Remove'))

    local removed = removeZone('combo-remove')
    harness.assertTrue(removed, 'RemoveZone must report success for a combo zone')
    for _, id in ipairs(combo.ids) do
        harness.assertTrue(Target.registrations[id] == nil, 'every combo sub-zone must be torn down')
    end
end)

harness.test('AddEntityZone follows the entity instead of snapshotting its initial coords', function()
    local zone = addEntityZone('entity-zone-smoke', 99, {}, opts('Entity Zone'))
    local registration = Target.registrations[zone.ids[1]]
    harness.assertTrue(registration ~= nil, 'AddEntityZone must register')
    harness.assertEqual(registration.kind, 'zone', 'AddEntityZone must retain zone containment semantics')
    harness.assertEqual(registration.targetEntity, 99,
        'AddEntityZone should be rejected before containment when another entity is aimed at')
    harness.assertTrue(zone:isPointInside({ x = 10, y = 20, z = 100 }),
        'an EntityZone without useZ must contain points over its current footprint')
    entityCoords[99] = { x = 50, y = 60, z = 30 }
    harness.assertFalse(zone:isPointInside({ x = 10, y = 20, z = 30 }), 'the old position must no longer match')
    harness.assertTrue(zone:isPointInside({ x = 50, y = 60, z = 30 }), 'the moved entity position must match')
end)

harness.test('RemoveGlobalPed/Vehicle/Object/Player forward to Target.removeGlobalType', function()
    addGlobalPed(opts('Global Ped'))
    harness.assertTrue(removeGlobalPed(), 'RemoveGlobalPed must remove the ped-type registration')
    harness.assertFalse(removeGlobalVehicle(), 'RemoveGlobalVehicle is a no-op with nothing registered')
    harness.assertFalse(removeGlobalObject(), 'RemoveGlobalObject is a no-op with nothing registered')
    harness.assertFalse(removeGlobalPlayer(), 'RemoveGlobalPlayer is a no-op with nothing registered')
end)

harness.test('RemoveTargetBone accepts bone names and optional labels', function()
    local id = addTargetBone({ 'boot' }, opts('Bone Option'))
    harness.assertTrue(Target.registrations[id] ~= nil, 'AddTargetBone must register')
    harness.assertTrue(removeTargetBone('boot', 'Bone Option'), 'RemoveTargetBone must remove the labeled option')
    harness.assertTrue(Target.registrations[id] == nil, 'the bone registration must be gone after removal')
end)

harness.test('SpawnPed supports qb-taxijob config and registers its entity target', function()
    qbCorePlayerData.job = { name = 'taxi', type = 'taxi', grade = { level = 0 } }
    local actionCalls = 0
    local pedConfig = {
        model = 'a_m_m_indian_01',
        coords = { x = 901.34, y = -170.06, z = 74.08, w = 228.81 },
        minusOne = true,
        freeze = true,
        invincible = true,
        blockevents = true,
        target = {
            options = {
                {
                    type = 'client',
                    event = 'qb-taxijob:client:requestcab',
                    icon = 'fas fa-sign-in-alt',
                    label = 'Request Taxi Cab',
                    job = 'taxi',
                },
            },
            distance = 2.5,
        },
        action = function() actionCalls = actionCalls + 1 end,
        networked = true,
        spawnNow = true,
        currentpednumber = 0,
    }

    spawnPed(pedConfig)

    local ped = pedConfig.currentpednumber
    local created = createdPeds[#createdPeds]
    harness.assertEqual(requestedModels[#requestedModels], 'a_m_m_indian_01', 'SpawnPed must request the configured model')
    harness.assertEqual(created.ped, ped, 'SpawnPed must publish the created handle as currentpednumber')
    harness.assertEqual(created.z, 73.08, 'minusOne must lower the spawn z coordinate by one')
    harness.assertEqual(created.heading, 228.81, 'the vector4 w component must become the ped heading')
    harness.assertFalse(created.networked, 'SpawnPed must remain local even when legacy config requests networking')
    harness.assertTrue(created.missionPed, 'explicitly spawned peds must be script-hosted mission peds')
    harness.assertTrue(frozenPeds[ped], 'freeze must freeze the spawned ped')
    harness.assertTrue(invinciblePeds[ped], 'invincible must make the spawned ped invincible')
    harness.assertTrue(blockedPeds[ped], 'blockevents must block non-temporary events')
    harness.assertEqual(actionCalls, 1, 'the optional spawn action must run once')

    local registrations = Target.byEntity[ped]
    harness.assertTrue(registrations ~= nil, 'the spawned ped must have an entity target registration')
    local registrationId = next(registrations)
    local registration = Target.registrations[registrationId]
    harness.assertEqual(registration.distance, 2.5, 'the embedded target distance must be preserved')
    harness.assertTrue(registration.options[1].canInteract(ped, 1.0, {}), 'the embedded taxi job filter must be enforced')

    removeSpawnedPed(ped)
    harness.assertEqual(deletedPeds[#deletedPeds], ped, 'RemoveSpawnedPed must delete the ped')
    harness.assertEqual(pedConfig.currentpednumber, 0, 'RemoveSpawnedPed must clear currentpednumber')
    harness.assertTrue(Target.registrations[registrationId] == nil,
        'RemoveSpawnedPed must tear down the ped target registration')
end)

harness.test('SpawnPed fails cleanly when kora_lib cannot stream the model', function()
    local original = Kora.stream.loadModel
    Kora.stream.loadModel = function() return false, 'model timeout' end
    local ok, err = pcall(spawnPed, {
        model = 'missing_model',
        coords = { x = 0, y = 0, z = 0 },
        spawnNow = true,
    })
    Kora.stream.loadModel = original

    harness.assertFalse(ok, 'an unavailable model must reject instead of waiting forever')
    harness.assertTrue(tostring(err):find('model timeout', 1, true) ~= nil,
        'the bounded streaming failure should reach the caller')
end)

harness.test('SpawnPed rolls back its target when the caller action throws', function()
    local before = 0
    for _ in pairs(Target.registrations) do before = before + 1 end
    local deletedBefore = #deletedPeds

    local ok, err = pcall(spawnPed, {
        model = 'action_failure_model',
        coords = { x = 0, y = 0, z = 0 },
        spawnNow = true,
        target = { useModel = true, options = { { label = 'Temporary' } } },
        action = function() error('action exploded') end,
    })

    local after = 0
    for _ in pairs(Target.registrations) do after = after + 1 end
    harness.assertFalse(ok, 'the caller action error should reach the SpawnPed caller')
    harness.assertTrue(tostring(err):find('action exploded', 1, true) ~= nil)
    harness.assertEqual(after, before, 'the failed spawn must not leave a model-wide target registered')
    harness.assertEqual(#deletedPeds, deletedBefore + 1, 'the partially configured ped must be deleted')
end)

harness.test('RaycastCamera matches qb-target return order and shapes', function()
    local coords, distance, entityHit, entityType = raycastCamera(nil, { x = 1, y = 2, z = 0 })
    harness.assertEqual(coords.x, 1, 'end coords must be first')
    harness.assertEqual(distance, 3, 'distance must be measured from playerCoords')
    harness.assertEqual(entityHit, 42, 'entity handle must be third')
    harness.assertEqual(entityType, 3, 'entity type must be fourth')
end)

harness.test('AllowTargeting and forced DisableTarget match upstream polarity', function()
    allowTargeting(false)
    harness.assertFalse(Target.enabled, 'AllowTargeting(false) must disable targeting')
    allowTargeting(true)
    harness.assertTrue(Target.enabled, 'AllowTargeting(true) must enable targeting')

    disableTarget(true)
    harness.assertTrue(Target.enabled, 'DisableTarget(true) cancels only the current session')
    harness.assertFalse(Target.active, 'DisableTarget(true) must clear active targeting state')
    disableTarget(false)
    harness.assertTrue(Target.enabled, 'DisableTarget(false) is an upstream no-op')
end)

harness.test('entity/model options support label-addressed get, update, and removal', function()
    local addEntity = getExport('AddTargetEntity')
    local getEntity = getExport('GetTargetEntityData')
    local updateEntity = getExport('UpdateTargetEntityData')
    local removeEntity = getExport('RemoveTargetEntity')
    addEntity(77, { options = {
        { label = 'Keep', action = function() end },
        { label = 'Replace', action = function() end },
    }, distance = 3.0 })
    harness.assertEqual(getEntity(77, 'Replace').label, 'Replace')
    updateEntity(77, 'Replace', { label = 'Replace', icon = 'new', action = function() end })
    harness.assertEqual(getEntity(77, 'Replace').icon, 'new')
    updateEntity(77, 'Added', { label = 'Added', icon = 'plus', action = function() end })
    harness.assertEqual(getEntity(77, 'Added').icon, 'plus', 'upstream setters add a missing label')
    harness.assertTrue(removeEntity(77, 'Replace'))
    harness.assertTrue(getEntity(77, 'Replace') == nil)
    harness.assertTrue(getEntity(77, 'Keep') ~= nil, 'labeled removal must preserve sibling options')
end)

-- job/gang/item/jobType enforcement -- confirmed broken before this fix
-- (real qb-policejob's target zones use jobType = 'leo' and were reachable
-- by every player). Ported verbatim from real qb-target's own JobCheck/
-- JobTypeCheck/GangCheck/CitizenCheck/ItemCheck semantics.

-- Registrations are cheap and harmless to leave behind in Target.registrations
-- for the rest of this file's tests -- each call below uses a fresh zone name,
-- so nothing collides.
local filterSmokeCounter = 0
local function addOptionAndCheck(option)
    filterSmokeCounter = filterSmokeCounter + 1
    local zone = addBoxZone('filter-smoke-' .. filterSmokeCounter, { x = 0, y = 0, z = 0 }, 1, 1, {}, {
        options = { option },
    })
    return Target.registrations[zone.ids[1]].options[1].canInteract(nil, 0, {})
end

harness.test('a job filter denies a player in the wrong job', function()
    qbCorePlayerData.job = { name = 'unemployed', type = 'none', grade = { level = 0 } }
    harness.assertFalse(addOptionAndCheck({ label = 'Cop only', job = 'police' }), 'unemployed must not pass a police-only filter')
end)

harness.test('a job filter allows a player in the right job at/above the required grade', function()
    qbCorePlayerData.job = { name = 'police', type = 'leo', grade = { level = 2 } }
    harness.assertTrue(addOptionAndCheck({ label = 'Cop only, grade 1+', job = { police = 1 } }), 'grade 2 must satisfy a grade>=1 requirement')
    harness.assertFalse(addOptionAndCheck({ label = 'Cop only, grade 3+', job = { police = 3 } }), 'grade 2 must NOT satisfy a grade>=3 requirement')
end)

harness.test('jobType denies a player whose job type does not match -- the confirmed real-world bug', function()
    qbCorePlayerData.job = { name = 'unemployed', type = 'none', grade = { level = 0 } }
    harness.assertFalse(addOptionAndCheck({ label = 'LEO only', jobType = 'leo' }), 'a civilian must not pass jobType = "leo"')

    qbCorePlayerData.job = { name = 'police', type = 'leo', grade = { level = 1 } }
    harness.assertTrue(addOptionAndCheck({ label = 'LEO only', jobType = 'leo' }), 'an actual LEO must pass jobType = "leo"')
end)

harness.test('excludejob/excludejobType deny the excluded party and allow everyone else', function()
    qbCorePlayerData.job = { name = 'police', type = 'leo', grade = { level = 1 } }
    harness.assertFalse(addOptionAndCheck({ label = 'Not cops', excludejob = 'police' }), 'excludejob must deny the named job')
    harness.assertFalse(addOptionAndCheck({ label = 'Not LEOs', excludejobType = 'leo' }), 'excludejobType must deny the named type')

    qbCorePlayerData.job = { name = 'unemployed', type = 'none', grade = { level = 0 } }
    harness.assertTrue(addOptionAndCheck({ label = 'Not cops', excludejob = 'police' }), 'a non-matching job must pass excludejob')
end)

harness.test('a gang filter behaves like a job filter', function()
    qbCorePlayerData.gang = { name = 'ballas', grade = { level = 2 } }
    harness.assertTrue(addOptionAndCheck({ label = 'Ballas only', gang = { ballas = 1 } }))
    harness.assertFalse(addOptionAndCheck({ label = 'Ballas boss only', gang = { ballas = 5 } }))
    qbCorePlayerData.gang = { name = 'none', grade = { level = 0 } }
end)

harness.test('an item filter checks QBCore.Functions.HasItem', function()
    heldItems.lockpick = nil
    harness.assertFalse(addOptionAndCheck({ label = 'Needs lockpick', item = 'lockpick' }))
    heldItems.lockpick = true
    harness.assertTrue(addOptionAndCheck({ label = 'Needs lockpick', item = 'lockpick' }))
    heldItems.lockpick = nil
end)

harness.test('a citizenid filter matches a single id or a set', function()
    qbCorePlayerData.citizenid = 'CID1'
    harness.assertTrue(addOptionAndCheck({ label = 'Only CID1', citizenid = 'CID1' }))
    harness.assertFalse(addOptionAndCheck({ label = 'Only CID2', citizenid = 'CID2' }))
    harness.assertTrue(addOptionAndCheck({ label = 'CID1 or CID3', citizenid = { CID1 = true, CID3 = true } }))
end)

harness.test('multiple filters on one option all AND together, and the option\'s own canInteract still runs last', function()
    qbCorePlayerData.job = { name = 'police', type = 'leo', grade = { level = 1 } }
    heldItems.badge = true
    local ownCanInteractCalled = false
    harness.assertTrue(addOptionAndCheck({
        label = 'Cop with a badge',
        jobType = 'leo',
        item = 'badge',
        canInteract = function() ownCanInteractCalled = true; return true end,
    }))
    harness.assertTrue(ownCanInteractCalled, 'the option\'s own canInteract must still run once every filter passes')
    heldItems.badge = nil
end)

harness.test('an option with no filters at all is unaffected (no QBCore dependency introduced for plain options)', function()
    harness.assertTrue(addOptionAndCheck({ label = 'Anyone' }))
end)

harness.test('pending SpawnPed configs spawn on OnPlayerLoaded and respawn after unload', function()
    local pedConfig = {
        model = 'pending_model',
        coords = { x = 1.0, y = 2.0, z = 3.0, w = 4.0 },
        target = { options = { { label = 'Pending' } } },
        currentpednumber = 0,
    }
    spawnPed(pedConfig)
    harness.assertEqual(pedConfig.currentpednumber, 0, 'a config without spawnNow must not spawn immediately')

    netHandlers['QBCore:Client:OnPlayerLoaded']()
    local ped = pedConfig.currentpednumber
    harness.assertTrue(ped ~= 0, 'OnPlayerLoaded must spawn the pending ped')
    harness.assertTrue( Target.byEntity[ped] ~= nil, 'the pending ped must get its entity target')

    netHandlers['QBCore:Client:OnPlayerLoaded']()
    harness.assertEqual(pedConfig.currentpednumber, ped, 'an already spawned ped must not be spawned twice')

    netHandlers['QBCore:Client:OnPlayerUnload']()
    harness.assertEqual(pedConfig.currentpednumber, 0, 'unload must delete spawned peds')
    netHandlers['QBCore:Client:OnPlayerLoaded']()
    harness.assertTrue(pedConfig.currentpednumber ~= 0, 'reload must respawn the configured ped')
    removeSpawnedPed(pedConfig.currentpednumber)
end)

harness.report('qbtarget qb-target compatibility')
