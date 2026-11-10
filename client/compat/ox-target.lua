-- Drop-in bridge translating the public ox_target API onto Target.* directly (same resource, no exports round trip).
-- See ../../AGENTS.md for the mapping table. canInteract receives ox_target's (entity, distance, coords, name, bone)
-- with bone always nil; `groups` is enforced against kora_core job/gang data (see makeCanInteract).

Target = Target or {}

-- See qb-target.lua's copy for why this is needed: `provide` alone doesn't make exports.ox_target:Fn() resolve here,
-- only registering the __cfx_export_ox_target_<name> event does.
local provideExport = Kora.compat.provideExport

-- Export-boundary callbacks are tables with __call, not functions; see qb-target.lua's copy for the failure this fixes.
local isCallable = Kora.util.isCallable

-- Fields upstream strips from the table handed to export/event/serverEvent
-- handlers (client/main.lua getResponse); everything else on the option
-- (name, label, bones, distance, offset, menuName, ...) is passed through.
local RESPONSE_STRIPPED = {
    icon = true, groups = true, items = true, canInteract = true, onSelect = true,
    export = true, event = true, serverEvent = true, command = true,
}

-- The compat response uses the captured hit, while native Kora callbacks keep their arguments.
local function responseFor(entity, context, server, option)
    local coords = context and context.anchorCoords
    local response = {}
    for key, value in pairs(option or {}) do
        if not RESPONSE_STRIPPED[key] then response[key] = value end
    end
    response.entity = entity or 0
    response.coords = coords and vector3(coords.x, coords.y, coords.z) or nil
    response.distance = context and context.distance or nil
    response.zone = context and context.registration.kind == 'zone' and context.registration.id or nil
    if server then
        response.entity = entity and entity ~= 0 and DoesEntityExist(entity) and NetworkGetEntityIsNetworked(entity)
            and NetworkGetNetworkIdFromEntity(entity) or 0
    end
    return response
end

-- Sub-menus (openMenu / menuName)
--
-- Upstream shows only options whose menuName equals the current menu
-- (nil = home). Selecting an option with openMenu switches the menu and the
-- next targeting pass shows that menu's options plus a 'builtin:goback'
-- global entry. Kora resolves one snapshot per key hold, so the chosen menu
-- stays current across presses until go-back/'home' is chosen or
-- `kora_target:oxMenuTimeoutMs` (default 15000, 0 = never) passes.
local currentMenu, menuHistory, menuSetAt = nil, {}, 0
local gobackIds = nil
local GOBACK_NAME = 'builtin:goback'

local function menuTimeoutMs()
    return type(GetConvarInt) == 'function' and GetConvarInt('kora_target:oxMenuTimeoutMs', 15000) or 15000
end

local function removeGoback()
    if not gobackIds then return end
    for _, id in pairs(gobackIds) do Target.destroyRegistration(id) end
    gobackIds = nil
end

local function goBack()
    local previous = table.remove(menuHistory)
    currentMenu = previous or nil
    if not currentMenu then menuHistory = {} end
    menuSetAt = GetGameTimer()
    if not currentMenu then removeGoback() end
end

-- Zones are not covered by the global-type entries, so zones that use menus
-- carry their own go-back option (see translateOxOptions).
local function gobackOption()
    return {
        name = GOBACK_NAME,
        label = Target.text and Target.text('goBack', 'Go back') or 'Go back',
        icon = 'fa-solid fa-circle-chevron-left',
        canInteract = function() return currentMenu ~= nil end,
        onSelect = function() goBack() end,
        _onSelectContext = function() goBack() end,
    }
end

local function ensureGoback()
    if gobackIds then return end
    gobackIds = {}
    for _, entityType in ipairs({ 'ped', 'vehicle', 'object', 'player' }) do
        gobackIds[entityType] = Target.addGlobalType(entityType, { gobackOption() })
    end
end

local function activeMenu()
    if currentMenu then
        local timeout = menuTimeoutMs()
        if timeout > 0 and GetGameTimer() - menuSetAt > timeout then
            currentMenu, menuHistory = nil, {}
            removeGoback()
        end
    end
    return currentMenu
end

