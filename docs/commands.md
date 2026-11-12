---
title: "Commands"
sidebar_position: 4
---


# Commands

Kora Target registers client commands only. There are no server commands and no ACE checks. Names marked as configurable come from `Config.target`.

## Client commands

### `/target-reset`

Force-clears targeting: ends the session without running an option, closes the option menu, drops any legacy NUI focus granted by the qb-target layer and sends `-<command>` so the key binding does not think the key is still down. Use it when targeting sticks after Alt+Tab. The name is `Config.target.recovery.resetCommand`; set it to `false` or `""` to not register the command at all.

| Field | Details |
| --- | --- |
| Context | In-game · client command (configurable name) |
| Arguments | No arguments. |
| Access | Any player. Registered at resource start only if `Config.target.recovery.enabled` is not false and `resetCommand` is a non-empty string. |

**Example**

```text
/target-reset
```

**Result**

No chat output. Targeting, the menu and the on-screen dot disappear immediately.

### `/kora_target_debug [on|off]`

Developer tool: turns the debug drawing of target zones on or off at runtime (it calls `Kora.zones.setDebug`, which also affects zones that already exist). With no argument it toggles the current state.

| Field | Details |
| --- | --- |
| Context | In-game · client command |
| Arguments | on \| off — optional; omit to toggle. |
| Access | Any player (the command is not ACE-restricted). |

**Example**

```text
/kora_target_debug on
```

**Result**

Prints `[kora_target] target zone debug drawing enabled.` (or `disabled.`) to the client console. An unrecognised argument prints a hint to use `on`, `off`, or no argument.

## Not commands, but related

The ConVars `kora_target:oxGroups` and `kora_target:oxMenuTimeoutMs` (ox_target compatibility) are documented on the How to use page. Key rebinding is done by the player in the FiveM settings; this resource does not expose a chat command for it.

## Command reference table

All commands are client-side and registered as unrestricted (`RegisterCommand(..., false)`). They need no ACE permission, job or other requirement. Players can run them from chat or the F8 console.

| Command | Arguments | Effect |
| --- | --- | --- |
| `+target` / `-target` | none | The targeting key pair, registered by kora_lib's `Kora.keybind.add`. It has a key mapping on `Config.target.keybind.defaultKey` (default `LMENU`), labelled `Config.target.keybind.label`. Press starts targeting. Release (hold mode) acts on the options. The name follows `Config.target.keybind.command`. |
| `+playerTarget` / `-playerTarget` | none | Aliases of the target key press and release, kept for stock qb-target configs and scripts. They have no key mapping of their own, so the player's binding stays on `+target`. |
| `target-reset` | none | Force-clears targeting, closes the option menu, and releases any legacy qb-target NUI focus. No option is run. The name comes from `Config.target.recovery.resetCommand`. The command is not registered when that value is `false`/`''` or when `recovery.enabled` is false. |
| `kora_target_debug` | `on`, `off`, or nothing | Turns kora_lib zone debug drawing on or off for all existing zones (`Kora.zones.setDebug`). With no argument, it toggles. Any other argument prints a usage message. This does not change `Config.target.debug`. |

### Key mapping

kora_lib registers the mapping with `RegisterKeyMapping('+target', ...)`, using the `keyboard` mapper. Players can rebind it in **Settings, Key Bindings, FiveM**. Rebinding away from Alt automatically turns off the Alt control fallback used by stuck-target recovery (see [Configuration](./configuration.md#stuck-target-recovery)).
