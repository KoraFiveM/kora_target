# qbtarget

A crosshair/zone-based targeting engine built on `qblib` (`QB.raycast` for aim resolution, `QB.zones` for area-based targets, `QB.world`/`QB.drawing` as the underlying pool-query/prompt-rendering primitives, `QB.nui` for display-only HUD/picker messages, `QB.callback` for the optional server-action relay). One resource, no separate proxy resources: it declares `provide 'qb-target'` and `provide 'ox_target'` in its `fxmanifest.lua` and registers the real, public qb-target/ox_target export names directly (`client/compat/qb-target.lua`, `client/compat/ox-target.lua`), so scripts written against `exports['qb-target']:...` or `exports.ox_target:...` keep working unmodified against this same running resource — see those two files for the exact mapping onto qbtarget's own API, and `AGENTS.md`'s "Compatibility mechanism" section for how `provide` + manual export registration actually makes that resolve.

`PolyZone` remains a dependency for the qb-target surface, just as it is
upstream. The manifest loads its classes so legacy zone exports return genuine
BoxZone/CircleZone/PolyZone/ComboZone/EntityZone objects and retain their full
public methods; qbtarget's native zone engine still resolves selection through
qblib.

## Usage
Hold `Config.target.keybind` (default `LMENU`, i.e. left Alt) to enter targeting mode. While held, aiming at a registered entity/model/global-type/global-bone/zone shows a world-space prompt fixed at screen centre (it never moves the mouse pointer or takes NUI focus). A zone match is decided by where the crosshair's raycast actually lands, not by whether the player is standing inside a zone -- you don't need to be inside a zone to target it, just aiming at a point within it. Release Alt to act: a sole available option runs immediately (its label is shown in the prompt while held); two or more options open qblib's focused menu after Alt is released, where the player can choose with mouse or keyboard.

## Performance configuration
Targeting has no idle client thread while its key is up. The first scan happens
immediately on activation; `tickAcquire` and `tickActive` both default to
50ms while targeting is held. Rendering remains every frame in a separate
lightweight loop, while the resolver uses broad and entity-focused raycasts to
avoid missing an entity behind a non-targetable world hit. There is no targeting
loop at all when the key is released. Zone matching is a plain per-tick scan of
each registered zone's own `contains(point)` test against that tick's raycast
hit -- no separate polling cadence to tune. `canInteractCacheMs` is disabled
by default so dynamic foreign `canInteract`
functions are always fresh; enable a small value only after profiling static
checks. Set `diagnostics = true` temporarily to print per-hold resolver
metrics. The built-in global ped/vehicle demo is disabled by default and should
only be enabled for development.

## API
All functions are plain FiveM exports on `qbtarget` — `exports.qbtarget:<name>(...)`. The same targets are also reachable through `exports['qb-target']:...` (PascalCase, qb-target's real function names) and `exports.ox_target:...` (camelCase, ox_target's real function names) — both are compatibility layers over this same API, not separate implementations.

### qb-target drop-in compatibility

The `qb-target` identity exposes every export in current upstream, including
all zone/entity/model/bone/global add/remove calls, label-addressed getters and
updates, ped spawning, target/NUI state controls, raycast helpers, and outline/
bone checks. Legacy options retain `num` ordering, `required_item`, the exact
`action`/client/server/command/qbcommand dispatch payload, and
`canInteract(entity, distance, data)`. Job, job-type, gang, item, and citizen
filters are enforced through `qb-core`.

Zone calls keep PolyZone behavior: they return zone-compatible objects,
`GetZoneData` returns that same object, vec2 polygons are accepted, missing Z
bounds remain 2D, combo calls accept live PolyZone objects, and EntityZone
bounds follow the entity. Entity/model/bone/global options merge and can be
read, replaced, or removed by label. `RaycastCamera` returns
`coords, distance, entity, entityType`; `DisableTarget(true)` cancels the
current session while `AllowTargeting(false)` changes the persistent gate.

### `addEntity(entity, options, defaultDistance?)` / `removeEntity(entity, id?)`
Targets one or more specific entity handles.
- `entity: number | number[]`
- Returns the registration `id` (integer).
- `removeEntity(entity, id?)`: with `id`, removes only that registration. Without it, removes **every** registration touching `entity` — including ones registered on multiple entities at once, which are torn down entirely, not just trimmed for this one entity.

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
Zone-based targets, backed by `QB.zones.box/sphere/poly` — interact by aiming
at a point inside the zone; standing inside it is not required. Returns the
registration `id`.

`Config.target.debug = true` outlines every target zone through qblib, useful
when placing or diagnosing zones. A zone may also set `debug = true`
individually. `Config.target.sprites` draws a compact `shared/info` world
sprite at each coordinate-zone anchor so players can see interactable
locations before holding Alt; set `drawSprite = false` on one zone to hide its
icon. The sprite renderer is distance-culled and does not scan entities, so it
does not add work to the target raycast loop. Entity/model/global targets do
not get static sprites because they do not have one fixed world location.

### `removeZone(id)`
Removes a zone-based registration.

### `setEnabled(enabled)`
Globally enables/disables the whole targeting loop.

### `getState()`
Returns `{ enabled: boolean, active: boolean, success: boolean, hovering: table|nil }`. `hovering` mirrors whatever the tick loop last resolved (`{ kind, id, entity?, zoneId?, optionCount }`), or `nil` when nothing is currently targeted.

### `runServerAction(name, entity?, maxDistance?, ...)` (client) / `registerServerAction(name, handler)` (server)
Optional server-action relay with distance revalidation — see "Server actions" below.

## Option shape
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

## Opaque `item`/`job`/`gang`/`groups` fields
An option registered through **this native API** may also carry `item`, `job`, `gang`, or `groups` fields (accepted so a script using them doesn't error), but **qbtarget's own resolver never interprets them** — that's deliberate; a targeting engine has no business being coupled to a specific framework. A native caller relying on these must supply its own `canInteract` doing that check itself.

If you're porting a real `qb-target` script instead of writing against this native API directly, this doesn't apply to you: the **qb-target compat shim** (`exports['qb-target']:...`, see AGENTS.md's "Job/gang/item enforcement") enforces `job`/`excludejob`/`jobType`/`excludejobType`/`gang`/`excludegang`/`item`/`citizenid` against qbcore. The ox_target compat does not interpret ox_core groups.

## Server actions
Neither real `qb-target` nor real `ox_target` validate actions server-side themselves — that has always been the consumer script's own job, and it still is here: an `onSelect` can fire its own `TriggerServerEvent`/`QB.callback.trigger` exactly as before. `runServerAction`/`registerServerAction` are an **optional** convenience for a common case (an action needs to check the target is real and nearby, server-side) without hand-rolling that check every time:
```lua
-- server
exports.qbtarget:registerServerAction('openTrunk', function(src, entity)
    -- entity is already distance-checked against src; TriggerEvent your own logic here
end)

-- client, inside an onSelect
local ok, result = exports.qbtarget:runServerAction('openTrunk', entity, 3.0)
```
`entity` must be a **networked** entity (a real ped/vehicle/player) — entities from `QB.entities.create` have no server-side twin to validate distance against.

## Example
```lua
exports.qbtarget:addModel('prop_atm_01', {
    {
        label = 'Use ATM',
        icon = 'CreditCard',
        onSelect = function(entity)
            print('using ATM', entity)
        end,
    },
}, 1.5)

exports.qbtarget:addBoxZone({
    coords = vector3(100.0, 200.0, 30.0),
    size = vector3(2.0, 2.0, 3.0),
    options = {
        { label = 'Open shop', onSelect = function() print('shop opened') end },
    },
})
```
