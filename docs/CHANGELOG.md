# Changelog

## v0.16.6

- Fixes End Current Loot Session so cleared loot does not return.
- Adds an authoritative EQ log byte watermark when a new loot session begins.
- Adds backend-owned loot session IDs and rejects delayed writes from closed sessions.
- Suspends polling and persistence safely while a session reset is in progress.
- Improves Live Loot responsiveness during long and busy sessions.
- Removes lazy loading from local spell icons so Researchable Spells icons appear faster.
- Adds cache-control and build-version query strings so updated browser code is not reused from an older build.
- Makes Bastion Research corpus syncing safe while the application remains open.
- Uses atomic file replacement and retry handling for transient Windows file locks during sync.
- Preserves v0.16.5 updater restart-state recovery and v0.16.4 performance improvements.

## v0.16.6-demo.6

- Makes Bastion Research corpus sync safe while the application remains open.
- Writes completed sync data to a temporary file first, then atomically replaces the live corpus.
- Retries transient Windows file-lock failures instead of aborting the entire sync.
- Keeps the previous verified corpus available until the new corpus is fully written.
- Uses the same atomic-write protection for sync status files.
- Applies the same safe-write path to the companion's internal Research corpus writer.
- Retains demo.5's proven session-reset log watermark, session IDs, cache-control fixes, and immediate spell-icon loading.

## v0.16.6-demo.5

- Adds an authoritative **EQ log byte watermark** when End Current Loot Session is used.
- The companion advances its log reader to the file's current physical end before the new session begins.
- Clears any partial-line carry buffer during reset.
- Prevents the reader from falling behind the new session watermark unless the EQ log is genuinely truncated/rotated.
- Exposes `sessionStartPosition` and reset time in diagnostics.
- Retains authoritative backend session IDs, stale-write rejection, polling suspension, cache-control fixes, and immediate spell-icon loading.

## v0.16.6-demo.4

- Replaces timing-only session clearing with an authoritative backend session identity.
- Every active loot session now has a persistent unique session ID.
- **End Current Loot Session** rotates to a new backend session ID before deleting the old session data.
- Delayed writes from the closed session are permanently rejected with HTTP 409 and are never retried.
- Older browser tabs/builds that do not send a valid session ID can no longer resurrect cleared loot.
- The browser automatically adopts the backend's current session ID.
- If another window ends the session, this page detects the session-ID change and clears its stale in-memory session.
- Session state exposes stale-write diagnostics for troubleshooting.
- Retains demo.3 polling suspension, demo.2 cache-control fixes, and immediate spell-icon loading.

## v0.16.6-demo.3

- Fixes a second End Session race where a new Live Loot poll could start after reset began but before the backend clear completed.
- Suspends all Live Loot polling for the full duration of session reset.
- Invalidates polls that were already in flight when reset begins.
- Prevents new session-persistence queue entries while reset is active.
- Prevents normal event processing while reset is active.
- Waits for any active persistence write to settle before clearing.
- Clears and verifies backend persistence while polling is suspended.
- Moves the browser event cursor to the backend's post-clear frontier before polling resumes.
- Disables the End Session button while the reset is running and shows **Session Cleared** only after verification succeeds.
- Retains demo.2 cache-control fixes and immediate spell-icon loading.

## v0.16.6-demo.2

- Prevents stale browser code after updates/demos by sending `no-store` cache headers for HTML, JavaScript, CSS, and local data files.
- Adds build-version query strings to core browser assets so each build executes its own `app.js` and settings code.
- Keeps local spell-icon/image files cacheable for fast repeat rendering.
- Verifies `/api/session-state` is actually empty after **End Current Loot Session** before reporting success.
- Shows an explicit **Session Cleared** confirmation and Live Monitor status message after a verified clear.
- Retains demo.1's session-generation protection and immediate spell-icon loading.

## v0.16.6-demo.1

