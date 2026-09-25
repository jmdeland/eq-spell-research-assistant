# v0.17.2 Field Test Notes

This build is on the **demo** channel and is intended for Windows/Bastion field testing before stable promotion.

## Two-Character Magelo

1. Load the Primary Character. Confirm inventory, bank, shared bank, and item locations appear normally.
2. Load the Additional Character. Confirm the first profile remains loaded.
3. Toggle **Include additional character in Research readiness** OFF and ON. Confirm spell readiness/have totals change without unloading the profile.
4. With both profiles loaded, inspect ingredients owned by different characters. Location should include the character, e.g. `Bromm — Inventory Bag 6`.
5. Leave **Treat Shared Bank as the same shared storage for both profiles** ON for same-account characters. Confirm shared-bank quantities are not doubled.
6. Clear only the Additional Character. Confirm the Primary Character remains loaded and usable.
7. Reload both profiles, then intentionally try a bad refresh on one slot. Confirm the previously loaded data in that slot and the other slot are preserved.
8. Restart the app. Confirm old single-profile settings migrate to Primary and both saved profiles restore.
9. With the EQ monitor on one character, loot an item provisionally. Refresh the *other* Magelo profile first: it must not consume that provisional loot. Refresh the matching character: reconciliation may occur when the exact item count increased.
10. During all Magelo tests, watch Live Loot latency. Magelo must not add recurring work to port 8767.

## Corpse Recovery Protection

Expected sequence:

- `You regain experience from resurrection.`
- zone entry back to the corpse zone
- first self-loot begins within 120 seconds
- continuing self-loot remains in corpse-recovery mode while gaps stay under 60 seconds

Expected UI:

`CORPSE RECOVERY — not counted as a new drop`

Recovered items should remain visible in Recent Loot/session export for transparency, but must not:

- enter permanent Observed Loot History
- increase Session Loot ownership totals
- increase provisional owned counts
- advance Research readiness
- fire Research/high-value sounds
- generate newly-craftable alerts

Normal loot after the recovery window must return to ordinary behavior.

## Revert

Keep the previous working ZIP. If this build misbehaves, exit the tray application completely and copy the previous package back over the application folder using the same extract/copy process used for prior demos.

## demo.2 persistence regression check

- Confirm a newly looted item appears in `/api/session-state` within a few seconds.
- Confirm the current monthly `loot-history-YYYY-MM.jsonl` file gains a new line for normal (non-corpse-recovery) loot.
- Confirm a restart offers the saved session when session data exists.
- Confirm corpse-recovery loot remains excluded from permanent Observed Loot History.


## Release note

Corpse Recovery Protection is included in v0.17.2 but remains under active Bastion field testing.
