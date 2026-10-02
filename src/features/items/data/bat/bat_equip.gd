extends MeleeEquip
## Bat melee. Config-only: a single heavy swing (LMB) plus the legacy timed guard
## (RMB plays bat_block once and auto-lowers). The attack is authored as a
## [MeleeAttack] resource on the scene's `attacks` export (bat_swing.tres); guard
## settings live on the scene's guard_* exports. All swing/hit behavior lives in the
## shared MeleeEquip engine.
