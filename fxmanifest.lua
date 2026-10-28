fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_target'
-- Keep the legacy resource name resolvable for exports['qbtarget'] callers.
provide 'qbtarget'
author 'Jamie'
version '1.0.0'
description 'World/zone/model targeting engine built on qblib'

dependencies {
    'kora_lib'
}

-- Makes this ONE resource a true drop-in for scripts calling
-- exports['qb-target']:... or exports.ox_target:... -- no separate shim
-- resources needed. `provide` alone only affects dependency resolution
-- (satisfies another resource's `dependency 'qb-target'`/`dependencies`
-- check); actually making exports['qb-target']:Fn() resolve to code running
-- in THIS resource additionally requires manually registering the
-- underlying __cfx_export_<name>_<export> event for each provided identity
-- -- see client/compat/qb-target.lua and client/compat/ox-target.lua's
-- provideExport() helper.
provide 'qb-target'
provide 'ox_target'

-- Required to reach QB.raycast/QB.zones/QB.world/QB.drawing/QB.nui/QB.cache/
-- QB.callback/QB.resources -- see kora_lib's own AGENTS.md for why this is how a
-- consumer resource pulls in the QB proxy (init.lua).
shared_script '@kora_lib/init.lua'

shared_scripts {
    'config.lua'
}

-- state.lua must load before everything below references Target.addEntity
-- etc -- listed explicitly rather than globbed for the same reason kora_lib's
-- own fxmanifest lists local/** explicitly: alphabetic glob order would put
-- exports.lua before state.lua ever defines anything on it. The two compat
-- files only need to load after state.lua (they call Target.* directly,
-- same-resource -- no exports.kora_target: round trip needed internally), so
-- their relative order versus loop.lua/exports.lua doesn't matter.
client_scripts {
    'client/state.lua',
    'client/sprites.lua',
    'client/loop.lua',
    'client/exports.lua',
    'client/compat/qb-target.lua',
    'client/compat/ox-target.lua'
}

server_scripts {
    'server/server.lua'
}
