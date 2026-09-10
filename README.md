# EverQuest Spell Research Assistant

Version **0.14.0**

A local browser + PowerShell companion for Bastion Research recipe planning, Magelo inventory loading, reverse Research-item lookup, and live EverQuest loot monitoring.

## v0.14.0 production changes

- Bastion Magelo inventory uses the exact embedded `invSearch` JSON structure.
- Spell class/level metadata can be synchronized from Bastion spell pages.
- Missing class/level metadata is shown as unresolved instead of misleading `ALL`.
- Live loot supports two ownership modes:
  - Group / personal: tracked loot counts provisionally as owned.
  - Raid / observation: loot is tracked but does not affect recipe readiness.
- Magelo refresh reconciles provisional owned loot so an item is not counted twice after it appears in Magelo.
- Session loot can be exported to CSV.
- Sounds / attention alerts are enabled by default; individual alert types remain configurable.
- Production requires an EverQuest log for the live companion. Demo-only no-log behavior was not promoted.

## Start

Run `START-LIVE-MONITOR.bat`. On first run, choose the active `eqlog_*.txt` file. The app opens at `http://127.0.0.1:8765/`.

## Inventory

Magelo is the preferred inventory source. Enter a Bastion character name or full character URL and choose **Load / Refresh Magelo**.

The optional **Use Inventory Output File Instead** button accepts tab/comma-delimited inventory output containing `Name`, `ID`, and `Count` columns.

## Privacy

The app runs locally. Its local settings and inventory state stay on the computer unless the user explicitly exports or shares files. Bastion sync actions request public Bastion Library/character pages.

## GitHub / releases

This source tree is sanitized for publication. See `docs/RELEASE_PROCESS.md` and `docs/UPDATER_PLAN.md`.

## Development lines

- Stable production: **v0.14.0**
- Experimental visual/features: keep in a separate demo branch/package and promote selectively after testing.
