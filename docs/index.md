---
layout: default
title: qbtarget
---

A crosshair/zone-based targeting and interaction engine for FiveM, built on
[qblib](https://qbcore2.github.io/qblib/) (`QB.raycast` for aim resolution,
`QB.zones` for area-based targets, `QB.world`/`QB.drawing` as the underlying
pool-query/prompt-rendering primitives). It's one resource, no separate proxy
resources: it declares `provide 'qb-target'` and `provide 'ox_target'` in its
`fxmanifest.lua` and registers the real, public qb-target/ox_target export
names directly, so scripts written against `exports['qb-target']:...` or
`exports.ox_target:...` keep working unmodified against this same running
resource.

## Requirements

- [qblib](https://qbcore2.github.io/qblib/) — shared helper library qbtarget is built on (raycasting, zones, world/drawing primitives, NUI, callbacks)

## Installation

`server.cfg`, in this order:
```
ensure qblib
ensure qbtarget
```
No database and no framework (qb-core/ox_core/QBCore) are required — qbtarget
has no persistence and does not check jobs/gangs/inventory itself (see the
"Opaque fields" note under API reference below).

## Usage examples

### Target a specific entity
```lua
-- client
local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)

local id = exports.qbtarget:addEntity(vehicle, {
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
exports.qbtarget:removeEntity(vehicle, id)
```

### Target every entity spawned from a model
```lua
-- client
exports.qbtarget:addModel('prop_atm_01', {
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
exports.qbtarget:addTargetBone(vehicle, 'boot', {
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
exports.qbtarget:addGlobalType('ped', {
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
local id = exports.qbtarget:addBoxZone({
    coords = vector3(100.0, 200.0, 30.0),
    size = vector3(2.0, 2.0, 3.0),
    rotation = 0.0,
    options = {
        { label = 'Open shop', icon = 'Store', onSelect = function() print('shop opened') end },
    },
})

-- later
exports.qbtarget:removeZone(id)
```

### ox_target compat — same call signature, no separate resource
```lua
-- client, written against ox_target but running on qbtarget unmodified
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
exports.qbtarget:registerServerAction('openTrunk', function(src, entity)
    -- entity is already distance-checked against src here
    TriggerClientEvent('myscript:openTrunk', src, entity)
end)

-- client, inside an onSelect
local ok, result = exports.qbtarget:runServerAction('openTrunk', entity, 3.0)
if not ok then print('too far away or invalid target') end
```

## API reference

All functions are plain FiveM exports on `qbtarget` — `exports.qbtarget:<name>(...)`.
The same targets are also reachable through `exports['qb-target']:...`
(PascalCase, qb-target's real function names) and `exports.ox_target:...`
(camelCase, ox_target's real function names) — both are compatibility layers
over this same API, not separate implementations.

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

### `addBoxZone({coords, size, rotation?, options, distance?, debug?, drawSprite?})`
### `addSphereZone({coords, radius, options, distance?, debug?, drawSprite?})`
### `addPolyZone({points, thickness?, minZ?, maxZ?, options, distance?, debug?, drawSprite?})`
Zone-based targets, backed by `QB.zones.box/sphere/poly` — no aiming required, just aiming at (not necessarily standing inside) the zone. Returns the registration `id`.

Set `Config.target.debug = true` to outline every target zone while developing;
an individual zone can also set `debug = true`. `Config.target.sprites` draws
a small, distance-culled `shared/info` world sprite at each coordinate-zone
anchor. Set `drawSprite = false` on a zone to suppress its icon. This visual
loop never raycasts or scans the entity pool; model/entity/global targets have
no single stable anchor and therefore intentionally do not get static sprites.

### `removeZone(id)`
Removes a zone-based registration.

### `setEnabled(enabled)`
Globally enables/disables the whole targeting loop.

### `getState()`
Returns `{ enabled: boolean, hovering: table|nil }`. `hovering` mirrors whatever the tick loop last resolved (`{ kind, id, entity?, zoneId?, optionCount }`), or `nil` when nothing is currently targeted.

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
    onSelect = function(entity, data) ... end,  -- required
    data = { foo = "bar" },        -- optional, passed through to canInteract/onSelect
}
```

### Opaque `item`/`job`/`gang`/`groups` fields
An option may also carry `item`, `job`, `gang`, or `groups` fields (accepted so ported `qb-target`/`ox_target` scripts don't error), but **qbtarget never interprets them** — there is no framework installed to check a player's job/gang/inventory against. A ported script that relied on qb-target/ox_target auto-filtering these will show its option to everyone until the consumer supplies its own `canInteract` doing that check itself.

## Config highlights (`config.lua`)

`Config.target.keybind` (default `LMENU`, hold-to-target) and `Config.target.toggle`
(set `true` for press-to-activate instead of hold, matching ox_target's default).
Releasing `Config.target.keybind` runs the sole option or opens qblib's focused
menu for multiple options (mouse and keyboard both work). `Config.target.maxDistance`
(10.0m raycast reach) and `defaultOptionDistance` (2.5m fallback interact
distance). `tickAcquire`/`tickActive` (50ms resolver cadence while the key is
held; no thread at all while released). `canInteractCacheMs` (0/disabled by
default — enable only after profiling static checks). `debug` (global zone
outline) and `diagnostics` (per-hold resolver metrics) both default to
`false`. `sprites` controls the enabled-by-default, distance-culled zone
location icons; `demo` (built-in global ped/vehicle demo targets) defaults to
`false`.

## Related resources

Part of the [qbcore2](https://github.com/qbcore2) resource set:

- [qblib](https://qbcore2.github.io/qblib/) — shared helper library
- [qbsql](https://qbcore2.github.io/qbsql/) — database driver
- [qbcore](https://qbcore2.github.io/qbcore/) — framework core
- [qbinventory](https://qbcore2.github.io/qbinventory/) — headless inventory
- [qbclothing](https://qbcore2.github.io/qbclothing/) — clothing/wardrobe
- [full resource list ↗](https://github.com/orgs/qbcore2/repositories)
