# EverQuest Research & Loot Tool v0.17.3

This release promotes the tested `v0.17.2-demo.8` baseline to stable.

## Highlights

### Easier first run
`START HERE.bat` is now the recommended entry point. It lets a user choose Portable Mode, Desktop Mode, or a setup check without needing PowerShell knowledge.

### Portable Mode
The tool can run directly from an extracted folder with persistent data under `portable-data\`. Settings, session recovery, Observed Loot History, Magelo profile names, and supported browser-backed preferences can travel with the folder.

### Safe Portable / Desktop migration
Moving between Portable and Desktop modes now backs up destination data and merges monthly Observed Loot History instead of replacing it. Source data remains intact after migration.

### Better EverQuest log selection
First-run detection now prefers the actively written EQ log and avoids silently choosing stale older installs. Ambiguous selections still fall back to the normal Windows file picker.

### Loot value overrides
Items can be marked Default, High Value, Keep, or Not Valuable. These player-facing preferences do not erase verified Research recipe relevance.

### Corpse-recovery protection
The recovery detector handles Bastion's in-zone resurrection path where `Returning to Resurrect, please wait...` is followed immediately by corpse loot without a new `You have entered ...` line. Recovered corpse items remain excluded from new-drop history/readiness behavior.

## Existing features retained
- Two-character Bastion Magelo support
- Shared Bank deduplication
- Live Loot and Session Loot
- Permanent Observed Loot History
- Research readiness and reverse lookup
- Dedicated Live Event, persistence, and history-index workers
- Stable updater flow

## Upgrade note
Existing users can extract this release to a permanent folder and use `START HERE.bat`. Portable/Desktop migration should be allowed to complete before deleting older folders.

## Release package

- Asset: `eq_spell_research_assistant_v0.17.3.zip`
- SHA-256: `6ba8a8f12f5ab052cb84bdab691592f981b7bbdcb0274e14bdca860b6fed1424`
