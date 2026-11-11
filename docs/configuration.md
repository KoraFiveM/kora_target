---
title: Configuration
sidebar_position: 3
---

# Configuration

All settings are in `config.lua` under `Config.target`. When the running kora_lib provides `Kora.config`, the table is registered with kora_lib's configuration system (`Kora.config.adopt`), and most keys get a label and description. kora_target binds to the `target` section with `Kora.config.bind`. Published changes replace `Config.target` at runtime and invalidate the resolver caches. `defaultOptionDistance` is marked as a live setting.

A few values are read only once:

- `keybind.*` and `recovery.resetCommand` are read when the resource starts.
- `debug` is read when each zone is created.

Changing them needs a resource restart. Registrations do not survive that restart (see [Troubleshooting](./troubleshooting.md#registration-lifetime)).

## Keybind and mode

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `keybind.command` | string | `'target'` | Command name for the key mapping. kora_lib registers `+target`/`-target`. Changing it can affect players' saved bindings. |
| `keybind.defaultKey` | string | `'LMENU'` | Default keyboard key (Left Alt). Players can rebind it in FiveM settings. |
| `keybind.label` | string | `'Hold to target'` | Label shown in the FiveM key binding settings. |
| `toggle` | boolean | `false` | `false`: target only while the key is held. `true`: the first press starts, the second press acts and stops. |
| `skipInvalidEntities` | boolean | `true` | When `addEntity` gets a handle that is not a number, it prints a warning and returns `nil` instead of raising an error. |

## Distances

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `maxDistance` | number | `10.0` | Raycast reach in metres while targeting. |
| `defaultOptionDistance` | number | `2.5` | Fallback interact distance in metres when neither the option nor the registration sets one. Range 0.1 to 25.0. Live. |
| `legacyMaxDistance` | number | `7.0` | Default distance for registrations made through the qb-target compatibility exports when they pass no `distance`. |
| `boneTolerance` | number | `0.35` | How close (metres) the hit point must be to a bone for a bone-scoped option to match. |
| `serverActionMaxDistance` | number | `5.0` | Cap and default for `registerServerAction` distance checks. See [Exports](./exports.md#server-actions). |
| `rangeTolerance` | number | `0.5` | Metres added to an option's distance before an open menu closes as out of range, or before a selected option is refused. |

## Gameplay gates

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `disableInVehicle` | boolean | `true` | Blocks targeting while seated in a vehicle. Options or zones with `allowInVehicle = true` stay usable. |
| `disableWhileDead` | boolean | `true` | Blocks targeting and option execution while dead, in last stand or downed. |
| `downedPollMs` | integer | `250` | Milliseconds between death/busy state reads while targeting. |
| `allowWhileDead` | string array | `{}` | Option `name` values that stay usable while downed. Any entry also lets a downed player open targeting, and then only these options are listed. |
| `blockWhileBusy` | boolean | `true` | Blocks targeting while cuffed (`koraCuffed` state bag) or during a kora_lib progress bar. |
| `uiBlockBag` | string or `false` | `'koraUiBlocked'` | Name of a `LocalPlayer.state` bag that blocks targeting when true. This check is independent of `blockWhileBusy`. Set `false` or `''` to disable it. |
| `ownerScopedRemoval` | boolean | `true` | When true, `removeZone`, `removeEntity`, `removeModel`, `removeGlobalType` and `removeGlobalBone` called with an id only remove a registration of that kind made by the calling resource. Other calls are ignored with a console message. |

## Option menu

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `menuMovement` | `'allow'`, `'close'`, `'freeze'` or nil | `nil` | How movement is treated while the multi-option menu is open. `nil` falls back to `freezeOnMenu`. `'allow'`: free movement. `'close'`: a new movement key press closes the menu. `'freeze'`: movement keys are ignored, but the ped is never position-frozen. |
| `freezeOnMenu` | boolean | `false` | Legacy flag, used only when `menuMovement` is unset. `true` means `'freeze'` and `false` means `'allow'`. |
| `lockCameraOnMenu` | boolean | `false` | Disables look controls while the menu is open. |
| `closeMenuOutOfRange` | boolean | `true` | Closes the menu when the player is out of range of every listed option. Checked every `tickActive` ms. |
| `closeWhenAirborne` | boolean | `false` | When true, cancels targeting and closes the menu while falling, jumping, ragdolling, parachuting, climbing or vaulting. Releasing the key while airborne does nothing. |
| `showCloseHint` | boolean | `false` | Shows `text.closeHint` as GTA help text for 5 s when the menu opens. |
| `suppressPauseOnClose` | boolean | `true` | Stops the Escape press that closes the menu from also opening the pause menu. |
| `pauseSuppressMs` | integer | `250` | How long (0 to 2000 ms) pause controls stay blocked after the menu closes. |

## Player-facing text

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `text.closeHint` | string | `'Press ~INPUT_FRONTEND_PAUSE_ALTERNATE~ to close'` | Help text used by `showCloseHint`. |
| `text.optionCount` | string | `'%d options'` | Prompt label when several options are under the aim. `%d` is the count. |
| `text.goBack` | string | `'Go back'` | Label of the ox_target sub-menu back entry. |

## Stuck-target recovery

`Config.target.recovery` controls the watchdog that runs while a session, the option menu or legacy qb-target NUI focus is active. It never runs an option when it cancels. See [Troubleshooting](./troubleshooting.md#stuck-targeting).

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `recovery.enabled` | boolean | `true` | Master switch for everything below. When false, no watchdog runs and the reset command is not registered. |
| `recovery.releaseGraceMs` | integer | `250` | Hold mode: how long the key must read "up" (after being seen down) before the session is dropped. |
| `recovery.cancelOnPause` | boolean | `true` | Cancel when the pause menu opens. |
| `recovery.cancelControls` | boolean | `true` | While holding, Escape, Backspace/cancel and right-click (controls 200, 177, 25) cancel without selecting. Also covers cancel events from `ui/focus.html`. |
| `recovery.cancelOnFocusLoss` | boolean | `true` | Cancel when the game window loses focus (`IsGameWindowFocused`, plus NUI blur events). |
| `recovery.focusReleaseIgnoreMs` | integer | `1500` | Hold mode: a key-up this soon after a focus loss cancels instead of selecting. `0` disables. |
| `recovery.altControlFallback` | boolean | `true` | Hold mode with the default `LMENU` key: read control 19 (INPUT_CHARACTER_WHEEL) for key state. Skipped when the player rebound the key away from Alt. |
| `recovery.menuIdleTimeoutMs` | integer | `30000` | Close the option menu after this long without select/scroll input. `0` disables. |
| `recovery.nuiListener` | boolean | `true` | Act on blur/cancel events posted by `ui/focus.html`. |
| `recovery.resetCommand` | string or `false` | `'target-reset'` | Name of the client command that force-clears targeting. `false` or `''` disables it. |

## Sprites

`Config.target.sprites` draws a world icon at each coordinate zone (native box/sphere/poly zones, and qb-target zones created through the standalone path). Only zones with a sprite anchor are drawn. The sprite worker exists only while at least one zone would draw.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `sprites.enabled` | boolean | `false` | Show icons for every zone that does not set `drawSprite = false`. |
| `sprites.allowPerZoneOverride` | boolean | `true` | A zone registered with `drawSprite = true` shows its icon even while `enabled` is false. |
| `sprites.drawDistance` | number | `20.0` | Metres. Icons beyond this distance are not drawn. |
| `sprites.offset` | table | `{ x = 0.0, y = 0.0, z = 0.45 }` | World-space offset from the zone anchor. |
| `sprites.dict` | string | `'shared'` | Streamed texture dictionary. |
| `sprites.name` | string | `'info'` | Texture name. |
| `sprites.width` | number | `0.015` | Screen-fraction width. |
| `sprites.height` | number | `0.02` | Screen-fraction height. |
| `sprites.colour` | table | `{ r = 149, g = 255, b = 0, a = 220 }` | Fallback tint. `a` is always used as the icon alpha. |
| `sprites.useThemeColour` | boolean | `true` | Tint with kora_theme's `getPrimaryColor()` when kora_theme is started. Otherwise `colour` is used. |
| `sprites.hideWhileTargeting` | boolean | `true` | Hide icons while a targeting session is active. |

## Performance and diagnostics

See [Performance](./performance.md) for what these settings trade off.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `tickIdle` | integer | `150` | ms the resolver waits while targeting is disabled, the menu is open, or interactions are locked. |
| `tickAcquire` | integer | `50` | ms between resolves while aiming at an entity with no available option. |
| `tickActive` | integer | `50` | ms between resolves while an option is available. Also the menu range-check interval. |
| `tickMiss` | integer | `100` | ms between resolves when no entity or zone option is hit. |
| `staticRefresh` | integer | `200` | Maximum ms a motionless aim over a target may reuse the previous resolve. `0` disables reuse. |
| `staticMissRefresh` | integer | `500` | Maximum ms a motionless empty aim may reuse its miss. |
| `entityProbeInterval` | integer | `250` | Minimum ms between entity-only fallback raycasts. |
| `canInteractCacheMs` | integer | `0` | How long a successful `canInteract` result is reused. `0` re-checks every pass. |
| `canInteractFailureCacheMs` | integer | `250` | How long a failed `canInteract` result is reused. |
| `diagnostics` | boolean | `false` | Print a per-hold resolver summary (scans, skipped ticks, raycasts, options, `canInteract` calls, average resolve time). |
| `diagnosticsInterval` | integer | `5000` | ms between diagnostics prints. |
| `debug` | boolean | `false` | Pass `debug = true` to every native zone created while set, so kora_lib draws its outline. Read at zone creation time. |

## Other

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `legacyOutline.enabled` | boolean | `false` | Lets the qb-target `DrawOutlineEntity` export outline non-ped entities. |
| `legacyOutline.colour` | integer array | `{ 255, 255, 255, 255 }` | RGBA outline colour for `DrawOutlineEntity`. |
| `reticle` | boolean | `true` | Retained setting. The current targeting loop does not read it. |
| `demo` | boolean | `false` | Registers demo global ped and vehicle options ("Inspect ped (demo)", "Inspect vehicle (demo)") at start. Development only. |

## Convars

| Convar | Type | Default | Description |
| --- | --- | --- | --- |
| `kora_target:oxGroups` | integer | `1` | `0` disables ox_target `groups` enforcement, so groups are passed through unchecked. |
| `kora_target:oxMenuTimeoutMs` | integer | `15000` | How long an ox_target sub-menu (`openMenu`) stays current before it resets to the home menu. `0` means it never resets. |
| `fft_kora_hooks` | string | `'false'` | `'true'` loads the optional FFT test hooks in `fft_hooks.lua`. Development only. |

These are read on the client with `GetConvar`/`GetConvarInt`, so set them with `setr` (replicated):

```cfg
setr kora_target:oxGroups 1
setr kora_target:oxMenuTimeoutMs 15000
```

## Example

```lua
Config.target = {
    -- ...
    toggle = true,               -- press to start, press again to act
    disableInVehicle = false,    -- allow targeting from vehicles
    allowWhileDead = { 'ems_call_help' },
    sprites = {
        enabled = true,
        drawDistance = 15.0,
        -- keep the other sprite keys
    },
    -- ...
}
```
