fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ox_target'
author 'kora'
-- ox_target API level emulated by kora_target's client/compat/ox-target.lua.
version '1.17.2'
description 'Compatibility placeholder for kora_target, not affiliated with Overextended'

-- Content-free on purpose: no scripts and no exports. kora_target registers the
-- __cfx_export_ox_target_* events itself, so exports.ox_target:* keeps resolving
-- to it. Declaring any export or script here would shadow or break that.
dependency 'kora_target'
