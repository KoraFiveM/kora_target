---
title: Events
sidebar_position: 9
---

# Events

kora_target has no public events of its own for other resources to trigger. Use the [native API](./api/target-api.md) instead. This page lists what the resource listens to, what it sends, and the state it reads, so you can integrate with it.

## Callbacks

| Name | Side | Payload | Notes |
| --- | --- | --- | --- |
| `kora_target:server:runAction` | Server (`Kora.callback.register`) | `name, netId, clientDistance, ...` | **Internal.** Used by the `runServerAction` export. Do not trigger it directly. Every call is validated server-side against the registered action. |

## Events kora_target listens to

| Event | Side | Payload | Effect |
| --- | --- | --- | --- |
| `QBCore:Client:OnPlayerLoaded` | Client (net) | none | Refreshes kora_core player data for the qb-target and ox_target filters, and spawns pending `SpawnPed` configs. |
| `QBCore:Client:OnPlayerUnload` | Client (net) | none | Clears the cached player data and deletes `SpawnPed` peds. |
| `QBCore:Client:OnPlayerUpdated` | Client (net) | `key, value` | Updates the cached `job` or `gang`, or replaces all data when `key` is `'all'`. |
| `qb-inventory:client:updateInventory` | Client (net) | any | Clears the ox_target `items` cache. |
| `inventory:client:updateInventory` | Client (net) | any | Clears the ox_target `items` cache. |
| `onResourceStop` / `onClientResourceStop` | Client and server | `resource` | When another resource stops, its registrations, zones, spawned peds and server actions are removed. When kora_target stops, its menu, legacy NUI focus and spawned peds are cleaned up. |

## Events kora_target triggers

Option handlers registered through the compatibility layers fire whatever events the option names:

- **qb-target:**
  - `type = 'client'`: `TriggerEvent(event, data)`
  - `type = 'server'`: `TriggerServerEvent(event, data)`
  - `type = 'qbcommand'`: `TriggerServerEvent('QBCore:CallCommand', event, data)`
- **ox_target:**
  - `event`: `TriggerEvent(event, response)`
  - `serverEvent`: `TriggerServerEvent(serverEvent, response)`

See [Compatibility](./api/compatibility.md) for the payload shapes. Native options call `onSelect` directly and fire no events.

Development-only: when `fft_kora_hooks` is enabled and an FFT session is active, a local client event `fft:kora:target` is fired with `{ label, model, coords }` for each option that runs.

## NUI

| Name | Direction | Payload | Notes |
| --- | --- | --- | --- |
| `kora_target:target` | Lua to kora_lib NUI (`Kora.nui.send`) | `{ active = false }` or `{ active = true, label, optionCount }` | The prompt snapshot. It is sent only when the value changes. |
| `targetFocus` | `ui/focus.html` to Lua (NUI callback) | `{ event = 'blur' }` or `{ event = 'cancel' }` | Window blur, or Escape/Backspace/right-click in the page. Used by stuck-target recovery when `recovery.nuiListener` is on. |

## State read by kora_target

| State | Source | Effect |
| --- | --- | --- |
| `LocalPlayer.state['kora_multichar:mode']` | kora_multichar | Any value other than `nil`/`false` blocks targeting. |
| `LocalPlayer.state.koraCuffed` | kora_police | Blocks targeting when `blockWhileBusy` is on. |
| `LocalPlayer.state.koraUiBlocked` (the `uiBlockBag` setting) | for example kora_emotemenu | Blocks targeting. |
| `LocalPlayer.state.isDead`, `inLastStand`, `isDowned` | any | Blocks targeting when `disableWhileDead` is on. |
| `LocalPlayer.state.isLoggedIn` | kora_core | When kora_target starts, pending `SpawnPed` configs are spawned if this is set. |
| kora_core `metadata.isdead`, `metadata.inlaststand` | `exports.kora_core:getPlayerData()` | Blocks targeting when `disableWhileDead` is on. |

## kora_qa

Each option that runs calls `Kora.qa.mark('target:option', { label, name, resource })`. This is a no-op unless the player is running a kora_qa scenario.
