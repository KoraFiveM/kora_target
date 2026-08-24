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
-- Monotonic local generation used by loop.lua to invalidate its aim cache as
-- soon as a registration changes. This is not exposed as API state.
Target.registrationRevision = 0

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
-- resource-local copy of the same check qblib's own modules use (see e.g.
-- qblib/modules/zones/client.lua), since qbtarget is a separate resource
-- with its own separate Lua chunks and can't share qblib's local.
local function isCallable(x)
    if type(x) == "function" then return true end
    local mt = type(x) == "table" and getmetatable(x) or nil
    return mt ~= nil and mt.__call ~= nil
end

-- A "coords-like" value: a table with numeric x/y/z, satisfied by both a
-- real vector3 and a plain {x=, y=, z=} table (both are accepted throughout
-- this file). Used to validate addBoxZone/addSphereZone/addPolyZone's
-- coords/size/points BEFORE handing them to QB.zones.* -- unlike `options`,
-- these were previously passed through unchecked, so a malformed call only
-- failed with an opaque error from deep inside qblib.
local function isCoordsLike(x)
    -- Deliberately does NOT gate on type(x) == "table" first: FiveM natives
    -- like GetEntityCoords return vector3 values whose Lua type() is
    -- "vector3", not "table" (mirrors qblib/modules/zones/client.lua's
    -- toVec3). pcall guards the field reads so a bare number/nil/boolean
    -- fails the check instead of erroring on the index.
    local ok, isNum = pcall(function()
        return type(x.x) == "number" and type(x.y) == "number" and type(x.z) == "number"
    end)
    return ok and isNum
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
---for a zone-backed registration, removes the underlying qblib zone. Safe to
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
        -- INTO qblib -- which is "qbtarget" itself when a third-party
        -- consumer called exports.qbtarget:addBoxZone, not that consumer.
        -- qblib's own cleanup-on-stop therefore never fires for the real
        -- consumer stopping; Target.ownership above (tracked against the
        -- REAL invoking resource, captured in Target.addBoxZone/etc before
        -- ever calling into QB.zones.*) is what has to proactively tear the
        -- underlying zone down here. See AGENTS.md "Ownership subtlety".
        Target.byZone[id] = nil
        if registration.zoneHandle then registration.zoneHandle.remove() end
    end
end

-- Ownership: which resource registered a target, and bulk cleanup when that
-- resource stops. Deliberately NOT QB.resources.registry -- that factory's
-- returned track/untrack/owner closures live inside qblib's own environment,
-- and while FXServer's exports boundary generally supports returning
-- function references, qblib's own local/resources/AGENTS.md only ever
-- documents/exercises this factory being consumed from WITHIN qblib itself
-- (every listed consumer is an internal qblib module). Rather than rest a
-- leak-sensitive mechanism on an unconfirmed cross-resource reuse pattern,
-- qbtarget hand-rolls the exact same well-established shape locally -- a
-- byResource/ownerOf table pair swept on onClientResourceStop, mirroring
-- qblib/local/resources/client.lua almost verbatim. Exposed as fields on
-- Target (not locals) so Target.addBoxZone/addSphereZone/addPolyZone below
-- -- which build their registration record before this file's own register()
-- helper would run -- can track against it directly too.
local ownershipByResource = {}
local ownershipOwnerOf = {}

local function trackOwnership(resource, id)
    local previousOwner = ownershipOwnerOf[id]

    if previousOwner and previousOwner ~= resource then
        local previouslyOwned = ownershipByResource[previousOwner]
        if previouslyOwned then previouslyOwned[id] = nil end
    end

    local owned = ownershipByResource[resource]
    if not owned then
        owned = {}
        ownershipByResource[resource] = owned
    end

    owned[id] = true
    ownershipOwnerOf[id] = resource
end

local function untrackOwnership(id)
    local resource = ownershipOwnerOf[id]

    if resource then
        local owned = ownershipByResource[resource]
        if owned then owned[id] = nil end
        ownershipOwnerOf[id] = nil
    end

    return resource
end

Target.ownership = { track = trackOwnership, untrack = untrackOwnership }

AddEventHandler("onClientResourceStop", function(resource)
    local owned = ownershipByResource[resource]
    if not owned then return end

    ownershipByResource[resource] = nil

    for id in pairs(owned) do
        ownershipOwnerOf[id] = nil
        Target.destroyRegistration(id)
    end
end)

---Shared by addEntity/addModel/addGlobalType/addGlobalBone: validates
---options, allocates an id, captures the real invoking resource, and tracks
---ownership. Zone registrations don't use this -- they need the id BEFORE
---creating the underlying qblib zone (so it can be stamped onto the zone's
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
    -- GetInvokingResource(), the caller will read as "qbtarget", not the
    -- real external consumer.
    local owner = GetInvokingResource() or GetCurrentResourceName()

    local zoneHandle = QB.zones.box({
        coords = zoneOptions.coords,
        size = zoneOptions.size,
        rotation = zoneOptions.rotation,
        debug = zoneOptions.debug,
    })

    Target.registrations[id] = {
        id = id,
        kind = "zone",
        options = options,
        distance = zoneOptions.distance,
        zoneHandle = zoneHandle,
    }
    Target.byZone[id] = true
    touchRegistrations()
    Target.ownership.track(owner, id)

    return id
end

---@class QBTargetSphereZoneOptions
---@field coords any Sphere center.
---@field radius number
---@field options QBTargetOption[]
---@field distance? number
---@field debug? boolean

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
        debug = zoneOptions.debug,
    })

    Target.registrations[id] = {
        id = id,
        kind = "zone",
        options = options,
        distance = zoneOptions.distance,
        zoneHandle = zoneHandle,
    }
    Target.byZone[id] = true
    touchRegistrations()
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
        debug = zoneOptions.debug,
    })

    Target.registrations[id] = {
        id = id,
        kind = "zone",
        options = options,
        distance = zoneOptions.distance,
        zoneHandle = zoneHandle,
    }
    Target.byZone[id] = true
    touchRegistrations()
    Target.ownership.track(owner, id)

    return id
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
end

---@return table state `{enabled: boolean, hovering: table|nil}` -- `hovering` mirrors whatever client/loop.lua last resolved under the crosshair/inside a zone, or nil when nothing is targeted.
function Target.getState()
    return { enabled = Target.enabled, hovering = Target.hovering }
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
---@return boolean? ok `nil` if the callback itself failed (timeout/handshake failure -- check qblib's own console). Otherwise `true`/`false` reflecting the server action's own outcome (unknown action name, missing/too-far entity, the handler erroring, or the handler's own deliberate `return false, reason`).
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

    -- qblib's QB.callback module forwards a handler's return values in full
    -- (multi-value returns end to end) -- server/server.lua's handler
    -- replies with (ok, ...) directly, so there's nothing to unpack here.
    return QB.callback.trigger("qbtarget:server:runAction", name, netId, maxDistance, ...)
end
