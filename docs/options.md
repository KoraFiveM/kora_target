---
title: Option format
sidebar_position: 6
---

# Option format

Every native registration export (`addEntity`, `addModel`, `addGlobalType`, `addGlobalBone`, `addTargetBone`, `addBoxZone`, `addSphereZone`, `addPolyZone`) takes `options`, a non-empty array of option tables. Options are validated when they are registered. An invalid option raises an error.

```lua
{
    label = 'Open trunk',          -- required, non-empty string
    onSelect = function(entity, data) end, -- required, callable
    name = 'open_trunk',           -- optional, used by Config.target.allowWhileDead
    icon = 'Car',                  -- optional, passed to kora_lib's interact selector
    distance = 2.0,                -- optional number, overrides the registration default
    bones = { 'boot' },            -- optional array of bone names
    canInteract = function(entity, distance, data, coords) return true end, -- optional, callable
    allowInVehicle = true,         -- optional boolean
    data = { foo = 'bar' },        -- optional, passed to canInteract and onSelect
}
```

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `label` | string | Yes | Text shown in the prompt and selector. |
| `onSelect` | function | Yes | Called as `onSelect(entity, data)` when the option is chosen. `entity` is the aimed entity, or `nil` for a zone hit on world geometry. Errors are caught and printed. |
| `name` | string | No | Identifier. Only read by `Config.target.allowWhileDead`. |
| `icon` | string | No | Icon name forwarded to kora_lib's interact selector. |
| `distance` | number | No | Maximum distance from the player to the aim point. The fallback order is option, then registration default, then `Config.target.defaultOptionDistance`. |
| `bones` | string array | No | Restricts the option to hits within `Config.target.boneTolerance` of one of these bones. Bone-scoped options never match zone candidates. |
| `canInteract` | function | No | Called as `canInteract(entity, distance, data, coords)`. `coords` is the raycast hit point. A return value of exactly `false`, or an error, hides the option. Errors are printed. Results may be cached (see `canInteractCacheMs`/`canInteractFailureCacheMs`). |
| `allowInVehicle` | boolean | No | `true` keeps the option usable while seated when `Config.target.disableInVehicle` is on. It overrides a zone-level `allowInVehicle`, including when set to `false`. |
| `data` | any | No | Passed through to `canInteract` and `onSelect`. |

Functions passed through an export boundary arrive as callable tables. kora_target accepts both plain functions and callable tables.

## Fields the native API does not interpret

The native API accepts `item`, `job`, `gang` and `groups` on an option, but never checks them. A native caller that needs job, gang or item checks must do them in its own `canInteract`. The qb-target and ox_target compatibility exports do enforce their own filter fields. See [Compatibility](./compatibility.md).

## Zone-level fields

Zone constructors accept these fields next to `options`:

| Field | Description |
| --- | --- |
| `distance` | Default distance for the zone's options. |
| `allowInVehicle` | Default `allowInVehicle` for options that do not set their own. |
| `debug` | `true` draws kora_lib's zone outline. `Config.target.debug` forces it for every zone. |
| `drawSprite` | `false` hides this zone's sprite. `true` shows it even when sprites are globally off, if `Config.target.sprites.allowPerZoneOverride` is on. |

## Examples

Bone-scoped vehicle option:

```lua
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

Option usable from a vehicle, inside a zone:

```lua
exports.kora_target:addBoxZone({
    coords = vector3(100.0, 200.0, 30.0),
    size = vector3(4.0, 4.0, 3.0),
    allowInVehicle = true, -- default for every option below
    options = {
        { label = 'Drive-thru order', onSelect = function() end },
        { label = 'Walk-up counter', allowInVehicle = false, onSelect = function() end },
    },
})
```