-- Called before the option's own handler, like upstream's NUI select callback.
local function enterMenu(option)
    if not option.openMenu then return end
    menuHistory[#menuHistory + 1] = currentMenu or false
    -- table.remove on a `false` entry returns false; normalised in goBack.
    currentMenu = option.openMenu ~= 'home' and option.openMenu or nil
    menuSetAt = GetGameTimer()
    if currentMenu then
        ensureGoback()
    else
        menuHistory = {}
        removeGoback()
    end
end

-- Upstream order: onSelect, export, event, serverEvent, command. `action`
-- is the legacy qtarget callback (receives the entity only).
local function dispatchLegacy(option, entity, context, invoker)
    enterMenu(option)
    if isCallable(option.onSelect) then
        option.onSelect(responseFor(entity, context, false, option))
    elseif isCallable(option.action) then
        option.action(entity)
    elseif option.export then
        local resource = option.resource or invoker or 'ox_target'
        local ok, err = pcall(function()
            exports[resource][option.export](nil, responseFor(entity, context, false, option))
        end)
        if not ok then
            print(('[kora_target:ox_target] export %s.%s for option %q failed: %s')
                :format(tostring(resource), tostring(option.export), tostring(option.label), tostring(err)))
        end
    elseif option.event then
        TriggerEvent(option.event, responseFor(entity, context, false, option))
    elseif option.serverEvent then
        TriggerServerEvent(option.serverEvent, responseFor(entity, context, true, option))
    elseif option.command then
        ExecuteCommand(option.command)
    end
end

-- `groups` enforcement (ox_target form: 'name' | {'a','b'} | {a = minGrade}),
-- checked against the same kora_core PlayerData the qb-target bridge tracks
-- (job and gang). Set convar `kora_target:oxGroups 0` to restore the previous
-- behaviour of passing `groups` through unenforced. If no kora_core identity is
-- running the check never denies (graceful degradation, warned at registration).
local function groupsEnforced()
    return type(GetConvarInt) ~= 'function' or GetConvarInt('kora_target:oxGroups', 1) ~= 0
end

local function groupGrade(entry, name)
    return entry and entry.name == name and entry.grade and (entry.grade.level or entry.grade) or nil
end

local function hasGroup(groups)
    if not Target._playerData then return true end
    local available, data = Target._playerData()
    if not available then return true end
    if not data then return false end

    local function satisfied(name, minGrade)
        local grade = groupGrade(data.job, name) or groupGrade(data.gang, name)
        return grade ~= nil and grade >= (tonumber(minGrade) or 0)
    end

    if type(groups) == 'string' then return satisfied(groups, 0) end
    if type(groups) ~= 'table' then return true end
    for key, value in pairs(groups) do
        if type(key) == 'number' then
            if satisfied(value, 0) then return true end
        elseif satisfied(key, value) then
            return true
        end
    end
    return next(groups) == nil
end

-- ox_target accepts either an array of options or one bare option table.
local function optionList(options)
    assert(type(options) == 'table', 'ox_target options must be a table.')
    if options[1] == nil and next(options) ~= nil then return { options } end
    return options
end

-- `items` / `anyItem` (upstream client/utils.lua hasPlayerGotItems), checked
-- through kora_inventory's client HasItem(name, amount) export, which reads
-- the same kora_core item data a stock ox_inventory count would. Forms:
-- 'name' | {'a','b'} (all, or any with anyItem) | {a = amount}. Without a
-- running kora_inventory the check never denies (warned once), matching
-- upstream's "no inventory resource -> true".
local inventoryWarned = false

-- Results are cached ~300 ms per (item, count) because canInteract runs for
-- every candidate on every targeting pass; kora_inventory's inventory-change
-- events drop the cache immediately.
local HAS_CACHE_MS = 300
local hasCache = {}

local function playerHas(name, amount)
    local key = tostring(name) .. ':' .. tostring(amount)
    local now = GetGameTimer()
    local hit = hasCache[key]
    if hit and now - hit.at < HAS_CACHE_MS then return hit.value end
    local ok, result = pcall(function() return exports.kora_inventory:HasItem(name, amount) end)
    if not ok then return nil end
    result = result == true
    hasCache[key] = { at = now, value = result }
    return result
end

local function clearHasCache() hasCache = {} end
for _, eventName in ipairs({ 'qb-inventory:client:updateInventory', 'inventory:client:updateInventory' }) do
    if type(RegisterNetEvent) == 'function' then RegisterNetEvent(eventName, clearHasCache) end
end

local function hasItems(filter, hasAny)
    local function check(name, amount)
        local result = playerHas(name, amount)
        if result == nil and not inventoryWarned then
            inventoryWarned = true
            print('[kora_target:ox_target] WARNING: option sets items but kora_inventory is unavailable '
                .. '-- item requirements cannot be checked and will not deny.')
        end
        return result
    end

    local kind = type(filter)
    local entries = {}
    if kind == 'string' then
        entries[1] = { filter, 1 }
        hasAny = false
    elseif kind == 'table' then
        if filter[1] ~= nil then
            for _, name in ipairs(filter) do entries[#entries + 1] = { name, 1 } end
        else
            for name, amount in pairs(filter) do entries[#entries + 1] = { name, tonumber(amount) or 1 } end
        end
    else
        return true
    end

    for _, entry in ipairs(entries) do
        local result = check(entry[1], entry[2])
        if result == nil then return true end
        if hasAny then
            if result then return true end
        elseif not result then
            return false
        end
    end
    return not hasAny
end

-- `offset` / `offsetAbsolute` / `offsetSize` (upstream main.lua shouldHide):
-- the aim point must be within offsetSize (default 1.0) of a point on the
-- entity. `offset` is a fraction of the model's dimensions unless absolute
-- (upstream names the flag `absoluteOffset`; `offsetAbsolute` is accepted too).
local function offsetAllows(option, entity, coords)
    local offset = option.offset
    if not offset or not coords or not entity or entity == 0 then return true end
    if not DoesEntityExist(entity) then return false end
    if not option.absoluteOffset and not option.offsetAbsolute then
        local min, max = GetModelDimensions(GetEntityModel(entity))
        offset = vector3(
            (max.x - min.x) * offset.x + min.x,
            (max.y - min.y) * offset.y + min.y,
            (max.z - min.z) * offset.z + min.z)
    end
    local world = GetOffsetFromEntityInWorldCoords(entity, offset.x, offset.y, offset.z)
    local dx, dy, dz = coords.x - world.x, coords.y - world.y, coords.z - world.z
    local size = option.offsetSize or 1
    return dx * dx + dy * dy + dz * dz <= size * size
end

-- Translates ox_target's option shape ({name?, icon, label, distance?,
-- bones?, canInteract?, onSelect?, export?, event?, serverEvent?, command?,
-- groups?, items?, anyItem?, offset?, menuName?, openMenu?}) into
-- kora_target's own KoraTargetOption shape. `distance`/`bones` map 1:1 --
-- ox_target already stores these per-option, unlike qb-target. Everything
-- else is enforced in the canInteract wrapper below, in upstream's order:
-- menu, groups, items, offset, then the caller's own canInteract.
local function makeCanInteract(option, isZone)
    local userCheck, groups = option.canInteract, option.groups
    local enforce = groups ~= nil and groupsEnforced()

    if enforce then
        local available = Target._playerData and (Target._playerData())
        if not available then
            print(('[kora_target:ox_target] WARNING: option %q sets groups but no kora_core identity is running '
                .. '-- groups cannot be checked and the option will be shown to everyone.')
                :format(tostring(option.label)))
        end
    end

    -- Options register once but the menu changes later, so the menu test is
    -- always installed (it is one comparison); the rest only when needed.
    -- kora_target calls canInteract(entity, distance, data, anchorCoords); ox_target's
    -- contract is (entity, distance, coords, name, bone). Zones pass entity 0 in ox_target.
    -- `bone` is not tracked by the resolver and is always nil.
    return function(entity, distance, _, anchorCoords)
        if option.menuName ~= activeMenu() then return false end
        if enforce and not hasGroup(groups) then return false end
        if option.items and not hasItems(option.items, option.anyItem) then return false end
        if not isZone and option.offset and not offsetAllows(option, entity, anchorCoords) then return false end
        if userCheck then
            local coords = anchorCoords and vector3(anchorCoords.x, anchorCoords.y, anchorCoords.z) or nil
            -- Upstream hides the option on any falsy result, including a bare `return`.
            return userCheck(entity or 0, distance, coords, option.name, nil) and true or false
        end
        return true
    end
end

local function translateOxOptions(options, isZone)
    options = optionList(options)

    local translated = {}
    local invoker = GetInvokingResource and GetInvokingResource() or nil

    for i, option in ipairs(options) do
        local bones = option.bones
        if type(bones) == 'string' then bones = { bones } end

        translated[i] = {
            name = option.name,
            label = option.label or option.name or 'Interact',
            icon = option.icon,
            iconColor = option.iconColor,
            distance = option.distance,
            bones = bones,
            canInteract = makeCanInteract(option, isZone),
            groups = option.groups,
            items = option.items,
            onSelect = function(entity)
                dispatchLegacy(option, entity, nil, invoker)
            end,
            _onSelectContext = function(context)
                dispatchLegacy(option, context.entity, context, invoker)
            end,
            _oxCompat = true,
        }
    end

    if isZone then
        for _, option in ipairs(options) do
            if option.menuName or option.openMenu then
                translated[#translated + 1] = gobackOption()
                break
            end
        end
    end

    return translated
end

local function addLocalEntity(entities, options)
    return Target.addEntity(entities, translateOxOptions(options))
end

local function addModel(models, options)
    return Target.addModel(models, translateOxOptions(options))
end

local zonesByName = {}

local function addBoxZone(zoneOpts)
    assert(type(zoneOpts) == 'table', 'addBoxZone requires an options table.')

    local id = Target.addBoxZone({
        coords = zoneOpts.coords,
        size = zoneOpts.size or vector3(2.0, 2.0, 2.0),
        rotation = zoneOpts.rotation or 0.0,
        debug = zoneOpts.debug,
        drawSprite = zoneOpts.drawSprite,
        options = translateOxOptions(zoneOpts.options, true),
    })
    if zoneOpts.name then zonesByName[zoneOpts.name] = id end
    return id
end

local function addSphereZone(zoneOpts)
    assert(type(zoneOpts) == 'table', 'addSphereZone requires an options table.')

    local id = Target.addSphereZone({
        coords = zoneOpts.coords,
        radius = zoneOpts.radius,
        debug = zoneOpts.debug,
        drawSprite = zoneOpts.drawSprite,
        options = translateOxOptions(zoneOpts.options, true),
    })
    if zoneOpts.name then zonesByName[zoneOpts.name] = id end
    return id
end

local function addPolyZone(zoneOpts)
    assert(type(zoneOpts) == 'table', 'addPolyZone requires an options table.')

    local id = Target.addPolyZone({
        points = zoneOpts.points,
        thickness = zoneOpts.thickness,
        debug = zoneOpts.debug,
        drawSprite = zoneOpts.drawSprite,
        options = translateOxOptions(zoneOpts.options, true),
    })
    if zoneOpts.name then zonesByName[zoneOpts.name] = id end
    return id
end

local function addGlobal(entityType)
    return function(options)
        local id = Target.addGlobalType(entityType, translateOxOptions(options))
        Target.registrations[id]._oxGlobal = true
        return id
    end
end

local addGlobalPlayer = addGlobal('player')
local addGlobalPed = addGlobal('ped')
local addGlobalVehicle = addGlobal('vehicle')
local addGlobalObject = addGlobal('object')

-- ox_target zones are already id-based, same as kora_target's own -- the
-- cleanest mapping in the suite, no translation table needed.
local function removeZone(id)
    if type(id) == 'string' then
        local named = zonesByName[id]
        zonesByName[id] = nil
        id = named
    end
    if id == nil then return false end
    for name, zoneId in pairs(zonesByName) do
        if zoneId == id then zonesByName[name] = nil end
    end
    return Target.removeZone(id)
end

local function optionNames(names)
    local wanted = {}
    for _, name in ipairs(type(names) == 'table' and names or { names }) do wanted[name] = true end
    return wanted
end

local function removeNamedOptions(id, wanted)
    local registration = Target.registrations[id]
    if not registration then return false end

    local remaining = {}
    for _, option in ipairs(registration.options) do
        if not wanted[option.name] then remaining[#remaining + 1] = option end
    end
    if #remaining == #registration.options then return false end

    if #remaining == 0 then
        Target.destroyRegistration(id)
    else
        Target._replaceOptions(id, remaining, registration.distance)
    end
    return true
end

-- Removes the named options from bridge-created registrations indexed under
-- `key` in `index` (Target.byEntity / Target.byModel). Native and qb-target
-- registrations on the same key are left alone.
local function removeNamedFromIndex(index, key, wanted)
    local ids = {}
    for id in pairs(index[key] or {}) do ids[#ids + 1] = id end
    local removed = false
    for _, id in ipairs(ids) do
        local registration = Target.registrations[id]
        local first = registration and registration.options[1]
        if first and first._oxCompat and removeNamedOptions(id, wanted) then removed = true end
    end
    return removed
end

-- removeLocalEntity(entities, names?): without `names` every registration on the
-- entities goes; with a name or array of names only those options do.
local function removeLocalEntity(entities, names)
    local wanted = names ~= nil and optionNames(names) or nil
    local removedAny = false
    for _, entity in ipairs(type(entities) == 'table' and entities or { entities }) do
        if wanted then
            if removeNamedFromIndex(Target.byEntity, entity, wanted) then removedAny = true end
        elseif Target.removeEntity(entity) then
            removedAny = true
        end
    end

    return removedAny
end

local function removeModel(models, names)
    if names == nil then return Target.removeModel(models) end

    local wanted, removedAny = optionNames(names), false
    for _, model in ipairs(type(models) == 'table' and models or { models }) do
        local hash = type(model) == 'string' and joaat(model) or model
        if removeNamedFromIndex(Target.byModel, hash, wanted) then removedAny = true end
    end
    return removedAny
end

-- Note the INVERTED boolean sense: ox_target's disableTargeting(true) turns
-- targeting OFF. A naive passthrough to setEnabled would silently invert
-- behavior.
local function disableTargeting(state)
    return Target.setEnabled(not state)
end

-- ox_target's exact getState() return shape isn't known; kora_target's own shape is returned as-is.
local function getState()
    return Target.getState()
end

local function removeGlobal(entityType)
    return function(names)
        if type(names) ~= 'string' and type(names) ~= 'table' then
            return Target.removeGlobalType(entityType, names)
        end

        local ids = {}
        for id in pairs(Target.byGlobalType[entityType] or {}) do
            if Target.registrations[id]._oxGlobal then ids[#ids + 1] = id end
        end
        local wanted, removed = optionNames(names), false
        for _, id in ipairs(ids) do
            if removeNamedOptions(id, wanted) then removed = true end
        end
        return removed
    end
end

local removeGlobalPlayer = removeGlobal('player')
local removeGlobalPed = removeGlobal('ped')
local removeGlobalVehicle = removeGlobal('vehicle')
local removeGlobalObject = removeGlobal('object')

-- Universal registrations remain grouped so the existing numeric removal alias
-- still works alongside the documented option-name removal.
local globalOptionGroups = {}
local nextGlobalOptionId = 0

local function addGlobalOption(options)
    nextGlobalOptionId = nextGlobalOptionId + 1
    local groupId = nextGlobalOptionId

    local entries = {}
    for _, entityType in ipairs({ 'ped', 'vehicle', 'object', 'player' }) do
        entries[#entries + 1] = { entityType = entityType, id = Target.addGlobalType(entityType, translateOxOptions(options)) }
    end

    globalOptionGroups[groupId] = entries
    return groupId
end

local function removeGlobalOption(groupId)
    if type(groupId) == 'string' or type(groupId) == 'table' then
        local wanted, removed = optionNames(groupId), false
        for _, entries in pairs(globalOptionGroups) do
            for _, entry in ipairs(entries) do
                if removeNamedOptions(entry.id, wanted) then removed = true end
            end
        end
        return removed
    end

    local entries = globalOptionGroups[groupId]
    if not entries then return false end

    globalOptionGroups[groupId] = nil

    local removedAny = false
    for _, entry in ipairs(entries) do
        if Target.removeGlobalType(entry.entityType, entry.id) then removedAny = true end
    end

    return removedAny
end

---@param value any
---@return table
local function toArray(value)
    if type(value) == 'table' then return value end
    return { value }
end

-- addEntity/removeEntity take NETWORK ids (unlike addLocalEntity), bridged to the local-handle Target.* via NetworkGetEntityFromNetworkId.
-- Indexed by network id (as upstream), so an entity that is not streamed in yet,
-- or streams out and back in under a new handle, keeps its options.
local function addEntity(netIds, options)
    return Target._addNetworkEntity(netIds, translateOxOptions(options))
end

local function removeEntity(netIds)
    local removedAny = false
    for _, netId in ipairs(toArray(netIds)) do
        if Target._removeNetworkEntity(netId) then removedAny = true end
    end

    return removedAny
end

-- isActive: upstream returns state.isActive(), true for the whole targeting
-- session (key press until release, select or disableTargeting) -- not only
-- while an option is under the reticle. Target.active is exactly that flag
-- (client/loop.lua), so it is returned directly.
local function isActive()
    return Target.active == true
end

for exportName, func in pairs({
    addLocalEntity = addLocalEntity,
    addModel = addModel,
    addBoxZone = addBoxZone,
    addSphereZone = addSphereZone,
    addPolyZone = addPolyZone,
    addGlobalPlayer = addGlobalPlayer,
    addGlobalPed = addGlobalPed,
    addGlobalVehicle = addGlobalVehicle,
    addGlobalObject = addGlobalObject,
    addGlobalOption = addGlobalOption,
    addEntity = addEntity,
    removeZone = removeZone,
    removeLocalEntity = removeLocalEntity,
    removeModel = removeModel,
    removeGlobalPlayer = removeGlobalPlayer,
    removeGlobalPed = removeGlobalPed,
    removeGlobalVehicle = removeGlobalVehicle,
    removeGlobalObject = removeGlobalObject,
    removeGlobalOption = removeGlobalOption,
    removeEntity = removeEntity,
    disableTargeting = disableTargeting,
    getState = getState,
    isActive = isActive,
}) do
    provideExport('ox_target', exportName, func)
end
