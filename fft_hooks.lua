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
local VERSION = 2

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
    return {
        ped = { x = p.x, y = p.y, z = p.z }, cam = { x = cam.x, y = cam.y, z = cam.z },
        rot = { x = rot.x, z = rot.z }, hit = hit == 1,
        hitCoords = hit == 1 and { x = coords.x, y = coords.y, z = coords.z } or nil,
        entity = entity ~= 0 and entity or nil, active = Target.active, hovering = hovering(),
    }
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
        return true, nil, 'selected'
    end
    release()
    return true, nil, 'menu'
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
