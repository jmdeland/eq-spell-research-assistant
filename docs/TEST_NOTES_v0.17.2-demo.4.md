# v0.17.2-demo.5 Test Notes

## Portable mode
1. Extract to a fresh folder.
2. Double-click `RUN-PORTABLE.bat`.
3. Confirm the app opens and shows v0.17.2-demo.5.
4. Loot an item and confirm `portable-data\session-loot.jsonl` is created/updated.
5. Confirm Observed Loot History writes beneath `portable-data\history\`.
6. Set a loot-value override and Magelo profiles, close the app, reopen Portable mode, and confirm they persist.
7. Run `INSTALL-DESKTOP-SHORTCUT.bat`; accept the portable-data import prompt.
8. Launch from the desktop shortcut and confirm session/history/settings are present in Desktop mode.

## Existing feature regression checks
- Two Magelo profiles load and aggregate correctly.
- Shared Bank deduplication remains correct.
- Session persistence and restore remain functional.
- Observed History records normal loot.
- Corpse recovery uses the in-zone `Returning to Resurrect, please wait...` path when applicable.
- Not Valuable overrides suppress value alerts without hiding verified Research uses.

## Windows validation
This build has only static/package validation until tested on Windows PowerShell 5.1.