- Fixes a race where **End Current Loot Session** could clear successfully and then be repopulated by an older Live Loot poll already in flight.
- Adds a session-generation guard so pre-clear poll responses are discarded.
- Starts the fresh session at the monitor's current event frontier instead of resetting the browser event cursor to 0.
- Removes lazy loading from the small local spell-icon PNGs so Researchable Spells icons begin loading immediately.
- Keeps icon decoding asynchronous.
- Retains the v0.16.5 updater-state hotfix and v0.16.4 Live Loot performance improvements.

## v0.16.5

- Fixes the Application Updates page remaining stuck on **RESTARTING** after a successful update.
- Persists the target update version before installation begins.
- Detects when the local companion returns on the requested/newer version.
- Automatically changes updater status to **UPDATE COMPLETE** after restart.
- Reloads the previous update result and restores normal update controls without requiring a manual browser refresh.
- Pending update state survives a browser refresh during the restart window.
- No Live Loot, Research, session, shortcut, or updater-installation behavior changed from v0.16.4.

## v0.16.4

- Improves Live Loot responsiveness during long and busy sessions by batching persistence and UI updates.
- Avoids unnecessary full recipe recalculation for ordinary/unmapped loot.
- Fixes End Current Loot Session / Start New Session so cleared sessions cannot replay from the monitor's in-memory buffer.
- Refreshes and self-repairs the desktop shortcut so it points at the active updated application root.
- Hides the updater PowerShell window during update installation.
- Adds matching bounded scrolling panes for Recent Loot and Session Loot.
- Renames **Session Research Loot** to **Session Loot**.
- Preserves v0.16.3 updater verification, rollback backups, and single-tray/browser protections.

## v0.16.4-demo.4

- Adds a subtle border around the Recent Loot scrolling pane so its bounds are clear.
- Makes Session Loot independently scrollable at the same height as Recent Loot.
- Renames **Session Research Loot** to **Session Loot** because it contains all tracked items.
- Prevents long sessions from continuously increasing the page height.
- UI-only polish; retains demo.3 shortcut/update fixes, demo.2 Live Loot performance improvements, and demo.1 session-reset fix.

## v0.16.4-demo.3

- Refreshes the **EverQuest Research & Loot Tool** desktop shortcut after every successful update.
- The shortcut is rebuilt to point at the newly installed application root and current VBS launcher/icon.
- The tray self-repairs the desktop shortcut on normal application startup.
- Stores the current canonical application root under LocalAppData for diagnostics.
- Hides the updater PowerShell process window instead of leaving a visible console open.
- Keeps updater rollback backups rather than deleting every older application copy.
- Preserves the Live Loot performance improvements from demo.2 and session-reset fix from demo.1.

## v0.16.4-demo.2

- Performance pass for long/busy Live Loot sessions.
- Batches session persistence instead of issuing one HTTP POST per loot event.
- Batches Live Loot DOM updates so a poll containing many drops redraws the UI once instead of once per item.
- Ordinary/unmapped loot no longer forces a full recipe readiness recalculation.
- Keeps full session history and recovery persistence intact.
- Preserves the v0.16.4-demo.1 session-reset fix.

## v0.16.4-demo.1

- Fixes **End Current Loot Session** / **Start New Session** allowing the previous session to reappear.
- Clearing a session now removes both the persisted recovery file and the running monitor's in-memory event buffer.
- A new session starts at the current point in the EverQuest log rather than replaying loot already seen by the running monitor.
- The browser now verifies `/api/session-clear` succeeded instead of silently ignoring failures.
- The recovery dialog only closes after a new-session clear succeeds.
- Preserves v0.16.3 launcher, updater, single-tray, and browser-restart fixes.

## v0.16.3

