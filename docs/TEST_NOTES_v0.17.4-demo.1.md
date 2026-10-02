# v0.17.4-demo.4 Test Notes

## Purpose
Focused final-polish candidate on top of stable v0.17.3.

## 1. Desktop shortcut root test
1. Extract this demo to a fresh folder.
2. Run `START HERE.bat` -> Desktop Mode.
3. Confirm the desktop shortcut launches this demo.
4. Reboot Windows.
5. Launch only from the desktop shortcut.
6. Confirm `/api/status` reports `0.17.4-demo.4` and the fresh demo root, not an older demo/stable folder.
7. Optionally launch an older copy manually, exit it, then launch the desktop shortcut again. The shortcut should still resolve the root last selected through Desktop Setup.

## 2. Icon refresh
After Desktop Setup, inspect shortcut properties. The shortcut should target `wscript.exe` with a LocalAppData persistent-launcher argument and use a version-specific icon under `%LOCALAPPDATA%\EverQuest Research & Loot Tool\`.

## 3. Sound reliability
1. Open the app and interact with it once to unlock browser audio.
2. Use the existing replay/test path to verify sound.
3. Leave the tab in the background while normal Live Loot continues.
4. Verify high-value/research/craftable sounds no longer wait for a later click when the AudioContext was suspended.
5. Return to the tab and verify alerts continue normally.

## 4. Setup Check
Run `START HERE.bat` -> Check / Repair Setup and verify it reports Desktop app location and Desktop shortcut status.

## Regression
- Correct active EverQuest log remains selected.
- Live Loot and session persistence continue working.
- Observed History remains intact.
- Two-character Magelo and Shared Bank behavior remain intact.
- Portable <-> Desktop migration retains backup + merge safety.
- Updater still stages/verifies with SHA-256 and restarts successfully.

## Validation limitation
Static JavaScript/packaging checks can be performed here. Windows shortcut COM behavior, reboot persistence, Windows icon caching, and real background-browser audio require live Windows testing.
