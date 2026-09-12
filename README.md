# EverQuest Research & Loot Tool by Bromm


## v0.16.1
- Adds a fixed-height, scrollable Recent Loot feed while preserving the complete session history.
- Persists live-loot sessions outside the app folder so they can survive crashes, reboots, and updates.
- Offers Restore Session or Start New Session after an interrupted session.
- Adds **End Current Loot Session** with saved-event count and confirmation.
- Adds automatic startup update checks with a non-blocking update notification and Settings badge.

Version **0.16.1**

A local Windows companion for Bastion spell Research planning, Magelo inventory mapping, and live EverQuest loot monitoring.

## Highlights

- Live Loot Monitor is the primary workspace, with looter names and Research-value classification.
- Bastion Magelo inventory loading with verified stack quantities and bag/bank location mapping.
- Exact default ROF2/Bastion spell icons mapped from the supplied client `spells_us.txt` and default icon sheets.
- Research recipe readiness, ingredient locations, reverse item lookup, and partial-name autocomplete.
- Autocomplete supports **Up/Down**, **Tab**, **Enter**, and **Esc** and is optimized for responsive typing.
- Settings workspace for appearance, monitoring, alerts, Bastion data, and application updates.
- Selectable **Default**, **EQBlue**, **EQGold**, and **EQRed** appearances.
- GitHub self-updater with SHA-256 verification, full-folder backup, config preservation, rollback protection, and restart.
- Friend-friendly hidden launcher, Windows tray controls, desktop shortcut installer, and guarded Exit warning.

## Recommended installation for friends

1. Download the ZIP only from the official GitHub Release page.
2. Extract the entire ZIP to a permanent folder. Do not run the application from inside the ZIP.
3. Run `INSTALL-DESKTOP-SHORTCUT.bat` once.
4. Launch **EverQuest Research & Loot Tool** from the desktop shortcut.
5. On first launch, choose the active EverQuest `eqlog_*.txt` file when prompted.
6. Leave the tray companion running while playing EverQuest.

### Windows security warning

This hobby project is not code-signed. Windows may show an **Unknown publisher** or Microsoft Defender SmartScreen warning. Only proceed when the files were downloaded from the official GitHub Release for this project.

The older `START-LIVE-MONITOR.bat` remains available for troubleshooting. Normal users should use `START-RESEARCH-TOOL.bat` or the desktop shortcut.

## Search shortcuts

Autocomplete is available in Quick Loot Lookup, Item Lookup, and Researchable Spells. Type a partial name such as `Rune of Z`, then use:

- **Down / Up** — move through suggestions
- **Tab** — complete the highlighted or first suggestion
- **Enter** — select / run the relevant action
- **Esc** — dismiss suggestions

Exact item IDs still work.

## Inventory accuracy

Bastion Magelo is the preferred inventory source. The parser preserves exact item IDs, rendered stack quantities, and verified inventory/bank bag placement. Live-loot quantities can count provisionally in Group / Personal mode until a Magelo refresh confirms them.

## Updating

Settings → **Application Updates** checks the latest stable GitHub Release. Updating is optional; older installed releases do not expire just because a newer version exists.

## Privacy

The app runs locally. Inventory state and local settings remain on the computer unless the user explicitly exports or shares them. Public Bastion pages and GitHub Releases are contacted only for their relevant sync/update functions.

## Development channels

- `main` — stable production
- `demo` — experimental/testing builds
