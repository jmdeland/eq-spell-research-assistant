# v0.17.2-demo.5 Test Notes

## Purpose
Harden the Portable -> Desktop transition so a user who tries the tool portably can reliably keep their data when choosing Desktop setup later.

## Test A - Portable detection
1. Run `RUN-PORTABLE.bat`.
2. Allow `portable-data` to contain session/history/browser-state files.
3. Exit the tray application completely.
4. Run `INSTALL-DESKTOP-SHORTCUT.bat`.
5. Confirm the console prominently shows `PORTABLE DATA DETECTED`.
6. Confirm it displays the portable-data path and a non-zero file count.

## Test B - Import portable data
1. Answer `Y` to the migration prompt.
2. Confirm the installer reports `Portable-data migration verified`.
3. Confirm it reports the number of files copied.
4. Confirm `%LOCALAPPDATA%\EverQuest Research & Loot Tool\` contains the migrated state/history/session files.
5. Confirm the original `portable-data` folder still exists and is unchanged.
6. Launch from the desktop shortcut and verify settings/history/session state are present.

## Test C - Decline migration
1. Repeat setup with portable data present.
2. Answer `N`.
3. Confirm the installer explicitly says portable data was not imported.
4. Confirm portable data remains unchanged.
5. Confirm the desktop shortcut is still created/refreshed.

## Regression checks
- Portable mode still reports `portableMode : True`.
- Portable data continues writing under `portable-data`.
- Desktop mode continues using `%LOCALAPPDATA%\EverQuest Research & Loot Tool`.
- Two-character Magelo still loads.
- Loot-value overrides persist.
- Session persistence and Observed Loot History continue recording.
- Corpse recovery remains on the demo.3 rules pending additional live verification.
