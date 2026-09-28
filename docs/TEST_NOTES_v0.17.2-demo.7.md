# v0.17.2-demo.8 Test Notes

1. Extract to a fresh folder and double-click `START HERE.bat`.
2. Confirm Portable, Desktop, Check / Repair, and Exit are clear.
3. Portable should launch `0.17.2-demo.8` and keep data under `portable-data`.
4. With a blank `monitor-config.json`, exactly one recently active common Sony EverQuest log should be selected automatically; multiple candidates should open the Windows picker with the newest suggested.
5. Desktop Mode should preserve the demo.6 backup + safe history merge and then launch automatically.
6. Check / Repair Setup should report core files, saved log, and—while running—the main service, Live Loot worker, and persistence worker.

Regression: two-character Magelo, Shared Bank dedupe, loot-value overrides, session persistence, Observed History, and corpse-recovery behavior are unchanged.
