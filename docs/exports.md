---
title: Exports
sidebar_position: 5
---

# Exports

These are the native exports, called as `exports.kora_target:name(...)`. The same targets can also be reached through the qb-target and ox_target compatibility exports. See [Compatibility](./compatibility.md). The option table format is described in [Option format](./options.md).

Registration ids are integers. They start at 1 each time kora_target starts and are unique across all registration kinds.

## Ownership and cleanup

Each registration is tracked against the resource that called the export. When that resource stops, its registrations (including kora_lib zones) are removed automatically.

When `Config.target.ownerScopedRemoval` is true (the default), a remove call that passes an id is refused if the id belongs to a different resource or is a different kind of registration. The call returns `false` and prints a console message. Remove calls without an id (for example `removeModel(model)`) are not owner-scoped. They remove every matching registration.

## Client exports

### addEntity

```lua
local id = exports.kora_target:addEntity(entity, options, defaultDistance)
```

Registers options on one or more specific entity handles.

- `entity`: a handle, or an array of handles.
- `options`: option array.
- `defaultDistance` (optional): a number.
- Returns: the registration id, or `nil` when a handle is not a number and `Config.target.skipInvalidEntities` is true.

Networked entities are also indexed by network id, so their options survive the entity streaming out and back in under a new handle. Local (non-networked) entities are tracked by handle only. Remove them before deleting the entity.

### removeEntity

```lua
local removed = exports.kora_target:removeEntity(entity, id)
```

- With `id`: removes only that registration (owner-scoped). Returns `true` unless the removal was refused.
- Without `id`: removes every registration that covers `entity`, by handle or network id. A registration made for several entities at once is removed entirely. Returns `true` if anything was removed.

### addModel

```lua
local id = exports.kora_target:addModel(model, options, defaultDistance)
```

Registers options on every current and future entity with any of the given models. `model` is a hash, a model name string (hashed with `joaat`), or an array of these. Returns the registration id.

### removeModel

```lua
local removed = exports.kora_target:removeModel(model, id)
```

With `id`, removes that registration (owner-scoped). Without it, removes every registration on the given model or models. Returns a boolean.

### addGlobalType

```lua
local id = exports.kora_target:addGlobalType(entityType, options, defaultDistance)
```

Registers options on every entity of a type. `entityType` is `'ped'`, `'vehicle'`, `'object'` or `'player'`. `'ped'` matches non-player peds only, and `'player'` matches player peds.

### removeGlobalType

```lua
local removed = exports.kora_target:removeGlobalType(entityType, id)
```

With `id`, removes that registration (owner-scoped). Without it, removes every registration of that type.

### addGlobalBone

```lua
local id = exports.kora_target:addGlobalBone(bones, options, defaultDistance)
```

Registers options on any entity that has one of the named bones, when the aim lands within `Config.target.boneTolerance` of that bone. `bones` is a string or an array of strings. For example, `'boot'` matches every vehicle's boot.

### removeGlobalBone

```lua
local removed = exports.kora_target:removeGlobalBone(id)
```

Removes a global bone registration (owner-scoped). Returns `true` unless refused.

### addTargetBone

```lua
local id = exports.kora_target:addTargetBone(entity, bone, options, defaultDistance)
```

A shortcut for `addEntity`: every option is copied with `bones = { bone }`. Remove the registration with `removeEntity`.

### addBoxZone

```lua
local id = exports.kora_target:addBoxZone({
    coords = vector3(100.0, 200.0, 30.0), -- centre
    size = vector3(2.0, 2.0, 3.0),        -- full extents x, y, z
    rotation = 0.0,                       -- optional, degrees around Z
    options = { ... },
    distance = 2.0,          -- optional
    debug = false,           -- optional
    drawSprite = nil,        -- optional
    allowInVehicle = nil,    -- optional
})
```

Creates a kora_lib box zone. `coords` and `size` accept a vector3 or a table with `x`/`y`/`z`. Returns the registration id.

### addSphereZone

```lua
local id = exports.kora_target:addSphereZone({
    coords = vector3(100.0, 200.0, 30.0),
    radius = 1.5,            -- positive number
    options = { ... },
    -- distance, debug, drawSprite, allowInVehicle as for addBoxZone
})
```

### addPolyZone

