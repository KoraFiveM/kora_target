-- Neither real qb-target nor real ox_target validate actions server-side
-- themselves -- that has always been the consumer script's own job. This is
-- one small, OPT-IN primitive worth having anyway (given "don't trust the
-- client" is otherwise unaddressed here): a distance-revalidated relay for a
-- server action, registered by name. Deliberately not a permission framework
-- (job/gang/item checks) -- no qb-core/ox_core exists in this repo to hook
-- into one, see qbtarget/docs.md.
ServerTarget = ServerTarget or {}

local serverActions = {}

-- QB.callback's wire protocol only carries a SINGLE result value end to end
-- (see local/callback/server.lua's `local ok, result = pcall(handler, ...)` --
-- any second return value from a callback handler is silently dropped before
-- it ever reaches the client). So this handler returns one envelope table
-- rather than (ok, error) as two values, and Target.runServerAction on the
-- client unpacks it back into (ok, resultOrError) for its own callers.
QB.callback.register('qbtarget:server:runAction', function(src, name, netId, maxDistance, ...)
    local handler = serverActions[name]
    if not handler then
        return { ok = false, error = ('Unknown qbtarget server action: %s'):format(tostring(name)) }
    end

    local entity = nil

    if netId then
        entity = NetworkGetEntityFromNetworkId(netId)
        if not entity or entity == 0 then
            return { ok = false, error = 'Target entity no longer exists.' }
        end

        local playerPed = GetPlayerPed(src)
        local distance = #(GetEntityCoords(playerPed) - GetEntityCoords(entity))

        if distance > (maxDistance or Config.target.serverActionMaxDistance) then
            return { ok = false, error = 'Too far from target.' }
        end
    end

    local ok, result = pcall(handler, src, entity, ...)
    if not ok then
        print(('[qbtarget] server action \'%s\' errored: %s'):format(name, tostring(result)))
        return { ok = false, error = 'Server action errored.' }
    end

    return { ok = true, result = result }
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
