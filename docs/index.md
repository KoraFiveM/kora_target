---
title: kora_target
sidebar_position: 1
---

# kora_target

kora_target is a crosshair and zone-based targeting and interaction engine for FiveM, built on [kora_lib](https://github.com/KoraFiveM/kora_lib). Players hold a key (Left Alt by default), aim at an entity, model, bone or coordinate zone that another resource registered, and release the key to run an option or pick one from a short list. It is a single resource that also answers `exports['qb-target']:...` and `exports.ox_target:...` calls, so scripts written for qb-target or ox_target keep working without separate proxy resources.

## Features

- **Hold or toggle targeting.** The key (default `LMENU`) starts a targeting session. In hold mode, releasing it runs the selected option. In toggle mode, a second press does that. See [Player usage](./usage.md).
- **Entity, model, type, bone and zone targets.** Options can be registered on specific entity handles, on every entity of a model, on every ped/vehicle/object/player, on any entity with a named bone, or on box/sphere/poly zones. See [Exports](./exports.md) and [Option format](./options.md).
- **Aim-point zone matching.** A zone matches when the crosshair raycast lands inside it. The player does not need to stand in the zone.
- **Pointer-free option selection.** A single available option runs immediately on release. Two or more open kora_lib's interact selector, which uses scroll or Up/Down and E, with no mouse cursor or NUI focus.
- **Gameplay gates.** Targeting is blocked while seated in a vehicle (options can opt back in), while dead/downed, while cuffed, during a kora_lib progress bar, while a UI-block state bag is set, and during kora_multichar's character/spawn modes. See [Player usage](./usage.md#when-targeting-is-blocked).
- **Stuck-target recovery.** A watchdog cancels a session that was left on by Alt+Tab, the pause menu, cancel keys, or an idle menu. The `target-reset` command force-clears a stuck session. See [Troubleshooting](./troubleshooting.md).
- **Zone location sprites.** An optional, distance-culled world icon is drawn at each coordinate zone. It is off by default. See [Configuration](./configuration.md#sprites).
- **Owner tracking.** Each registration is tracked against the resource that created it. Registrations are removed when that resource stops. By default, a resource can remove a registration by id only if it owns that registration.
- **Server action relay.** `registerServerAction` and `runServerAction` provide an optional server callback that is distance-checked against a networked entity. See [Exports](./exports.md#server-actions).
- **qb-target and ox_target compatibility.** Both public export surfaces are registered and mapped onto the native engine. This includes qb-target job/gang/item/citizen filters, `SpawnPed`, and ox_target `groups`/`items`/sub-menus. See [Compatibility](./compatibility.md).
- **Low idle cost.** No targeting thread runs while the key is up. A broad-phase grid filters zones before exact tests, and motionless aims reuse the previous result. See [Performance](./performance.md).
- **Live configuration.** When the running kora_lib supports `Kora.config`, settings are registered with its configuration system and changes are applied at runtime.

## Requirements

| Resource | Required | Used for |
| --- | --- | --- |
| [kora_lib](https://github.com/KoraFiveM/kora_lib) | Yes (`dependencies` in `fxmanifest.lua`) | Raycasts, zones, keybinds, the interact selector, NUI, callbacks, cache, streaming, config |
| [kora_core](https://github.com/KoraFiveM/kora_core) | Optional | Player data for the qb-target job/gang/citizen filters and ox_target `groups`. Death metadata (`isdead`, `inlaststand`) for the downed gate |
| [kora_inventory](https://github.com/KoraFiveM/kora_inventory) | Optional | The `HasItem` export for qb-target `item`/`required_item` and ox_target `items`/`anyItem` |
| [kora_theme](https://github.com/KoraFiveM/kora_theme) | Optional | The sprite tint (`getPrimaryColor`) |

kora_target also reads state set by other Kora resources when they are running. It reads `koraCuffed` (kora_police), the UI-block bag `koraUiBlocked` (for example kora_emotemenu's freecam), and `kora_multichar:mode` (kora_multichar). The resource has no database tables and no inventory items.

## Installation

1. Place the resource in your resources folder.
2. Add it to `server.cfg` after kora_lib. Start resources that use the native or qb-target exports after kora_target:

   ```cfg
   ensure kora_lib
   ensure kora_core        # optional, enables qb-target/ox_target job, gang and citizen checks
   ensure kora_inventory   # optional, enables item checks
   ensure kora_target
   # resources that use exports.kora_target, exports['qb-target'] or exports.ox_target go here
   ```

3. Optional: some resources declare `dependency 'ox_target'` or check `GetResourceState('ox_target')` (for example ox_inventory with `inventory:target`). For those, copy `stubs/ox_target` from this repository to `resources/[compat]/ox_target` and ensure it after kora_target. Never run it alongside the real ox_target. See [Compatibility](./compatibility.md#the-ox_target-placeholder).

You do not need to import SQL or add items.

The manifest declares `provide 'qb-target'`, so a resource with `dependency 'qb-target'` starts after kora_target.

## Quick example

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

## Documentation pages

- [Player usage](./usage.md): controls, the option menu, and blocking rules.
- [Configuration](./configuration.md): every `Config.target` option and convar.
- [Commands](./commands.md): the key mapping and chat/F8 commands.
- [Exports](./exports.md): native client exports and the server action relay.
- [Option format](./options.md): the option table used by every native registration.
- [Compatibility](./compatibility.md): qb-target and ox_target export surfaces, plus the `ox_target` placeholder.
- [Events](./events.md): events, callbacks, NUI messages and state bags.
- [Performance](./performance.md): resolver cadence and tuning.
- [Troubleshooting](./troubleshooting.md): stuck targeting, debugging zones, and registration lifetime.

## Testing

`test/run.sh` runs plain-Lua smoke tests (`test/smoke/*.lua`) against stubbed natives. `tests/*.feature` contains kora_qa Gherkin scenarios, which are registered through `qa_feature` in `fxmanifest.lua`.
