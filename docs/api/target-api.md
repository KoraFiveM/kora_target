---
title: "Native API"
sidebar_position: 2
---


# Native API

## Client

The native kora_target API: register interactions on entities, models, global entity types, bones and coordinate zones, remove them again, gate the engine, read its state and call validated server actions. Every function is a plain client export of `kora_target`.

Namespace: `exports.kora_target` · Source: `client/exports.lua, client/state.lua`

### Target option properties

Every property an option table passed to the add functions can contain. Only `label` and `onSelect` are required.

| Property | Type | Required | Description |
| --- | --- | --- | --- |
| `label` | string | required | Required, non-empty. Shown in the prompt (alone) or in the selection menu. |
| `onSelect` | function | required | Required. Called as onSelect(entity, data) when the option is chosen. entity is the hit entity (nil for a zone point on world geometry). Runs in pcall: an error prints `[kora_target] onSelect for option '<label>' errored: ...` and is otherwise swallowed. |
| `name` | string | optional | Optional identifier. The only place the engine reads it is `Config.target.allowWhileDead`: an option whose name is in that list stays usable while the player is downed. Compat layers also use it for removal by name (ox_target). |
| `icon` | string | optional | Optional icon name passed to the Kora Lib option menu when several options are available. The single-option prompt shows the label only. |
| `distance` | number | optional | Optional per-option reach in metres, measured from the player to the AIMED point. Overrides the registration's default distance, which overrides `Config.target.defaultOptionDistance`. Must be a number. |
| `bones` | string[] | optional | Optional list of bone names. When set, the aimed point must land within `Config.target.boneTolerance` of one of those bones on the hit entity. On a zone (no entity) an option with bones never matches. Overrides the bones of a global-bone registration. |
| `canInteract` | function | optional | Optional filter called as canInteract(entity, distance, data, anchorCoords) after the cheap distance and bone checks pass. Only an explicit `false` hides the option; so does an error (printed as `[kora_target] canInteract for option '<label>' errored: ...`). Returning nil allows it. |
| `allowInVehicle` | boolean | optional | Optional. With `Config.target.disableInVehicle` on, a seated player can still use options (or whole zones) that set this to true. An option's own value, including false, overrides the zone's. Must be boolean. |
| `data` | any | optional | Optional value handed back as the second argument of onSelect and the third of canInteract. Keep it plain data so it survives the exports boundary. |
| `item / job / gang / groups` | any | optional | Accepted and stored but NEVER interpreted by the native engine. A native caller that wants such rules must do them inside canInteract (and again on the server). The qb-target and ox_target compat layers translate their own filter fields before they reach the engine. |

### How it works

kora_target keeps one registry of registrations. Each add call validates its options, allocates the next integer id (ids are shared by every kind and never reused while the resource runs), records the invoking resource as owner, and indexes the registration by entity, model, global type, global bone or zone. Zone registrations are additionally placed in an XY grid of 50 m cells. When the targeting key is held the loop casts rays, finds registrations that apply to what was hit, filters their options by distance, bone and canInteract, and shows the result. Registrations belong to the resource that created them and are destroyed automatically when that resource stops; compat registrations are attributed the same way.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| Registration | One call to an add function. It has an integer id, an owner resource, a list of options and a default distance. |
| Aimed point | The world position where the aim ray hit something. Distances and zone containment are measured against it. |
| Candidate | An option that passed the distance, bone and canInteract checks in the current scan. |
| Global type | One of ped, vehicle, object or player. Players are peds for which IsPedAPlayer is true. |

### Ownership and cleanup

