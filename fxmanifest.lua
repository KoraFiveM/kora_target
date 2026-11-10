fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_target'
author 'Jamie'
version '1.0.0'
description 'World/zone/model targeting engine built on kora_lib'

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
--
-- `ox_target` is deliberately NOT provided: the stubs/ox_target placeholder
-- owns that resource name, and claiming it here too made `stop ox_target`
-- stop kora_target (and its dependents). exports.ox_target:* still resolves
-- through the manual export registration; resources that declare
-- `dependency 'ox_target'` or check GetResourceState('ox_target') need the
-- placeholder ensured after kora_target.
provide 'qb-target'

-- Required to reach Kora.raycast/Kora.zones/Kora.world/Kora.drawing/Kora.nui/Kora.cache/
-- Kora.callback/Kora.resources -- see kora_lib's own AGENTS.md for why this is how a
-- consumer resource pulls in the Kora proxy (init.lua).
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
    'client/compat/ox-target.lua',
    -- Optional FFT hooks: returns immediately unless fft_kora_hooks is true.
    'fft_hooks.lua'
}

server_scripts {
    'server/server.lua'
}

-- Tiny listener page: reports browser-side window blur and Escape/right-click
-- to client/loop.lua (Config.target.recovery.nuiListener). It never takes focus.
ui_page 'ui/focus.html'
files { 'ui/focus.html' }
