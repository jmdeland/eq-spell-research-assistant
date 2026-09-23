# Changelog

## v0.17.1-demo.1

### Corpse Recovery Protection
- Detects successful resurrection from the EverQuest log and arms corpse-recovery tracking for the first post-resurrection self-loot sequence.
- Requires the first self-loot event to begin within 120 seconds after returning to the resurrection zone.
- Keeps the recovery sequence active while self-loot continues, ending it after 60 seconds without another recovered item, after 10 minutes total, or on another zone transition.
- Marks recovered loot as `corpse_recovery` in the live event/session record.
- Shows **CORPSE RECOVERY — not counted as a new drop** in the Live Loot feed for easy field testing.
- Keeps recovered items in the current recoverable session and CSV export for transparency.
- Does not count recovered items as new session loot, provisional owned inventory, Research readiness progress, craftable alerts, or Research loot sounds.
- Excludes recovered items from permanent Observed Loot History so corpse contents cannot be learned as drops from the recovery zone.
- Applies the same detection logic to both the dedicated Live Event Worker and the main companion fallback parser.
- Adds corpse-recovery status fields to live polling diagnostics.

## v0.17.0

### Zone Tracking & Observed Loot History
- Adds live zone tracking from Bastion/ROF2 log messages.
- Preserves canonical zone names for instanced zones and stores Zone ID, Instance ID, and Version as separate metadata.
- Adds a dedicated Observed History workspace with item, zone, looter, and Research filters.
- Stores raw observations permanently in monthly archive files.
- Adds a compact history index and archive-aware searching.
- Adds optional Observed Loot History recording, ON by default; disabling it never deletes existing history.
- Keeps zone tracking active even when permanent history recording is disabled.

### Live Loot Reliability & Performance
- Adds a dedicated Live Event Worker on port 8767.
- Keeps the main application/API on port 8765.
- Keeps session/history persistence on port 8766.
- Keeps history indexing in a separate hidden worker process.
- Preserves display-first Live Loot behavior and latency diagnostics.
- Preserves session byte-watermark reset protections so ended-session loot does not reappear.

### Maintenance
- Retains in-place updater replacement and automatic browser refresh after successful updates.
- Retains atomic Bastion corpus sync behavior and icon-loading improvements.

## v0.17.0

- Fixes Bastion instanced-zone identity so different instances no longer collapse into the generic `a Instanced Version of the zone` bucket.
- Treats the Bastion PID line as authoritative instance identity when it follows a zone transition, when the current zone is a generic instance placeholder, or when the PID zone already matches the current zone.
- Preserves the real zone name separately from instance metadata. Example: `Chardok: The Halls of Betrayal` + Zone ID 277 + Instance ID 120 + Version 255.
- Adds a 30-second zone-transition association window so the delayed PID line can enrich the correct zone without allowing unrelated stale PID messages to replace the active zone later.
- Applies the same parser behavior to both the dedicated Live Event Worker and the main companion fallback/replay parser.
- Keeps dedicated Live Loot delivery on port 8767, persistence on 8766, history indexing out-of-process, and the demo.8 Research/UI behavior baseline.

## v0.17.0-demo.10

- Rolls back the demo.9 Research/planner refresh experiment to the demo.8 UI/behavior baseline.
- Adds a dedicated hidden **Live Event Worker** on localhost port **8767**.
- The Live Event Worker has one job: tail the active EverQuest log, track zone context, and serve `/api/live-poll`.
- The browser now polls port 8767 directly for Live Loot instead of sharing the main application companion on port 8765.
- The main companion no longer continuously tails the EQ log while waiting for application/API requests.
- Session/history persistence remains isolated on port 8766.
- History indexing remains in its own hidden worker process.
- The Live Event Worker watches `session-meta.json` and resets its source boundary automatically when End Current Loot Session rotates the session.
- Keeps the demo.8 UI, dedicated Observed History workspace, monthly archives, and updater/session reliability fixes.

## v0.17.0-demo.8

- Adds a separate hidden **persistence worker** on localhost port 8766.
- Session recovery writes and permanent monthly-history writes no longer use the Live Loot listener on port 8765.
- Live `/api/live-poll` traffic now has a dedicated listener lane instead of waiting behind disk persistence requests.
- Removes automatic history-summary/index parsing from the recurring Live polling path.
- Keeps persistence batching asynchronous and increases its batching window because it can no longer block Live delivery.
- Keeps stale-session protection by validating persistence writes against the authoritative `session-meta.json`.
- Keeps raw observed-history archives as the source of truth and retains the separate history-index worker.
- Retains display-first Live Loot, batched Research recalculation, zone tracking, monthly archives, and updater/session reliability fixes.

## v0.17.0-demo.7

- Changes Live Loot to a two-stage pipeline: **display first, classify second**.
- New loot rows are painted immediately with a brief `CHECKING` state before Research classification completes.
- The latency badge is now updated at the immediate-display stage instead of after Research processing.
- Batches Research recipe-readiness recalculation so a burst of multiple Research drops triggers one readiness pass instead of one pass per item.
- Defers Research planner/reverse-lookup rerendering until after Live Loot has painted.
- Adds a bounded Live classification cache for repeated loot names.
- Retains the separate history-index worker, combined fast Live polling endpoint, monthly archives, zone tracking, updater polish, and prior reliability fixes.

## v0.17.0-demo.6

