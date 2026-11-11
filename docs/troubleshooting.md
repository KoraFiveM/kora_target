---
title: Troubleshooting
sidebar_position: 10
---

# Troubleshooting

## Stuck targeting

If a key-up is lost (typically Alt+Tab while holding Alt), targeting or the option menu could stay on. With `Config.target.recovery.enabled` (the default), a watchdog runs while a session, the menu or legacy qb-target NUI focus is active. It cancels, without running any option, when:

- the game window loses focus (`cancelOnFocusLoss`), or `ui/focus.html` reports a blur
- the pause menu opens (`cancelOnPause`)
- Escape, Backspace or right-click is pressed while holding (`cancelControls`)
- in hold mode, the key reads "up" for `releaseGraceMs` after being seen down. With the default Alt key, control 19 is read (`altControlFallback`).
- the option menu sees no input for `menuIdleTimeoutMs` (30 s)
- legacy NUI focus is still held one second after the session ended

A key-up within `focusReleaseIgnoreMs` (1.5 s) of a focus loss cancels instead of selecting.

To clear a stuck session manually, run `target-reset` in chat or F8 (or whatever `recovery.resetCommand` is set to).

## Options do not show

- Check that you are aiming at the zone. Zones match the raycast hit point, not where the player stands. If the ray passes over a low zone and hits the floor beyond it, the zone is not matched.
- Check the option distance. It is measured from the player to the aim point. qb-target registrations default to `legacyMaxDistance` (7.0), and native ones to `defaultOptionDistance` (2.5).
- Check the gates: in a vehicle, downed, cuffed, in a progress bar, `koraUiBlocked` set, or in kora_multichar mode. See [Player usage](./usage.md#when-targeting-is-blocked).
- A `canInteract` that errors hides the option and prints `[kora_target] canInteract for option '...' errored`.
- qb-target job, gang or item filters need kora_core and kora_inventory. Without kora_core, a warning is printed at registration and the filters are skipped.

## Seeing zones

- `kora_target_debug on` (or `off`, or no argument to toggle) turns kora_lib's debug outline on or off for all existing zones.
- `Config.target.debug = true` outlines every zone created while it is set.
- Pass `debug = true` (native/ox_target) or `debugPoly = true` (qb-target box/circle/poly zones that become native zones) on a single zone.

## Registration lifetime

Registrations exist only while kora_target is running. Nothing is queued before it starts or replayed after it restarts, and ids restart at 1.

- A resource that registers when its files load should declare `dependency 'kora_target'` (or `'qb-target'`). It then starts after kora_target and is stopped with it. Start it again after you restart kora_target.
- Otherwise:
  - register only when `GetResourceState('kora_target') == 'started'`
  - register again from `onClientResourceStart` for `kora_target`
  - discard stored ids on its `onClientResourceStop`
- With `ownerScopedRemoval`, a stale id from before a restart cannot remove another resource's registration.

## Console messages

| Message | Cause |
| --- | --- |
| `addEntity skipped: invalid entity handle` | A non-number handle was passed (for example a failed spawn) while `skipInvalidEntities` is on. |
| `... tried to remove registration ... owned by ...; ignored` | A remove call with an id that belongs to another resource. |
| `onSelect for option '...' errored` | The option's `onSelect` raised an error. |
| `server action '...' errored` | A `registerServerAction` handler raised an error on the server. |
| `WARNING: server action '...' is already registered` | Two resources (or one restarted resource) registered the same action name. |
| `[kora_target:qb-target] WARNING: option ... sets a job/gang/item/jobType filter but kora_core is not running` | Filters are skipped. |
| `[kora_target:ox_target] WARNING: option ... sets groups but no kora_core identity is running` | `groups` is not enforced. |
| `[kora_target:ox_target] WARNING: option sets items but kora_inventory is unavailable` | `items` is not enforced. |
