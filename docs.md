# kora_target

A crosshair/zone-based targeting engine built on `kora_lib` (`Kora.raycast` for aim resolution, `Kora.zones` for area-based targets, `Kora.world`/`Kora.drawing` as the underlying pool-query/prompt-rendering primitives, `Kora.nui` for display-only HUD/picker messages, `Kora.callback` for the optional server-action relay). One resource, no separate proxy resources: it declares `provide 'qb-target'` in its `fxmanifest.lua` (it does not provide `ox_target`; the `stubs/ox_target` placeholder owns that name) and registers the real, public qb-target/ox_target export names directly (`client/compat/qb-target.lua`, `client/compat/ox-target.lua`), so scripts written against `exports['qb-target']:...` or `exports.ox_target:...` keep working unmodified against this same running resource. `exports.ox_target:*` works without the placeholder; resources that declare `dependency 'ox_target'` or check `GetResourceState('ox_target')` need `stubs/ox_target` ensured after kora_target — see those two files for the exact mapping onto kora_target's own API, and `AGENTS.md`'s "Compatibility mechanism" section for how `provide` + manual export registration actually makes that resolve.

`PolyZone` is not required by kora_target or the native kora_lib stack. The
qb-target compatibility exports return kora_lib-backed, zone-compatible objects
without it. Start the optional `PolyZone` wrapper only for a third-party
resource whose manifest imports `@PolyZone/...`; when present, its classes can
still be passed to `AddComboZone`.

## Usage
Hold `Config.target.keybind` (default `LMENU`, i.e. left Alt) to enter targeting mode. While held, aiming at a registered entity/model/global-type/global-bone/zone shows a world-space prompt fixed at screen centre (it never moves the mouse pointer or takes NUI focus). A zone match is decided by where the crosshair's raycast actually lands, not by whether the player is standing inside a zone -- you don't need to be inside a zone to target it, just aiming at a point within it. Release Alt to act: a sole available option runs immediately (its label is shown in the prompt while held); two or more options open kora_lib's pointer-free interact selector after Alt is released. Use scroll or Up/Down to choose, then E to select.

## Stuck-target recovery

