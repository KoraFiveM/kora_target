Config = {}

-- Keep the raw value when this resource is loaded with an older kora_lib. The
-- descriptor makes this hot-path-safe setting editable live without changing
-- kora_target's public Config shape.
local configNumber = Kora and Kora.config and Kora.config.number

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

    -- Stuck-target recovery. Alt+Tab while holding the key swallows the key-up
    -- event, which used to leave targeting (and any legacy NUI focus) stuck on.
    -- While a session runs, a watchdog checks the physical key and cancel
    -- inputs and releases the session (no option is run) when needed.
    recovery = {
        enabled = true,          -- master switch for everything below
        releaseGraceMs = 250,    -- hold mode: ms the key must read "up" (after being seen down) before the session is dropped
        cancelOnPause = true,    -- cancel targeting when the pause menu opens
        cancelControls = true,   -- Escape, Backspace and right-click cancel targeting without selecting
        cancelOnFocusLoss = true,      -- drop the session/menu when the game window loses focus (Alt+Tab); uses IsGameWindowFocused and the NUI blur listener
        focusReleaseIgnoreMs = 1500,   -- hold mode: a key-up within this many ms of a focus loss cancels instead of selecting (0 disables)
        altControlFallback = true,     -- hold mode with the default LMENU key: read INPUT_CHARACTER_WHEEL (19) instead of the +command hash for key state
        menuIdleTimeoutMs = 30000,     -- close the option menu after this many ms without select/scroll input (0 disables)
        nuiListener = true,            -- act on blur/cancel events posted by ui/focus.html
        resetCommand = 'target-reset', -- chat/F8 command that force-clears targeting; false or "" disables it
    },

    maxDistance = 10.0,            -- meters; Kora.raycast.fromCamera's max reach while the hold key is down
    defaultOptionDistance = configNumber and configNumber(2.5, {
        label = 'Default option distance',
        description = 'How close players must be to use an interaction without its own distance setting, in metres. Changes apply immediately.',
        advanced = false,
        min = 0.1,
        max = 25.0,
        step = 0.1,
        live = true,
    }) or 2.5,                    -- meters; fallback per-option interact distance when nothing more specific is set
    legacyMaxDistance = 7.0,       -- qb-target Config.MaxDistance default used only by the qb-target compatibility surface
    legacyOutline = {              -- mirrors current qb-target's outline defaults
        enabled = false,
        colour = { 255, 255, 255, 255 },
    },
    boneTolerance = 0.35,          -- meters; how close a raycast hit must land to a candidate bone to count as a match

    -- Adaptive target-loop cadence. A scan happens immediately when targeting
    -- starts. It then polls slowly while no option is available and keeps a
    -- 20Hz resolver cadence while an option is visible.
    tickIdle = 150,                -- ms while targeting is disabled
    -- Resolver cadence while Alt is held. Prompt/reticle rendering remains
    -- frame-perfect in a separate lightweight loop; raycasts and option
    -- resolution run at 20Hz, matching the responsive split-loop approach
    -- used by ox_target without tying expensive native work to every frame.
    tickAcquire = 50,              -- ms while held with no available option
    tickActive = 50,               -- ms while an option is visible
    tickMiss = 100,                -- ms while held without an entity or available zone option
    staticMissRefresh = 500,       -- max ms between real scans while a miss remains perfectly motionless
    entityProbeInterval = 250,     -- ms between entity-only fallback rays when the broad ray reports no entity

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

    -- Development aid: draw kora_lib's full box/sphere/poly outline for every
    -- target zone. A zone registered with `debug = true` is also outlined
    -- when this is false; set this to true to inspect all zone bounds at once.
    debug = false,

    -- A lightweight, ox_target-style world sprite at each target-zone
    -- anchor. This deliberately only covers coordinate zones: entity/model/
    -- global targets have no single stable location, and scanning every game
    -- entity just to draw icons would be needlessly expensive.
    sprites = {
        enabled = false,
        -- When true, a zone registered with drawSprite = true shows its sprite
        -- even while `enabled` is false. Zones that do not set drawSprite are
        -- unaffected.
        allowPerZoneOverride = true,
        drawDistance = 20.0, -- meters; sprite draw work is skipped beyond this
        offset = { x = 0.0, y = 0.0, z = 0.45 },
        dict = 'shared',
        name = 'info',
        width = 0.015,
        height = 0.02,
        -- Fallback colour, also used when useThemeColour is false or kora_theme
        -- is not started.
        colour = { r = 30, g = 144, b = 255, a = 220 },
        -- Tint the icon with kora_theme's primary colour (alpha still comes from
        -- colour.a). Falls back to `colour` when kora_theme is unavailable.
        useThemeColour = true,
        -- Hide the icons while the target key is held: the player is already
        -- aiming, so the hints are only useful before that.
        hideWhileTargeting = true,
    },

    -- No idle thread when the key is up. See client/loop.lua's +/- handlers.

    serverActionMaxDistance = 5.0, -- meters; default cap Target.runServerAction's server-side distance check enforces

    -- What player movement does while the multi-option menu is open:
    --   'freeze' = hold the ped still and ignore movement keys (no walk-in-place)
    --   'close'  = pressing a movement key closes the menu; the player walks away
    --   'allow'  = free movement (closeMenuOutOfRange still applies)
    -- Leave it unset to follow the legacy freezeOnMenu flag below.
    menuMovement = nil,
    -- Legacy flag, still honoured when menuMovement is unset: true = 'freeze', false = 'allow'.
    freezeOnMenu = false,
    lockCameraOnMenu = false,      -- also lock the gameplay camera (look controls) while the menu is open
    closeMenuOutOfRange = true,    -- close the open menu when its target moves or the player walks out of range
    showCloseHint = false,         -- show the GTA help message "Press Escape to close" for a few seconds when the multiple-option menu opens; false (default) shows nothing. Escape still closes the menu and pause-menu suppression is unaffected
    suppressPauseOnClose = true,   -- Escape closes the option menu without also opening the GTA pause menu (pause controls are blocked while the menu is open and briefly after it closes). Set false to leave pause-key handling alone.
    pauseSuppressMs = 250,         -- how long (milliseconds, 0-2000) the pause controls stay blocked after the menu closes; only used when suppressPauseOnClose is true

    reticle = true,                -- draw a small centre-screen dot while holding the key, so targeting mode is VISIBLE even when nothing is under the crosshair (brightens over a target). Set false for a fully headless engine.
    demo = false,                  -- development-only global ped/vehicle targets; enable explicitly when testing kora_target itself.
}

