# v0.17.2-demo.8 Test Notes

## Desktop -> Portable onboarding
- Start from a fresh extraction with existing Desktop data in `%LOCALAPPDATA%\EverQuest Research & Loot Tool`.
- Choose Portable Mode from `START HERE.bat`.
- Confirm the tool offers to use existing Desktop data.
- Choose Y and confirm settings/history are copied/merged, not overwritten.
- Confirm Desktop data remains unchanged and a portable backup is made if portable data already existed.
- Confirm Observed History is present after launch.

## Active EQ log selection
- With Bastion_1.1 stale and Bastion_1.2 actively writing, clear `monitor-config.json` logPath.
- Start Portable Mode.
- Confirm the single log updated within 10 minutes is selected automatically.
- `/api/status` should point to the active Bastion_1.2 log.
- Confirm current zone matches the newest zone-entry/PID lines.

## Regression
- Portable -> Desktop safe backup/history merge from demo.6 remains intact.
- Two-character Magelo, Shared Bank dedupe, loot-value overrides, sessions, Live Loot, Observed History, and corpse-recovery behavior remain unchanged.
