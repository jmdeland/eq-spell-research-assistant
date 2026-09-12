# Changelog

## v0.16.1
- Makes the Recent Loot feed fixed-height and scrollable while keeping a bounded recent-event DOM for performance.
- Persists the full live-loot session snapshot outside the application folder under LocalAppData.
- On crash/reboot restart, offers Restore Session or Start New Session.
- Restores full CSV session history, aggregate session loot, provisional owned counts, and recent-feed state.
- Adds an explicit End / Clear Session control.
- Automatically checks GitHub stable releases after startup.
- Shows a non-blocking Update Available toast and a Settings notification dot when a newer stable release exists.

## v0.16.0
- Promotes the accepted v0.15.1 demo line to stable production.
- Live Loot moved to the primary workspace with dynamic ownership-mode explanation and active-log badge.
- Settings and application headers redesigned; Settings now contains updater, monitoring, alert, data-sync, and appearance controls.
- Default appearance is now distinct neutral charcoal/black/grey; EQBlue, EQGold, and EQRed remain selectable.
- Verified Magelo inventory/bank bag mapping is shown directly on recipe ingredients.
- Fixed Magelo stacked-item quantities so recipe ownership uses rendered stack counts rather than occupied-slot count.
- Added exact default-client spell icons throughout Research spell references.
- Added partial-name autocomplete with keyboard completion and performance optimizations.
- Added friend-friendly hidden launcher, tray controls, desktop shortcut installer, and guarded Exit warning.
- Normalized Research spell rows and fixed READY badge alignment.
- Prevented Application Updates status badge text from wrapping in Settings.

## v0.15.1-demo.14
- Moves active log name into a compact Live Loot header badge.
- Folds ownership-mode behavior into the Live Loot description and updates it dynamically.
- Removes redundant live-monitor status sentences from the main body.


## v0.15.1-demo.14
- Optimized autocomplete/search typing performance with cached normalized indexes, debounce, and single-pass rendering.


## v0.15.1-demo.12
- Added partial/autocomplete matching to Quick Loot Lookup, Item Lookup, and Researchable Spells.
- Added keyboard completion: Up/Down, Tab, Enter, Esc.
- Added friend-friendly hidden launcher + Windows system-tray controls.
- Added guarded tray Exit warning, monitor restart, open-tool command, desktop shortcut installer, and app icon.
- Preserved demo.11 stack-count accuracy fix, verified bag mapping, and exact default spell-icon mapping.

## v0.15.1-demo.12
- Fixes Magelo stack quantity accuracy: stacked items now use the rendered Magelo stack count instead of counting each occupied slot as one item.
- Preserves verified inventory/bank bag location mapping while attaching quantity to each placement.
- Fixes ingredient `You Have` totals for stacked Research components such as Coin of Xev.


## v0.15.1-demo.12
- Normalizes Researchable Spells rows to a fixed icon / spell text / status layout.
- Prevents READY badges from wrapping into long green bars or pushing spell text between rows.
- Keeps row alignment consistent across Default, EQBlue, EQGold, and EQRed.

## v0.15.1-demo.9
- Replaces experimental/generated spell graphics with exact default-client spell icons from the supplied ROF2/Bastion `spells_us.txt` and `spells01.tga`–`spells07.tga`.
- Maps all 309 currently indexed Research spell names and all 166 packaged catalog spell names to default-client icons, including known Bastion naming variants.
- Shows the same spell icon consistently in the Research list, selected-spell detail, reverse item uses, loot-use results, craftable alerts, and other visible spell references.
- RebuildEQ spell art is not used for spell icons.

## v0.15.1-demo.12
- Updated header identity to EVERQUEST RESEARCH & LOOT TOOL by Bromm.
- Polished Settings header to match the primary application header.
- Reset fresh demo appearance default to neutral Default while preserving future selections under a new preference key.


