-- Neither real qb-target nor real ox_target validate actions server-side
-- themselves -- that has always been the consumer script's own job. This is
-- one small, OPT-IN primitive worth having anyway (given "don't trust the
-- client" is otherwise unaddressed here): a distance-revalidated relay for a
-- server action, registered by name. Deliberately not a permission framework
-- (job/gang/item checks) -- no qb-core/ox_core exists in this repo to hook
-- into one, see qbtarget/docs.md.
ServerTarget = ServerTarget or {}

local serverActions = {}

-- qblib's QB.callback module now forwards a handler's return values in full
-- (multi-value returns end to end), so this replies with (ok, ...) directly
-- -- true plus the action handler's own return values, or false plus a
-- reason string -- rather than the hand-rolled envelope table this used to
-- need before that fix. Target.runServerAction on the client receives these
-- as real return values with no unpacking of its own required.
QB.callback.register('qbtarget:server:runAction', function(src, name, netId, maxDistance, ...)
    local handler = serverActions[name]
    if not handler then
        return false, ('Unknown qbtarget server action: %s'):format(tostring(name))
    end

    local entity = nil

    if netId then
        entity = NetworkGetEntityFromNetworkId(netId)
        if not entity or entity == 0 then
            return false, 'Target entity no longer exists.'
        end

        local playerPed = GetPlayerPed(src)
        local distance = #(GetEntityCoords(playerPed) - GetEntityCoords(entity))

        if distance > (maxDistance or Config.target.serverActionMaxDistance) then
            return false, 'Too far from target.'
        end
    end

    local results = table.pack(pcall(handler, src, entity, ...))
    local ok = results[1]

    if not ok then
        print(('[qbtarget] server action \'%s\' errored: %s'):format(name, tostring(results[2])))
        return false, 'Server action errored.'
    end

    return true, table.unpack(results, 2, results.n)
end)

---Registers a server-side handler runnable via the client's
---Target.runServerAction(name, entity, maxDistance, ...). `handler(src, entity, ...)`
---runs after the entity (if any) has already been resolved from its network
---id and distance-checked against the calling player.
---@param name string
---@param handler fun(src: number, entity: number?, ...: any): any
function ServerTarget.registerServerAction(name, handler)
    assert(type(name) == 'string' and #name > 0, 'registerServerAction requires a name.')
    assert(type(handler) == 'function', 'registerServerAction requires a handler function.')

    serverActions[name] = handler
end

exports('registerServerAction', ServerTarget.registerServerAction)
