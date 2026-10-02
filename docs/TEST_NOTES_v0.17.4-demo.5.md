# v0.17.4-demo.5 Test Notes

## Purpose
Final release-candidate fix for a confirmed desktop-launch failure caused by an orphaned tray process holding the single-instance mutex while port 8765 was offline.

## Confirmed failure reproduced before this build
- `tray.pid` referenced a live PowerShell tray process.
- Port 8765 was offline.
- Launching the desktop shortcut silently exited because the tray mutex was still owned.
- Manually stopping the stale tray process allowed stable v0.17.4 to launch normally.

## Fix
- A second launch still reuses a healthy running instance.
- If the mutex is owned but port 8765 is offline, the launcher treats the state as potentially orphaned.
- It only terminates a process after verifying its Windows command line explicitly contains `research-tool-tray.ps1`.
- If `tray.pid` is missing or stale, it can locate only verified Research & Loot Tool tray PowerShell processes.
- It removes the stale PID file and retries mutex acquisition.
- `AbandonedMutexException` is treated as successful ownership transfer.
- If safe recovery cannot be completed, the app displays a warning instead of failing silently.

## Regression expectations
No intended change to native alerts, 8767 readiness, Live Loot, history, migration, Magelo, Research, corpse recovery, or desktop root selection.
