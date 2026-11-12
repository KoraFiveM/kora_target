---
title: "Compatibility"
sidebar_position: 3
---


# Compatibility

Scripts written for ox_target or qb-target keep working without edits. Each export below is registered under its original name and converted onto the native kora_target engine. Open a group to see what every call becomes.

Namespace: `exports.ox_target · exports['qb-target']` · Source: `client/compat/ox-target.lua, client/compat/qb-target.lua`

## ox_target (`exports.ox_target:`)

### Entities and models

| Legacy call | Becomes |
| --- | --- |
| `addLocalEntity(entities, options)` | ``addEntity` on local entity handles` |
| `addEntity(netIds, options)` | ``addEntity`, each network id resolved to its entity first` |
| `addModel(models, options)` | ``addModel`` |

### Global types

| Legacy call | Becomes |
| --- | --- |
| `addGlobalPlayer(options)` | ``addGlobalType('player')`` |
| `addGlobalPed(options)` | ``addGlobalType('ped')`` |
| `addGlobalVehicle(options)` | ``addGlobalType('vehicle')`` |
| `addGlobalObject(options)` | ``addGlobalType('object')`` |
| `addGlobalOption(options)` | `All four global types in one call; returns a group id` |

### Zones

| Legacy call | Becomes |
| --- | --- |
| `addBoxZone(zoneOpts)` | ``addBoxZone`; a `name` can later be passed to `removeZone`` |
| `addSphereZone(zoneOpts)` | ``addSphereZone`; named zones supported` |
| `addPolyZone(zoneOpts)` | ``addPolyZone`; `minZ` / `maxZ` are not forwarded` |

### Removal

| Legacy call | Becomes |
| --- | --- |
| `removeLocalEntity(entities, names?)` | ``removeEntity`, or only the named options` |
| `removeEntity(netIds)` | ``removeEntity` after resolving the network ids` |
| `removeModel(models, names?)` | ``removeModel`, or only the named options` |
| `removeGlobalPlayer(names)` | ``removeGlobalType('player')`, or only the named options` |
| `removeGlobalPed(names)` | ``removeGlobalType('ped')`, or only the named options` |
| `removeGlobalVehicle(names)` | ``removeGlobalType('vehicle')`, or only the named options` |
| `removeGlobalObject(names)` | ``removeGlobalType('object')`, or only the named options` |
| `removeGlobalOption(groupId)` | `Removes the group from all four global types, or only the named options` |
| `removeZone(id)` | ``removeZone`; accepts the zone id or its name` |

### Targeting state

| Legacy call | Becomes |
| --- | --- |
| `disableTargeting(state)` | ``setEnabled(not state)`` |
| `getState()` | ``getState`; returns kora_target's own state table` |
| `isActive()` | `Whether a targeting session is running (`getState().active`)` |

## qb-target (`exports['qb-target']:`)

### Zones

| Legacy call | Becomes |
| --- | --- |
| `AddBoxZone(name, coords, length, width, boxOpts, targetOptions)` | `Name-keyed box: native box with `minZ` / `maxZ`, otherwise a 2D footprint` |
| `AddCircleZone(name, coords, radius, boxOpts, targetOptions)` | `Name-keyed circle: native sphere with `useZ`, otherwise a vertical cylinder` |
| `AddPolyZone(name, points, boxOpts, targetOptions)` | `Name-keyed polygon, `minZ` / `maxZ` optional` |
| `AddComboZone(zones, options, targetOptions)` | `One zone per sub-zone, all sharing the same options` |
| `AddEntityZone(name, entity, boxOpts, targetOptions)` | `Box that follows the entity, sized from its model` |
| `RemoveZone(name)` | `Destroys the zone by name, including every sub-zone of a combo zone` |
| `GetZoneData(name)` | `Returns the zone object` |
| `UpdateZoneData(name, data)` | `Replaces the zone's options and distance` |

### Targets

| Legacy call | Becomes |
| --- | --- |
| `AddTargetEntity(entity, targetOptions)` | ``addEntity`; options merge by label` |
| `AddTargetModel(models, targetOptions)` | ``addModel`; options merge by label` |
| `AddTargetBone(bones, targetOptions)` | ``addGlobalBone`` |
| `AddGlobalType(entityType, targetOptions)` | ``addGlobalType`; accepts 1 / 2 / 3 or ped / vehicle / object` |
| `AddGlobalPed(targetOptions)` | ``addGlobalType('ped')`` |
| `AddGlobalVehicle(targetOptions)` | ``addGlobalType('vehicle')`` |
| `AddGlobalObject(targetOptions)` | ``addGlobalType('object')`` |
| `AddGlobalPlayer(targetOptions)` | ``addGlobalType('player')`` |

### Removal by label

