---
title: Commands
sidebar_position: 4
---

# Commands

All commands are client-side and registered as unrestricted (`RegisterCommand(..., false)`). They need no ACE permission, job or other requirement. Players can run them from chat or the F8 console.

| Command | Arguments | Effect |
| --- | --- | --- |
| `+target` / `-target` | none | The targeting key pair, registered by kora_lib's `Kora.keybind.add`. It has a key mapping on `Config.target.keybind.defaultKey` (default `LMENU`), labelled `Config.target.keybind.label`. Press starts targeting. Release (hold mode) acts on the options. The name follows `Config.target.keybind.command`. |
| `+playerTarget` / `-playerTarget` | none | Aliases of the target key press and release, kept for stock qb-target configs and scripts. They have no key mapping of their own, so the player's binding stays on `+target`. |
| `target-reset` | none | Force-clears targeting, closes the option menu, and releases any legacy qb-target NUI focus. No option is run. The name comes from `Config.target.recovery.resetCommand`. The command is not registered when that value is `false`/`''` or when `recovery.enabled` is false. |
| `kora_target_debug` | `on`, `off`, or nothing | Turns kora_lib zone debug drawing on or off for all existing zones (`Kora.zones.setDebug`). With no argument, it toggles. Any other argument prints a usage message. This does not change `Config.target.debug`. |

## Key mapping

kora_lib registers the mapping with `RegisterKeyMapping('+target', ...)`, using the `keyboard` mapper. Players can rebind it in **Settings, Key Bindings, FiveM**. Rebinding away from Alt automatically turns off the Alt control fallback used by stuck-target recovery (see [Configuration](./configuration.md#stuck-target-recovery)).
