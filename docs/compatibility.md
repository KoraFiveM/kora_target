---
title: Compatibility
sidebar_position: 7
---

# qb-target and ox_target compatibility

kora_target registers the public qb-target and ox_target client exports under those resource names, using kora_lib's `Kora.compat.provideExport`. Scripts that call `exports['qb-target']:...` or `exports.ox_target:...` therefore run against kora_target without changes. Both layers translate their calls into the native engine, so all three APIs share the same resolver, prompt, menu, gates and recovery.

- The manifest declares `provide 'qb-target'`, which satisfies `dependency 'qb-target'` in other resources.
- `ox_target` is **not** provided. `exports.ox_target:*` works without anything else. Resources that declare `dependency 'ox_target'` or check `GetResourceState('ox_target')` need the [placeholder resource](#the-ox_target-placeholder).
- Native-only option fields such as `allowInVehicle` are not read by either compatibility layer.

## qb-target

### Exports

| Group | Exports |
| --- | --- |
| Zones | `AddBoxZone(name, coords, length, width, boxOpts, targetOptions)`, `AddCircleZone(name, coords, radius, boxOpts, targetOptions)`, `AddPolyZone(name, points, boxOpts, targetOptions)`, `AddComboZone(zones, options, targetOptions)`, `AddEntityZone(name, entity, boxOpts, targetOptions)`, `RemoveZone(name)`, `GetZoneData(name)`, `UpdateZoneData(name, data)` |
| Entities and models | `AddTargetEntity(entity, targetOptions)`, `AddTargetModel(models, targetOptions)`, `RemoveTargetEntity(entities, labels)`, `RemoveTargetModel(models, labels)`, `GetTargetEntityData(entity, label)`, `GetTargetModelData(model, label)`, `UpdateTargetEntityData(entity, label, data)`, `UpdateTargetModelData(model, label, data)` |
| Bones | `AddTargetBone(bones, targetOptions)`, `RemoveTargetBone(bones, labels)`, `GetTargetBoneData(bone, label)`, `UpdateTargetBoneData(bone, label, data)` |
| Global types | `AddGlobalType(type, targetOptions)`, `AddGlobalPed`, `AddGlobalVehicle`, `AddGlobalObject`, `AddGlobalPlayer` (each `(targetOptions)`), `RemoveGlobalType(type, labels)`, `RemoveGlobalPed`, `RemoveGlobalVehicle`, `RemoveGlobalObject`, `RemoveGlobalPlayer` (each `(labels)`), `GetGlobalTypeData(type, label)`, `GetGlobalPedData`, `GetGlobalVehicleData`, `GetGlobalObjectData`, `GetGlobalPlayerData` (each `(label)`), `UpdateGlobalTypeData(type, label, data)`, `UpdateGlobalPedData`, `UpdateGlobalVehicleData`, `UpdateGlobalObjectData`, `UpdateGlobalPlayerData` (each `(label, data)`) |
| Peds | `SpawnPed(data)`, `RemoveSpawnedPed(peds)`, `DeletePeds()`, `GetPeds()`, `UpdatePedsData(index, data)` |
| State and helpers | `AllowTargeting(state)`, `DisableTarget(state)`, `IsTargetActive()`, `IsTargetSuccess()`, `RaycastCamera(flag, playerCoords)`, `EnableNUI(options)`, `DisableNUI()`, `LeftTarget()`, `DrawOutlineEntity(entity, enabled)`, `CheckEntity(flag, datatable, entity, distance)`, `CheckBones(coords, entity, bones)` |

`AddGlobalType` and the related type exports accept `1`, `2`, `3`, `'ped'`, `'vehicle'` or `'object'`.

### targetOptions and option fields

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

### Zones

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

### State helpers

- `AllowTargeting(false)` disables targeting persistently (the same as `setEnabled(false)`). `AllowTargeting(true)` enables it again.
- `DisableTarget(true)` cancels the current session only. The next key press starts a new session.
- `IsTargetActive()` and `IsTargetSuccess()` return the native `active` and `success` flags.
- `RaycastCamera(flag, playerCoords)` raycasts 16 m from the camera and returns `coords, distance, entity, entityType`. Without a hit, `coords` is a zero vector.
- `EnableNUI`, `DisableNUI` and `LeftTarget` handle NUI focus and send upstream's NUI messages (`validTarget`, `leftTarget`, `closeTarget`). kora_target ships no page that renders them. Any focus they leave behind is released by stuck-target recovery.
- `DrawOutlineEntity(entity, enabled)` outlines non-ped entities only when `Config.target.legacyOutline.enabled` is true.
- `CheckEntity` returns true when `datatable` is a non-empty table.
- `CheckBones(coords, entity, bones)` returns the closest registered bone's `index, position, name`, or `false`.

### SpawnPed

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

## ox_target

### Exports

| Export | Notes |
| --- | --- |
| `addLocalEntity(entities, options)` | Local entity handles. |
| `addEntity(netIds, options)` | Network ids. Options apply when the entity streams in, and survive re-streaming. |
| `addModel(models, options)` | |
| `addGlobalPed`, `addGlobalVehicle`, `addGlobalObject`, `addGlobalPlayer` | `(options)` |
| `addGlobalOption(options)` | Registers on peds, vehicles, objects and players. Returns a group id. |
| `addBoxZone(data)` | `coords`, `size` (default `vec3(2, 2, 2)`), `rotation`, `name`, `debug`, `drawSprite`, `options`. Returns the zone id. |
| `addSphereZone(data)` | `coords`, `radius`, `name`, `debug`, `drawSprite`, `options`. |
| `addPolyZone(data)` | `points` (vec3), `thickness`, `name`, `debug`, `drawSprite`, `options`. |
| `removeZone(idOrName)` | By id or by `name`. |
| `removeLocalEntity(entities, names)` | Without `names`, removes every registration on the entities. With a name or array of names, removes only those options from ox_target registrations. |
| `removeEntity(netIds)` | Removes registrations indexed under the network ids. |
| `removeModel(models, names)` | Same `names` rule as `removeLocalEntity`. |
| `removeGlobalPed`, `removeGlobalVehicle`, `removeGlobalObject`, `removeGlobalPlayer` | `(names)`. Removes the named options from ox_target global registrations. |
| `removeGlobalOption(groupIdOrNames)` | A group id from `addGlobalOption`, or option names. |
| `disableTargeting(state)` | `true` disables targeting, `false` enables it. |
| `getState()` | Returns the native `getState()` table, not ox_target's shape. |
| `isActive()` | True for the whole targeting session. |

### Option fields

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

### Sub-menus

An option with `openMenu = 'menuName'` switches the current menu before its handler runs. After that, only options with a matching `menuName` are shown, plus a **Go back** entry (`builtin:goback`, label from `Config.target.text.goBack`). The entry is added to every global type, and to zones that use menus. `openMenu = 'home'` returns to the top level. The chosen menu persists across key presses until go-back or home is chosen, or until `kora_target:oxMenuTimeoutMs` (default 15000 ms, `0` = never) passes.

## The ox_target placeholder

`stubs/ox_target` is a manifest-only resource named `ox_target` that contains no scripts or exports. Its only purpose is to make `GetResourceState('ox_target')` return `started` (for example for ox_inventory with `setr inventory:target true`). It also satisfies `dependency 'ox_target'`. Calls to `exports.ox_target:*` are still answered by kora_target.

```cfg
ensure kora_target
ensure [compat]/ox_target
ensure ox_inventory
```

Copy `stubs/ox_target` to `resources/[compat]/ox_target` before you ensure it. Never run it alongside the real ox_target, and do not add scripts to it. After restarting kora_target, restart the placeholder and its dependents too. See [stubs/ox_target/README.md](https://github.com/KoraFiveM/kora_target/blob/dev/stubs/ox_target/README.md).
