---
title: "How to use"
sidebar_position: 3
---


# How to use

The player holds a key, looks at something, and releases the key to use it. Scripts register targets (models, entities, zones, global types, bones) with `exports.kora_target`, or keep using their existing `qb-target` / `ox_target` calls. This page explains the model, shows complete examples and lists the settings that matter.

## How targeting works for the player

1. **Hold the key** — Hold Left Alt (`Config.target.keybind.defaultKey = 'LMENU'`). Players can rebind it in the FiveM key bindings under the label "Hold to target". A dot is drawn at the centre of the screen while targeting is active (`Config.target.toggle = true` turns this into press to start, press again to act).

2. **Aim at something** — Each scan casts a ray from the camera up to `Config.target.maxDistance` (10.0 m). Entity targets match the entity that the ray hit. Zone targets match the point where the ray lands: you do not need to stand inside a zone, only aim at a point inside it.

3. **See what is available** — An option appears when the distance from the player to the aimed point is within the option's distance (default 2.5 m), any bone restriction matches, and `canInteract` does not return `false`. The on-screen label is the option label, or "N options" when several are available.

4. **Release to act** — Releasing the key runs a single available option immediately. With two or more, Kora Lib's pointer-free selector opens: scroll or use the arrow keys to choose and press E. The candidate list is captured at release, so the menu keeps working until you leave range.

5. **Cancel safely** — Escape, Backspace and right-click cancel without selecting. Alt+Tab, opening the pause menu, dying, getting into a vehicle and (optionally) falling also cancel. A watchdog recovers the session if the key-up event is lost.

## Register targets: the native API

Native calls go through `exports.kora_target`. Each `add*` call returns a numeric registration id (or `nil` when `addEntity` skips an invalid handle). Keep the id so you can remove exactly that registration later.

```lua title="client/targets.lua"
-- 1) Every ATM prop in the world, for everyone
local atmId = exports.kora_target:addModel({ 'prop_atm_01', 'prop_atm_02', 'prop_atm_03' }, {
    {
        name = 'use_atm',
        label = 'Use ATM',
        icon = 'credit-card',
        onSelect = function(entity, data)
            TriggerServerEvent('bank:server:requestAtm', NetworkGetNetworkIdFromEntity(entity))
        end,
    },
}, 1.5)

-- 2) A fixed counter, aimed at as a box zone
local counterId = exports.kora_target:addBoxZone({
    coords = vector3(441.2, -981.9, 30.7),
    size = vector3(1.6, 0.8, 1.2),
    rotation = 90.0,
    distance = 2.0,
    options = {
        {
            label = 'Book a suspect',
            icon = 'clipboard',
            canInteract = function() return LocalPlayer.state.onDuty == true end,
            onSelect = function() TriggerServerEvent('police:server:openBooking') end,
        },
    },
})

-- 3) Every vehicle, but only when the aim is on the boot
local trunkId = exports.kora_target:addGlobalType('vehicle', {
    {
        label = 'Open trunk',
        icon = 'car',
        bones = { 'boot' },
        distance = 2.5,
        onSelect = function(vehicle) TriggerServerEvent('trunk:server:open', NetworkGetNetworkIdFromEntity(vehicle)) end,
    },
})

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    exports.kora_target:removeModel(nil, atmId)
    exports.kora_target:removeZone(counterId)
    exports.kora_target:removeGlobalType('vehicle', trunkId)
end)
```

> **Note:** You do not have to write the cleanup above: registrations are tracked by the resource that created them and are removed automatically when that resource stops. Remove them yourself when a target should disappear while your resource keeps running (for example when a ped despawns).

## Choosing the right registration

- `addEntity(entity, options, distance?)`: one or more specific entity handles (a spawned ped, a vehicle you own). The registration is removed whole, never per entity.
- `addModel(model, options, distance?)`: every current and future entity with that model (names are `joaat` hashed). Best for props such as ATMs and vending machines.
- `addGlobalType(type, options, distance?)`: every `ped`, `vehicle`, `object` or `player` the ray hits.
- `addGlobalBone(bones, options, distance?)`: any entity that has a matching bone, whatever its type or model.
- `addTargetBone(entity, bone, options, distance?)`: shorthand for `addEntity` where every option is forced onto one bone.
- `addBoxZone` / `addSphereZone` / `addPolyZone`: fixed areas in the world, matched against the aimed point. Only these (and qb-target zones) can show a world sprite.

## Security: the client is not authoritative

Everything in an option runs on the player's machine: `canInteract`, `distance`, `bones`, and the compat `job` / `gang` / `item` / `groups` filters only decide what is shown. A modified client can call your `onSelect` body or fire your server event directly. Treat the target as a convenience for honest players and revalidate on the server: job, item, ownership, cooldown, and distance from the real server-side player and entity position.

