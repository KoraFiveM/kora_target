Config = {}

Config.target = {
    -- Hold this key to enter targeting mode (raycasting + drawing a prompt
    -- every tick). Uses FiveM's +/- command-pair convention, not a plain
    -- RegisterCommand, specifically so press vs release can be told apart.
    keybind = { command = 'target', defaultKey = 'LMENU', label = 'Hold to target' },

    -- Press this key while a prompt is showing to run its option (or open a
    -- menu, if more than one option is available).
    selectKeybind = { command = 'qbtarget_select', defaultKey = 'E', label = 'Target: select / interact' },

    maxDistance = 10.0,            -- meters; QB.raycast.fromCamera's max reach while the hold key is down
    defaultOptionDistance = 2.5,   -- meters; fallback per-option interact distance when nothing more specific is set
    boneTolerance = 0.35,          -- meters; how close a raycast hit must land to a candidate bone to count as a match

    tickWhileHeld = 0,             -- ms Wait() between raycasts while the hold key is down (0 = every frame)
    -- No idle tick: targeting runs on demand (a per-hold thread), so nothing
    -- polls while the key is up. See client/loop.lua's +target/-target handlers.

    serverActionMaxDistance = 5.0, -- meters; default cap Target.runServerAction's server-side distance check enforces

    reticle = true,                -- draw a small centre-screen dot while holding the key, so targeting mode is VISIBLE even when nothing is under the crosshair (brightens over a target). Set false for a fully headless engine.
    demo = true,                   -- register a demo "Inspect" option on all peds/vehicles at load, so holding the key + aiming at any ped/car shows a prompt out of the box. Turn OFF once real scripts register their own targets.
}
