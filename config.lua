Config = {}

Config.target = {
    -- Hold this key to enter targeting mode (raycasting + drawing a prompt
    -- every tick). Uses FiveM's +/- command-pair convention, not a plain
    -- RegisterCommand, specifically so press vs release can be told apart.
    keybind = { command = 'qbtarget_hold', defaultKey = 'LMENU', label = 'Hold to target' },

    -- Press this key while a prompt is showing to run its option (or open a
    -- menu, if more than one option is available).
    selectKeybind = { command = 'qbtarget_select', defaultKey = 'E', label = 'Target: select / interact' },

    maxDistance = 10.0,            -- meters; QB.raycast.fromCamera's max reach while the hold key is down
    defaultOptionDistance = 2.5,   -- meters; fallback per-option interact distance when nothing more specific is set
    boneTolerance = 0.35,          -- meters; how close a raycast hit must land to a candidate bone to count as a match

    tickWhileHeld = 0,             -- ms Wait() between raycasts while the hold key is down (0 = every frame)
    tickIdle = 200,                -- ms Wait() while the hold key is up

    serverActionMaxDistance = 5.0, -- meters; default cap Target.runServerAction's server-side distance check enforces
}
