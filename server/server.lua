-- Neither real qb-target nor real ox_target validate actions server-side
-- themselves -- that has always been the consumer script's own job. This is
-- one small, OPT-IN primitive worth having anyway (given "don't trust the
-- client" is otherwise unaddressed here): a distance-revalidated relay for a
-- server action, registered by name. Deliberately not a permission framework
-- (job/gang/item checks) -- no qb-core/ox_core exists in this repo to hook
-- into one, see kora_target/docs.md.
ServerTarget = ServerTarget or {}

local serverActions = {}
local ENTITY_VALIDATION_MESSAGES = {
    invalid_network_id = 'A networked target entity is required.',
    entity_unavailable = 'Target entity no longer exists.',
    player_unavailable = 'Player entity unavailable.',
    routing_bucket_mismatch = 'Target is in another routing bucket.',
    too_far = 'Too far from target.',
}

-- kora_lib's Kora.callback module now forwards a handler's return values in full
-- (multi-value returns end to end), so this replies with (ok, ...) directly
-- -- true plus the action handler's own return values, or false plus a
-- reason string -- rather than the hand-rolled envelope table this used to
-- need before that fix. Target.runServerAction on the client receives these
-- as real return values with no unpacking of its own required.
Kora.callback.register('qbtarget:server:runAction', function(src, name, netId, _clientDistance, ...)
    local action = serverActions[name]
    if not action then
        return false, ('Unknown qbtarget server action: %s'):format(tostring(name))
    end

    local entity, reason = Kora.world.resolveNetworkEntity(src, netId, { maxDistance = action.maxDistance })
    if not entity then
        return false, ENTITY_VALIDATION_MESSAGES[reason] or 'Target entity is unavailable.'
    end

    local results = table.pack(pcall(action.handler, src, entity, ...))
    local ok = results[1]

    if not ok then
        print(('[qbtarget] server action \'%s\' errored: %s'):format(name, tostring(results[2])))
        return false, 'Server action errored.'
    end

    return true, table.unpack(results, 2, results.n)
end)

---Registers a server-side handler runnable via the client's
---Target.runServerAction(name, entity, clientDistance, ...). The client value
---is compatibility-only; the authoritative maximum is captured here.
---runs after the entity (if any) has already been resolved from its network
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
        print(('[qbtarget] WARNING: server action \'%s\' is already registered -- overwriting the previous '
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