| Legacy call | Becomes |
| --- | --- |
| `RemoveTargetEntity(entities, labels?)` | `Removes the labelled options, or the whole entity entry` |
| `RemoveTargetModel(models, labels?)` | `Removes the labelled options, or the whole model entry` |
| `RemoveTargetBone(bones, labels?)` | `Removes the labelled options, or the whole bone entry` |
| `RemoveGlobalType(entityType, labels?)` | `Removes the labelled options, or the whole type entry` |
| `RemoveGlobalPed(labels?)` | `Same as `RemoveGlobalType` for ped` |
| `RemoveGlobalVehicle(labels?)` | `Same as `RemoveGlobalType` for vehicle` |
| `RemoveGlobalObject(labels?)` | `Same as `RemoveGlobalType` for object` |
| `RemoveGlobalPlayer(labels?)` | `Same as `RemoveGlobalType` for player` |

### Read stored options

| Legacy call | Becomes |
| --- | --- |
| `GetTargetEntityData(entity, label)` | `Returns the stored legacy option for that label` |
| `GetTargetModelData(model, label)` | `Returns the stored legacy option for that label` |
| `GetTargetBoneData(bone, label)` | `Returns the stored legacy option for that label` |
| `GetGlobalTypeData(entityType, label)` | `Returns the stored legacy option for that label` |
| `GetGlobalPedData(label)` | `Same as `GetGlobalTypeData` for ped` |
| `GetGlobalVehicleData(label)` | `Same as `GetGlobalTypeData` for vehicle` |
| `GetGlobalObjectData(label)` | `Same as `GetGlobalTypeData` for object` |
| `GetGlobalPlayerData(label)` | `Same as `GetGlobalTypeData` for player` |

### Update stored options

| Legacy call | Becomes |
| --- | --- |
| `UpdateTargetEntityData(entity, label, data)` | `Replaces or adds the option and refreshes the live registration` |
| `UpdateTargetModelData(model, label, data)` | `Replaces or adds the option and refreshes the live registration` |
| `UpdateTargetBoneData(bone, label, data)` | `Replaces or adds the option and refreshes the live registration` |
| `UpdateGlobalTypeData(entityType, label, data)` | `Replaces or adds the option and refreshes the live registration` |
| `UpdateGlobalPedData(label, data)` | `Same as `UpdateGlobalTypeData` for ped` |
| `UpdateGlobalVehicleData(label, data)` | `Same as `UpdateGlobalTypeData` for vehicle` |
| `UpdateGlobalObjectData(label, data)` | `Same as `UpdateGlobalTypeData` for object` |
| `UpdateGlobalPlayerData(label, data)` | `Same as `UpdateGlobalTypeData` for player` |

### Ped spawning

| Legacy call | Becomes |
| --- | --- |
| `SpawnPed(data)` | `Spawns local peds (on player load, or at once with `spawnNow`) and registers their target` |
| `RemoveSpawnedPed(peds)` | `Deletes the spawned peds and their targets` |
| `DeletePeds()` | `Deletes every ped spawned through `SpawnPed`` |
| `GetPeds()` | `Returns the registered ped configs` |
| `UpdatePedsData(index, data)` | `Overwrites the stored ped config at that index` |

### Targeting state and helpers

| Legacy call | Becomes |
| --- | --- |
| `AllowTargeting(state)` | ``setEnabled(state)`; also cancels the current session when false` |
| `DisableTarget(state)` | `Cancels the current session without changing the gate` |
| `IsTargetActive()` | `Whether a targeting session is running` |
| `IsTargetSuccess()` | `Whether at least one option is currently available` |
| `RaycastCamera(flag?, playerCoords?)` | `Camera raycast returning coords, distance, entity and entity type` |
| `CheckEntity(flag, datatable, entity, distance)` | `True when `datatable` is a non-empty table` |
| `CheckBones(coords, entity, bones)` | `Closest registered bone to the point` |
| `EnableNUI(options)` | `Grants legacy NUI focus and sends the `validTarget` message` |
| `DisableNUI()` | `Releases legacy NUI focus` |
| `LeftTarget()` | `Drops legacy NUI focus and clears the hover state` |
| `DrawOutlineEntity(entity, enabled)` | `Entity outline; needs `Config.target.legacyOutline.enabled`, never outlines peds` |

## Related guides

- [Native API](./target-api.md)

## Behaviour details from the code

kora_target registers the public qb-target and ox_target client exports under those resource names, using kora_lib's `Kora.compat.provideExport`. Scripts that call `exports['qb-target']:...` or `exports.ox_target:...` therefore run against kora_target without changes. Both layers translate their calls into the native engine, so all three APIs share the same resolver, prompt, menu, gates and recovery.