## v0.15.1-demo.7
- Fixes Settings controls not responding after the Settings refactor by loading application scripts only after the full Settings DOM exists.
- No updater, live-monitor, inventory-location, or Research logic changed.

## v0.15.1-demo.7
- Renamed app presentation to Spell Research Assistant & Live Loot Monitor.
- Added premium theme-aware application header and identity treatment.
- Removed redundant live-workspace heading while keeping Live Loot first.
- Preserved verified bag-level ingredient location mapping.
- Additional spacing and visual-hierarchy polish for production-candidate review.

## v0.15.1-demo.5
- Makes Default a distinct neutral black/charcoal/grey appearance instead of a near-EQBlue palette.
- Preserves individual Magelo placement rows in addition to aggregate inventory quantities.
- Adds a player-facing Where column to recipe ingredients.
- Maps Bastion bag slot IDs conservatively to Inventory Bag / Bank Bag labels; inner container slot is not claimed because Magelo does not expose it in the captured payload.
- Live-loot-only ownership shows as pending Magelo refresh.

## v0.15.1-demo.5
- Moves Live Loot to the top of the main workflow as the primary active experience.
- Replaces raw Magelo ID counters with player-facing inventory insights.
- Inventory now highlights mapped Research pieces, high-value components, ready recipes, and storage distribution.
- Keeps raw inventory diagnostics out of the primary UI.

## v0.15.1-demo.2
- Added EQRed selectable skin based on supplied EverQuest UI textures and spell artwork.
- Visible live-loot feed now includes all observed loot and always shows the looter; non-Research items display as OTHER.
- Include other characters defaults on for fresh installs while saved choices remain respected.


## v0.15.1-demo.1
- Added dedicated Settings workspace opened from the top-right header.
- Moved Application Updates, Bastion data sync, live monitor configuration, alerts, ownership, and advanced data tools out of the main workflow.
- Kept Magelo, class selection, spell readiness/detail, live loot results, and reverse lookup on the main screen.
- No updater install mechanics changed from accepted v0.15.0 production.

## v0.15.0
- Promoted the Windows-tested GitHub updater to production.
- Checks the latest stable GitHub release from inside the app.
- Downloads the release ZIP through the local companion and verifies GitHub SHA-256 before install.
- Creates a full timestamped backup before replacement.
- Preserves `monitor-config.json` across updates.
- Restarts automatically after a successful update and restores backup on failure.
- Reports previous update result and available rollback backups.
- Retains the two newest backups for the current install path.

## v0.14.1-demo.5
- Fixes demo updater status detection so demo builds newer than the latest stable release display `DEMO AHEAD` instead of `UP TO DATE`.
- No self-install, backup, rollback, download, or restart mechanics changed.

## v0.14.1-demo.4
- Adds startup reporting for the previous updater result (`update-result.json`).
- Separates Demo Build, Stable Baseline, and Latest Stable version status.
- Discovers timestamped rollback backups for the current install path.
- Adds post-success backup retention: keep the two newest matching backups.
- Keeps the tested demo.3 replacement/rollback engine unchanged otherwise.

# Changelog

## v0.14.1-demo.4
- Added guarded self-install/restart path for already verified GitHub release assets.
- Entire current application folder is backed up before replacement.
- Preserves monitor-config.json and writes update-result.json.
- Refuses install if staged ZIP hash no longer matches GitHub SHA-256 digest.
- Demo install may intentionally install the current stable v0.14.0 to validate rollback-safe replacement.

## 0.14.0
- Promoted selected tested demo functionality to stable production.
- Added Bastion spell class/level metadata synchronization.
- Added tracked-loot ownership modes for group/personal vs raid/observation use.
- Added Magelo reconciliation for provisional live-loot inventory counts.
- Added full session loot CSV export.
- Enabled sounds/attention alerts by default.
- Preserved production live-log requirement.
- Did not promote visual skins, no-log demo behavior, bag-slot display, or combined sync workflow.
- Sanitized the release tree for public GitHub distribution.
- Added updater/release manifest foundation.