- Enforces a single system-tray process to prevent duplicate tray instances.
- Makes the tray launcher the only component responsible for opening the browser.
- Prevents repeated browser tabs during startup and restored-session workflows.
- Starting the shortcut while the same build is already running opens the tool without creating another tray.
- Update and rollback restarts suppress automatic browser opening once, preserving the existing browser tab.
- Removes `cmd.exe` from updater and rollback restart paths; restarts now launch directly through `wscript.exe`.
- Fixes the Application Updates screen so the installed version reflects the actual running build.
- Moves launcher/shortcut working directories away from the application folder to reduce file-lock risk.
- Refreshes release-manifest metadata.
- Preserves v0.16.2 updater coordination, session recovery, Live Loot behavior, Bastion data, and inventory logic.

## v0.16.3-demo.4

- Removes `cmd.exe` entirely from updater and rollback restart paths.
- Successful updates now restart the hidden application launcher directly with `wscript.exe`.
- Rollback restarts use the same direct `wscript.exe` path.
- Avoids the `cmd.exe - Application Error (0xc0000142)` seen after update installation.
- Retains demo.3 truthful installed-version display.
- Retains demo.2 browser-flood fix and demo.1 single-tray behavior.
- No Research, inventory, Bastion sync, or session data behavior changed.

## v0.16.3-demo.3

- Fixes the Application Updates screen showing a hardcoded `v0.16.0` installed version.
- Installed version now comes from the running local companion and update API.
- Demo builds now clearly explain when their stable base already matches the latest stable release.
- Retains the demo.2 fix preventing repeated browser tabs during session restore/startup.
- No Research, inventory, Bastion sync, or session data behavior changed.

## v0.16.3-demo.2

- Fixes repeated browser tabs caused by the tray timer's browser-open guard using event-handler-local scope.
- The initial browser-open flag is now explicitly script-scoped, so the automatic launch can occur only once per tray session.
- Session Restore itself does not open or reload the browser.
- Retains all v0.16.3-demo.1 single-tray and updater browser-suppression changes.

## v0.16.3-demo.1

- Enforces a single system-tray process to prevent duplicate tray instances.
- Makes the tray launcher the only component responsible for opening the browser.
- The live monitor no longer launches a browser window itself.
- Normal startup opens the tool exactly once after the companion becomes available.
- Starting the shortcut while the same build is already running opens the tool without creating another tray.
- Update and rollback restarts suppress the automatic browser open once, leaving the existing browser tab in place.
- Desktop shortcut working directory is `%TEMP%`, not the application folder.
- `START-RESEARCH-TOOL.bat` no longer changes into the application directory.
- Refreshes stale release-manifest metadata.
- No Research, Bastion data, inventory, or session-recovery behavior changed.

## v0.16.2

- Hotfixes the self-updater so the system-tray companion and live monitor both release the application folder before replacement.
- Stores tray/update coordination files under LocalAppData, outside the installation folder.
- Runs the tray with a TEMP working directory and explicitly releases icon resources.
- Restarts the full tray launcher after successful updates and rollbacks.
- Adds version-aware launcher behavior so a stale companion on port 8765 is not silently reused.
- `/api/status` reports app identity/version/channel/root so launchers can safely determine whether to reuse or replace an existing companion.
- Preserves the v0.16.1 session recovery, bounded/scrollable live-loot feed, and startup update notifications.
- Automatic session expiration based on inactivity remains planned for a later feature release.

## 0.16.2

- Added version-aware tray launching so a stale companion on port 8765 is not silently reused.
- `/api/status` now reports app identity, version, channel, and application root.
- On a version mismatch, the launcher requests tray shutdown, waits for the listener to release, and only then starts the intended build.
- Retains the demo.1 updater handoff fix that waits for both tray and monitor processes before replacing the application folder.

## v0.16.2-demo.1

- Updater hotfix: coordinates shutdown of both the live monitor and system-tray companion before replacing the app folder.
- Tray PID and update-shutdown request are stored under LocalAppData outside the installation folder.
- Tray process now runs with TEMP as its working directory and releases the icon file handle.
- Successful updates and rollbacks restart the full tray launcher.


## v0.16.2-demo.1
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
