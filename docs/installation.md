---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora Target is the interaction (third-eye) engine for the Kora stack. It runs on the client, needs only Kora Lib, and also answers to the `qb-target` and `ox_target` export names so existing scripts keep working. Follow these steps in order.

## Install Kora Target

1. **Add the folder** — Place the `kora_target` folder inside your resources directory (on the Kora recipe it lives in `resources/[kora]/kora_target`). Keep the folder name unchanged: it is also the name consumer scripts use in `exports.kora_target:...`.

2. **Make sure Kora Lib is installed** — The manifest declares `dependencies { "kora_lib" }` and loads `@kora_lib/init.lua` as a shared script, so Kora Lib (and the Kora Theme resource Kora Lib itself requires) must already be present. Kora Target uses `Kora.raycast`, `Kora.zones`, `Kora.interact`, `Kora.nui`, `Kora.keybind`, `Kora.cache`, `Kora.callback`, `Kora.world`, `Kora.resources`, `Kora.stream` and `Kora.config` from it.

3. **Start it from server.cfg** — Start it after Kora Lib and before any resource that registers targets:

   ```bash title="server.cfg"
   ensure kora_theme
   ensure kora_lib
   ensure kora_target
   # ...resources that call exports.kora_target / exports["qb-target"] / exports.ox_target
   ```

## What the manifest sets up

- `provide 'qb-target'` satisfies another resource's `dependency 'qb-target'` check. The export identity `exports['qb-target']` is registered separately in code (`client/compat/qb-target.lua`), so scripts calling `exports['qb-target']:AddBoxZone(...)` reach this resource.
- `ox_target` is deliberately NOT provided. `exports.ox_target:...` calls are still answered by kora_target (registered in `client/compat/ox-target.lua`), but the resource name `ox_target` belongs to the placeholder in `stubs/ox_target`. This prevents `stop ox_target` from stopping kora_target.
- Client scripts load in a fixed order: `client/state.lua` (registry and the public add/remove functions), `client/sprites.lua`, `client/loop.lua` (targeting loop and keybind), `client/exports.lua` (native exports), then the two compat files. The server side is a single file, `server/server.lua`.
- `ui_page 'ui/focus.html'` is a tiny invisible listener page. It never takes focus; it only reports window blur and Escape / Backspace / right-click back to the Lua side (`targetFocus` NUI callback) so a lost key-up can be recovered.
- `config.lua` is a shared script, so the server side can read `Config.target.serverActionMaxDistance`.

## If it does not start or nothing can be targeted

- Check the console for a missing `kora_lib` dependency and that `kora_lib` is ensured before `kora_target`.
- If targeting seems stuck after Alt+Tab, run `/target-reset` in chat or F8.

## Optional resources and server.cfg order

kora_target also works with these optional Kora resources. Start them before kora_target when you use them:

```cfg title="server.cfg"
ensure kora_lib
ensure kora_core        # optional, enables qb-target/ox_target job, gang and citizen checks
ensure kora_inventory   # optional, enables item checks
ensure kora_target
# resources that use exports.kora_target, exports['qb-target'] or exports.ox_target go here
```

You do not need to import SQL or add items: the resource has no database tables and no inventory items.

## The ox_target placeholder (optional)

Some resources declare `dependency 'ox_target'` or check `GetResourceState('ox_target')` (for example ox_inventory with `inventory:target`). For those, copy `stubs/ox_target` from this repository to `resources/[compat]/ox_target` and ensure it after kora_target. Never run it alongside the real ox_target. See [Compatibility](./api/compatibility.md#placeholder-resource).
