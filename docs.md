# qbtarget

A crosshair/zone-based targeting engine built on `qblib` (`QB.raycast` for aim resolution, `QB.zones` for area-based targets, `QB.world`/`QB.drawing` as the underlying pool-query/prompt-rendering primitives, `QB.nui` for the multi-option select menu, `QB.callback` for the optional server-action relay). One resource, no separate proxy resources: it declares `provide 'qb-target'` and `provide 'ox_target'` in its `fxmanifest.lua` and registers the real, public qb-target/ox_target export names directly (`client/compat/qb-target.lua`, `client/compat/ox-target.lua`), so scripts written against `exports['qb-target']:...` or `exports.ox_target:...` keep working unmodified against this same running resource — see those two files for the exact mapping onto qbtarget's own API, and `AGENTS.md`'s "Compatibility mechanism" section for how `provide` + manual export registration actually makes that resolve.

## Usage
Hold `Config.target.keybind` (default `LMENU`, i.e. left Alt) to enter targeting mode. While held, aiming at a registered entity/model/global-type/global-bone, or standing inside a registered zone, shows a world-space prompt. Press `Config.target.selectKeybind` (default `E`) to run the sole option, or open a select menu when more than one is available.

## API
All functions are plain FiveM exports on `qbtarget` — `exports.qbtarget:<name>(...)`. The same targets are also reachable through `exports['qb-target']:...` (PascalCase, qb-target's real function names) and `exports.ox_target:...` (camelCase, ox_target's real function names) — both are compatibility layers over this same API, not separate implementations.

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

### `addBoxZone({coords, size, rotation?, options, distance?, debug?})`
### `addSphereZone({coords, radius, options, distance?, debug?})`
### `addPolyZone({points, thickness?, minZ?, maxZ?, options, distance?, debug?})`
Zone-based targets, backed by `QB.zones.box/sphere/poly` — no aiming required, just standing inside. Returns the registration `id`.

### `removeZone(id)`
Removes a zone-based registration.

### `setEnabled(enabled)`
Globally enables/disables the whole targeting loop.

### `getState()`
Returns `{ enabled: boolean, hovering: table|nil }`. `hovering` mirrors whatever the tick loop last resolved (`{ kind, id, entity?, zoneId?, optionCount }`), or `nil` when nothing is currently targeted.

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
An option may also carry `item`, `job`, `gang`, or `groups` fields (accepted so ported `qb-target`/`ox_target` scripts don't error), but **qbtarget never interprets them** — there is no framework installed in this repo to check a player's job/gang/inventory against. A ported script that relied on qb-target/ox_target auto-filtering these will show its option to everyone until the consumer supplies its own `canInteract` doing that check itself. This is the one behavior gap worth knowing about before relying on a ported script's restrictions.

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
