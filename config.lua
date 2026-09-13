Config = {}

Config.target = {
    -- Hold this key to enter targeting mode (raycasting + drawing a prompt
    -- every tick). Uses FiveM's +/- command-pair convention, not a plain
    -- RegisterCommand, specifically so press vs release can be told apart.
    keybind = { command = 'target', defaultKey = 'LMENU', label = 'Hold to target' },

    -- Toggle vs hold. Default (false) is hold-to-target: targeting runs only
    -- while the key is physically down, matching qb-target's LMENU feel. Set
    -- true for press-to-activate / press-again-to-deactivate -- the key press
    -- flips targeting on, the next press flips it off, and the key can be
    -- released in between (matching ox_target's default). The +/- command pair
    -- is registered either way; in toggle mode the release (-target) is ignored
    -- and only the press flips state. See client/loop.lua.
    toggle = false,

    maxDistance = 10.0,            -- meters; QB.raycast.fromCamera's max reach while the hold key is down
    defaultOptionDistance = 2.5,   -- meters; fallback per-option interact distance when nothing more specific is set
    legacyMaxDistance = 7.0,       -- qb-target Config.MaxDistance default used only by the qb-target compatibility surface
    legacyOutline = {              -- mirrors current qb-target's outline defaults
        enabled = false,
        colour = { 255, 255, 255, 255 },
    },
    boneTolerance = 0.35,          -- meters; how close a raycast hit must land to a candidate bone to count as a match

    -- Adaptive target-loop cadence. A scan happens immediately when targeting
    -- starts. It then polls slowly while no option is available, but renders
    -- and resolves every frame while an option is visible so target changes
    -- still feel immediate.
    tickIdle = 150,                -- ms while targeting is disabled
    -- Resolver cadence while Alt is held. Prompt/reticle rendering remains
    -- frame-perfect in a separate lightweight loop; raycasts and option
    -- resolution run at 20Hz, matching the responsive split-loop approach
    -- used by ox_target without tying expensive native work to every frame.
    tickAcquire = 50,              -- ms while held with no available option
    tickActive = 50,               -- ms while an option is visible
    tickMiss = 100,                -- ms while held without an entity or available zone option

    -- Longest a held aim may reuse its previous scan while the camera AND the
    -- player ped are both bit-for-bit motionless (client/loop.lua's
    -- aimIsStatic). Standing still looking at a door is by far the most
    -- common thing a player does while holding the key, and re-firing two
    -- shape tests 20x/second down an identical ray cannot produce a different
    -- answer -- the only thing it can catch is the WORLD moving under a
    -- frozen crosshair (a ped walking into it), which is what this cap bounds.
    -- Any actual aim input resolves on the very next tick, so this never adds
    -- latency to targeting something deliberately. Set 0 to disable.
    staticRefresh = 200,
    -- Default to no cache: third-party canInteract functions commonly depend
    -- on rapidly-changing local state. Successful checks therefore remain
    -- fresh, while failed checks get a small cooldown so an unavailable option
    -- does not invoke the same callback on every resolver pass.
    canInteractCacheMs = 0,
    canInteractFailureCacheMs = 250,

    -- Prints a small per-hold profiler summary every diagnosticsInterval ms.
    -- Keep this off in production; it exists to make resmon investigations
    -- measurable without adding a permanent hot-path cost.
    diagnostics = false,
    diagnosticsInterval = 5000,

    -- Development aid: draw qblib's full box/sphere/poly outline for every
    -- target zone. A zone registered with `debug = true` is also outlined
    -- when this is false; set this to true to inspect all zone bounds at once.
    debug = false,

    -- A lightweight, ox_target-style world sprite at each target-zone
    -- anchor. This deliberately only covers coordinate zones: entity/model/
    -- global targets have no single stable location, and scanning every game
    -- entity just to draw icons would be needlessly expensive.
    sprites = {
        enabled = false,
        drawDistance = 20.0, -- meters; sprite draw work is skipped beyond this
        offset = { x = 0.0, y = 0.0, z = 0.45 },
        dict = 'shared',
        name = 'info',
        width = 0.015,
        height = 0.02,
        colour = { r = 30, g = 144, b = 255, a = 220 },
    },

    -- No idle thread when the key is up. See client/loop.lua's +/- handlers.

    serverActionMaxDistance = 5.0, -- meters; default cap Target.runServerAction's server-side distance check enforces

    reticle = true,                -- draw a small centre-screen dot while holding the key, so targeting mode is VISIBLE even when nothing is under the crosshair (brightens over a target). Set false for a fully headless engine.
    demo = false,                  -- development-only global ped/vehicle targets; enable explicitly when testing qbtarget itself.
}

-- Registers this resource-owned configuration with qblib without changing its public Config table.
if QB and QB.config and QB.config.adopt then Config = QB.config.adopt(Config) end
