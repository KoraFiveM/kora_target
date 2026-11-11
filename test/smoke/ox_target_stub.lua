-- ox_target placeholder: manifest-only resource that owns the name; kora_target
-- must not provide it and must still register every exports.ox_target:* handler.
local function readFile(path)
    local f = assert(io.open(path, 'rb'))
    local s = f:read('a'); f:close(); return s
end
local dir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local root = dir .. '../../'
local failed = 0
local function check(cond, msg)
    if not cond then failed = failed + 1; print('FAIL: ' .. msg) end
end

local stub = readFile(root .. 'stubs/ox_target/fxmanifest.lua')
check(stub:match("\nname 'ox_target'"), 'stub name')
check(stub:match("dependency 'kora_target'"), 'stub depends on kora_target')
local a, b, c = stub:match("\nversion '(%d+)%.(%d+)%.(%d+)'")
a, b, c = tonumber(a), tonumber(b), tonumber(c)
check(a and (a > 1 or (a == 1 and b >= 14)), 'stub version >= 1.14.0')
for _, key in ipairs({ 'client_script', 'server_script', 'shared_script', 'export', 'provide' }) do
    check(not stub:match("\n%s*" .. key), 'stub must not declare ' .. key)
end

local main = readFile(root .. 'fxmanifest.lua')
check(not main:match("\nprovide%s+['\"]ox_target['\"]"), 'kora_target must not provide ox_target')
check(main:match("\nprovide 'qb%-target'"), 'still provides qb-target')

-- Every name the compat file exports under ox_target is registered at load.
local compat = readFile(root .. 'client/compat/ox-target.lua')
local expected = {}
local block = compat:match("for exportName, func in pairs%(%{(.-)%}%) do")
for name in block:gmatch("(%w+)%s*=") do expected[#expected + 1] = name end
check(#expected >= 23, 'found ox_target export table (' .. #expected .. ')')
check(compat:match("provideExport%('ox_target', exportName, func%)"), 'exports registered under ox_target identity')
for _, n in ipairs({ 'addBoxZone', 'removeZone', 'addLocalEntity', 'addModel', 'addGlobalVehicle',
    'removeGlobalOption', 'disableTargeting', 'getState', 'isActive' }) do
    local found = false
    for _, e in ipairs(expected) do if e == n then found = true end end
    check(found, 'export ' .. n)
end

print(('ox-target-stub: %s'):format(failed == 0 and 'ok' or (failed .. ' failed')))
os.exit(failed == 0 and 0 or 1)