- Moves Observed Loot History index maintenance into a dedicated hidden PowerShell worker process.
- Live Loot recognition no longer performs history-index updates or index serialization on the companion thread.
- The worker watches monthly history archives and updates `loot-history-index.json` independently.
- Raw monthly history files remain the source of truth; no observation data is discarded.
- Existing history is automatically reindexed by the worker when its state file is missing.
- History index reads now detect worker-written index changes instead of holding a stale in-memory copy forever.
- Renames latency breakdown labels to **timestamp→companion** and **companion→browser** so blocked companion time is not misidentified as an EverQuest log-write delay.
- Reduces automatic history-summary refresh frequency on the Live page.
- Keeps the combined fast Live polling endpoint, 125 ms browser poll interval, zone tracking, monthly archives, updater polish, and all prior reliability fixes.

## v0.17.0-demo.5

- Removes periodic full history-index serialization from the Live Loot critical path.
- Adds a combined `/api/live-poll` endpoint so status and new loot arrive in one request.
- Forces an immediate EQ-log read whenever the browser requests live data.
- Reduces the companion wait interval to 75 ms and browser Live polling to 125 ms.
- Adds per-event `detectedAt` timing so the app can distinguish EQ log/source delay from app delivery delay.
- Adds a Live **LATENCY** badge showing total observed delay; hover it to see source-vs-delivery timing.
- Keeps raw monthly history writes and all existing archive data intact.
- Keeps the history index rebuildable and flushes it on clean shutdown rather than blocking Live Loot every few seconds.
- Retains dedicated Observed History workspace, monthly archives, zone tracking, updater polish, and all prior reliability fixes.

## v0.17.0-demo.4

- Reduces Live Loot browser polling from 1 second to 250 ms for much faster recognition.
- Reduces the companion log-read wait interval from 250 ms to 125 ms.
- Stops loading detailed Observed History in the background while using Live & Research.
- Adds a lightweight history-summary endpoint for the Home card/navigation counters.
- Only reads archive event rows when the Observed History workspace is actually opened or filtered.
- Keeps the history index in memory and flushes it to disk about every five seconds instead of rewriting the full index on every loot batch.
- Raw monthly loot observations are still appended immediately; deferred index writes cannot lose the authoritative observation data and the index remains rebuildable.
- Forces a final history-index flush on clean companion shutdown.
- Retains dedicated workspaces, monthly archives, permanent retention, zone tracking, and all v0.16.x reliability fixes.

## v0.17.0-demo.3

- Moves **Observed Loot History** out of the main Live/Research page into its own full-width workspace.
- Adds top-level **Live & Research** and **Observed History** navigation.
- Adds a compact history summary card on the main page with total observations, zones, and unique items.
- Adds an **Open History** shortcut from the main page and a **Back to Live & Research** control from History.
- Remembers the selected workspace for the current browser session.
- Automatically hides the History navigation and Home summary card when permanent history recording is turned OFF.
- Keeps zone tracking and current-session zone stamping active regardless of the selected workspace.
- Keeps monthly archive rotation, archive-aware searching, permanent raw retention, storage statistics, and the compact history index from demo.2.
- Carries forward updater auto-refresh/in-place backup behavior and all v0.16.x session/sync reliability fixes.

## v0.17.0-demo.2

- Replaces the single growing history file with automatic monthly archives under the local history folder.
- Adds a compact `loot-history-index.json` used to identify relevant archive months before detailed history reads.
- Makes archive searching transparent: item, zone, looter, and Research filters automatically query the relevant monthly files.
- Keeps every raw observation indefinitely; there is no automatic purge or retention limit.
- Adds **Record Observed Loot History** in Settings, ON by default.
- Turning history recording OFF stops new archival writes and hides the history workspace without deleting any existing data.
- Zone tracking and current-session zone stamping remain active even when permanent history recording is OFF.
- Adds total observation count, disk usage, archive count, and oldest-history status.
- Adds a manual **Rebuild History Index** maintenance control.
- Automatically migrates v0.17.0-demo.1's legacy `loot-history.jsonl` into monthly archives and keeps the original as a `.bak` file after successful migration.
- Retains all v0.17.0-demo.1 zone tracking/history UI and all v0.16.x updater/session/sync fixes.

## v0.17.0-demo.1

- Adds live zone tracking from Bastion/ROF2 `You have entered <zone>.` log messages.
- Recovers the most recent known zone from the tail of the active log at companion startup.
- Captures zone ID, instance ID, and zone version from Bastion PID/instance log messages when available.
- Stamps every observed loot event with zone context.
- Adds permanent local **Observed Loot History** stored separately from the active/resettable loot session.
- Adds history filters for item, zone, looter, and Research classification.
- Adds observed-event, unique-item, zone, and Research-related summary metrics.
- Adds Top Zones and Top Items summaries.
- Adds CSV export for persistent observed loot history.
- Adds Zone columns to current-session CSV export and shows zone directly on Recent Loot.
- Carries forward v0.16.7-demo.1 updater auto-refresh/in-place backup behavior and all v0.16.6 reliability fixes.

## v0.16.7-demo.1

- Automatically reloads the browser after the updated companion is verified running, so the top-right version badge and all build-stamped assets update without a manual refresh.
- Changes updater backups from **moving/renaming the active install folder** to **copying its contents** into the rollback backup.
- Keeps the active install root directory in place while replacing its contents.
- Prevents an open Windows File Explorer window from following the application folder into the `_backup_...` directory during updates.
- Updates rollback to restore backup contents into the existing install root.
- Retains all v0.16.6 Live Loot, session reset, Bastion sync, cache, and icon improvements.

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