- The manifest declares `provide 'qb-target'`, which satisfies `dependency 'qb-target'` in other resources.
- `ox_target` is **not** provided. `exports.ox_target:*` works without anything else. Resources that declare `dependency 'ox_target'` or check `GetResourceState('ox_target')` need the [placeholder resource](#placeholder-resource).
- Native-only option fields such as `allowInVehicle` are not read by either compatibility layer.

### qb-target

#### targetOptions and option fields

`targetOptions` is `{ options = { ... }, distance = number }`.

- When `distance` is omitted, the registration uses `Config.target.legacyMaxDistance` (7.0).
- An option without its own `distance`, or with a larger one than the registration, is set to the registration distance.
- Options are keyed by `label`. Adding an option with an existing label on the same target replaces the earlier one, as upstream does.
- Options are ordered by `num` when it is present, otherwise by label.

| Field | Behaviour |
| --- | --- |
| `label`, `icon` | Shown in the prompt and selector. |
| `num` | Sort order. |
| `action` | When callable, it is called as `action(entity)` and no event is fired. |
| `event` with `type` | Used when there is no `action`. The type selects the dispatch: `'client'` (the default) runs `TriggerEvent(event, data)`. `'server'` runs `TriggerServerEvent(event, data)`. `'command'` runs `ExecuteCommand(event)`. `'qbcommand'` runs `TriggerServerEvent('QBCore:CallCommand', event, data)`. `data` is a copy of the option plus `entity` and, when the entity still exists, `coords`. If there is neither `action` nor `event`, an error is raised and printed. |
| `canInteract` | Called as `canInteract(entity, distance, data)`. Any falsy result hides the option. |
| `job`, `excludejob` | String, `'all'`, or a table of `{ jobName = minGrade }`. |
| `jobType`, `excludejobType` | String, `'all'`, or a table keyed by job type. |
| `gang`, `excludegang` | Same forms as `job`. |
| `citizenid` | A string, or a table keyed by citizen id. |
| `item`, `required_item` | Requires `exports.kora_inventory:HasItem(item)` to return true. `required_item` is copied to `item`. |
| `bones`, `distance` | Passed to the native option. |

The filters read player data from kora_core (`exports.kora_core:toLegacyPlayerData(exports.kora_core:getPlayerData())`). The data is refreshed on `QBCore:Client:OnPlayerLoaded` and updated on `QBCore:Client:OnPlayerUpdated`. All filters must pass before the option's own `canInteract` runs. If kora_core is not available when an option with a filter is registered, a warning is printed and the filters are skipped, so the option is shown to everyone unless its own `canInteract` hides it.

#### Zones

`boxOpts` fields:

- `heading`
- `minZ`, `maxZ`
- `debugPoly`
- `scale`, `offset` (3 or 6 values, PolyZone order)
- `useZ` (circle and entity zones)
- `drawSprite`

How each export builds its zone:

- `AddBoxZone`: with `minZ` and `maxZ` and no `scale`/`offset`, it becomes a native box zone. Otherwise it uses an exact 2D (or scaled/offset) box test, as PolyZone does.
- `AddCircleZone`: with `useZ = true` it becomes a native sphere zone. Otherwise it is an infinite vertical cylinder.
- `AddPolyZone`: accepts vec2 or vec3 points. A missing `minZ`/`maxZ` gives an effectively unbounded height band.
- `AddEntityZone`: a box around the entity's model dimensions that follows the entity as it moves. It is only evaluated when the raycast hits that entity.
- `AddComboZone(zones, options, targetOptions)`: `options.name` is required. Each entry in `zones` must expose a callable `isPointInside` or `contains` field.

Zone calls return a zone object that contains these fields:

- `name`, `kind`, `ids`, `targetoptions`
- `isPointInside(point)`, `contains(point)`, `destroy()`
- shape data (`center`, `length`, `width`, `radius`, `points`, ...)

`GetZoneData(name)` returns the same object. Adding a zone with an existing name replaces the earlier zone.

When PolyZone's `BoxZone`, `CircleZone`, `PolyZone`, `ComboZone` or `EntityZone` classes exist as globals in kora_target's own Lua environment, the real PolyZone objects are created and returned instead. kora_target's manifest does not load PolyZone, so the standalone kora_lib-backed path above is what normally runs. PolyZone is not required.

#### State helpers

- `AllowTargeting(false)` disables targeting persistently (the same as `setEnabled(false)`). `AllowTargeting(true)` enables it again.
- `DisableTarget(true)` cancels the current session only. The next key press starts a new session.
- `IsTargetActive()` and `IsTargetSuccess()` return the native `active` and `success` flags.
- `RaycastCamera(flag, playerCoords)` raycasts 16 m from the camera and returns `coords, distance, entity, entityType`. Without a hit, `coords` is a zero vector.
- `EnableNUI`, `DisableNUI` and `LeftTarget` handle NUI focus and send upstream's NUI messages (`validTarget`, `leftTarget`, `closeTarget`). kora_target ships no page that renders them. Any focus they leave behind is released by stuck-target recovery.
- `DrawOutlineEntity(entity, enabled)` outlines non-ped entities only when `Config.target.legacyOutline.enabled` is true.
- `CheckEntity` returns true when `datatable` is a non-empty table.
- `CheckBones(coords, entity, bones)` returns the closest registered bone's `index, position, name`, or `false`.

#### SpawnPed

`SpawnPed(data)` accepts one ped config or an array of configs. Each config has these fields:

- `model`, `coords` (with optional `w` heading)
- `minusOne`
- `freeze`, `invincible`, `blockevents`
- `animDict` with `anim` and `flag`
- `scenario`
- `pedrelations` (`groupname`, `toplayer`, `toowngroup`)
- `weapon` (`name`, `ammo`, `hidden`)
- `target` (`targetOptions` plus `useModel`)
- `action` (called with the config after spawning)
- `spawnNow`

Spawning rules:

- Peds are always created as local (non-networked) peds.
- Configs without `spawnNow` are stored. They are spawned on `QBCore:Client:OnPlayerLoaded`, or when kora_target starts if `LocalPlayer.state.isLoggedIn` is set.
- `QBCore:Client:OnPlayerUnload` deletes spawned peds. They respawn on the next load.
- Models and animation dictionaries load through kora_lib's bounded `Kora.stream` helpers. A failure raises an error and rolls back the partly created ped.
- A ped and its target registration are removed when the resource that spawned it stops.

### ox_target

#### Option fields

`options` may be an array or a single option table. Supported fields:

- `name`, `label` (defaults to `name`, then `'Interact'`), `icon`, `iconColor`
- `distance`, `bones` (string or array)
- `canInteract`, `onSelect`, `export`, `event`, `serverEvent`, `command`, `action`
- `groups`, `items`, `anyItem`
- `offset`, `offsetSize`, `absoluteOffset` (alias `offsetAbsolute`)
- `menuName`, `openMenu`, `resource`

`canInteract` is called as `canInteract(entity, distance, coords, name, bone)`. `entity` is `0` for world hits, and `bone` is always `nil`. Before it runs, these checks are applied in upstream order:

1. The current sub-menu must match `menuName`.
2. `groups`: a string, an array, or `{ name = minGrade }`. Checked against kora_core job and gang name and grade. If kora_core is not running, the check passes and a warning is printed when the option is registered. Disable with the convar `kora_target:oxGroups 0`.
3. `items`: a string, an array (all required, or any with `anyItem = true`), or `{ name = count }`. Checked through `exports.kora_inventory:HasItem(name, count)`. Results are cached for about 300 ms and cleared on `qb-inventory:client:updateInventory` / `inventory:client:updateInventory`. Without kora_inventory the check passes and a warning is printed once.
4. `offset`: the aim point must be within `offsetSize` (default 1.0) of the offset point on the entity. The offset is a fraction of the model size unless `absoluteOffset` is set. This check is ignored for zones.

On selection, the first available handler runs:

1. `onSelect(response)`
2. `action(entity)`
3. `exports[resource][export](nil, response)`, where `resource` defaults to the registering resource
4. `TriggerEvent(event, response)`
5. `TriggerServerEvent(serverEvent, response)`, where `response.entity` is a network id or `0`
6. `ExecuteCommand(command)`

`response` is the option without `icon`, `groups`, `items`, `canInteract`, `onSelect`, `export`, `event`, `serverEvent` and `command`. It adds `entity`, `coords`, `distance` and `zone`.

#### Sub-menus

An option with `openMenu = 'menuName'` switches the current menu before its handler runs. After that, only options with a matching `menuName` are shown, plus a **Go back** entry (`builtin:goback`, label from `Config.target.text.goBack`). The entry is added to every global type, and to zones that use menus. `openMenu = 'home'` returns to the top level. The chosen menu persists across key presses until go-back or home is chosen, or until `kora_target:oxMenuTimeoutMs` (default 15000 ms, `0` = never) passes.

### Placeholder resource

`stubs/ox_target` is a manifest-only resource named `ox_target` that contains no scripts or exports. Its only purpose is to make `GetResourceState('ox_target')` return `started` (for example for ox_inventory with `setr inventory:target true`). It also satisfies `dependency 'ox_target'`. Calls to `exports.ox_target:*` are still answered by kora_target.

```cfg
ensure kora_target
ensure [compat]/ox_target
ensure ox_inventory
```

Copy `stubs/ox_target` to `resources/[compat]/ox_target` before you ensure it. Never run it alongside the real ox_target, and do not add scripts to it. After restarting kora_target, restart the placeholder and its dependents too. See [stubs/ox_target/README.md](https://github.com/KoraFiveM/kora_target/blob/dev/stubs/ox_target/README.md).