-- Registers this resource-owned configuration with kora_lib without changing its public Config table.
if Kora and Kora.config and Kora.config.adopt then
    Config.target.sprites.offset.x = Kora.config.number(Config.target.sprites.offset.x, { label = 'Icon east-west offset (metres)', advanced = true })
    Config.target.sprites.offset.y = Kora.config.number(Config.target.sprites.offset.y, { label = 'Icon north-south offset (metres)', advanced = true })
    Config.target.sprites.offset.z = Kora.config.number(Config.target.sprites.offset.z, { label = 'Icon height offset (metres)', advanced = true })
    Config.target.sprites.colour.r = Kora.config.integer(Config.target.sprites.colour.r, { label = 'Icon red', advanced = false, min = 0, max = 255 })
    Config.target.sprites.colour.g = Kora.config.integer(Config.target.sprites.colour.g, { label = 'Icon green', advanced = false, min = 0, max = 255 })
    Config.target.sprites.colour.b = Kora.config.integer(Config.target.sprites.colour.b, { label = 'Icon blue', advanced = false, min = 0, max = 255 })
    Config.target.sprites.colour.a = Kora.config.integer(Config.target.sprites.colour.a, { label = 'Icon opacity', advanced = false, min = 0, max = 255 })
    Config.target.sprites.useThemeColour = Kora.config.boolean(Config.target.sprites.useThemeColour, { label = 'Tint icons with the theme colour', advanced = false })
    Config.target.sprites.hideWhileTargeting = Kora.config.boolean(Config.target.sprites.hideWhileTargeting, { label = 'Hide icons while targeting', advanced = false })
    Config.target.keybind.command = Kora.config.string(Config.target.keybind.command, { label = 'Target command', advanced = true })
    Config.target.keybind.defaultKey = Kora.config.string(Config.target.keybind.defaultKey, { label = 'Default target key', advanced = false })
    Config.target.keybind.label = Kora.config.string(Config.target.keybind.label, { label = 'Target key label', advanced = false })
    Config.target.legacyOutline.enabled = Kora.config.boolean(Config.target.legacyOutline.enabled, { label = 'Legacy entity outlines', advanced = false })
    Config.target.legacyOutline.colour = Kora.config.list(Config.target.legacyOutline.colour, Kora.config.integer(255, { min = 0, max = 255 }), { label = 'Legacy outline colour', advanced = false })
    Config.target.sprites.enabled = Kora.config.boolean(Config.target.sprites.enabled, { label = 'Show interaction location icons', advanced = false })
    Config.target.sprites.drawDistance = Kora.config.number(Config.target.sprites.drawDistance, { label = 'Location icon distance (metres)', advanced = false })
    Config.target.sprites.dict = Kora.config.string(Config.target.sprites.dict, { label = 'Icon texture collection', advanced = true })
    Config.target.sprites.name = Kora.config.string(Config.target.sprites.name, { label = 'Icon texture name', advanced = true })
    Config.target.sprites.width = Kora.config.number(Config.target.sprites.width, { label = 'Icon screen width', advanced = true })
    Config.target.sprites.height = Kora.config.number(Config.target.sprites.height, { label = 'Icon screen height', advanced = true })
    Config.target.freezeOnMenu = Kora.config.boolean(Config.target.freezeOnMenu, { label = 'Hold player still in option menu (legacy)', advanced = true })
    -- Unset menuMovement follows the legacy freezeOnMenu flag.
    local menuMovementDefault = Config.target.menuMovement
    if menuMovementDefault ~= 'freeze' and menuMovementDefault ~= 'close' and menuMovementDefault ~= 'allow' then
        menuMovementDefault = Config.target.freezeOnMenu and 'freeze' or 'allow'
    end
    Config.target.menuMovement = Kora.config.enum(menuMovementDefault, { label = 'Movement while option menu is open', advanced = false, options = { 'freeze', 'close', 'allow' } })
    Config.target.lockCameraOnMenu = Kora.config.boolean(Config.target.lockCameraOnMenu, { label = 'Lock camera while option menu is open', advanced = false })
    Config.target.closeMenuOutOfRange = Kora.config.boolean(Config.target.closeMenuOutOfRange, { label = 'Close option menu when out of range', advanced = false })
    Config.target.showCloseHint = Kora.config.boolean(Config.target.showCloseHint, { label = 'Show option menu close hint', advanced = false })
    Config.target.suppressPauseOnClose = Kora.config.boolean(Config.target.suppressPauseOnClose, { label = 'Block pause menu when closing option menu', advanced = false })
    Config.target.pauseSuppressMs = Kora.config.integer(Config.target.pauseSuppressMs, { label = 'Pause menu block time after closing (milliseconds)', advanced = true, min = 0, max = 2000 })
    Config.target.sprites.allowPerZoneOverride = Kora.config.boolean(Config.target.sprites.allowPerZoneOverride, { label = 'Let zones show icons individually', advanced = false })
    Config.target.toggle = Kora.config.boolean(Config.target.toggle, { label = 'Press to toggle targeting', advanced = false })
    Config.target.maxDistance = Kora.config.number(Config.target.maxDistance, { label = 'Target search distance (metres)', advanced = false })
    Config.target.legacyMaxDistance = Kora.config.number(Config.target.legacyMaxDistance, { label = 'Legacy target distance (metres)', advanced = true })
    Config.target.boneTolerance = Kora.config.number(Config.target.boneTolerance, { label = 'Vehicle part aim tolerance (metres)', advanced = true })
    Config.target.tickIdle = Kora.config.integer(Config.target.tickIdle, { label = 'Inactive check delay (milliseconds)', advanced = true, min = 0 })
    Config.target.tickAcquire = Kora.config.integer(Config.target.tickAcquire, { label = 'Unavailable target check delay (milliseconds)', advanced = true, min = 0 })
    Config.target.tickActive = Kora.config.integer(Config.target.tickActive, { label = 'Available target check delay (milliseconds)', advanced = true, min = 0 })
    Config.target.tickMiss = Kora.config.integer(Config.target.tickMiss, { label = 'Empty aim check delay (milliseconds)', advanced = true, min = 0 })
    Config.target.staticMissRefresh = Kora.config.integer(Config.target.staticMissRefresh, { label = 'Still empty aim refresh (milliseconds)', advanced = true, min = 0 })
    Config.target.entityProbeInterval = Kora.config.integer(Config.target.entityProbeInterval, { label = 'Extra entity search delay (milliseconds)', advanced = true, min = 0 })
    Config.target.staticRefresh = Kora.config.integer(Config.target.staticRefresh, { label = 'Still target refresh (milliseconds)', advanced = true, min = 0 })
    Config.target.canInteractCacheMs = Kora.config.integer(Config.target.canInteractCacheMs, { label = 'Available interaction reuse (milliseconds)', advanced = true, min = 0 })
    Config.target.canInteractFailureCacheMs = Kora.config.integer(Config.target.canInteractFailureCacheMs, { label = 'Unavailable interaction reuse (milliseconds)', advanced = true, min = 0 })
    Config.target.diagnostics = Kora.config.boolean(Config.target.diagnostics, { label = 'Log targeting performance', advanced = true })
    Config.target.diagnosticsInterval = Kora.config.integer(Config.target.diagnosticsInterval, { label = 'Performance log interval (milliseconds)', advanced = true, min = 0 })
    Config.target.debug = Kora.config.boolean(Config.target.debug, { label = 'Draw all target zone boundaries', advanced = true })
    Config.target.serverActionMaxDistance = Kora.config.number(Config.target.serverActionMaxDistance, { label = 'Server action distance cap (metres)', advanced = true })
    Config.target.reticle = Kora.config.boolean(Config.target.reticle, { label = 'Legacy aiming dot preference', advanced = true })
    Config.target.demo = Kora.config.boolean(Config.target.demo, { label = 'Enable demonstration interactions', advanced = true })
    Config = Kora.config.adopt(Config, { descriptions = {
        ['target.keybind.command'] = 'Internal command name used to start and stop targeting. Changing it can affect saved key bindings.',
        ['target.keybind.defaultKey'] = 'Key players use to target nearby interactions. Players can change their own binding in FiveM settings.',
        ['target.keybind.label'] = 'Text shown for the targeting key in the player key-binding settings.',
        ['target.toggle'] = 'Turn on to start and stop targeting with separate presses. Turn off to target only while holding the key.',
        ['target.maxDistance'] = 'Farthest point the targeting view checks. Each interaction still has its own allowed distance.',
        ['target.legacyMaxDistance'] = 'Fallback distance for interactions registered through qb-target compatibility.',
        ['target.legacyOutline.enabled'] = 'Allow the qb-target outline helper to outline non-pedestrian entities when a compatible script requests it.',
        ['target.legacyOutline.colour'] = 'Red, green, blue and opacity values used by the qb-target outline helper, in that order. Each uses 0 to 255.',
        ['target.boneTolerance'] = 'How close the aim must land to a named part, such as a vehicle door, for its interaction to match.',
        ['target.tickIdle'] = 'Delay used if the targeting worker finds targeting inactive.',
        ['target.tickAcquire'] = 'Time between checks while aiming at an entity with no available interaction. Lower values do more work.',
        ['target.tickActive'] = 'Time between interaction checks while an option is available. Lower values do more work.',
        ['target.tickMiss'] = 'Time between checks when no entity or available zone interaction is found.',
        ['target.staticMissRefresh'] = 'Maximum time to reuse an empty result while the camera and player remain motionless.',
        ['target.entityProbeInterval'] = 'Minimum time between extra searches for entities when the main aim check finds none.',
        ['target.staticRefresh'] = 'Maximum time to reuse a target result while the camera and player remain motionless. Zero disables reuse.',
        ['target.canInteractCacheMs'] = 'How long a successful availability check can be reused. Zero checks again every pass.',
        ['target.canInteractFailureCacheMs'] = 'How long a failed availability check can be reused. Longer values can delay newly available interactions.',
        ['target.diagnostics'] = 'Print targeting workload summaries for troubleshooting.',
        ['target.diagnosticsInterval'] = 'Time between workload summaries while performance logging is enabled and targeting runs.',
        ['target.debug'] = 'Show zone outlines for setup and troubleshooting. Individual zones may also request their own outlines.',
        ['target.menuMovement'] = 'Movement while the multiple-option menu is open: freeze holds the player still, close closes the menu when a movement key is pressed, allow lets the player move freely.',
        ['target.freezeOnMenu'] = 'Legacy: used as freeze (on) or allow (off) only when Movement while option menu is open was never set.',
        ['target.lockCameraOnMenu'] = 'Lock the gameplay camera while the multiple-option menu is open.',
        ['target.closeMenuOutOfRange'] = 'Close the multiple-option menu when its target is no longer within reach.',
        ['target.showCloseHint'] = 'Show the GTA help message explaining how to close the multiple-option menu for a few seconds when it opens. Off by default; Escape still closes the menu either way.',
        ['target.suppressPauseOnClose'] = 'Stop Escape from also opening the game pause menu when it closes the multiple-option menu. The pause keys are blocked while the menu is open and briefly after it closes.',
        ['target.pauseSuppressMs'] = 'How long the pause keys stay blocked after the multiple-option menu closes. Only used when the pause menu block is on.',
        ['target.sprites.allowPerZoneOverride'] = 'Allow a zone that asks for its own icon to show it even when location icons are turned off globally.',
        ['target.sprites.enabled'] = 'Show nearby icons for fixed interaction zones that allow them.',
        ['target.sprites.drawDistance'] = 'Maximum distance at which fixed interaction location icons are drawn.',
        ['target.sprites.offset'] = 'Move location icons away from their zone anchor using world directions.',
        ['target.sprites.offset.x'] = 'Position adjustment along the world X direction from the zone anchor.',
        ['target.sprites.offset.y'] = 'Position adjustment along the world Y direction from the zone anchor.',
        ['target.sprites.offset.z'] = 'Height added to the zone anchor when drawing its location icon.',
        ['target.sprites.dict'] = 'Game texture collection containing the location icon. Must match the icon texture name.',
        ['target.sprites.name'] = 'Game texture to draw from the selected texture collection.',
        ['target.sprites.width'] = 'Width of each location icon as a fraction of screen width.',
        ['target.sprites.height'] = 'Height of each location icon as a fraction of screen height.',
        ['target.sprites.colour.r'] = 'Red amount in location icons, from 0 to 255.',
        ['target.sprites.colour.g'] = 'Green amount in location icons, from 0 to 255.',
        ['target.sprites.colour.b'] = 'Blue amount in location icons, from 0 to 255.',
        ['target.sprites.colour.a'] = 'Location icon opacity, from 0 for invisible to 255 for solid.',
        ['target.serverActionMaxDistance'] = 'Maximum distance allowed for registered server actions. An action may choose a smaller limit.',
        ['target.reticle'] = 'Retained aiming-dot setting. The current targeting loop does not read this value.',
        ['target.demo'] = 'Add example pedestrian and vehicle interactions for testing.',
    } })
end