The invoking resource is recorded for every registration. When that resource stops (`onClientResourceStop` through Kora Lib's registry), every registration it created is destroyed, including zones, which are removed from Kora Lib too. A registration that is removed twice is a no-op. With `Config.target.ownerScopedRemoval` true (the default), a remove call that passes an id is refused (it returns `false` and prints a console message) when the id belongs to a different resource or is a different kind of registration. Set it to false to allow any resource to remove any registration by id.

### Removal semantics

removeEntity, removeModel and removeGlobalType without an id remove every matching registration regardless of who created it, and always remove whole registrations. Use the id from the add call to remove only what you added.

### Functions

Sixteen client exports. The add functions return a numeric registration id (zone functions, addEntity, addModel, addGlobalType, addGlobalBone, addTargetBone); keep it for removal. The accepted option properties are listed in the table at the top of this page.

#### `exports.kora_target:addEntity(entity, options, defaultDistance?)`

Registers target options on one or more specific entity handles (a spawned ped, a vehicle you own, a prop). The registration is indexed under every handle given and matched when the aim ray hits one of them. Returns the registration id.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | number \| number[] | One entity handle or an array of handles. All handles share one registration. |
| `options` | table[] | Non-empty array of target option tables (see "Target option properties"). Every entry needs a non-empty `label` string and an `onSelect` callable; `canInteract` must be callable, `distance` a number, `bones` a table and `allowInVehicle` a boolean when present, otherwise registration raises an assertion. |
| `defaultDistance?` | number | Default interaction distance in metres for options in this registration that set no `distance` of their own. When omitted, `Config.target.defaultOptionDistance` (2.5) is used. |

**Returns**

- **id** — integer registration id, to pass to removeEntity(entity, id).
- **nil** — returned instead of an id when a handle is not a number and `Config.target.skipInvalidEntities` is true (the default). A line `[kora_target] addEntity skipped: invalid entity handle (...) from <resource>` is printed and nothing is registered, not even the valid handles in the same array.

**Example**

```lua
local ped = CreatePed(4, joaat('a_m_m_business_01'), 25.7, -1347.3, 29.5, 0.0, false, true)
local id = exports.kora_target:addEntity(ped, {
    {
        name = 'talk_banker',
        label = 'Talk to the banker',
        icon = 'comments',
        distance = 2.0,
        canInteract = function(entity, distance) return not IsPedDeadOrDying(entity, true) end,
        onSelect = function(entity) TriggerServerEvent('bank:server:talk') end,
    },
})
if not id then print('banker ped is invalid, target not registered') end
```

**Representative console output**

```text
Returns 7 (the next registration id). Aiming at the ped within 2.0 m shows "Talk to the banker"; releasing the key runs onSelect.
```

#### `exports.kora_target:removeEntity(entity, id?)`

Removes entity registrations. With an id, that one registration is destroyed. Without an id, every registration indexed under the entity is destroyed. Registrations are removed whole: a registration created for several entities disappears for all of them, not only for the one passed here.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | number | Entity handle. Must be a number or the call raises "entity must be a number.". |
| `id?` | integer | Registration id returned by addEntity. When given, only this registration is removed (the entity argument is still required but is not matched against it). |

**Returns**

- **removed** — boolean. With an id it is always true, even if the id is unknown or was already removed. Without an id it is true only if at least one registration was found on the entity.

**Example**

```lua
-- remove just the option set you registered
exports.kora_target:removeEntity(ped, id)

-- or clear everything registered on the entity (also other resources' registrations)
local had = exports.kora_target:removeEntity(ped)
```

**Representative console output**

```text
Returns true. The ped no longer shows the option on the next scan (the resolver cache is invalidated immediately).
```

#### `exports.kora_target:addModel(model, options, defaultDistance?)`

Registers target options on every current and future entity whose model matches. Model names are hashed with joaat; numbers are used as hashes unchanged. The match happens at scan time with GetEntityModel, so entities spawned later are covered automatically.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `model` | string \| number \| (string \| number)[] | Model name or hash, or an array of them. Anything else raises "Models must be strings or numbers."; an empty array raises "addModel requires at least one model.". |
| `options` | table[] | Non-empty array of target option tables (see "Target option properties"). Every entry needs a non-empty `label` string and an `onSelect` callable; `canInteract` must be callable, `distance` a number, `bones` a table and `allowInVehicle` a boolean when present, otherwise registration raises an assertion. |
| `defaultDistance?` | number | Default interaction distance in metres for options in this registration that set no `distance` of their own. When omitted, `Config.target.defaultOptionDistance` (2.5) is used. |

**Returns**

- **id** — integer registration id.

**Example**

```lua
local vendingId = exports.kora_target:addModel({ 'prop_vend_soda_01', 'prop_vend_soda_02' }, {
    {
        label = 'Buy a drink',
        icon = 'bottle-water',
        onSelect = function(entity)
            TriggerServerEvent('vending:server:buy', 'water', GetEntityCoords(entity))
        end,
    },
}, 1.5)
```

**Representative console output**

```text
Returns the id. Every soda machine in the world now offers "Buy a drink" when aimed at within 1.5 m.
```

#### `exports.kora_target:removeModel(model, id?)`

Removes model registrations, with the same whole-registration semantics as removeEntity. With an id only that registration is destroyed; otherwise every registration indexed under any of the given models is destroyed.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `model` | string \| number \| (string \| number)[] | Model name(s) or hash(es). Ignored when id is given, so nil is acceptable then. |
| `id?` | integer | Registration id returned by addModel. |

**Returns**

- **removed** — boolean. Always true when an id is given. Otherwise true if at least one registration was removed.

**Example**

```lua
exports.kora_target:removeModel(nil, vendingId)
exports.kora_target:removeModel({ 'prop_vend_soda_01' }) -- every registration on that model
```

**Representative console output**

```text
Returns true; the machines stop offering the option.
```

#### `exports.kora_target:addGlobalType(entityType, options, defaultDistance?)`

Registers options on every entity of a type. The type is derived at scan time: players are separated from peds (IsPedAPlayer), vehicles and objects use GetEntityType.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entityType` | 'ped' \| 'vehicle' \| 'object' \| 'player' | Global type. Anything else raises "entityType must be 'ped', 'vehicle', 'object', or 'player'.". |
| `options` | table[] | Non-empty array of target option tables (see "Target option properties"). Every entry needs a non-empty `label` string and an `onSelect` callable; `canInteract` must be callable, `distance` a number, `bones` a table and `allowInVehicle` a boolean when present, otherwise registration raises an assertion. |
| `defaultDistance?` | number | Default interaction distance in metres for options in this registration that set no `distance` of their own. When omitted, `Config.target.defaultOptionDistance` (2.5) is used. |

**Returns**

- **id** — integer registration id.

**Example**

```lua
local id = exports.kora_target:addGlobalType('player', {
    {
        name = 'check_pulse',
        label = 'Check pulse',
        icon = 'heart-pulse',
        distance = 2.0,
        canInteract = function(entity) return LocalPlayer.state.job == 'ambulance' end,
        onSelect = function(entity)
            local serverId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
            TriggerServerEvent('ems:server:checkPulse', serverId)
        end,
    },
})
```

**Representative console output**

```text
Returns the id. Aiming at another player within 2.0 m shows the option to on-duty ambulance staff only (cosmetic check; the server must verify the job).
```

#### `exports.kora_target:removeGlobalType(entityType, id?)`

Removes global-type registrations. With an id only that registration is removed; without it every registration for that type is destroyed, including ones from other resources.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entityType` | 'ped' \| 'vehicle' \| 'object' \| 'player' | Global type. Validated even when an id is given. |
| `id?` | integer | Registration id returned by addGlobalType. |

**Returns**

- **removed** — boolean. Always true with an id; otherwise true when something was removed.

**Example**

```lua
exports.kora_target:removeGlobalType('player', id)
```

**Representative console output**

```text
Returns true.
```

#### `exports.kora_target:addGlobalBone(bones, options, defaultDistance?)`

Registers options on any entity, of any type or model, that has a matching bone. The ray must land within `Config.target.boneTolerance` (0.35 m) of the bone's world position for the option to match. An option with its own `bones` list overrides the registration's bones.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `bones` | string \| string[] | Bone name(s), for example 'boot', 'bonnet', 'door_dside_f'. Non-strings raise "Bone names must be strings."; an empty list raises an assertion. |
| `options` | table[] | Non-empty array of target option tables (see "Target option properties"). Every entry needs a non-empty `label` string and an `onSelect` callable; `canInteract` must be callable, `distance` a number, `bones` a table and `allowInVehicle` a boolean when present, otherwise registration raises an assertion. |
| `defaultDistance?` | number | Default interaction distance in metres for options in this registration that set no `distance` of their own. When omitted, `Config.target.defaultOptionDistance` (2.5) is used. |

**Returns**

- **id** — integer registration id, to pass to removeGlobalBone.

**Example**

```lua
local id = exports.kora_target:addGlobalBone({ 'boot', 'bonnet' }, {
    {
        label = 'Inspect compartment',
        icon = 'magnifying-glass',
        distance = 2.0,
        onSelect = function(entity) print('inspecting', entity) end,
    },
})
```

**Representative console output**

```text
Returns the id. Any vehicle shows the option only while the aim point is near its boot or bonnet bone.
```

#### `exports.kora_target:removeGlobalBone(id)`

Destroys a global-bone registration by id.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | integer | Registration id returned by addGlobalBone. |

**Returns**

- **removed** — boolean; always true, even if the id was unknown.

**Example**

```lua
exports.kora_target:removeGlobalBone(id)
```

**Representative console output**

```text
Returns true.
```

#### `exports.kora_target:addTargetBone(entity, bone, options, defaultDistance?)`

Shorthand for addEntity: copies each option and forces `bones = { bone }` on every copy, so the options only match when the aim is near that bone of that entity. Any `bones` an option already had is replaced. The call is delegated to addEntity, so an invalid handle is skipped and nil returned under skipInvalidEntities.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | number | Entity handle. |
| `bone` | string | Bone name; anything else raises "bone must be a string.". |
| `options` | table[] | Non-empty array of target option tables (see "Target option properties"). Every entry needs a non-empty `label` string and an `onSelect` callable; `canInteract` must be callable, `distance` a number, `bones` a table and `allowInVehicle` a boolean when present, otherwise registration raises an assertion. |
| `defaultDistance?` | number | Default interaction distance in metres for options in this registration that set no `distance` of their own. When omitted, `Config.target.defaultOptionDistance` (2.5) is used. |

**Returns**

- **id** — integer registration id, or nil when addEntity skipped the handle.

**Example**

```lua
local id = exports.kora_target:addTargetBone(vehicle, 'boot', {
    { label = 'Open trunk', icon = 'box-open', distance = 2.0, onSelect = function(entity) OpenMyTrunk(entity) end },
})
```

**Representative console output**

```text
Returns the id; the option only appears when aiming at the boot of that vehicle.
```

#### `exports.kora_target:addBoxZone(zoneOptions)`

Creates a rotated box zone through Kora.zones.box (with trackPlayer = false, so there are no enter/exit callbacks) and registers options against it. The zone matches the point where the aim ray lands. Zones are indexed in a 50 m XY grid so many zones do not slow the scan.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `zoneOptions` | table | Required. Fields: coords (vector3 or &#123;x,y,z&#125;, box centre), size (vector3 or &#123;x,y,z&#125;, FULL extents), rotation? (degrees around Z), options (required array), distance?, debug?, drawSprite?, allowInVehicle?. |

**Returns**

- **id** — integer registration id, to pass to removeZone.
- **Failure** — assertions: options table required; coords and size must have numeric x/y/z; options array rules; allowInVehicle must be boolean.

**Example**

```lua
local id = exports.kora_target:addBoxZone({
    coords = vector3(-1037.6, -2738.1, 20.2),
    size = vector3(2.0, 1.2, 2.0),
    rotation = 330.0,
    distance = 2.0,
    drawSprite = true,
    options = {
        { label = 'Check in', icon = 'plane', onSelect = function() TriggerServerEvent('airport:server:checkIn') end },
    },
})
```

**Representative console output**

```text
Returns the id. Aiming at any point inside the 2.0 x 1.2 x 2.0 box (rotated 330 degrees) from within 2.0 m offers "Check in"; a sprite is drawn at the box centre.
```

#### `exports.kora_target:addSphereZone(zoneOptions)`

Creates a sphere zone through Kora.zones.sphere and registers options against it. The aimed point must be inside the sphere.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `zoneOptions` | table | Required. Fields: coords (vector3 or &#123;x,y,z&#125;, centre), radius (positive number), options (required array), distance?, debug?, drawSprite?, allowInVehicle?. |

**Returns**

- **id** — integer registration id.
- **Failure** — radius must be a positive number; coords must have numeric x/y/z.

**Example**

```lua
local id = exports.kora_target:addSphereZone({
    coords = vector3(1692.3, 3584.8, 35.6),
    radius = 1.5,
    options = {
        { label = 'Search the crate', icon = 'box', onSelect = function() TriggerServerEvent('crates:server:search', 'sandy') end },
    },
})
```

**Representative console output**

```text
Returns the id. Aiming within the 1.5 m radius sphere shows the option when you are within the default 2.5 m.
```

#### `exports.kora_target:addPolyZone(zoneOptions)`

Creates a polygon zone through Kora.zones.poly and registers options against it. The sprite anchor is the average of the points unless `spriteCoords` is supplied. Without both minZ and maxZ the broad-phase treats the vertical band as unbounded, while the exact containment still uses Kora Lib's own height rules.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `zoneOptions` | table | Required. Fields: points (array of at least 3 vector3 or &#123;x,y,z&#125;), thickness?, minZ?, maxZ?, spriteCoords? (vector3 or &#123;x,y,z&#125; sprite anchor), options (required array), distance?, debug?, drawSprite?, allowInVehicle?. |

**Returns**

- **id** — integer registration id.
- **Failure** — fewer than 3 points or a point without numeric x/y/z raises an assertion.

**Example**

```lua
local id = exports.kora_target:addPolyZone({
    points = {
        vector3(-267.1, -962.6, 31.2), vector3(-262.4, -950.0, 31.2),
        vector3(-251.0, -954.1, 31.2), vector3(-255.9, -966.8, 31.2),
    },
    minZ = 30.2, maxZ = 33.0,
    spriteCoords = vector3(-259.0, -958.0, 31.7),
    options = {
        { label = 'Browse listings', icon = 'house', onSelect = function() TriggerEvent('realty:client:browse') end },
    },
})
```

**Representative console output**

```text
Returns the id. Aiming at the floor of the lobby polygon (30.2 to 33.0 m high) offers the option.
```

#### `exports.kora_target:removeZone(id)`

Destroys a zone registration: removes it from the zone grid, the sprite counters and the underlying Kora.zones zone.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | integer | Id returned by addBoxZone, addSphereZone or addPolyZone. |

**Returns**

- **removed** — boolean. false if the id is unknown or belongs to a non-zone registration; true after removal.

**Example**

```lua
if exports.kora_target:removeZone(counterId) then
    counterId = nil
end
```

**Representative console output**

```text
Returns true; the sprite (if any) disappears and the zone can no longer be aimed at.
```

#### `exports.kora_target:setEnabled(enabled)`

Globally opens or closes the targeting gate. Disabling clears the active session, hover state and success flag and cancels any open menu; registrations are kept. While disabled, holding the key starts nothing useful (the loop idles) and nothing can be selected.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `enabled` | boolean | true to allow targeting, false to block it. Non-booleans raise "enabled must be a boolean.". |

**Returns**

- **No return value.**

**Example**

```lua
-- block targeting while the player is in a minigame
exports.kora_target:setEnabled(false)
local won = RunLockpick()
exports.kora_target:setEnabled(true)
```

**Representative console output**

```text
Nothing is printed. While disabled, getState().enabled is false.
```

#### `exports.kora_target:getState()`

Returns a snapshot of the engine state. `hovering` mirrors the top candidate resolved by the loop.

**Parameters**



**Returns**

- **state** — table `{ enabled, active, success, hovering }`. enabled: the setEnabled gate. active: targeting session is running. success: at least one candidate is currently available.
- **state.hovering** — nil, or `{ kind, id, entity, zoneId, option, optionCount }` where kind is 'entity', 'model', 'globalType', 'globalBone' or 'zone', zoneId is set only for zones and optionCount is the number of available options.

**Example**

```lua
local state = exports.kora_target:getState()
if state.active and state.hovering then
    print(('aiming at %s registration %d with %d option(s)'):format(state.hovering.kind, state.hovering.id, state.hovering.optionCount))
end
```

**Representative console output**

```text
aiming at model registration 7 with 1 option(s)
```

#### `exports.kora_target:runServerAction(name, entity?, maxDistance?, ...)`

Calls a server action registered with registerServerAction through the Kora Lib callback `kora_target:server:runAction`. The server resolves the entity from its network id, checks that it exists, is in the player's routing bucket and within the action's distance cap, then runs the handler. Blocks until the server replies, so call it from a thread, command handler or onSelect.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Action name registered on the server. Empty or non-string raises "runServerAction requires a name.". |
| `entity?` | number | Networked entity (a real ped, vehicle or object known to the server) to distance-check. Non-networked entities raise an assertion. In the current server code a missing entity always fails with "A networked target entity is required." because the server rejects a nil network id. |
| `maxDistance?` | number | Accepted for compatibility but ignored: the server uses the cap captured at registration, never the client value. |
| `...` | any | Extra arguments forwarded to the server handler after (src, entity). |

**Returns**

- **ok** — boolean | nil. nil if the callback itself failed (timeout or handshake problem, see Kora Lib's console). true when the handler ran; false for an unknown action, a missing, unavailable or too-far entity, a routing-bucket mismatch, a handler error, or a deliberate `return false, reason` from the handler.
- **...** — on true, the handler's own return values; on false, the reason string. Nothing when ok is nil.

**Example**

```lua
-- onSelect of a shop-keeper ped option
onSelect = function(entity)
    local ok, result = exports.kora_target:runServerAction('shop:openStock', entity, 3.0, 'ammunation')
    if not ok then
        print('shop refused:', result)
        return
    end
    print('stock id', result)
end
```

**Representative console output**

```text
shop refused: Too far from target.
```

### Limits and related APIs

Client only: registrations, zones and callbacks exist in the player's game, not on the server. The server side only validates server actions. The ids are plain integers local to each client. Entities from Kora.entities.create and local peds cannot be used with runServerAction. getState().hovering contains the option table whose functions become references when read from another resource.

### Related guides

- [Compatibility](./compatibility.md)

## Server

The server half is one opt-in primitive: a distance-revalidated relay for named server actions. A client calls `runServerAction`; the server resolves the network id, checks the entity and the distance, then runs your handler. It is not a permission framework.

Namespace: `exports.kora_target` · Source: `server/server.lua`

### How it works

Registered actions are held in a table keyed by name. The Kora Lib callback `kora_target:server:runAction(src, name, netId, clientDistance, ...)` looks the action up, calls Kora.world.resolveNetworkEntity(src, netId, &#123; maxDistance = action.maxDistance &#125;), runs the handler under pcall and replies with `true, ...handlerResults` or `false, reason`. The client distance argument is ignored. Actions belonging to a resource are removed when that resource stops.

### Server action flow

1. **Register on the server** — Call `registerServerAction(name, handler, { maxDistance })` once when your resource starts. The name should be unique to your resource (for example `shop:openStock`). Re-registering a name overwrites it and logs a warning.
2. **Client calls it from onSelect** — `exports.kora_target:runServerAction(name, entity, 3.0, ...)`. The entity must be networked; the client's distance value is ignored.
3. **Server validates the target** — Failure codes map to messages: invalid_network_id ("A networked target entity is required."), entity_unavailable, player_unavailable, routing_bucket_mismatch, too_far; anything else becomes "Target entity is unavailable.".
4. **Handler decides** — The handler receives `(src, entity, ...)` and makes the real decision with server data. It may return `false, reason` to refuse.

### Security notes

The distance is the server's: `opts.maxDistance`, or `Config.target.serverActionMaxDistance` (5.0), measured between the player's ped and the entity. The same routing bucket is required. There is no job, item or ownership check unless your handler adds one. The action name is not secret, so never rely on it for authorization.

### Entity is required in practice

Because resolveNetworkEntity rejects a nil network id, every call currently needs a valid networked entity; an action with nothing to distance-check will always return false with "A networked target entity is required.". The shipped docs describe the entity as optional; the code does not allow it.

### Callable handlers

The registration asserts `type(handler) == 'function'`. FXServer exposes callbacks received across exports as callable tables, so registering from another resource may be rejected by that assertion. Register from inside a function you control and test on your server before depending on it.

### Functions

One export, `registerServerAction`. Anything else (job, gang, item, cooldown, ownership checks) is the handler's responsibility.

#### `exports.kora_target:registerServerAction(name, handler, opts?)`

Registers a named server-side handler that clients can run with runServerAction. Before the handler runs, the server resolves the client-supplied network id with Kora.world.resolveNetworkEntity, checking existence, same routing bucket and the action's maximum distance from the player's ped. Re-registering a name overwrites it and prints a warning. Actions registered by a resource are removed when that resource stops.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Non-empty action name. Otherwise raises "registerServerAction requires a name.". |
| `handler` | function | Called as handler(src, entity, ...) inside pcall. src is the calling player, entity the resolved server entity handle, followed by the client's extra arguments. Return values are relayed to the client after `true`. Raises "registerServerAction requires a handler function." when the value is not a function. |
| `opts?` | table | Optional `{ maxDistance? }`. maxDistance must be greater than 0 and not above `Config.target.serverActionMaxDistance` (5.0), otherwise registration asserts. Defaults to the cap. |

**Returns**

- **No return value. Raises assertions on invalid input.**

**Example**

```lua
-- server
exports.kora_target:registerServerAction('shop:openStock', function(src, ped, shopName)
    if not DoesEntityExist(ped) then return false, 'Shop keeper missing.' end
    if shopName ~= 'ammunation' then return false, 'Unknown shop.' end
    -- server-side rules: licence, cooldown, job...
    return true, GetStockIdFor(shopName)
end, { maxDistance = 3.0 })
```

**Representative console output**

```text
No output. A client calling runServerAction('shop:openStock', ped, 3.0, 'ammunation') within 3 m receives true, <stock id>.
```

### Limits and related APIs

maxDistance must be greater than 0 and no more than Config.target.serverActionMaxDistance. Handler errors are printed as `[kora_target] server action '<name>' errored: ...` and the client receives `false, 'Server action errored.'`.

## Additional notes from the code

### Registration ids and ownership-scoped removal

Registration ids are integers. They start at 1 each time kora_target starts and are unique across all registration kinds. Because ids restart, an id kept across a kora_target restart can name someone else's registration, which is why removal by id checks the kind and the owner (`Config.target.ownerScopedRemoval`, default true). Remove calls without an id (for example `removeModel(model)`) are not owner-scoped and remove every matching registration. See [Option format](../options.md) for the option table and [Configuration](../configuration.md) for every `Config.target` key.

### Entity registrations and streaming

Networked entities passed to `addEntity` are also indexed by network id, so their options survive the entity streaming out and back in under a new handle. Local (non-networked) entities are tracked by handle only: remove them before deleting the entity. `removeEntity(entity)` without an id removes every registration that covers the entity, by handle or network id, and a registration made for several entities at once is removed entirely.

### Zone option fields

`addBoxZone`, `addSphereZone` and `addPolyZone` take a single table. The box takes `coords`, `size` (full extents) and `rotation` (degrees around Z); the sphere takes `coords` and a positive `radius`; the polygon takes `points` (at least three entries with x, y, z), optional `thickness`, `minZ`, `maxZ` and `spriteCoords` (sprite anchor, defaults to the average of the points). All three also accept `options`, `distance`, `debug`, `drawSprite` and `allowInVehicle`. If a polygon omits `minZ`/`maxZ`, kora_lib derives the vertical band from `thickness` and its own defaults. `coords` and `size` accept a vector3 or a table with `x`/`y`/`z`.

### runServerAction return values

`runServerAction` returns:

- `nil`: the callback itself failed (timeout or handshake). Check kora_lib's console output.
- `false, reason`: the action name is unknown, entity validation failed, or the handler raised an error. The reason strings are `A networked target entity is required.`, `Target entity no longer exists.`, `Player entity unavailable.`, `Target is in another routing bucket.`, `Too far from target.`, `Target entity is unavailable.`, `Server action errored.` and `Unknown kora_target server action: name`.
- `true, ...`: the handler ran. Its own return values follow `true`, including a handler that returns `false, reason`.

### Development-only exports

When the replicated convar `fft_kora_hooks` is `true`, `fft_hooks.lua` adds the client exports `fftVersion` and `fftAction`. `fftAction` only accepts calls from a resource named `fft`. These exist for automated test runs and are not a public API.
