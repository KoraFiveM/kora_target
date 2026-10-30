---@alias QBTargetGlobalType "ped" | "vehicle" | "object" | "player"

---@class QBTargetOption
---@field label string
---@field icon? string
---@field distance? number Overrides the registration's own default distance.
---@field bones? string[] Restricts this option to specific bone names.
---@field canInteract? fun(entity: number|nil, distance: number, data: any): boolean
---@field onSelect fun(entity: number|nil, data: any)
---@field data? any
---@field item? string Opaque passthrough -- never interpreted, see docs.md.
---@field job? string|table Opaque passthrough -- never interpreted, see docs.md.
---@field gang? string|table Opaque passthrough -- never interpreted, see docs.md.
---@field groups? string|table Opaque passthrough -- never interpreted, see docs.md.

Target = Target or {}

Target.registrations = {}  -- id -> {id, kind, options, distance, entities?/models?/entityType?/bones?, zoneHandle?}
Target.byEntity = {}       -- entity -> {[id]=true}
Target.byModel = {}        -- modelHash -> {[id]=true}
Target.byGlobalType = {}   -- "ped"|"vehicle"|"object"|"player" -> {[id]=true}
Target.byGlobalBone = {}   -- id -> {boneNames}
Target.byZone = {}         -- id -> true, every zone-kind registration id (client/loop.lua tests zoneHandle.contains(hitCoords) against each)
Target.enabled = true
Target.hovering = nil      -- maintained by client/loop.lua each tick
Target.active = false      -- true while the targeting key/toggle is active
Target.success = false     -- true while at least one candidate is resolved
-- Tracks only the qbtarget_debug command's own on/off state (client/loop.lua)
-- so its no-arg toggle has something local to flip against -- separate from
-- Config.target.debug, which stays the creation-time default and is never
-- mutated at runtime.
Target.debugEnabled = false
-- Monotonic local generation used by loop.lua to invalidate its aim cache as
-- soon as a registration changes. This is not exposed as API state.
Target.registrationRevision = 0

-- kora_multichar sets this replicated state for its character, spawn, and scene
-- editor modes. Targeting the preview world would expose real gameplay
-- actions (beds, banking, doors, etc.) while the player is choosing a spawn.
function Target.interactionsLocked()
    local state = LocalPlayer and LocalPlayer.state
    local mode = state and state['qbmultichar:mode']
    return mode ~= nil and mode ~= false
end

local function touchRegistrations()
    Target.registrationRevision = Target.registrationRevision + 1
end

local nextRegistrationId = 0

local function nextId()
    nextRegistrationId = nextRegistrationId + 1
    return nextRegistrationId
end

-- FXServer's exports boundary hands a cross-resource function argument back
-- as a table with a __call metamethod, not a plain Lua function -- a
-- resource-local copy of the same check kora_lib's own modules use (see e.g.
-- kora_lib/modules/zones/client.lua), since kora_target is a separate resource
-- shared through kora_lib so every compatibility boundary recognizes the same shapes.
local isCallable = QB.util.isCallable

-- A "coords-like" value: a table with numeric x/y/z, satisfied by both a
-- real vector3 and a plain {x=, y=, z=} table (both are accepted throughout
-- this file). Used to validate addBoxZone/addSphereZone/addPolyZone's
-- coords/size/points BEFORE handing them to QB.zones.* -- unlike `options`,
-- these were previously passed through unchecked, so a malformed call only
-- failed with an opaque error from deep inside kora_lib.
local function isCoordsLike(x)
    -- Deliberately does NOT gate on type(x) == "table" first: FiveM natives
    -- like GetEntityCoords return vector3 values whose Lua type() is
    -- "vector3", not "table" (mirrors kora_lib/modules/zones/client.lua's
    -- toVec3). pcall guards the field reads so a bare number/nil/boolean
    -- fails the check instead of erroring on the index.
    local ok, isNum = pcall(function()
        return type(x.x) == "number" and type(x.y) == "number" and type(x.z) == "number"
    end)
    return ok and isNum
end

-- kora_lib owns the actual debug shape rendering. Keeping the choice here means
-- callers can still opt one zone into debugging, while Config.target.debug is
-- a convenient server-wide override when laying out or diagnosing zones.
local function zoneDebugEnabled(zoneOptions)
    return Config.target.debug == true or zoneOptions.debug == true
end

local function copyCoords(coords)
    return { x = coords.x, y = coords.y, z = coords.z }
end

-- A poly has no supplied centre. Its mean vertex position is a stable and
-- intuitive icon anchor even for concave shapes; it is only a visual hint and
-- does not participate in the zone's actual containment test.
local function polySpriteCoords(points)
    local x, y, z = 0.0, 0.0, 0.0
    for _, point in ipairs(points) do
        x, y, z = x + point.x, y + point.y, z + point.z
    end

    local count = #points
    return { x = x / count, y = y / count, z = z / count }