```lua title="server/bank.lua"
-- Server: the authoritative check, whatever the client claims it was aiming at
exports.kora_target:registerServerAction('bank:openAtm', function(src, atm)
    -- src and atm are already resolved from a network id and distance-checked (see below)
    local identifier = GetPlayerIdentifierByType(src, 'license')
    if not identifier then return false, 'No identity.' end
    -- ...job / balance / cooldown checks here, using only server state...
    TriggerClientEvent('bank:client:openUi', src)
    return true
end, { maxDistance = 3.0 })
```

- `ServerTarget.registerServerAction` (exported as `registerServerAction`) and the client `runServerAction` relay only re-check that the target is a real networked entity near the calling player, in the same routing bucket. They are not a permission framework: job, gang and item checks are still your handler's job.
- The distance cap is enforced on the server (`Config.target.serverActionMaxDistance`, default 5.0). The distance a client passes is ignored.
- Entities created locally (for example with `Kora.entities.create`, or the peds from the qb-target `SpawnPed` helper) have no server twin and cannot be used with `runServerAction`.

## Migrating a qb-target or ox_target script

No code change is needed. `exports['qb-target']:AddBoxZone(...)`, `AddTargetEntity`, `SpawnPed` and the other qb-target exports, and `exports.ox_target:addBoxZone(...)`, `addLocalEntity`, `addModel`, `addGlobalVehicle` and the other ox_target exports, are registered by kora_target and translated onto the native engine. See the Compatibility module for the full list of converted exports.

```lua title="client/legacy.lua"
-- Unmodified qb-target script
exports['qb-target']:AddBoxZone('pd_lockers', vector3(450.0, -985.0, 30.7), 1.6, 0.6, {
    name = 'pd_lockers', heading = 90.0, minZ = 29.7, maxZ = 32.1,
}, {
    options = {
        { type = 'client', event = 'police:client:openLockers', icon = 'fas fa-box', label = 'Open lockers', job = 'police' },
    },
    distance = 2.0,
})

-- Unmodified ox_target script
exports.ox_target:addGlobalVehicle({
    { name = 'impound', label = 'Impound', icon = 'fa-solid fa-truck', groups = { police = 2 },
      event = 'police:client:impound', distance = 3.0 },
})
```

## ConVars, ACEs and server switches

- ConVar `kora_target:oxGroups` (integer, default `1`): set to `0` and ox_target compat `groups` are passed through without being enforced. Read at registration time and on every check.
- ConVar `kora_target:oxMenuTimeoutMs` (integer, default `15000`): how long an ox_target sub-menu (`openMenu` / `menuName`) stays open between key presses before it resets to the home menu. `0` means never.
- There are no ACE permissions, no server commands and no server events to configure. All behaviour is controlled by `Config.target` in `config.lua`, which Kora Lib's configuration system also adopts (see the Configuration module).
- Wrapper command names (`target`, `target-reset`) come from `Config.target.keybind.command` and `Config.target.recovery.resetCommand`.

## Integration points other scripts can rely on

- Net event `QBCore:Client:OnPlayerLoaded`, `QBCore:Client:OnPlayerUnload` and `QBCore:Client:OnPlayerUpdated(key, value)` are listened to (client) to refresh job / gang data and to spawn or delete `SpawnPed` peds.
- Net events `qb-inventory:client:updateInventory` and `inventory:client:updateInventory` clear the ox_target item-check cache.
- NUI message `kora_target:target` is sent through `Kora.nui.send` with `{ active, label?, optionCount? }` whenever the hover state changes. The NUI callback `targetFocus` (`{ event = 'blur' | 'cancel' }`) is received from `ui/focus.html`.
- Kora Lib callback `kora_target:server:runAction` is the server end of `runServerAction`.
- Option `name` strings are matched against `Config.target.allowWhileDead`, so give options stable names when they must work while downed.

## Common mistakes

- `canInteract` only denies when it returns the literal value `false` or raises an error. Returning `nil` (a function with no `return`) counts as allowed.
- An option is only offered when the aimed point is within its `distance` of the player. The distance is measured from the player to the point the ray hit, not to the entity origin and not to the zone centre, so a long vehicle can be reachable at its boot but not its bonnet.
- Registering the same model or entity twice creates two registrations and duplicate options. Keep the id and remove the old one, or use the qb-target label API where options merge by label.
- Callbacks passed through exports arrive as function references: keep `onSelect` and `canInteract` as functions, and keep `data` plain (numbers, strings, tables).
- Menu order is not guaranteed. All options resolved in one scan share the same aimed point, so the "closest first" ordering does not separate them.
