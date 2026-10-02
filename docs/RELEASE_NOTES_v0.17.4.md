# EverQuest Research & Loot Tool v0.17.4

## Stable Final Polish Release

v0.17.4 is the long-lived stable release built from the fully tested v0.17.4-demo.5 release candidate.

The release focuses on reliability, startup behavior, immediate alert audio, desktop-launch consistency, safe data handling, and first-run usability. No new feature family was added during the final promotion.

## Live Loot polish

- Native Windows-side alert audio is used for normal High Value and Research alerts.
- Alerts no longer depend on the browser tab being selected and remain immediate while EverQuest has focus.
- Browser WebAudio remains available as fallback behavior where appropriate.
- Live Event Worker startup now exposes readiness and startup timing.
- The worker opens its local listener earlier and uses a faster initial log-tail scan for current-zone initialization.
- The active ownership mode in the Live Loot Monitor is now displayed in high-contrast white text, bold, and underlined:
  - **Group/personal mode**
  - **Raid/observation mode**

## Desktop launcher reliability

- Desktop shortcuts use a persistent launcher stored under `%LOCALAPPDATA%\EverQuest Research & Loot Tool\`.
- The preferred Desktop application root is stored separately so an older extracted copy cannot silently reclaim the shortcut.
- A Windows PowerShell 5.1 encoding issue that could prepend visible `ï»¿` characters to the saved application path is fixed.
- Shortcut icons use a version-specific cached file to reduce stale Windows icon caching.
- The updater uses the same persistent Desktop launcher flow.

### Orphaned tray recovery

Final testing reproduced a case where the tray PowerShell process remained alive after the main monitor on port 8765 had stopped. Older builds saw the single-instance mutex and silently exited, making the desktop icon appear broken.

v0.17.4 now:

- checks whether port 8765 is actually healthy before treating an existing tray as authoritative;
- verifies a stale process by confirming its Windows command line contains `research-tool-tray.ps1`;
- terminates only that verified orphaned tray process;
- clears the stale tray PID file;
- reacquires the single-instance mutex and launches normally;
- correctly handles an abandoned Windows mutex;
- shows a visible warning instead of silently exiting if safe recovery cannot be completed.

This exact failure was reproduced and successfully recovered during release-candidate testing.

## Data safety and onboarding

- `START HERE.bat` remains the recommended entry point.
- Portable Mode and Desktop Mode remain supported.
- Portable → Desktop and Desktop → Portable migration use backup-first, merge-safe handling.
- Monthly Observed Loot History archives are merged instead of blindly overwritten.
- Existing history remains at its source after migration.
- Active EverQuest log detection strongly prefers the client log that is actually being written.
- Setup checking remains available for core files, log selection, main service, Live Loot worker, and persistence worker.

## Loot / Research behavior retained

- Two-character Bastion Magelo support.
- Primary and Additional Character profiles.
- Shared Bank deduplication.
- Exact item-ID inventory mapping.
- Player loot-value overrides:
  - Default
  - High Value
  - Keep
  - Not Valuable
- Bastion corpse-recovery protection for in-zone resurrection sequences.
- Session recovery.
- Permanent Observed Loot History.
- Group / Personal and Raid / Observation ownership modes.
- Research readiness and reverse item lookup.
- Dedicated Live Event Worker.
- Dedicated persistence worker.
- Separate history-index worker.
- Bastion Research dataset through level 70 / Omens of War.

## Getting started

1. Download `eq_spell_research_assistant_v0.17.4.zip`.
2. Extract it to a permanent folder.
3. Double-click `START HERE.bat`.
4. Choose Portable Mode or Desktop Mode.
5. Follow the guided prompts.

Normal use does not require PowerShell or command-line knowledge.

## Upgrade note

Keep your previous application folder until v0.17.4 has launched successfully and your history/settings have been verified.

The application includes backup and merge protections, but retaining the previous folder through first launch remains the safest upgrade practice.

## Release asset

`eq_spell_research_assistant_v0.17.4.zip`

## SHA-256

`de656bac824ba6b2a8ac74f128f42607ee0a84ee50cc3b10a66dee35b8caaed7`