Targeting never freezes or interrupts player movement by default: walking, sprinting, jumping and falling all keep working while Alt is held and while the option menu is open. The menu stays available while the player is within reach of one of its options and closes (`Config.target.closeMenuOutOfRange`, default `true`) once they leave it; this is a throttled check (`tickActive` ms) that runs only while the menu is open, and a chosen option is refused if its target is out of range at that moment (`rangeTolerance`, default 0.5 m, is added to each option's distance). Opt-in switches: `Config.target.menuMovement` (`'allow'` default via the unset legacy `freezeOnMenu = false`, `'close'` to close the menu when a movement key is pressed, `'freeze'` to hold the player still; a ped that is airborne or dead is never held) and `Config.target.closeWhenAirborne` (default `false`; `true` cancels targeting and closes the menu while the ped is jumping, falling, ragdolling, parachuting or climbing).

`Config.target.disableInVehicle` (default `true`) stops targeting while the player is seated in a vehicle, as driver or passenger, so ATMs, peds and other world interactions cannot be used from a car. The state comes from kora_lib's `cache.vehicle` (no polling): the key does nothing while seated, and an open eye or option menu closes as soon as the player gets in. Set it to `false` to allow targeting from inside vehicles.

Dead, last-stand and downed players (kora_core metadata `isdead`/`inlaststand`, or the native fatal-injury flag) cannot target or run options while `Config.target.disableWhileDead` is `true` (default). The state is re-read right before an option fires, and an open eye or menu closes when the player goes down. `Config.target.allowWhileDead` is a list of option `name`s that stay usable while down (default empty); `downedPollMs` (250) sets the read interval.

If the key-up event is lost (typically Alt+Tab while holding Alt), targeting or the option menu would stay on. `Config.target.recovery` (enabled by default) runs a watchdog while a session, the option menu or legacy NUI focus is active. It never runs an option when it cancels. Options:

- `cancelOnFocusLoss` (true): cancel when the game window loses focus (`IsGameWindowFocused`, plus blur events from `ui/focus.html` when `nuiListener` is true).
- `focusReleaseIgnoreMs` (1500): in hold mode a key-up this soon after a focus loss cancels instead of opening the menu or selecting. 0 disables.
- `altControlFallback` (true): in hold mode with the default `LMENU` key, key state is read from control 19 (INPUT_CHARACTER_WHEEL, Left Alt) instead of the unreliable `+target` command hash. The hold cancels after `releaseGraceMs` (250) of "up" once the key was seen down. Skipped if the key was rebound away from Alt.
- `menuIdleTimeoutMs` (30000): close the option menu after this long without select/scroll input. 0 disables.
- `cancelOnPause` (true): cancel when the pause menu opens.
- `cancelControls` (true): Escape, Backspace or right-click cancel without selecting (also reported from the NUI page when it has focus).
- `resetCommand` (`target-reset`; false/empty disables): force-clears targeting, the menu and any legacy NUI focus.

Orphaned legacy (qb-target compat) NUI focus is released one second after the session ends. Hold and toggle modes both keep working.

## Performance configuration
Targeting has no idle client thread while its key is up, and no targeting loop
at all once it is released. The first scan happens immediately on activation;
`tickAcquire` and `tickActive` both default to 50ms (20Hz) while targeting is
held over an entity or available option. A miss with no entity or zone option
uses `tickMiss` (100ms), reducing idle raycast work at the cost of a small,
intentional acquisition delay. The resolver is deliberately **not** a
per-frame loop. Rendering stays every frame in a separate lightweight loop.

Each real scan fires one broad world raycast. When it reports no entity, an
entity-focused fallback can still handle engine edge cases, but
`entityProbeInterval` limits that second shape test to once every 250ms. The
fallback may add one settle frame when it is needed. Both casts reuse the same
camera and player snapshot rather than repeating those native calls.

Zone matching runs each registered zone's own `contains(point)` test against
that tick's raycast hit, but only for zones that can possibly match. Two exact
filters run first -- the ped-to-aim-point distance against the largest interact
distance any zone option uses, then an AABB grid keyed on the aim point -- so
adding zones does not make holding the key more expensive. Stable box/poly
children of qb-target combo zones are indexed individually. Entity zones are
rejected before containment unless their own entity was hit. Shapes whose
extent can change or cannot safely be derived remain unbounded.

While the camera and the player ped are both completely motionless, a tick
reuses the previous scan instead of re-firing an identical ray.
`staticRefresh` (default 200ms) caps that delay over an entity or option;
`staticMissRefresh` allows an empty, motionless aim to reuse its miss for 500ms.
Any aim or player movement resolves on the next tick.

Successful `canInteract` results are uncached by default so dynamic foreign
callbacks remain fresh. Failed results use `canInteractFailureCacheMs` (250ms)
to avoid repeatedly invoking an unavailable option, then retry so an external
state change can surface it without requiring the player to aim away. Cache
entries use option identity rather than allocating formatted string keys. Set
`diagnostics = true` temporarily to print per-hold resolver metrics, including
how many ticks were skipped as static. The built-in global ped/vehicle demo is
disabled by default and should only be enabled for development.

## API
All functions are plain FiveM exports on `kora_target` — `exports.kora_target:<name>(...)`. The same targets are also reachable through `exports['qb-target']:...` (PascalCase, qb-target's real function names) and `exports.ox_target:...` (camelCase, ox_target's real function names) — both are compatibility layers over this same API, not separate implementations.

### qb-target drop-in compatibility

The `qb-target` identity exposes every export in current upstream, including
all zone/entity/model/bone/global add/remove calls, label-addressed getters and
updates, ped spawning, target/NUI state controls, raycast helpers, and outline/
bone checks. Legacy options retain `num` ordering, `required_item`, the exact
`action`/client/server/command/qbcommand dispatch payload, and
`canInteract(entity, distance, data)`. Job, job-type, gang, item, and citizen
filters are enforced through `qb-core`.

Zone calls return zone-compatible objects, `GetZoneData` returns that same
object, vec2 polygons are accepted, missing Z bounds remain 2D, combo calls
accept zone-compatible objects (including optional PolyZone instances), and
EntityZone bounds follow the entity. Entity/model/bone/global options merge
and can be read, replaced, or removed by label. `RaycastCamera` returns
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
Zone-based targets, backed by `Kora.zones.box/sphere/poly` — interact by aiming
at a point inside the zone; standing inside it is not required. Returns the
registration `id`.

`Config.target.debug = true` outlines every target zone through kora_lib, useful
when placing or diagnosing zones. A zone may also set `debug = true`
individually. `Config.target.sprites` draws a compact `shared/info` world
sprite at each coordinate-zone anchor so players can see interactable
locations before holding Alt; set `drawSprite = false` on one zone to hide its
icon. The sprite renderer is distance-culled and does not scan entities, so it
does not add work to the target raycast loop. It is **off by default**:
set `Config.target.sprites.enabled = true` (and tune `drawDistance`, default
20.0 m) to turn it on, or set `drawSprite = true` on single zones. The icon
is tinted with kora_theme's primary colour (`useThemeColour`, falling back to
`sprites.colour`), and is hidden while the target key is held
(`hideWhileTargeting`). Zones created by other resources (shops, etc.) get an
icon only if they are registered as coordinate zones. Entity/model/global targets do
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
An option registered through **this native API** may also carry `item`, `job`, `gang`, or `groups` fields (accepted so a script using them doesn't error), but **kora_target's own resolver never interprets them** — that's deliberate; a targeting engine has no business being coupled to a specific framework. A native caller relying on these must supply its own `canInteract` doing that check itself.

If you're porting a real `qb-target` script instead of writing against this native API directly, this doesn't apply to you: the **qb-target compat shim** (`exports['qb-target']:...`, see AGENTS.md's "Job/gang/item enforcement") enforces `job`/`excludejob`/`jobType`/`excludejobType`/`gang`/`excludegang`/`item`/`citizenid` against kora_core. The ox_target compat enforces `groups` (string, array or `{name = minGrade}`) against kora_core job and gang data (convar `kora_target:oxGroups 0` disables it) and enforces `items`/`anyItem` through `kora_inventory`'s `HasItem` export (results cached ~300 ms per item/count and dropped on inventory update events). It also honours `export`, `command`, `offset`/`offsetSize`/`absoluteOffset`, and `openMenu`/`menuName` sub-menus (a go-back entry is added, including on zones that use menus; the open menu resets after `kora_target:oxMenuTimeoutMs`, default 15000, 0 = never). `isActive` is true for the whole targeting session.

## Server actions
Neither real `qb-target` nor real `ox_target` validate actions server-side themselves — that has always been the consumer script's own job, and it still is here: an `onSelect` can fire its own `TriggerServerEvent`/`Kora.callback.trigger` exactly as before. `runServerAction`/`registerServerAction` are an **optional** convenience for a common case (an action needs to check the target is real and nearby, server-side) without hand-rolling that check every time:
```lua
-- server
exports.kora_target:registerServerAction('openTrunk', function(src, entity)
    -- entity is already distance-checked against src; TriggerEvent your own logic here
end)

-- client, inside an onSelect
local ok, result = exports.kora_target:runServerAction('openTrunk', entity, 3.0)
```
`entity` must be a **networked** entity (a real ped/vehicle/player) — entities from `Kora.entities.create` have no server-side twin to validate distance against.

## Example
```lua
exports.kora_target:addModel('prop_atm_01', {
    {
        label = 'Use ATM',
        icon = 'CreditCard',
        onSelect = function(entity)
            print('using ATM', entity)
        end,
    },
}, 1.5)

exports.kora_target:addBoxZone({
    coords = vector3(100.0, 200.0, 30.0),
    size = vector3(2.0, 2.0, 3.0),
    options = {
        { label = 'Open shop', onSelect = function() print('shop opened') end },
    },
})
```
