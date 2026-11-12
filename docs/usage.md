---
title: Player usage
sidebar_position: 6
---

# Player usage

## Targeting

- **Hold mode (default).** Hold the target key (`Config.target.keybind.defaultKey`, default `LMENU`, Left Alt) and aim. While the key is held, kora_target raycasts from the gameplay camera up to `Config.target.maxDistance` (10 m) and resolves every registered option that matches the hit. Release the key to act.
- **Toggle mode.** Set `Config.target.toggle = true`. The first press starts targeting, and you can let go of the key. The second press acts on the current options and ends the session.

Players can rebind the key in FiveM's key binding settings. The mapping is labelled `Config.target.keybind.label` ("Hold to target"). See [Commands](./commands.md).

While targeting, kora_lib's transparent NUI shows a compact prompt at screen centre. When one option is available, the prompt shows its label. When several are available, it shows a count (`Config.target.text.optionCount`, default `%d options`). The prompt never moves the mouse pointer or takes NUI focus.

### What matches

- **Entity, model, global-type and global-bone registrations** match the entity the raycast hit. An option with `bones` matches only when the hit point is within `Config.target.boneTolerance` (0.35 m) of one of those bones.
- **Zones** match when the raycast hit point is inside the zone. You do not have to stand inside the zone. You only need to aim at a point within it.
- Every option also needs the player to be within its distance of the hit point. The distance comes from the option's `distance`, then the registration's default distance, then `Config.target.defaultOptionDistance` (2.5 m). After that, the option's `canInteract` (if any) must not return `false`.
- The closest matching option is listed first.

## Acting on options

When the key is released (or pressed again in toggle mode):

- **No options:** nothing happens.
- **One option:** it runs immediately.
- **Two or more options:** kora_lib's interact selector opens. kora_lib's `Config.interact` sets its controls. By default, the mouse wheel or Up/Down chooses, E or left click selects, and Escape or Backspace closes the list without running anything.

While the key is still held, Escape, Backspace or right-click cancels the session without selecting anything (`Config.target.recovery.cancelControls`).

Before an option runs, kora_target checks it again. The option is refused if any of these apply:

- its target is out of range (option distance plus `Config.target.rangeTolerance`, 0.5 m)
- its entity no longer exists
- the player is now seated in a vehicle and the option has not opted in
- the player is downed or busy (see below)

### While the option menu is open

- Movement is allowed by default (`Config.target.menuMovement`, see [Configuration](./configuration.md#option-menu)). `'close'` closes the menu when a movement key is pressed. `'freeze'` ignores movement keys while the menu is open. The ped's position is never frozen.
- `Config.target.lockCameraOnMenu = true` also disables look controls.
- The menu closes when the player moves out of range of every listed option (`closeMenuOutOfRange`, checked every `tickActive` ms). It also closes after `recovery.menuIdleTimeoutMs` (30 s) without scroll or select input.
- The menu also closes when targeting gets disabled, kora_multichar locks interactions, or the player becomes downed or busy.
- With `closeWhenAirborne = true`, the menu also closes and targeting is cancelled while the ped is falling, jumping, ragdolling, parachuting, climbing or vaulting.
- With `suppressPauseOnClose = true` (default), closing the menu with Escape does not also open the pause menu. The pause controls stay blocked while the menu is open and for `pauseSuppressMs` (250 ms) after it closes.
- `showCloseHint = true` shows the GTA help text from `Config.target.text.closeHint` for 5 seconds when the menu opens.

## When targeting is blocked

| Condition | Setting | Behaviour |
| --- | --- | --- |
| Seated in a vehicle (driver or passenger) | `disableInVehicle = true` | The key does nothing unless some registered option has `allowInVehicle = true`. Then only those options are listed, and `canInteract` is not called for the rest. Getting in closes an open prompt or menu unless every option in it opted in. |
| Dead, in last stand or downed | `disableWhileDead = true` | Blocked when kora_core metadata `isdead`/`inlaststand` is true, when a `LocalPlayer.state` bag `isDead`, `inLastStand` or `isDowned` is true, or when kora_lib's `Kora.cache.isDead()` is true. Options whose `name` is in `allowWhileDead` stay usable. The state is read every `downedPollMs` and again right before an option runs. |
| Cuffed or in a progress bar | `blockWhileBusy = true` | Blocked when `LocalPlayer.state.koraCuffed` is true or a kora_lib progress bar is active. |
| UI-block state bag set | `uiBlockBag = 'koraUiBlocked'` | Blocked while `LocalPlayer.state[uiBlockBag]` is true. This check applies even when `blockWhileBusy` is false. Set `uiBlockBag` to `false` or `''` to disable it. |
| kora_multichar mode | none | Blocked while `LocalPlayer.state['kora_multichar:mode']` is set to anything other than `nil`/`false` (character select, spawn picker, scene editor). |
| Disabled by script | `setEnabled(false)` | Blocked until it is enabled again. See [Native API](./api/target-api.md). |

When one of these starts during a session, the prompt and any open menu close.

## Zone sprites

When `Config.target.sprites.enabled = true`, a small world icon (`shared/info` by default) is drawn at each coordinate zone within `drawDistance` (20 m). A single zone can also request its own sprite with `drawSprite = true` while `allowPerZoneOverride` is on. Icons are hidden while the target key is held (`hideWhileTargeting`). Entity, model and global targets never get sprites, because they have no fixed world position. See [Configuration](./configuration.md#sprites).
