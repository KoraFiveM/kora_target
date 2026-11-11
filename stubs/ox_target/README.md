# ox_target compatibility placeholder

Content-free resource (manifest only), not affiliated with Overextended. It exists
only so `GetResourceState('ox_target') == 'started'`, which stock ox_inventory
checks (`init.lua`, when `inventory:target` is true) and which kora_target no longer
claims (it does not `provide 'ox_target'`, so this placeholder alone owns the name and
`stop ox_target` does not stop kora_target). Calls to `exports.ox_target:*` are still answered
by kora_target (`client/compat/ox-target.lua`).

## Deploy
Copy this folder to `resources/[compat]/ox_target` and start in this order:

    ensure kora_target
    ensure [compat]/ox_target
    ensure ox_inventory

Never run it alongside the real ox_target. Do not add scripts or exports to the manifest.

## When it is needed
Resources that declare `dependency 'ox_target'` or check `GetResourceState('ox_target')`
need this placeholder ensured after kora_target. `exports.ox_target:*` works without it.

## Verify on a scratch server
1. Start the stack in the order above; no errors about duplicate resources.
2. In a debug resource: `GetResourceState('ox_target')` is `started`.
3. `exports.ox_target:addBoxZone({...})` returns a number and `removeZone(id)` returns true.
4. With `setr inventory:target true`, ox_inventory prints no `ox_target is not loaded`
   warning; dumpster, vehicle trunk, shop ped/model, stash, evidence and crafting
   targets appear and respond.
5. Stop and restart `kora_target`; restart the placeholder and ox_inventory afterwards.
   Zones registered by ox_inventory are re-created on ox_inventory restart.
