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
