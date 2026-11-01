-- Fixed-world visual hints for coordinate target zones. The sprite is a
-- display-only affordance: selection still goes through client/loop.lua's
-- normal raycast/contains path, so a marker can never make an unavailable
-- option executable.

local function squaredDistance(a, b)
    local x, y, z = a.x - b.x, a.y - b.y, a.z - b.z
    return x * x + y * y + z * z
end

-- An explicit per-zone drawSprite = true can bypass the global switch, but only
-- while allowPerZoneOverride is on.
local function spriteAllowed(registration, settings)
    return settings.enabled or (settings.allowPerZoneOverride and registration.spriteOverride)
end

local function canDrawSprite(registration, playerCoords, settings)
    if not spriteAllowed(registration, settings) or registration.drawSprite == false or not registration.spriteCoords then
        return false
    end

    local maxDistance = settings.drawDistance
    return type(maxDistance) == 'number' and maxDistance > 0
        and squaredDistance(registration.spriteCoords, playerCoords) <= maxDistance * maxDistance
end

local textureRequested = {}

local function ensureTexture(dict)
    if not textureRequested[dict] then
        RequestStreamedTextureDict(dict, false)
        textureRequested[dict] = true
    end

    return HasStreamedTextureDictLoaded(dict)
end

-- Reused across frames: this loop runs at frame cadence whenever a sprite is
-- on screen, and a fresh candidate array per frame is pure garbage-collector
-- pressure for no benefit.
local nearbyZones = {}

-- Checked twice per iteration by the worker below (loop condition + restart
-- guard), at frame cadence while anything is drawing, so this must not be a
-- registry walk. client/state.lua keeps the count as zones are registered and
-- destroyed; drawSprite/spriteCoords are fixed at registration time and never
-- mutate afterwards, so a counter can't drift out of sync with a walk.
local function hasSpriteEnabledZone()
    local settings = Config.target.sprites
    if not settings then return false end
    if settings.enabled then return Target.hasSpriteZone() end

    return settings.allowPerZoneOverride == true and Target.hasSpriteOverrideZone()
end

-- Primary colour from kora_theme as r, g, b (0-255), or nil when the theme
-- resource is missing or returns something unusable. Cached: the theme only
-- changes on resource restart, and a failed lookup is retried at most every
-- 10 seconds so a late-starting kora_theme is still picked up.
local themeRGB, themeCheckedAt
local function themeColour()
    if themeRGB then return themeRGB end
    local now = GetGameTimer()
    if themeCheckedAt and now - themeCheckedAt < 10000 then return nil end
    themeCheckedAt = now
    if GetResourceState('kora_theme') ~= 'started' then return nil end
    local ok, hex = pcall(function() return exports.kora_theme:getPrimaryColor() end)
    if not ok or type(hex) ~= 'string' then return nil end
    local r, g, b = hex:match('^#?(%x%x)(%x%x)(%x%x)$')
    if not r then return nil end
    themeRGB = { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) }
    return themeRGB
end

local function drawZoneSprites()
    local settings = Config.target.sprites
    if not settings or not hasSpriteEnabledZone() then return false end
    if type(settings.dict) ~= 'string' or type(settings.name) ~= 'string' then return false end
    -- Hints are for finding interaction points; once the player holds the
    -- target key they are already aiming. Cheap flag read, no extra work.
    if settings.hideWhileTargeting and Target.active then return false end
    if not ensureTexture(settings.dict) then return false end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local offset = settings.offset or {}
    local colour = settings.colour or {}
    local cr, cg, cb = colour.r or 255, colour.g or 255, colour.b or 255
    if settings.useThemeColour ~= false then
        local theme = themeColour()
        if theme then cr, cg, cb = theme[1], theme[2], theme[3] end
    end
    local drewAny = false

    -- Broad phase first: a server with thousands of registered zones would
    -- otherwise walk every one of them, every frame, only to reject almost
    -- all of them on distance. canDrawSprite still runs the exact check.
    for i = #nearbyZones, 1, -1 do nearbyZones[i] = nil end
    Target.zonesWithin(playerCoords.x, playerCoords.y, settings.drawDistance or 0.0, nearbyZones)

    for i = 1, #nearbyZones do
        local registration = Target.registrations[nearbyZones[i]]
        if registration and canDrawSprite(registration, playerCoords, settings) then
            local coords = registration.spriteCoords
            local visible, screenX, screenY = GetScreenCoordFromWorldCoord(
                coords.x + (offset.x or 0.0),
                coords.y + (offset.y or 0.0),
                coords.z + (offset.z or 0.0))

            if visible then
                DrawSprite(settings.dict, settings.name, screenX, screenY,
                    settings.width or 0.015, settings.height or 0.02, 0.0,
                    cr, cg, cb, colour.a or 255)
                drewAny = true
            end
        end
    end

    return drewAny
end

local spriteThreadRunning = false

-- Zone registration calls this hook after adding a coordinate-backed target.
-- There is no worker at all while sprites are disabled or every zone opted out.
function Target._syncSpriteLoop()
    if spriteThreadRunning or not hasSpriteEnabledZone() then return false end
    spriteThreadRunning = true

    CreateThread(function()
        while hasSpriteEnabledZone() do
            local drewAny = drawZoneSprites()
            Wait(drewAny and 0 or 500)
        end

        spriteThreadRunning = false
        -- Close the tiny race where a new zone is registered after the loop's
        -- final predicate check but before the running flag is cleared.
        Target._syncSpriteLoop()
    end)

    return true
end

Target._syncSpriteLoop()

if Config.target.testMode then
    Target._testSprites = {
        canDraw = canDrawSprite,
        hasEnabledZone = hasSpriteEnabledZone,
        isRunning = function() return spriteThreadRunning end,
        squaredDistance = squaredDistance,
    }
end
