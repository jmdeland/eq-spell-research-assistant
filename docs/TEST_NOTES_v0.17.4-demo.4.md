# v0.17.4-demo.4 Test Notes

## Purpose
Final polish of Live Event Worker startup after demo.3 proved native Windows alert audio is immediate once 8767 is ready.

## Test 1 — Startup readiness
1. Exit the tray app completely.
2. Launch `0.17.4-demo.4` in Desktop Mode.
3. Immediately run `Invoke-RestMethod "http://127.0.0.1:8767/api/native-alert-status" | Format-List *`.
4. Confirm the endpoint becomes reachable promptly and reports `ready : True`.
5. Record `startupMs`.
6. In the UI, a brief startup should show `STARTING`, not an alarming offline/error message.

## Test 2 — Native audio regression
1. Put EverQuest in the foreground and leave the tool tab in the background.
2. Loot a High Value or Research item that should alert.
3. Confirm sound is immediate and no delayed duplicate occurs when returning to the browser.
4. Run the direct high/research/craftable native-sound-test endpoints and confirm immediate playback.

## Test 3 — Desktop launcher/reboot
1. Install Desktop Mode from this demo.
2. Launch from the desktop icon and verify `/api/status` reports `0.17.4-demo.4`.
3. Reboot Windows.
4. Launch only from the desktop icon.
5. Confirm `/api/status` still reports `0.17.4-demo.4` and the expected install root.

## Regression
- Observed Loot History continues recording.
- Session persistence remains intact.
- Correct active EQ log is selected.
- Two-character Magelo and Shared Bank behavior are unchanged.
- Portable/Desktop safe history merge remains unchanged.
- Corpse recovery remains unchanged.
