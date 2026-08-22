-- One screen, one line per public function -- kept explicit (not generated,
-- unlike qblib's own build/finalise.lua) so it's directly auditable against
-- the qb-target/ox_target mapping tables in ../docs.md and the qb-target/
-- ox_target shim resources, both of which are hand-written against this
-- exact list.
exports('addEntity', Target.addEntity)
exports('removeEntity', Target.removeEntity)
exports('addModel', Target.addModel)
exports('removeModel', Target.removeModel)
exports('addGlobalType', Target.addGlobalType)
exports('removeGlobalType', Target.removeGlobalType)
exports('addGlobalBone', Target.addGlobalBone)
exports('removeGlobalBone', Target.removeGlobalBone)
exports('addTargetBone', Target.addTargetBone)
exports('addBoxZone', Target.addBoxZone)
exports('addSphereZone', Target.addSphereZone)
exports('addPolyZone', Target.addPolyZone)
exports('removeZone', Target.removeZone)
exports('setEnabled', Target.setEnabled)
exports('getState', Target.getState)
exports('runServerAction', Target.runServerAction)
