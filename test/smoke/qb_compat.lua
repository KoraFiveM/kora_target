local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local resourceRoot = scriptDir .. '../../'
local qblibTestRoot = resourceRoot .. '../qblib/test/'
package.path = qblibTestRoot .. '?.lua;' .. package.path

local harness = require('harness')
local exportsByEvent = {}

-- The native resource always loads config.lua first. Keep this focused compat
-- harness self-contained while state.lua now also reads the global zone-debug
-- switch during zone registration.
_G.Config = { target = { debug = false, maxDistance = 10.0 } }

local zoneCalls = {}
local function makeZoneHandle(opts)
    zoneCalls[#zoneCalls + 1] = opts
    return { remove = function() end, contains = function() return false end }
end

_G.QB = {
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
_G.GetCurrentResourceName = function() return 'qbtarget' end
_G.GetInvokingResource = function() return 'qb-banking' end
_G.AddEventHandler = function(name, handler) exportsByEvent[name] = handler end
_G.joaat = function(value) return value end
_G.GetEntityCoords = function(entity) return { x = 10, y = 20, z = 30 } end

-- The qb-target compat now fetches qb-core once at load time (job/gang/item
-- enforcement, see AGENTS.md's "Job/gang/item enforcement") -- CreateThread
-- runs synchronously here (same idiom qbcore's own legacy_callback_wire.lua
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
    ['qb-core'] = {
        GetCoreObject = function(_, _filters)
            return {
                Functions = {
                    GetPlayerData = function() return qbCorePlayerData end,
                    HasItem = function(item) return heldItems[item] == true end,
                },
            }
        end,
    },
}
-- Real FiveM builds vector3 as an engine-provided constructor; the
-- standalone lua interpreter has no such global, so AddBoxZone's (and
-- therefore AddComboZone/AddEntityZone's) size = vector3(width, length, ...)
-- call needs a plain-table stand-in.
_G.vector3 = function(x, y, z) return { x = x, y = y, z = z } end

dofile(resourceRoot .. 'client/state.lua')
dofile(resourceRoot .. 'client/compat/qb-target.lua')

local function getExport(name)
    local fn
    exportsByEvent[('__cfx_export_qb-target_%s'):format(name)](function(f) fn = f end)
    return fn
end

local addCircleZone = getExport('AddCircleZone')
local addBoxZone = getExport('AddBoxZone')
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
local raycastCamera = getExport('RaycastCamera')
local allowTargeting = getExport('AllowTargeting')
local disableTarget = getExport('DisableTarget')

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

    local id = addCircleZone('bank-smoke', { x = 0, y = 0, z = 0 }, 1.0, { drawSprite = false }, {
        options = { { label = 'Open Bank', action = bankAction } },
        distance = 1.5,
    })

    Target.registrations[id].options[1].onSelect(nil)
    harness.assertEqual(calls, 1, 'the callable export proxy must dispatch the legacy action')
    harness.assertTrue(Target.registrations[id].drawSprite == false,
        'legacy zones must be able to opt out of the configured location sprite')
end)

harness.test('AddComboZone registers one qbtarget zone per sub-zone definition', function()
    local ids = addComboZone('combo-smoke', {
        { type = 'Box', coords = { x = 0, y = 0, z = 0 }, length = 2.0, width = 2.0 },
        { type = 'Circle', coords = { x = 5, y = 5, z = 0 }, radius = 1.5 },
    }, opts('Combo Option'))

    harness.assertEqual(#ids, 2, 'AddComboZone must return one id per sub-zone')
    harness.assertTrue(Target.registrations[ids[1]] ~= nil, 'first combo sub-zone must be registered')
    harness.assertTrue(Target.registrations[ids[2]] ~= nil, 'second combo sub-zone must be registered')
end)

harness.test('RemoveZone tears down every sub-zone of a combo registration', function()
    local ids = addComboZone('combo-remove', {
        { type = 'Box', coords = { x = 0, y = 0, z = 0 }, length = 1.0, width = 1.0 },
        { type = 'Box', coords = { x = 1, y = 1, z = 0 }, length = 1.0, width = 1.0 },
    }, opts('Combo Remove'))

    local removed = removeZone('combo-remove')
    harness.assertTrue(removed, 'RemoveZone must report success for a combo zone')
    for _, id in ipairs(ids) do
        harness.assertTrue(Target.registrations[id] == nil, 'every combo sub-zone must be torn down')
    end
end)

harness.test('AddEntityZone snapshots the entity coords into a box zone', function()
    local id = addEntityZone('entity-zone-smoke', 99, {}, opts('Entity Zone'))
    local registration = Target.registrations[id]
    harness.assertTrue(registration ~= nil, 'AddEntityZone must register a zone')
    harness.assertEqual(registration.kind, 'zone', 'AddEntityZone must produce a zone-kind registration')
    harness.assertEqual(registration.spriteCoords.x, 10, 'AddEntityZone must snapshot the entity coords')
end)

harness.test('RemoveGlobalPed/Vehicle/Object/Player forward to Target.removeGlobalType', function()
    addGlobalPed(opts('Global Ped'))
    harness.assertTrue(removeGlobalPed(), 'RemoveGlobalPed must remove the ped-type registration')
    harness.assertFalse(removeGlobalVehicle(), 'RemoveGlobalVehicle is a no-op with nothing registered')
    harness.assertFalse(removeGlobalObject(), 'RemoveGlobalObject is a no-op with nothing registered')
    harness.assertFalse(removeGlobalPlayer(), 'RemoveGlobalPlayer is a no-op with nothing registered')
end)

harness.test('RemoveTargetBone forwards to Target.removeGlobalBone', function()
    local id = addTargetBone({ 'boot' }, opts('Bone Option'))
    harness.assertTrue(Target.registrations[id] ~= nil, 'AddTargetBone must register')
    harness.assertTrue(removeTargetBone(id), 'RemoveTargetBone must remove the bone registration')
    harness.assertTrue(Target.registrations[id] == nil, 'the bone registration must be gone after removal')
end)

harness.test('RaycastCamera reorders qbtarget raycast results to (entityHit, coords, hit, surfaceNormal)', function()
    local entityHit, coords, hit, surfaceNormal = raycastCamera()
    harness.assertEqual(entityHit, 42, 'entityHit must be the first return value')
    harness.assertEqual(coords.x, 1, 'coords must be the second return value')
    harness.assertTrue(hit, 'hit must be the third return value')
    harness.assertEqual(surfaceNormal.z, 1, 'surfaceNormal must be the fourth return value')
end)

harness.test('AllowTargeting/DisableTarget drive Target.setEnabled with opposite polarity', function()
    allowTargeting(false)
    harness.assertFalse(Target.enabled, 'AllowTargeting(false) must disable targeting')
    allowTargeting(true)
    harness.assertTrue(Target.enabled, 'AllowTargeting(true) must enable targeting')

    disableTarget(true)
    harness.assertFalse(Target.enabled, 'DisableTarget(true) must disable targeting')
    disableTarget(false)
    harness.assertTrue(Target.enabled, 'DisableTarget(false) must re-enable targeting')
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
    local id = addBoxZone('filter-smoke-' .. filterSmokeCounter, { x = 0, y = 0, z = 0 }, 1, 1, {}, {
        options = { option },
    })
    return Target.registrations[id].options[1].canInteract(nil, 0, {})
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

harness.report('qbtarget qb-target compatibility')