end

local GLOBAL_TYPES = { ped = true, vehicle = true, object = true, player = true }

---A bare entity/model/bone value is wrapped as a one-element array; an
---already-array-shaped value (multiple entities/models/bones in one call) is
---used as-is. Entity handles and model hashes/names are never themselves
---tables, so "is it a table" is enough to tell the two apart.
---@param value any
---@return table
local function toArray(value)
    if value == nil then return {} end
    if type(value) == "table" then return value end
    return { value }
end

local function hashModel(model)
    return type(model) == "string" and joaat(model) or model
end

---@param options QBTargetOption[]
---@return QBTargetOption[]
local function validateOptions(options)
    assert(type(options) == "table" and #options > 0, "options must be a non-empty array of target options.")

    for i, option in ipairs(options) do
        assert(type(option) == "table", ("options[%d] must be a table."):format(i))
        assert(type(option.label) == "string" and #option.label > 0,
            ("options[%d].label must be a non-empty string."):format(i))
        assert(isCallable(option.onSelect), ("options[%d].onSelect must be a function."):format(i))
        assert(option.canInteract == nil or isCallable(option.canInteract),
            ("options[%d].canInteract must be a function."):format(i))
        assert(option.distance == nil or type(option.distance) == "number",
            ("options[%d].distance must be a number."):format(i))
        assert(option.bones == nil or type(option.bones) == "table",
            ("options[%d].bones must be an array of bone names."):format(i))
    end

    return options
end

---Internal compatibility hook: atomically replaces a live registration's
---options/default distance and invalidates the resolver caches. It is kept off
---client/exports.lua; qb-target's labeled remove/update API needs option-level
---mutation while kora_target's native public API remains registration-oriented.
---@param id integer
---@param options QBTargetOption[]
---@param defaultDistance? number
---@return boolean updated
function Target._replaceOptions(id, options, defaultDistance)
    local registration = Target.registrations[id]
    if not registration then return false end
    registration.options = validateOptions(options)
    registration.distance = defaultDistance
    touchRegistrations()
    return true
end

---Applies the active target configuration received from kora_lib. The resolver
---reads Config.target at evaluation time, but its broad-phase maximum and
---aim result are revision-cached; touching registrations makes a changed
---default distance take effect on the very next resolver pass.
---@param settings table
function Target.applyConfig(settings)
    if type(settings) ~= 'table' then return end
    Config.target = settings
    touchRegistrations()
end

local function addToIndex(index, key, id)
    local set = index[key]
    if not set then
        set = {}
        index[key] = set
    end
    set[id] = true
end

local function removeFromIndex(index, key, id)
    local set = index[key]
    if not set then return end
    set[id] = nil
    if next(set) == nil then index[key] = nil end
end

local function syncSpriteLoop()
    if Target._syncSpriteLoop then Target._syncSpriteLoop() end
end

-- ---------------------------------------------------------------------------
-- Zone broad phase
--
-- Every zone-kind registration used to be tested with its own
-- `zoneHandle.contains(hitCoords)` on every resolver tick (client/loop.lua).
-- That is fine for a handful of zones and quadratic-feeling on a real server:
-- a qb-target-compatible install routinely registers hundreds-to-thousands of
-- zones (every shop, job point, garage and stash), and 20Hz x N point-in-poly
-- tests while Alt is held is the single largest cost the resolver had.
--
-- This is a uniform XY grid over each zone's axis-aligned bounding box,
-- mirroring the one kora_lib's own modules/zones already keeps for its
-- enter/exit tick (which kora_target cannot reuse -- that grid answers "which
-- zones are near the PLAYER", and kora_target deliberately resolves against the
-- AIM point instead; kora_lib exposes no point query over it either).
--
-- A zone is inserted into EVERY cell its AABB overlaps, so a point query only
-- ever has to look at the single cell containing that point -- no 3x3
-- neighbourhood, no radius padding. The AABB is then re-tested exactly before
-- the real `contains` predicate runs, so the grid only ever removes work; it
-- never decides containment.
--
-- Zones whose extent cannot be known (an arbitrary `contains` predicate from
-- the qb-target ComboZone/EntityZone bridges, or a moving entity zone) go in
-- `zoneUnbounded` and are still scanned every tick, exactly as before. That
-- is the safe fallback: a missing bound costs performance, never correctness.
-- ---------------------------------------------------------------------------
local ZONE_CELL_SIZE = 50.0

-- A bound that spans more cells than this is treated as unbounded rather than
-- written into thousands of buckets. Nothing legitimate in a target resource
-- is 3km across, and an accidental huge zone must not make registration itself
-- expensive.
local ZONE_MAX_CELL_SPAN = 64

local zoneGrid = {}        -- cellKey -> { [id] = true }
local zoneCellsOf = {}     -- id -> { cellKey, ... }
local zoneBoundsOf = {}    -- id -> aabb, absent for an unbounded zone
local zoneUnbounded = {}   -- id -> true
local zonesWithinSeen = {} -- scratch, see Target.zonesWithin
local spriteZoneCount = 0
local spriteOverrideCount = 0

-- Same packing kora_lib/modules/zones/client.lua uses: the world is roughly
-- +/-8000m, so at 50m cells the component magnitude stays far below the
-- 100000 stride and can never alias another cell.
local function zoneCellKey(cx, cy)
    return cx * 100000 + cy
end

local function zoneCell(x, y)
    return math.floor(x / ZONE_CELL_SIZE), math.floor(y / ZONE_CELL_SIZE)
end

local function boundsContain(bounds, point)
    return point.x >= bounds.minX and point.x <= bounds.maxX
        and point.y >= bounds.minY and point.y <= bounds.maxY
        and point.z >= bounds.minZ and point.z <= bounds.maxZ
end

---Registers a zone id in the broad phase. `bounds` is an
---{minX,maxX,minY,maxY,minZ,maxZ} AABB that must fully CONTAIN the zone --
---an over-large box only costs a wasted exact test, an under-sized one would
---silently hide the zone. Pass nil when the extent isn't knowable.
---@param id integer
---@param bounds table?
local function indexZone(id, bounds)
    if not bounds then
        zoneUnbounded[id] = true
        return
    end

    local minCx, minCy = zoneCell(bounds.minX, bounds.minY)
    local maxCx, maxCy = zoneCell(bounds.maxX, bounds.maxY)

    if (maxCx - minCx + 1) > ZONE_MAX_CELL_SPAN or (maxCy - minCy + 1) > ZONE_MAX_CELL_SPAN then
        zoneUnbounded[id] = true
        return
    end

    local cells = {}
    for cx = minCx, maxCx do
        for cy = minCy, maxCy do
            local key = zoneCellKey(cx, cy)
            local bucket = zoneGrid[key]
            if not bucket then
                bucket = {}
                zoneGrid[key] = bucket
            end
            bucket[id] = true
            cells[#cells + 1] = key
        end
    end

    zoneCellsOf[id] = cells
    zoneBoundsOf[id] = bounds
end

local function unindexZone(id)
    zoneUnbounded[id] = nil
    zoneBoundsOf[id] = nil

    local cells = zoneCellsOf[id]
    if not cells then return end
    zoneCellsOf[id] = nil

    for i = 1, #cells do
        local bucket = zoneGrid[cells[i]]
        if bucket then
            bucket[id] = nil
            if next(bucket) == nil then zoneGrid[cells[i]] = nil end
        end
    end
end

---Every zone-kind registration id whose bounds could possibly contain
---`point`, appended to `out`. The caller still has to run each zone's real
---`contains` predicate -- this only skips the ones that provably cannot match.
---@param point table {x, y, z}
---@param out integer[] Reused by the caller; cleared by it, not here.
---@return integer[] out
function Target.zonesNear(point, out)
    local bucket = zoneGrid[zoneCellKey(zoneCell(point.x, point.y))]

    if bucket then
        for id in pairs(bucket) do
            if boundsContain(zoneBoundsOf[id], point) then out[#out + 1] = id end
        end
    end

    for id in pairs(zoneUnbounded) do
        out[#out + 1] = id
    end

    return out
end

---Every zone-kind registration whose bounds fall within `radius` of the given
---XY position, appended to `out`. Used by the sprite loop, which cares about a
---disc around the player rather than a single aim point, so unlike
---`Target.zonesNear` it has to sweep the covered cells.
---@param x number
---@param y number
---@param radius number
---@param out integer[]
---@return integer[] out
function Target.zonesWithin(x, y, radius, out)
    local minCx, minCy = zoneCell(x - radius, y - radius)
    local maxCx, maxCy = zoneCell(x + radius, y + radius)

    -- A zone wider than one cell lives in several buckets, so an area sweep
    -- (unlike the single-cell Target.zonesNear) can see the same id twice.
    -- Reused rather than allocated per call: the sprite loop runs at frame
    -- cadence.
    local seen = zonesWithinSeen
    for id in pairs(seen) do seen[id] = nil end

    for cx = minCx, maxCx do
        for cy = minCy, maxCy do
            local bucket = zoneGrid[zoneCellKey(cx, cy)]
            if bucket then
                for id in pairs(bucket) do
                    if not seen[id] then
                        seen[id] = true
                        out[#out + 1] = id
                    end
                end
            end
        end
    end

    for id in pairs(zoneUnbounded) do
        out[#out + 1] = id
    end

    return out
end

---True when at least one registered zone would draw a sprite. A counter
---rather than a registry walk because client/sprites.lua checks this twice
---per frame while any sprite is on screen.
---@return boolean
function Target.hasSpriteZone()
    return spriteZoneCount > 0
end

---True when a zone explicitly asked for drawSprite = true, which can show its
---sprite even while sprites are globally disabled.
---@return boolean
function Target.hasSpriteOverrideZone()
    return spriteOverrideCount > 0
end

-- The largest interact distance any zone option can use. client/loop.lua
-- compares it against the ped->aim-point distance, which is identical for
-- every zone candidate in a given tick (a zone candidate's anchor IS the
-- raycast hit), so a single comparison can skip the entire zone pass. Cached
-- against the registration generation because option distances are mutable
-- via Target._replaceOptions.
local maxZoneOptionDistance, maxZoneOptionRevision = 0.0, -1

---@return number
function Target.maxZoneOptionDistance()
    if maxZoneOptionRevision == Target.registrationRevision then return maxZoneOptionDistance end

    local largest = 0.0
    for id in pairs(Target.byZone) do
        local registration = Target.registrations[id]
        if registration then
            for _, option in ipairs(registration.options) do
                local distance = option.distance or registration.distance or Config.target.defaultOptionDistance
                if distance > largest then largest = distance end
            end
        end
    end

    maxZoneOptionDistance, maxZoneOptionRevision = largest, Target.registrationRevision
    return largest
end

---Shared tail of every zone constructor: publishes the registration, indexes
---it for the broad phase, and keeps the sprite counter honest.
---@param id integer
---@param registration table
---@param bounds table? See indexZone.
local function registerZone(id, registration, bounds)
    Target.registrations[id] = registration
    Target.byZone[id] = true
    indexZone(id, bounds)
    if registration.drawSprite and registration.spriteCoords then
        spriteZoneCount = spriteZoneCount + 1
        if registration.spriteOverride then spriteOverrideCount = spriteOverrideCount + 1 end
    end
    syncSpriteLoop()
    touchRegistrations()
end

---Undoes registerZone's bookkeeping. Called from Target.destroyRegistration.
---@param id integer
---@param registration table
local function unregisterZone(id, registration)
    Target.byZone[id] = nil
    unindexZone(id)
    if registration.drawSprite and registration.spriteCoords then
        spriteZoneCount = spriteZoneCount - 1
        if registration.spriteOverride then spriteOverrideCount = spriteOverrideCount - 1 end
    end
end

-- Bounds builders. Each returns an AABB that fully contains the shape, or nil
-- when it cannot be derived (see indexZone).
local function boxBounds(coords, size, rotation)
    local radians = math.rad(rotation or 0.0)
    local cosR, sinR = math.abs(math.cos(radians)), math.abs(math.sin(radians))
    local halfX, halfY = size.x / 2, size.y / 2
    -- Rotating a box only ever grows its axis-aligned footprint, so the
    -- rotated half-extents below are the exact enclosing AABB, not padding.
    local extentX = halfX * cosR + halfY * sinR
    local extentY = halfX * sinR + halfY * cosR
    local halfZ = size.z / 2

    return {
        minX = coords.x - extentX, maxX = coords.x + extentX,
        minY = coords.y - extentY, maxY = coords.y + extentY,
        minZ = coords.z - halfZ, maxZ = coords.z + halfZ,
    }
end

local function sphereBounds(coords, radius)
    return {
        minX = coords.x - radius, maxX = coords.x + radius,
        minY = coords.y - radius, maxY = coords.y + radius,
        minZ = coords.z - radius, maxZ = coords.z + radius,
    }
end

-- minZ/maxZ are only known when the caller gave them explicitly: kora_lib
-- derives an implicit band from `thickness` against its own config default,
-- which lives in kora_lib's environment and isn't readable from here. An
-- unbounded vertical band is the correct conservative answer -- the grid is
-- indexed on XY only, so a tall AABB costs at most one wasted exact test and
-- can never hide a zone.
local function polyBounds(points, minZ, maxZ)
    local bounds = {
        minX = math.huge, maxX = -math.huge,
        minY = math.huge, maxY = -math.huge,
        minZ = minZ or -math.huge, maxZ = maxZ or math.huge,
    }

    for _, point in ipairs(points) do
        if point.x < bounds.minX then bounds.minX = point.x end
        if point.x > bounds.maxX then bounds.maxX = point.x end
        if point.y < bounds.minY then bounds.minY = point.y end
        if point.y > bounds.maxY then bounds.maxY = point.y end
    end

    return bounds
end


---Every id still owned by `id` collected into a plain array before any of
---them are torn down -- destroyRegistration mutates the very index tables
---these ids are read from, so walking `pairs(set)` while destroying entries
---out from under it would skip entries or invalidate the iterator mid-walk.
---@param set table<integer, boolean>?
---@return integer[]
local function idsOf(set)
    local ids = {}
    if set then
        for id in pairs(set) do ids[#ids + 1] = id end
    end
    return ids
end

---Tears a registration down: drops it from every index it appears in and,
---for a zone-backed registration, removes the underlying kora_lib zone. Safe to
---call more than once for the same id (a no-op after the first).
---@param id integer
function Target.destroyRegistration(id)
    local registration = Target.registrations[id]
    if not registration then return end

    Target.registrations[id] = nil
    touchRegistrations()
    Target.ownership.untrack(id)

    if registration.kind == "entity" then
        for _, entity in ipairs(registration.entities) do
            removeFromIndex(Target.byEntity, entity, id)
        end
    elseif registration.kind == "model" then
        for _, model in ipairs(registration.models) do
            removeFromIndex(Target.byModel, model, id)
        end
    elseif registration.kind == "globalType" then
        removeFromIndex(Target.byGlobalType, registration.entityType, id)
    elseif registration.kind == "globalBone" then
        Target.byGlobalBone[id] = nil
    elseif registration.kind == "zone" then
        -- The double-layer-ownership fix: QB.zones.box/sphere/poly attribute
        -- the zone's own qblib-internal cleanup to whichever resource called
        -- INTO kora_lib -- which is "qbtarget" itself when a third-party
        -- consumer called exports.kora_target:addBoxZone, not that consumer.
        -- kora_lib's own cleanup-on-stop therefore never fires for the real
        -- consumer stopping; Target.ownership above (tracked against the
        -- REAL invoking resource, captured in Target.addBoxZone/etc before
        -- ever calling into QB.zones.*) is what has to proactively tear the
        -- underlying zone down here. See AGENTS.md "Ownership subtlety".
        unregisterZone(id, registration)
        if registration.zoneHandle then registration.zoneHandle.remove() end
    end
end

-- Keep caller ownership separate from kora_lib's zone ownership: kora_lib sees
-- kora_target as its caller, while this registry tracks the original resource
-- that crossed kora_target's export boundary.
Target.ownership = QB.resources.registry(function(id)
    Target.destroyRegistration(id)
end)

---Shared by addEntity/addModel/addGlobalType/addGlobalBone: validates
---options, allocates an id, captures the real invoking resource, and tracks
---ownership. Zone registrations don't use this -- they need the id BEFORE
---creating the underlying kora_lib zone (so it can be stamped onto the zone's
---own `data` field), so they build their registration record directly.
---@param kind string
---@param extra table Additional fields merged onto the registration (e.g. `entities`, `models`).
---@param options QBTargetOption[]
---@param defaultDistance number?
---@return table registration
local function register(kind, extra, options, defaultDistance)
    options = validateOptions(options)

    local id = nextId()
    local owner = GetInvokingResource() or GetCurrentResourceName()

    local registration = { id = id, kind = kind, options = options, distance = defaultDistance }
    for k, v in pairs(extra) do registration[k] = v end

    Target.registrations[id] = registration
    touchRegistrations()
    Target.ownership.track(owner, id)

    return registration
end

---Registers target options on one or more specific entity handles.
---@param entity number|number[]
---@param options QBTargetOption[]
---@param defaultDistance? number
---@return integer id
function Target.addEntity(entity, options, defaultDistance)
    local entities = toArray(entity)
    assert(#entities > 0, "addEntity requires at least one entity handle.")
    for _, e in ipairs(entities) do
        assert(type(e) == "number", "Entity handles must be numbers.")
    end

    local registration = register("entity", { entities = entities }, options, defaultDistance)
    for _, e in ipairs(entities) do addToIndex(Target.byEntity, e, registration.id) end

    return registration.id
end

---Removes entity-scoped target registrations. Note this removes whole
---registrations, not individual options -- a registration created with
---multiple entities in one addEntity call is torn down entirely, on every
---entity it covers, not just the one passed here.
---@param entity number
---@param id? integer When given, only that registration is removed. Otherwise every registration touching `entity` is.
---@return boolean removed
function Target.removeEntity(entity, id)
    assert(type(entity) == "number", "entity must be a number.")

    if id then
        Target.destroyRegistration(id)
        return true
    end

    local ids = idsOf(Target.byEntity[entity])
    if #ids == 0 then return false end

    for _, regId in ipairs(ids) do Target.destroyRegistration(regId) end
    return true
end

---Registers target options on every current and future entity spawned with
---any of the given models.
---@param model number|string|(number|string)[]
---@param options QBTargetOption[]
---@param defaultDistance? number
---@return integer id
function Target.addModel(model, options, defaultDistance)
    local rawModels = toArray(model)
    assert(#rawModels > 0, "addModel requires at least one model.")

    local models = {}
    for i, m in ipairs(rawModels) do
        assert(type(m) == "string" or type(m) == "number", "Models must be strings or numbers.")
        models[i] = hashModel(m)
    end

    local registration = register("model", { models = models }, options, defaultDistance)
    for _, m in ipairs(models) do addToIndex(Target.byModel, m, registration.id) end

    return registration.id
end

---Removes model-scoped target registrations. Same whole-registration removal
---semantics as removeEntity -- see its docs.
---@param model number|string|(number|string)[]
---@param id? integer When given, only that registration is removed.
---@return boolean removed
function Target.removeModel(model, id)
    if id then
        Target.destroyRegistration(id)
        return true
    end

    local removedAny = false
    for _, m in ipairs(toArray(model)) do
        local ids = idsOf(Target.byModel[hashModel(m)])
        for _, regId in ipairs(ids) do
            Target.destroyRegistration(regId)
            removedAny = true
        end
    end

    return removedAny
end

---Registers target options on every entity of a given type -- e.g. every ped
---in the world, or every player.
---@param entityType QBTargetGlobalType
---@param options QBTargetOption[]
---@param defaultDistance? number
---@return integer id
function Target.addGlobalType(entityType, options, defaultDistance)
    assert(GLOBAL_TYPES[entityType], "entityType must be 'ped', 'vehicle', 'object', or 'player'.")

    local registration = register("globalType", { entityType = entityType }, options, defaultDistance)
    addToIndex(Target.byGlobalType, entityType, registration.id)

    return registration.id
end

---@param entityType QBTargetGlobalType
---@param id? integer When given, only that registration is removed.
---@return boolean removed
function Target.removeGlobalType(entityType, id)
    assert(GLOBAL_TYPES[entityType], "entityType must be 'ped', 'vehicle', 'object', or 'player'.")

    if id then
        Target.destroyRegistration(id)
        return true
    end

    local ids = idsOf(Target.byGlobalType[entityType])
    if #ids == 0 then return false end

    for _, regId in ipairs(ids) do Target.destroyRegistration(regId) end
    return true
end

---Registers target options on ANY entity, of any type, that has a matching
---bone -- e.g. every vehicle's "boot" bone, regardless of vehicle model.
---@param bones string|string[]
---@param options QBTargetOption[]
---@param defaultDistance? number
---@return integer id
function Target.addGlobalBone(bones, options, defaultDistance)
    local boneList = toArray(bones)
    assert(#boneList > 0, "addGlobalBone requires at least one bone name.")
    for _, bone in ipairs(boneList) do
        assert(type(bone) == "string", "Bone names must be strings.")
    end

    local registration = register("globalBone", { bones = boneList }, options, defaultDistance)
    Target.byGlobalBone[registration.id] = boneList

    return registration.id
end

---@param id integer
---@return boolean removed
function Target.removeGlobalBone(id)
    Target.destroyRegistration(id)
    return true
end

---Sugar over addEntity: registers `options` on `entity`, forcing every one
---of them onto `bone` specifically, so a caller doesn't have to repeat
---`bones = { bone }` on each option itself.
---@param entity number
---@param bone string
---@param options QBTargetOption[]
---@param defaultDistance? number
---@return integer id
function Target.addTargetBone(entity, bone, options, defaultDistance)
    assert(type(bone) == "string", "bone must be a string.")
    assert(type(options) == "table" and #options > 0, "options must be a non-empty array of target options.")

    local boned = {}
    for i, option in ipairs(options) do
        local copy = {}
        for k, v in pairs(option) do copy[k] = v end
        copy.bones = { bone }
        boned[i] = copy
    end

    return Target.addEntity(entity, boned, defaultDistance)
end

---@class QBTargetBoxZoneOptions
---@field coords any Box center.
---@field size any Full extents (x, y, z).
---@field rotation? number Degrees around the Z axis.
---@field options QBTargetOption[]
---@field distance? number
---@field debug? boolean
---@field drawSprite? boolean Set false to hide this zone's configured sprite.

---@param zoneOptions QBTargetBoxZoneOptions
---@return integer id
function Target.addBoxZone(zoneOptions)
    assert(type(zoneOptions) == "table", "addBoxZone requires an options table.")
    assert(isCoordsLike(zoneOptions.coords), "addBoxZone requires zoneOptions.coords to be a table with numeric x/y/z.")
    assert(isCoordsLike(zoneOptions.size), "addBoxZone requires zoneOptions.size to be a table with numeric x/y/z.")

    local options = validateOptions(zoneOptions.options)
    local id = nextId()

    -- Captured HERE, before calling into QB.zones.box -- see the "Ownership
    -- subtlety" note on destroyRegistration/Target.ownership above and in
    -- AGENTS.md. By the time QB.zones.box resolves its own
    -- GetInvokingResource(), the caller will read as "kora_target", not the
    -- real external consumer.
    local owner = GetInvokingResource() or GetCurrentResourceName()

    local zoneHandle = QB.zones.box({
        coords = zoneOptions.coords,
        size = zoneOptions.size,
        rotation = zoneOptions.rotation,
        debug = zoneDebugEnabled(zoneOptions),
        trackPlayer = false,
    })

    registerZone(id, {
        id = id,
        kind = "zone",
        options = options,
        distance = zoneOptions.distance,
        zoneHandle = zoneHandle,
        spriteCoords = copyCoords(zoneOptions.coords),
        drawSprite = zoneOptions.drawSprite ~= false,
        spriteOverride = zoneOptions.drawSprite == true,
    }, boxBounds(zoneOptions.coords, zoneOptions.size, zoneOptions.rotation))
    Target.ownership.track(owner, id)

    return id
end

---@class QBTargetSphereZoneOptions
---@field coords any Sphere center.
---@field radius number
---@field options QBTargetOption[]
---@field distance? number
---@field debug? boolean
---@field drawSprite? boolean Set false to hide this zone's configured sprite.

---@param zoneOptions QBTargetSphereZoneOptions
---@return integer id
function Target.addSphereZone(zoneOptions)
    assert(type(zoneOptions) == "table", "addSphereZone requires an options table.")
    assert(isCoordsLike(zoneOptions.coords), "addSphereZone requires zoneOptions.coords to be a table with numeric x/y/z.")
    assert(type(zoneOptions.radius) == "number" and zoneOptions.radius > 0,
        "addSphereZone requires zoneOptions.radius to be a positive number.")

    local options = validateOptions(zoneOptions.options)
    local id = nextId()
    local owner = GetInvokingResource() or GetCurrentResourceName()

    local zoneHandle = QB.zones.sphere({
        coords = zoneOptions.coords,
        radius = zoneOptions.radius,
        debug = zoneDebugEnabled(zoneOptions),
        trackPlayer = false,
    })

    registerZone(id, {
        id = id,
        kind = "zone",
        options = options,
        distance = zoneOptions.distance,
        zoneHandle = zoneHandle,
        spriteCoords = copyCoords(zoneOptions.coords),
        drawSprite = zoneOptions.drawSprite ~= false,
        spriteOverride = zoneOptions.drawSprite == true,
    }, sphereBounds(zoneOptions.coords, zoneOptions.radius))
    Target.ownership.track(owner, id)

    return id
end

---@class QBTargetPolyZoneOptions
---@field points any[] At least 3 points.
---@field thickness? number
---@field minZ? number
---@field maxZ? number
---@field options QBTargetOption[]
---@field distance? number
---@field debug? boolean
---@field drawSprite? boolean Set false to hide this zone's configured sprite.

---@param zoneOptions QBTargetPolyZoneOptions
---@return integer id
function Target.addPolyZone(zoneOptions)
    assert(type(zoneOptions) == "table", "addPolyZone requires an options table.")
    assert(type(zoneOptions.points) == "table" and #zoneOptions.points >= 3,
        "addPolyZone requires at least 3 points.")
    for i, point in ipairs(zoneOptions.points) do
        assert(isCoordsLike(point), ("addPolyZone requires points[%d] to be a table with numeric x/y/z."):format(i))
    end

    local options = validateOptions(zoneOptions.options)
    local id = nextId()
    local owner = GetInvokingResource() or GetCurrentResourceName()

    local zoneHandle = QB.zones.poly({
        points = zoneOptions.points,
        thickness = zoneOptions.thickness,
        minZ = zoneOptions.minZ,
        maxZ = zoneOptions.maxZ,
        debug = zoneDebugEnabled(zoneOptions),
        trackPlayer = false,
    })

    registerZone(id, {
        id = id,
        kind = "zone",
        options = options,
        distance = zoneOptions.distance,
        zoneHandle = zoneHandle,
        spriteCoords = polySpriteCoords(zoneOptions.points),
        drawSprite = zoneOptions.drawSprite ~= false,
        spriteOverride = zoneOptions.drawSprite == true,
    }, polyBounds(zoneOptions.points, zoneOptions.minZ, zoneOptions.maxZ))
    Target.ownership.track(owner, id)

    return id
end

---Internal compatibility constructor for a zone supplied by another resource
---(notably qb-target AddComboZone's PolyZone objects). The native kora_target API
---stays limited to validated kora_lib shapes; the bridge only needs a contains
---predicate and uses the same ownership/removal/cache machinery as native
---zones.
---@param contains fun(point: any): boolean
---@param options QBTargetOption[]
---@param defaultDistance? number
---@param spriteCoords? any
---@param drawSprite? boolean
---@param bounds? table
---@param targetEntity? number Only evaluate this zone when the raycast hit this entity.
---@return integer id
function Target._addCustomZone(contains, options, defaultDistance, spriteCoords, drawSprite, bounds, targetEntity)
    assert(isCallable(contains), 'custom zone contains must be callable.')
    options = validateOptions(options)
    local id = nextId()
    local owner = GetInvokingResource() or GetCurrentResourceName()
    local removed = false
    local zoneHandle = {
        contains = contains,
        remove = function() removed = true end,
    }
    registerZone(id, {
        id = id,
        kind = 'zone',
        options = options,
        distance = defaultDistance,
        zoneHandle = zoneHandle,
        spriteCoords = spriteCoords,
        drawSprite = spriteCoords ~= nil and drawSprite ~= false,
        spriteOverride = spriteCoords ~= nil and drawSprite == true,
        targetEntity = targetEntity,
    }, bounds)
    Target.ownership.track(owner, id)
    return id
end

---Builds a broad-phase AABB for Target._addCustomZone from an XY centre,
---per-axis half-extents, and an optional vertical band. Exposed for the compat
---bridges, which construct their own `contains` predicates but do know the
---shape those predicates describe.
---
---Every argument must be a bound the predicate can never match OUTSIDE of. An
---over-large box only costs a wasted exact test; an under-sized one silently
---makes the zone untargetable. Omit the bounds argument entirely (rather than
---guessing) whenever that cannot be guaranteed -- an unindexed zone is still
---scanned every tick, so the only cost is the performance this index exists
---to reclaim.
---@param x number
---@param y number
---@param extentX number
---@param extentY number
---@param minZ number? Omit for an unbounded vertical band.
---@param maxZ number?
---@return table bounds
function Target._zoneBounds(x, y, extentX, extentY, minZ, maxZ)
    return {
        minX = x - extentX, maxX = x + extentX,
        minY = y - extentY, maxY = y + extentY,
        minZ = minZ or -math.huge, maxZ = maxZ or math.huge,
    }
end

---@param id integer
---@return boolean removed
function Target.removeZone(id)
    local registration = Target.registrations[id]
    if not registration or registration.kind ~= "zone" then return false end

    Target.destroyRegistration(id)
    return true
end

---@param enabled boolean
function Target.setEnabled(enabled)
    assert(type(enabled) == "boolean", "enabled must be a boolean.")
    Target.enabled = enabled
    if not enabled then
        Target.active = false
        Target.success = false
        Target.hovering = nil
        if Target._cancelCurrentTargeting then Target._cancelCurrentTargeting() end
    end
end

---@return table state `{enabled: boolean, hovering: table|nil}` -- `hovering` mirrors whatever client/loop.lua last resolved under the crosshair/inside a zone, or nil when nothing is targeted.
function Target.getState()
    return {
        enabled = Target.enabled,
        active = Target.active,
        success = Target.success,
        hovering = Target.hovering,
    }
end

---Runs a server-registered action (see server/server.lua's
---ServerTarget.registerServerAction) with server-side distance revalidation
---against `entity`. Entirely optional -- an onSelect can just as easily fire
---its own TriggerServerEvent/QB.callback.trigger directly, exactly as with
---real qb-target/ox_target.
---@param name string The action name passed to ServerTarget.registerServerAction on the server.
---@param entity? number A NETWORKED entity (a real ped/vehicle/player -- NOT QB.entities.create output, which has no server-side twin) to distance-check against. Omit for an action with nothing to validate a distance against.
---@param maxDistance? number Overrides Config.target.serverActionMaxDistance.
---@param ... any Extra arguments forwarded to the server-side handler.
---@return boolean? ok `nil` if the callback itself failed (timeout/handshake failure -- check kora_lib's own console). Otherwise `true`/`false` reflecting the server action's own outcome (unknown action name, missing/too-far entity, the handler erroring, or the handler's own deliberate `return false, reason`).
---@return any ... The handler's own remaining return values on success (`ok == true`), or the failure reason string (`ok == false`). Nothing at all when `ok` is `nil`.
function Target.runServerAction(name, entity, maxDistance, ...)
    assert(type(name) == "string" and #name > 0, "runServerAction requires a name.")

    local netId = nil

    if entity then
        assert(NetworkGetEntityIsNetworked(entity),
            "runServerAction requires a networked entity (a real ped/vehicle/player) -- entities from " ..
            "QB.entities.create aren't networked and have no server-side twin to validate distance against.")
        netId = NetworkGetNetworkIdFromEntity(entity)
    end

    -- kora_lib's QB.callback module forwards a handler's return values in full
    -- (multi-value returns end to end) -- server/server.lua's handler
    -- replies with (ok, ...) directly, so there's nothing to unpack here.
    return QB.callback.trigger("qbtarget:server:runAction", name, netId, maxDistance, ...)
end

-- kora_lib invokes the binding once with the hydrated active snapshot and again
-- after every published live change. Keep this guarded so kora_target remains
-- usable with older kora_lib releases during a rolling upgrade.
if QB.config and QB.config.bind then
    QB.config.bind('kora_target', { 'target' }, Target.applyConfig)
end
