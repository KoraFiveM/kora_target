---
layout: default
title: kora_target
---

A crosshair/zone-based targeting and interaction engine for FiveM, built on
[kora_lib](https://qbcore2.github.io/kora_lib/) (`Kora.raycast` for aim resolution,
`Kora.zones` for area-based targets, `Kora.world`/`Kora.drawing` as the underlying
pool-query/prompt-rendering primitives). It's one resource, no separate proxy
resources: it declares `provide 'qb-target'` in its
`fxmanifest.lua` (not `ox_target`; the `stubs/ox_target` placeholder owns that
name) and registers the real, public qb-target/ox_target export
names directly, so scripts written against `exports['qb-target']:...` or
`exports.ox_target:...` keep working unmodified against this same running
resource. `exports.ox_target:*` works without the placeholder; resources that
declare `dependency 'ox_target'` or check `GetResourceState('ox_target')` need
`stubs/ox_target` ensured after kora_target.

## Requirements

- [kora_lib](https://qbcore2.github.io/kora_lib/) — shared helper library kora_target is built on (raycasting, zones, world/drawing primitives, NUI, callbacks)

## Installation

`server.cfg`, in this order:
```
ensure kora_lib
ensure kora_target
```
No database and no framework (qb-core/ox_core/QBCore) are required — kora_target
has no persistence and does not check jobs/gangs/inventory itself (see the
"Opaque fields" note under API reference below).

## Usage examples

### Target a specific entity
```lua
-- client
local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)

local id = exports.kora_target:addEntity(vehicle, {
    {
        label = 'Inspect vehicle',
        icon = 'Car',
        distance = 3.0,
        onSelect = function(entity)
            print('inspecting', entity)
        end,
    },
})

-- later
exports.kora_target:removeEntity(vehicle, id)
```

### Target every entity spawned from a model
```lua
-- client
exports.kora_target:addModel('prop_atm_01', {
    {
        label = 'Use ATM',
        icon = 'CreditCard',
        onSelect = function(entity)
            print('using ATM', entity)
        end,
    },
}, 1.5) -- defaultDistance
```

### Target a specific bone on an entity
```lua
-- client
local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)

-- sugar over addEntity: forces every option onto the 'boot' bone
exports.kora_target:addTargetBone(vehicle, 'boot', {
    {
        label = 'Open trunk',
        icon = 'Box',
        canInteract = function(entity, distance, data)
            return not IsVehicleDoorDamaged(entity, 5)
        end,
        onSelect = function(entity)
            SetVehicleDoorOpen(entity, 5, false, false)
        end,
    },
})
```

### Target every entity of a global type
```lua
-- client
exports.kora_target:addGlobalType('ped', {
    {
        label = 'Frisk',
        icon = 'Search',
        distance = 2.0,
        canInteract = function(entity)
            return not IsPedAPlayer(entity)
        end,
        onSelect = function(entity)
            print('frisking', entity)
        end,
    },
})
```

### Target a coordinate-based zone (no aiming required)
```lua
-- client
local id = exports.kora_target:addBoxZone({
    coords = vector3(100.0, 200.0, 30.0),
    size = vector3(2.0, 2.0, 3.0),
    rotation = 0.0,
    options = {
        { label = 'Open shop', icon = 'Store', onSelect = function() print('shop opened') end },
    },
})

-- later
exports.kora_target:removeZone(id)
```

### ox_target compat — same call signature, no separate resource
```lua
-- client, written against ox_target but running on kora_target unmodified
exports.ox_target:addBoxZone({
    coords = vector3(100.0, 200.0, 30.0),
    size = vector3(2.0, 2.0, 3.0),
    options = {
        { label = 'Open shop', icon = 'Store', onSelect = function() print('shop opened') end },
    },
})

exports.ox_target:addLocalEntity(entity, {
    { label = 'Inspect', onSelect = function(ent) print('inspecting', ent) end },
})
```

### Server-validated action relay
```lua
-- server
exports.kora_target:registerServerAction('openTrunk', function(src, entity)
    -- entity is already distance-checked against src here
    TriggerClientEvent('myscript:openTrunk', src, entity)
end)

-- client, inside an onSelect
local ok, result = exports.kora_target:runServerAction('openTrunk', entity, 3.0)
if not ok then print('too far away or invalid target') end
```

## API reference

All functions are plain FiveM exports on `kora_target` — `exports.kora_target:<name>(...)`.
The same targets are also reachable through `exports['qb-target']:...`
(PascalCase, qb-target's real function names) and `exports.ox_target:...`
(camelCase, ox_target's real function names) — both are compatibility layers
over this same API, not separate implementations.

The qb-target surface keeps its upstream `PolyZone` dependency. Its zone calls
return genuine PolyZone-derived objects with the complete public shape API,
while kora_target continues to resolve target selection through kora_lib.

### qb-target drop-in compatibility

Every export in current qb-target is registered: zone/entity/model/bone/global
registration and label-addressed CRUD, ped spawning, target/NUI controls,
raycast/state helpers, and outline/bone checks. Options preserve `num` order,
`required_item`, current three-argument `canInteract`, exact action/event/
command dispatch payloads, and qb-core job/job-type/gang/item/citizen filters.

Zone calls return PolyZone-compatible objects. Vec2 polygons and unbounded-Z
zones work, ComboZone accepts live PolyZone objects, EntityZone follows moving
entities, and `GetZoneData` returns the same object. `RaycastCamera` returns
`coords, distance, entity, entityType`; `DisableTarget(true)` only cancels the
current session, while `AllowTargeting(false)` changes the persistent gate.

### `addEntity(entity, options, defaultDistance?)` / `removeEntity(entity, id?)`
Targets one or more specific entity handles.
- `entity: number | number[]`
- Returns the registration `id` (integer).
- `removeEntity(entity, id?)`: with `id`, removes only that registration. Without it, removes **every** registration touching `entity`.

### `addModel(model, options, defaultDistance?)` / `removeModel(model, id?)`
Targets every current and future entity spawned with any of the given models.
- `model: number | string | (number|string)[]` — strings are `joaat`-hashed.
- Same whole-registration removal semantics as `removeEntity`.

### `addGlobalType(entityType, options, defaultDistance?)` / `removeGlobalType(entityType, id?)`
Targets every entity of a type: `"ped" | "vehicle" | "object" | "player"`.

### `addGlobalBone(bones, options, defaultDistance?)` / `removeGlobalBone(id)`
Targets **any** entity, of any type, that has a matching bone (e.g. every vehicle's `"boot"` bone). `bones: string | string[]`.

### `addTargetBone(entity, bone, options, defaultDistance?)`
Sugar over `addEntity`: registers `options` on `entity`, forcing every option onto `bone` specifically.

### `addBoxZone({coords, size, rotation?, options, distance?, debug?, drawSprite?, allowInVehicle?})`
### `addSphereZone({coords, radius, options, distance?, debug?, drawSprite?, allowInVehicle?})`
### `addPolyZone({points, thickness?, minZ?, maxZ?, options, distance?, debug?, drawSprite?, allowInVehicle?})`
Zone-based targets, backed by `Kora.zones.box/sphere/poly` — no aiming required, just aiming at (not necessarily standing inside) the zone. Returns the registration `id`.

Set `Config.target.debug = true` to outline every target zone while developing;
an individual zone can also set `debug = true`. `Config.target.sprites` draws
a small, distance-culled `shared/info` world sprite at each coordinate-zone
anchor. Set `drawSprite = false` on a zone to suppress its icon. This visual
loop never raycasts or scans the entity pool; model/entity/global targets have
no single stable anchor and therefore intentionally do not get static sprites.
The sprite worker is created lazily for the first sprite-enabled coordinate
zone and terminates after the last such zone is removed; globally disabled
sprites or an all-opted-out zone set create no worker.

### `removeZone(id)`
Removes a zone-based registration.

### `setEnabled(enabled)`
Globally enables/disables the whole targeting loop.

### `getState()`
Returns `{ enabled: boolean, active: boolean, success: boolean, hovering: table|nil }`. `hovering` mirrors whatever the tick loop last resolved (`{ kind, id, entity?, zoneId?, optionCount }`), or `nil` when nothing is currently targeted.

### `runServerAction(name, entity?, maxDistance?, ...)` (client) / `registerServerAction(name, handler)` (server)
Optional server-action relay with distance revalidation.

### Option shape
Every `add*`/zone constructor takes an `options` array of:
```lua
{
    label = "Open trunk",         -- required
    icon = "Car",                 -- optional
    distance = 2.0,                -- optional, overrides the registration's own default
    bones = { "boot" },            -- optional, restricts this option to specific bones
    canInteract = function(entity, distance, data) return true end,  -- optional
    allowInVehicle = true,         -- optional, keeps this option usable while seated in a vehicle (see Config.target.disableInVehicle)
    onSelect = function(entity, data) ... end,  -- required
    data = { foo = "bar" },        -- optional, passed through to canInteract/onSelect
}
```

### Opaque `item`/`job`/`gang`/`groups` fields
The native `exports.kora_target` API accepts these fields but deliberately leaves policy to its caller. The `exports['qb-target']` compatibility surface is different: it enforces `job`, `excludejob`, `jobType`, `excludejobType`, `gang`, `excludegang`, `item`, and `citizenid` through kora_core, then runs the option's own `canInteract`. The ox_target surface does not interpret ox_core `groups` because ox_core is not part of this stack.

## Config highlights (`config.lua`)

`Config.target.keybind` (default `LMENU`, hold-to-target) and `Config.target.toggle`
(set `true` for press-to-activate instead of hold, matching ox_target's default).
Releasing `Config.target.keybind` runs the sole option or opens kora_lib's pointer-free
interact selector for multiple options (scroll or Up/Down to choose, E to select). `Config.target.maxDistance`
(10.0m raycast reach) and `defaultOptionDistance` (2.5m fallback interact
distance). `tickAcquire`/`tickActive` (50ms resolver cadence over an entity or
available option), `tickMiss` (100ms when neither is hit; no thread at all while
released), `staticMissRefresh` (500ms for motionless misses), and
`entityProbeInterval` (250ms between entity-only fallback rays).
`canInteractFailureCacheMs` is the 250ms retry cooldown for failed checks;
successful checks remain uncached by default. `debug` (global zone
outline) and `diagnostics` (per-hold resolver metrics) both default to
`false`. `sprites` controls the distance-culled zone location icons (off by
default; see `sprites.enabled`, `drawDistance`, `useThemeColour`,
`hideWhileTargeting`); `demo` (built-in global ped/vehicle demo targets) defaults to
`false`.

## Related resources

Part of the [qbcore2](https://github.com/qbcore2) resource set:

- [kora_lib](https://qbcore2.github.io/kora_lib/) — shared helper library
- [kora_sql](https://qbcore2.github.io/kora_sql/) — database driver
- [kora_core](https://qbcore2.github.io/kora_core/) — framework core
- [kora_inventory](https://qbcore2.github.io/kora_inventory/) — headless inventory
- [kora_clothing](https://qbcore2.github.io/kora_clothing/) — clothing/wardrobe
- [full resource list ↗](https://github.com/orgs/qbcore2/repositories)
