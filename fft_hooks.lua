-- Optional FFT development hooks (client). Listed last in fxmanifest.lua and
-- inert unless `setr fft_kora_hooks true`.
--
-- Replay drives the real targeting state machine through the same hold
-- commands a keybind uses (+playerTarget / -playerTarget): the resolver picks
-- candidates from the live camera ray, and releasing runs the normal
-- selectCandidates -> runOption path with its range, vehicle, downed and busy
-- gates. Nothing here invokes a registered option directly. When several
-- options are visible the release opens kora_lib's interact selector; the
-- runner then chooses the label through kora_lib's own FFT hook.
if GetConvar('fft_kora_hooks', 'false') ~= 'true' then return end

local RUNNER = 'fft'
local VERSION = 3

local function session()
    if GetResourceState(RUNNER) ~= 'started' then return nil end
    local id = LocalPlayer.state.fftSession
    return type(id) == 'string' and id or nil
end

local selections = 0

-- GetEntityModel (native 0x9F47B058362C84B5) throws inside gta-streaming-five.dll
-- for map buildings and other handles that are not a ped (1), vehicle (2) or
-- object (3), and for entities that have since been deleted.
local MODEL_KINDS = { [1] = true, [2] = true, [3] = true }

---@param entity? integer
---@return integer|nil model hash, or nil when the handle has no readable model
local function entityModel(entity)
    if type(entity) ~= 'number' or entity == 0 or not DoesEntityExist(entity) then return nil end
    if not MODEL_KINDS[GetEntityType(entity)] then return nil end
    local ok, model = pcall(GetEntityModel, entity)
    return ok and type(model) == 'number' and model or nil
end

-- client/loop.lua's runOption calls this (its only FFT seam) once every gate
-- has passed and just before the option's onSelect runs. It only observes: an
-- error raised here would abort runOption and the option would never run.
Target._fftSelected = function(candidate)
    if not session() then return end
    selections = selections + 1
    pcall(function()
        local entity = candidate.entity
        local exists = type(entity) == 'number' and entity ~= 0 and DoesEntityExist(entity)
        local coords = exists and GetEntityCoords(entity) or candidate.anchorCoords
        TriggerEvent('fft:kora:target', {
            label = candidate.option.label,
            model = entityModel(entity),
            coords = coords and { x = coords.x, y = coords.y, z = coords.z } or nil,
        })
    end)
end

local function hovering()
    local hover = Target.active and Target.hovering or nil
    if not hover or not hover.option then return nil end
    return { label = hover.option.label, name = hover.option.name, entity = hover.entity, kind = hover.kind,
        zoneId = hover.zoneId, optionCount = hover.optionCount or 1 }
end

local function release()
    -- Toggle mode selects on the second press; hold mode on key-up.
    ExecuteCommand((Config.target.toggle and '+' or '-') .. 'playerTarget')
end

local actions = {}

function actions.start()
    if Target.active then return true end
    ExecuteCommand('+playerTarget')
    local deadline = GetGameTimer() + 500
    while not Target.active and GetGameTimer() < deadline do Wait(0) end
    if not Target.active then return false, 'Targeting is blocked (locked, downed, busy or disabled)', 'blocked' end
    return true
end

function actions.hovering() return hovering() end

-- Kept for protocol 1 callers: only the top option is observable from here.
function actions.options()
    local hover = hovering()
    return hover and { hover } or {}
end

-- Diagnostic only: where the crosshair ray lands. Zone options are reached
-- through the world point the ray hits, so a hit outside the zone (or no hit)
-- explains an option that never becomes visible.
function actions.probe()
    local ped = PlayerPedId()
    local cam, rot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local pitch, yaw = math.rad(rot.x), math.rad(rot.z)
    local flat, reach = math.abs(math.cos(pitch)), Config.target.maxDistance or 10.0
    local to = vector3(cam.x - math.sin(yaw) * flat * reach, cam.y + math.cos(yaw) * flat * reach, cam.z + math.sin(pitch) * reach)
    local handle = StartShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 511, ped, 4)
    local result, hit, coords, _, entity = 1, 0, nil, nil, 0
    local deadline = GetGameTimer() + 500
    while result == 1 and GetGameTimer() < deadline do
        result, hit, coords, _, entity = GetShapeTestResult(handle)
        if result == 1 then Wait(0) end
    end
    local p = GetEntityCoords(ped)
    -- Every gate that makes `start` refuse (see client/loop.lua startTargeting),
    -- so a refusal can be attributed without reading the resolver.
    local gates = {
        enabled = Target.enabled == true,
        focused = IsGameWindowFocused() == true,
        pauseMenu = IsPauseMenuActive() == true,
        inVehicle = IsPedInAnyVehicle(ped, false) == true,
        locked = Target.interactionsLocked() == true,
        downed = Target.isDowned(true) == true,
        busy = Target.isBusy(true) == true,
    }
    return {
        ped = { x = p.x, y = p.y, z = p.z }, cam = { x = cam.x, y = cam.y, z = cam.z },
        rot = { x = rot.x, z = rot.z }, hit = hit == 1,
        hitCoords = hit == 1 and { x = coords.x, y = coords.y, z = coords.z } or nil,
        entity = entity ~= 0 and entity or nil, active = Target.active, hovering = hovering(),
        gates = gates,
    }
