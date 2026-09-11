# EverQuest Spell Research Assistant

Version **0.15.0**

A local browser + PowerShell companion for Bastion Research recipe planning, Magelo inventory loading, reverse Research-item lookup, live EverQuest loot monitoring, and verified self-updates through GitHub Releases.

## v0.15.0 production changes

- Promotes the Windows-tested updater from the demo branch into stable production.
- Checks the latest stable GitHub release from inside the app.
- Downloads the release ZIP through the local companion.
- Verifies the GitHub-provided SHA-256 digest before installation.
- Creates a full timestamped backup before replacing the application folder.
- Preserves `monitor-config.json` across updates.
- Restarts automatically after successful installation.
- Restores the backup if replacement fails.
- Reports the previous update result and available rollback backups.
- Retains the two newest backups for the current install path.

All v0.14.0 production features remain included: Bastion Magelo inventory, spell class/level metadata sync, Research readiness, live loot ownership modes, Magelo reconciliation, session loot CSV export, alerts, and reverse item lookup.

## Start

Run `START-LIVE-MONITOR.bat`. On first run, choose the active `eqlog_*.txt` file. The app opens at `http://127.0.0.1:8765/`.

## Updating

Use **Application Updates → Check for Updates**. When a newer stable GitHub release exists, the app can download, SHA-256 verify, back up the current installation, install the release, preserve local monitor configuration, and restart automatically.

## Inventory

Magelo is the preferred inventory source. Enter a Bastion character name or full character URL and choose **Load / Refresh Magelo**.

The optional **Use Inventory Output File Instead** button accepts tab/comma-delimited inventory output containing `Name`, `ID`, and `Count` columns.

## Privacy

The app runs locally. Local settings and inventory state stay on the computer unless the user explicitly exports or shares files. Bastion sync actions request public Bastion Library/character pages.

## Development lines

- `main`: stable production
- `demo`: experimental features and UI work
