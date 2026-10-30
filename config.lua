Config = {}

-- Keep the raw value when this resource is loaded with an older kora_lib. The
-- descriptor makes this hot-path-safe setting editable live without changing
-- kora_target's public Config shape.
local configNumber = QB and QB.config and QB.config.number

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
        colour = { r = 30, g = 144, b = 255, a = 220 },
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
    showCloseHint = true,          -- show a short "press to close" help message when the menu opens

    reticle = true,                -- draw a small centre-screen dot while holding the key, so targeting mode is VISIBLE even when nothing is under the crosshair (brightens over a target). Set false for a fully headless engine.
    demo = false,                  -- development-only global ped/vehicle targets; enable explicitly when testing kora_target itself.
}

-- Registers this resource-owned configuration with kora_lib without changing its public Config table.
if QB and QB.config and QB.config.adopt then
    Config.target.sprites.offset.x = QB.config.number(Config.target.sprites.offset.x, { label = 'Icon east-west offset (metres)', advanced = true })
    Config.target.sprites.offset.y = QB.config.number(Config.target.sprites.offset.y, { label = 'Icon north-south offset (metres)', advanced = true })
    Config.target.sprites.offset.z = QB.config.number(Config.target.sprites.offset.z, { label = 'Icon height offset (metres)', advanced = true })
    Config.target.sprites.colour.r = QB.config.integer(Config.target.sprites.colour.r, { label = 'Icon red', advanced = false, min = 0, max = 255 })
    Config.target.sprites.colour.g = QB.config.integer(Config.target.sprites.colour.g, { label = 'Icon green', advanced = false, min = 0, max = 255 })
    Config.target.sprites.colour.b = QB.config.integer(Config.target.sprites.colour.b, { label = 'Icon blue', advanced = false, min = 0, max = 255 })
    Config.target.sprites.colour.a = QB.config.integer(Config.target.sprites.colour.a, { label = 'Icon opacity', advanced = false, min = 0, max = 255 })
    Config.target.keybind.command = QB.config.string(Config.target.keybind.command, { label = 'Target command', advanced = true })
    Config.target.keybind.defaultKey = QB.config.string(Config.target.keybind.defaultKey, { label = 'Default target key', advanced = false })
    Config.target.keybind.label = QB.config.string(Config.target.keybind.label, { label = 'Target key label', advanced = false })
    Config.target.legacyOutline.enabled = QB.config.boolean(Config.target.legacyOutline.enabled, { label = 'Legacy entity outlines', advanced = false })
    Config.target.legacyOutline.colour = QB.config.list(Config.target.legacyOutline.colour, QB.config.integer(255, { min = 0, max = 255 }), { label = 'Legacy outline colour', advanced = false })
    Config.target.sprites.enabled = QB.config.boolean(Config.target.sprites.enabled, { label = 'Show interaction location icons', advanced = false })
    Config.target.sprites.drawDistance = QB.config.number(Config.target.sprites.drawDistance, { label = 'Location icon distance (metres)', advanced = false })
    Config.target.sprites.dict = QB.config.string(Config.target.sprites.dict, { label = 'Icon texture collection', advanced = true })
    Config.target.sprites.name = QB.config.string(Config.target.sprites.name, { label = 'Icon texture name', advanced = true })
    Config.target.sprites.width = QB.config.number(Config.target.sprites.width, { label = 'Icon screen width', advanced = true })
    Config.target.sprites.height = QB.config.number(Config.target.sprites.height, { label = 'Icon screen height', advanced = true })
    Config.target.freezeOnMenu = QB.config.boolean(Config.target.freezeOnMenu, { label = 'Hold player still in option menu (legacy)', advanced = true })
    -- Unset menuMovement follows the legacy freezeOnMenu flag.
    local menuMovementDefault = Config.target.menuMovement
    if menuMovementDefault ~= 'freeze' and menuMovementDefault ~= 'close' and menuMovementDefault ~= 'allow' then
        menuMovementDefault = Config.target.freezeOnMenu and 'freeze' or 'allow'
    end
    Config.target.menuMovement = QB.config.enum(menuMovementDefault, { label = 'Movement while option menu is open', advanced = false, options = { 'freeze', 'close', 'allow' } })
    Config.target.lockCameraOnMenu = QB.config.boolean(Config.target.lockCameraOnMenu, { label = 'Lock camera while option menu is open', advanced = false })
    Config.target.closeMenuOutOfRange = QB.config.boolean(Config.target.closeMenuOutOfRange, { label = 'Close option menu when out of range', advanced = false })
    Config.target.showCloseHint = QB.config.boolean(Config.target.showCloseHint, { label = 'Show option menu close hint', advanced = false })
    Config.target.sprites.allowPerZoneOverride = QB.config.boolean(Config.target.sprites.allowPerZoneOverride, { label = 'Let zones show icons individually', advanced = false })
    Config.target.toggle = QB.config.boolean(Config.target.toggle, { label = 'Press to toggle targeting', advanced = false })
    Config.target.maxDistance = QB.config.number(Config.target.maxDistance, { label = 'Target search distance (metres)', advanced = false })
    Config.target.legacyMaxDistance = QB.config.number(Config.target.legacyMaxDistance, { label = 'Legacy target distance (metres)', advanced = true })
    Config.target.boneTolerance = QB.config.number(Config.target.boneTolerance, { label = 'Vehicle part aim tolerance (metres)', advanced = true })
    Config.target.tickIdle = QB.config.integer(Config.target.tickIdle, { label = 'Inactive check delay (milliseconds)', advanced = true, min = 0 })
    Config.target.tickAcquire = QB.config.integer(Config.target.tickAcquire, { label = 'Unavailable target check delay (milliseconds)', advanced = true, min = 0 })
    Config.target.tickActive = QB.config.integer(Config.target.tickActive, { label = 'Available target check delay (milliseconds)', advanced = true, min = 0 })
    Config.target.tickMiss = QB.config.integer(Config.target.tickMiss, { label = 'Empty aim check delay (milliseconds)', advanced = true, min = 0 })
    Config.target.staticMissRefresh = QB.config.integer(Config.target.staticMissRefresh, { label = 'Still empty aim refresh (milliseconds)', advanced = true, min = 0 })
    Config.target.entityProbeInterval = QB.config.integer(Config.target.entityProbeInterval, { label = 'Extra entity search delay (milliseconds)', advanced = true, min = 0 })
    Config.target.staticRefresh = QB.config.integer(Config.target.staticRefresh, { label = 'Still target refresh (milliseconds)', advanced = true, min = 0 })
    Config.target.canInteractCacheMs = QB.config.integer(Config.target.canInteractCacheMs, { label = 'Available interaction reuse (milliseconds)', advanced = true, min = 0 })
    Config.target.canInteractFailureCacheMs = QB.config.integer(Config.target.canInteractFailureCacheMs, { label = 'Unavailable interaction reuse (milliseconds)', advanced = true, min = 0 })
    Config.target.diagnostics = QB.config.boolean(Config.target.diagnostics, { label = 'Log targeting performance', advanced = true })
    Config.target.diagnosticsInterval = QB.config.integer(Config.target.diagnosticsInterval, { label = 'Performance log interval (milliseconds)', advanced = true, min = 0 })
    Config.target.debug = QB.config.boolean(Config.target.debug, { label = 'Draw all target zone boundaries', advanced = true })
    Config.target.serverActionMaxDistance = QB.config.number(Config.target.serverActionMaxDistance, { label = 'Server action distance cap (metres)', advanced = true })
    Config.target.reticle = QB.config.boolean(Config.target.reticle, { label = 'Legacy aiming dot preference', advanced = true })
    Config.target.demo = QB.config.boolean(Config.target.demo, { label = 'Enable demonstration interactions', advanced = true })
    Config = QB.config.adopt(Config, { descriptions = {
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
        ['target.showCloseHint'] = 'Show a short message explaining how to close the multiple-option menu.',
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