end

-- Read-only aiming aid: world points worth putting under the crosshair for an
-- option label, nearest first. Zones return sample points inside the zone
-- (the resolver tests the ray's hit point against the zone); entity and model
-- registrations return the entity's position and handle. Nothing is selected
-- or invoked here; the runner aims at a point and then goes through `select`.
local ZONE_OFFSETS = { 0.0, -0.35, 0.35, -0.7, 0.7 }
-- Low samples first: a ray through a point at standing height carries on to
-- the floor beyond the zone, while a floor-level point is where it lands.
local ZONE_HEIGHTS = { -0.9, -1.2, -0.6, 0.0, -0.3, 0.3 }
local PER_HEIGHT = 3

local GLOBAL_POOLS = { vehicle = 'CVehicle', ped = 'CPed', player = 'CPed', object = 'CObject' }

local function hasLabel(registration, label)
    for _, option in ipairs(registration.options or {}) do
        if option.label == label then return true end
    end
    return false
end

-- The middle of an entity's model bounds. A prop's origin is often at its base
-- (fuel pumps, chargers, benches): aiming there lands on the ground in front.
local function entityCentre(entity)
    local at = GetEntityCoords(entity)
    local model = entityModel(entity)
    if not model then return at end
    local ok, low, high = pcall(GetModelDimensions, model)
    if not ok or not low or not high then return at end
    local ok2, centre = pcall(GetOffsetFromEntityInWorldCoords, entity,
        (low.x + high.x) * 0.5, (low.y + high.y) * 0.5, (low.z + high.z) * 0.5)
    return ok2 and centre or at
end

local function modelEntities(models, origin, radius, out)
    local wanted = {}
    for _, model in ipairs(models or {}) do wanted[model] = true end
    for _, pool in ipairs({ 'CObject', 'CPed', 'CVehicle' }) do
        for _, entity in ipairs(GetGamePool(pool)) do
            if wanted[GetEntityModel(entity)] and #(GetEntityCoords(entity) - origin) <= radius then out[#out + 1] = entity end
        end
    end
end

---@param label string
---@param radius? number metres around the ped (default 30)
---@return table[] points `{ x, y, z, entity?, zone? }`, nearest first, at most 24
function actions.locate(label, radius)
    if type(label) ~= 'string' or #label > 200 then return {} end
    radius = math.min(tonumber(radius) or 30.0, 100.0)
    local origin = GetEntityCoords(PlayerPedId())
    local points = {}
    local seq = 0
    -- `anchor` ranks a zone's samples by the zone centre so they keep their
    -- low-first order; entities rank by their own position.
    local function add(point, entity, zone, anchor)
        local d = #(vector3(point.x, point.y, point.z) - origin)
        if d > radius then return end
        seq = seq + 1
        local rank = anchor and #(vector3(anchor.x, anchor.y, anchor.z) - origin) or d
        points[#points + 1] = { x = point.x, y = point.y, z = point.z, entity = entity, zone = zone, d = rank, seq = seq }
    end
    for id, registration in pairs(Target.registrations) do
        if hasLabel(registration, label) then
            if registration.kind == 'zone' and registration.zoneHandle and registration.spriteCoords then
                local c, inside = registration.spriteCoords, 0
                for _, dz in ipairs(ZONE_HEIGHTS) do
                    local level = 0
                    for _, dx in ipairs(ZONE_OFFSETS) do
                        for _, dy in ipairs(ZONE_OFFSETS) do
                            local p = vector3(c.x + dx, c.y + dy, c.z + dz)
                            local ok, contained = pcall(registration.zoneHandle.contains, p)
                            if level < PER_HEIGHT and ok and contained then
                                level, inside = level + 1, inside + 1
                                add(p, nil, id, c)
                            end
                        end
                    end
                end
                if inside == 0 then add(c, nil, id, c) end
            else
                local entities = {}
                for _, entity in ipairs(registration.entities or {}) do entities[#entities + 1] = entity end
                for _, netId in ipairs(registration.netIds or {}) do
                    if netId and NetworkDoesNetworkIdExist(netId) then entities[#entities + 1] = NetworkGetEntityFromNetworkId(netId) end
                end
                if registration.kind == 'model' then modelEntities(registration.models, origin, radius, entities) end
                if registration.kind == 'globalType' then
                    -- Every entity of the type qualifies; only nearby ones are useful aims.
                    local pool = GLOBAL_POOLS[registration.entityType]
                    local ped = PlayerPedId()
                    for _, entity in ipairs(pool and GetGamePool(pool) or {}) do
                        if entity ~= ped and #(GetEntityCoords(entity) - origin) <= 8.0
                            and (registration.entityType ~= 'player' or IsPedAPlayer(entity))
                            and (registration.entityType ~= 'ped' or not IsPedAPlayer(entity)) then
                            entities[#entities + 1] = entity
                        end
                    end
                end
                for _, entity in ipairs(entities) do
                    if type(entity) == 'number' and entity ~= 0 and DoesEntityExist(entity) then
                        add(entityCentre(entity), entity, nil)
                    end
                end
            end
        end
    end
    table.sort(points, function(a, b) if a.d ~= b.d then return a.d < b.d end return a.seq < b.seq end)
    for i = #points, 25, -1 do points[i] = nil end
    return points
end

-- Calls one public export in this VM and reports a refusal's message. A raised
-- error crossing the export boundary reaches the caller as nil, so refusal
-- tests could not otherwise read it. Same function, same validation.
local PUBLIC = { addEntity = true, removeEntity = true, addModel = true, removeModel = true, addGlobalType = true,
    removeGlobalType = true, addGlobalBone = true, removeGlobalBone = true, addTargetBone = true, addBoxZone = true,
    addSphereZone = true, addPolyZone = true, removeZone = true, setEnabled = true, getState = true, runServerAction = true }
function actions.call(name, ...)
    if not PUBLIC[name] or type(Target[name]) ~= 'function' then return false, 'Not a kora_target export: ' .. tostring(name) end
    local ok, result = pcall(Target[name], ...)
    if not ok then return false, (tostring(result):gsub('^[^%s:]+%.lua:%d+: ', '', 1)) end
    return true, result
end

function actions.state()
    return { enabled = Target.enabled, active = Target.active, success = Target.success, hovering = hovering(),
        selections = selections }
end

---@param label string option label expected under the crosshair
---@param entity? integer required entity handle; nil accepts a zone or any entity
---@return boolean ok, string? error, string? code `selected`, `menu`, `not_visible` or `rejected`
function actions.select(label, entity)
    if type(label) ~= 'string' or #label > 200 then return false, 'Invalid target label' end
    local hover = hovering()
    if not hover then return false, 'No target option is visible', 'not_visible' end
    if entity ~= nil and hover.entity ~= entity then return false, 'Crosshair is on a different target', 'not_visible' end
    if hover.optionCount == 1 then
        if hover.label ~= label then return false, 'Visible option is ' .. tostring(hover.label), 'not_visible' end
        local before = selections
        release()
        local deadline = GetGameTimer() + 500
        while selections == before and GetGameTimer() < deadline do Wait(0) end
        if selections == before then
            return false, 'Target option did not run (out of range, in a vehicle, downed or busy)', 'rejected'
        end
        return true, false, 'selected'
    end
    release()
    return true, false, 'menu'
end

exports('fftVersion', function() return VERSION end)
exports('fftAction', function(action, ...)
    if GetInvokingResource() ~= RUNNER then return false, 'FFT hooks are disabled or session is not authorised' end
    if action == 'stop' then Target._forceRelease(); return true end
    if not session() then return false, 'FFT hooks are disabled or session is not authorised' end
    local handler = actions[action]
    if not handler then return false, 'Unsupported target action' end
    return handler(...)
end)
