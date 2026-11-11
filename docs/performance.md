---
title: Performance
sidebar_position: 9
---

# Performance

The resolver is designed to cost nothing while the key is up and little while it is held.

## Threads

- **Key up:** no resolver thread runs. The sprite worker runs only when at least one zone would draw a sprite. It polls every 500 ms and runs every frame only while it is actually drawing an icon.
- **Key held:** one resolver thread runs. The first scan happens immediately. After that, the thread waits:
  - `tickActive` (50 ms) while an option is available
  - `tickAcquire` (50 ms) while aiming at an entity with no available option
  - `tickMiss` (100 ms) when neither an entity nor a zone option is hit
- **Menu open:** the resolver idles at `tickIdle`. A per-frame loop handles the menu input policy, and the range check runs every `tickActive` ms.
- **Stuck-target watchdog:** runs only while a session, the menu or legacy focus is active.

## Raycasts

Each real scan fires one broad raycast (flags `511`) from the gameplay camera, up to `maxDistance`. If that ray reports no entity, an entity-only ray (flags `26`) may follow, at most once every `entityProbeInterval` (250 ms). The closer hit wins. Both rays share one camera and ped snapshot. While the player is seated, the ray ignores the player's own vehicle.

## Static aim reuse

When the camera and the ped are exactly motionless and no registration has changed, a tick reuses the previous result. It reuses it for up to `staticRefresh` (200 ms) over a target, or `staticMissRefresh` (500 ms) over empty space. Any aim or player movement resolves on the next tick. Set `staticRefresh = 0` to disable reuse over targets.

## Zone broad phase

Two exact filters run before each zone's `contains` test. Neither can change which zones match:

1. **Reach.** If the aim point is farther from the ped than the largest distance used by any zone option, the whole zone pass is skipped.
2. **Grid.** Zones are indexed in a 50 m XY grid by their bounding box, and only the cell containing the aim point is checked.

Zones whose extent cannot be derived safely are still tested every tick. These are qb-target combo children that are circles, PolyZone boxes with `scale`/`offset`, and entity zones. Entity zones are also only tested when the ray hits their entity.

## canInteract caching

- Successful `canInteract` results are not cached by default (`canInteractCacheMs = 0`), so callbacks that read fast-changing state stay accurate.
- Failed results are reused for `canInteractFailureCacheMs` (250 ms). An unavailable option is therefore not re-evaluated on every pass, but it can still appear while the player keeps aiming.
- Cache entries are keyed per option, entity and 0.1 m distance bucket.

## Diagnostics

Set `Config.target.diagnostics = true` to print, every `diagnosticsInterval` ms while targeting:

- scans, and ticks skipped as static
- raycasts
- options evaluated
- `canInteract` calls
- average resolve time

Leave it off in production.

`Config.target.demo` adds global ped and vehicle options that are evaluated on every aimed ped or vehicle. Enable it only for development.
