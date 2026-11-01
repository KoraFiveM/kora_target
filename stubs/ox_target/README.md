# ox_target compatibility placeholder

Content-free resource (manifest only), not affiliated with Overextended. It exists
only so `GetResourceState('ox_target') == 'started'`, which stock ox_inventory
checks (`init.lua`, when `inventory:target` is true) and which `provide 'ox_target'`
in kora_target does not satisfy. Calls to `exports.ox_target:*` are still answered
by kora_target (`client/compat/ox-target.lua`).

## Deploy
Copy this folder to `resources/[compat]/ox_target` and start in this order:

    ensure kora_target
    ensure [compat]/ox_target
    ensure ox_inventory

Never run it alongside the real ox_target. Do not add scripts or exports to the manifest.

## Risk: `provide` + same-name resource
kora_target declares `provide 'ox_target'` and a resource named `ox_target` now also
exists. Expected (unverified on a server): the real resource wins `GetResourceState`
and dependency lookups, and the export event names do not clash because the placeholder
exports nothing. If the artifact treats the duplicate as a conflict, remove
`provide 'ox_target'` from kora_target's manifest (the export hijack does not depend on it).

## Verify on a scratch server
1. Start the stack in the order above; no errors about duplicate or provided resources.
2. In a debug resource: `GetResourceState('ox_target')` is `started`.
3. `exports.ox_target:addBoxZone({...})` returns a number and `removeZone(id)` returns true.
4. With `setr inventory:target true`, ox_inventory prints no `ox_target is not loaded`
   warning; dumpster, vehicle trunk, shop ped/model, stash, evidence and crafting
   targets appear and respond.
5. Stop and restart `kora_target`; restart the placeholder and ox_inventory afterwards.
   Zones registered by ox_inventory are re-created on ox_inventory restart.
