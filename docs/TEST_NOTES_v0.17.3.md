# v0.17.3 Release Verification

This stable release is promoted from the accepted `v0.17.2-demo.8` baseline with no intended functional changes beyond stable version/channel/release metadata and documentation.

## Verified during demo testing
- Portable Mode launches and persists data under `portable-data`.
- Portable -> Desktop migration backs up destination data and merges Observed Loot History.
- Desktop -> Portable onboarding preserves existing Desktop data and imports history/settings into Portable Mode.
- Active Bastion 1.2 log selection was verified against a stale Bastion 1.1 install.
- Startup zone resolved correctly to Karnor's Castle from the active log.
- Two-character Magelo, session/history persistence, and Live Loot architecture remain part of the baseline.

## Stable release checks
- Confirm header/version shows `v0.17.3`.
- Confirm `/api/status` reports `version = 0.17.3` and `channel = stable`.
- Confirm current EQ log path and zone are correct.
- Confirm Observed History is present.
- Confirm Portable Mode and Desktop Mode both launch through `START HERE.bat`.
- Confirm updater reports this GitHub Release as the latest stable version after publishing.
