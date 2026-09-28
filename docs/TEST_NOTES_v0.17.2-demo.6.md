# v0.17.2-demo.8 Test Notes

## Purpose
Prevent loss of existing Desktop Observed Loot History when portable data is imported.

## Critical safety test
1. Exit the tray application completely.
2. Ensure Desktop mode already has an Observed Loot History archive under `%LOCALAPPDATA%\EverQuest Research & Loot Tool\history`.
3. Ensure the extracted demo has its own `portable-data\history\loot-history-YYYY-MM.jsonl`.
4. Run `INSTALL-DESKTOP-SHORTCUT.bat`.
5. Choose `Y` to import portable data.
6. Confirm the installer reports a timestamped Desktop backup path.
7. Confirm it reports Desktop records, Portable records, duplicates skipped, and merged history records.
8. Confirm the Desktop monthly archive contains the union of unique records from both sources.
9. Confirm the portable monthly archive is unchanged.
10. Launch Desktop mode and allow the history index worker to rebuild.

## Backup verification
A sibling backup folder should exist under LocalAppData with a name similar to:
`EverQuest Research & Loot Tool_backup_20260926-123456`

## Regression checks
- Portable mode still stores data under `portable-data`.
- Desktop mode still stores data under `%LOCALAPPDATA%\EverQuest Research & Loot Tool`.
- Session recovery still works.
- Two-character Magelo still loads.
- Loot-value overrides still persist.
- Observed Loot History continues recording after migration.
- Corpse recovery remains on the demo.3 rules pending additional live verification.

## Important
This build prevents future history overwrite. It cannot reconstruct Desktop history that was already overwritten before the backup/merge logic existed.
