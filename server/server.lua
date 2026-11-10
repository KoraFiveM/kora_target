-- Opt-in primitive: distance-revalidated relay for named server actions. Not a permission framework (job/gang/item checks).
ServerTarget = ServerTarget or {}

local serverActions = {}
local ENTITY_VALIDATION_MESSAGES = {
    invalid_network_id = 'A networked target entity is required.',
    entity_unavailable = 'Target entity no longer exists.',
    player_unavailable = 'Player entity unavailable.',
    routing_bucket_mismatch = 'Target is in another routing bucket.',
    too_far = 'Too far from target.',
}

-- Replies with (ok, ...) directly: true plus the handler's return values, or false plus a reason string.
Kora.callback.register('kora_target:server:runAction', function(src, name, netId, _clientDistance, ...)
    local action = serverActions[name]
    if not action then
        return false, ('Unknown kora_target server action: %s'):format(tostring(name))
    end

    local entity, reason = Kora.world.resolveNetworkEntity(src, netId, { maxDistance = action.maxDistance })
    if not entity then
        return false, ENTITY_VALIDATION_MESSAGES[reason] or 'Target entity is unavailable.'
    end

    local results = table.pack(pcall(action.handler, src, entity, ...))
    local ok = results[1]

    if not ok then
        print(('[kora_target] server action \'%s\' errored: %s'):format(name, tostring(results[2])))
        return false, 'Server action errored.'
    end

    return true, table.unpack(results, 2, results.n)
end)

---Registers a server-side handler runnable via the client's
---Target.runServerAction(name, entity, clientDistance, ...). The client value
---is compatibility-only; the authoritative maximum is captured here.
---The handler runs after the entity (if any) has already been resolved from its network
---id and distance-checked against the calling player.
---@param name string
---@param handler fun(src: number, entity: number?, ...: any): any
---@param opts? {maxDistance?: number}
function ServerTarget.registerServerAction(name, handler, opts)
    assert(type(name) == 'string' and #name > 0, 'registerServerAction requires a name.')
    assert(type(handler) == 'function', 'registerServerAction requires a handler function.')
    opts = opts or {}
    local maxDistance = tonumber(opts.maxDistance) or Config.target.serverActionMaxDistance
    assert(maxDistance > 0 and maxDistance <= Config.target.serverActionMaxDistance,
        'registerServerAction maxDistance must be within the configured server cap.')

    if serverActions[name] then
        print(('[kora_target] WARNING: server action \'%s\' is already registered -- overwriting the previous '
            .. 'handler. Two resources (or a restarted resource) are registering the same action name.')
            :format(name))
    end

    serverActions[name] = {
        handler = handler,
        maxDistance = maxDistance,
        resource = GetInvokingResource() or GetCurrentResourceName(),
    }
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then return end
    for name, action in pairs(serverActions) do
        if action.resource == resource then serverActions[name] = nil end
    end
end)

exports('registerServerAction', ServerTarget.registerServerAction)