```lua
local id = exports.kora_target:addPolyZone({
    points = { vector3(...), vector3(...), vector3(...) }, -- at least 3 points with x, y, z
    thickness = 4.0,         -- optional, passed to kora_lib
    minZ = 28.0,             -- optional
    maxZ = 32.0,             -- optional
    spriteCoords = vector3(...), -- optional sprite anchor, defaults to the average of the points
    options = { ... },
    -- distance, debug, drawSprite, allowInVehicle as for addBoxZone
})
```

If you omit `minZ`/`maxZ`, kora_lib derives the vertical band from `thickness` and its own defaults.

### removeZone

```lua
local removed = exports.kora_target:removeZone(id)
```

Removes a zone registration and its kora_lib zone. Returns `false` when the id is not a zone, does not exist, or belongs to another resource (with `ownerScopedRemoval`).

### setEnabled

```lua
exports.kora_target:setEnabled(enabled)
```

`enabled` must be a boolean. `false` cancels any current session and closes the menu. Targeting then stays off until `setEnabled(true)` is called.

### getState

```lua
local state = exports.kora_target:getState()
-- { enabled = true, active = false, success = false, hovering = nil }
```

| Field | Description |
| --- | --- |
| `enabled` | The `setEnabled` state. |
| `active` | True while a targeting session is running. |
| `success` | True while at least one option is resolved under the aim. |
| `hovering` | `nil`, or the top candidate: `{ kind, id, entity, zoneId, option, optionCount }`. `kind` is `'entity'`, `'model'`, `'globalType'`, `'globalBone'` or `'zone'`. |

### runServerAction

```lua
local ok, result = exports.kora_target:runServerAction(name, entity, maxDistance, ...)
```

Triggers a server action registered with `registerServerAction`, through kora_lib's `Kora.callback`. See [Server actions](#server-actions).

## Server exports

### registerServerAction

```lua
exports.kora_target:registerServerAction(name, handler, opts)
```

- `name`: a non-empty string. Registering an existing name overwrites it and prints a warning.
- `handler`: called as `handler(src, entity, ...)`. `entity` is the server-side entity handle resolved from the client's network id. Any extra values from `runServerAction` follow it.
- `opts.maxDistance` (optional): the distance limit for this action. It must be greater than 0 and no larger than `Config.target.serverActionMaxDistance` (5.0), which is also the default.

Actions are removed automatically when the registering resource stops.

## Server actions

`runServerAction` and `registerServerAction` are an optional relay for a common case: a server action that must confirm the target entity is real and close to the player. An `onSelect` can still trigger its own server events instead.

```lua
-- server
exports.kora_target:registerServerAction('openTrunk', function(src, entity)
    -- entity already resolved and distance-checked against src
    TriggerClientEvent('myscript:openTrunk', src, NetworkGetNetworkIdFromEntity(entity))
end, { maxDistance = 3.0 })

-- client, inside an onSelect
local ok, reason = exports.kora_target:runServerAction('openTrunk', entity)
if not ok then print(reason) end
```

How a call is processed:

1. On the client, `entity` must be networked, or the call raises an error. Entities from `Kora.entities.create` are local and cannot be used. The client sends the network id.
2. On the server, the network id is resolved with `Kora.world.resolveNetworkEntity`. The entity must exist, share the player's routing bucket, and be within the action's `maxDistance`.
3. The return values are:
   - `nil`: the callback itself failed (timeout or handshake). Check kora_lib's console output.
   - `false, reason`: the action name is unknown, entity validation failed, or the handler raised an error. The reason strings are `A networked target entity is required.`, `Target entity no longer exists.`, `Player entity unavailable.`, `Target is in another routing bucket.`, `Too far from target.`, `Target entity is unavailable.`, `Server action errored.` and `Unknown kora_target server action: name`.
   - `true, ...`: the handler ran. Its own return values follow `true`, including a handler that returns `false, reason`.

The client `maxDistance` argument is accepted only for compatibility. The server ignores it and uses the distance stored by `registerServerAction`. An `entity` is always required: calling without one fails with `A networked target entity is required.`

## Development-only exports

When the replicated convar `fft_kora_hooks` is `true`, `fft_hooks.lua` adds the client exports `fftVersion` and `fftAction`. `fftAction` only accepts calls from a resource named `fft`. These exports exist for automated test runs and are not a public API.
