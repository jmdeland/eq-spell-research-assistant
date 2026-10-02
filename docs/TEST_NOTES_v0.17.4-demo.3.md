# v0.17.4-demo.4 Test Notes

## Goal
Verify that loot alert audio is immediate even when the browser tab is backgrounded or EverQuest has focus.

## Test A - Native alert worker status
1. Start the app normally.
2. Run: `Invoke-RestMethod "http://127.0.0.1:8767/api/native-alert-status" | Format-List *`
3. Confirm `native : True`, `enabled : True`, and a non-zero `researchItems` count.

## Test B - Direct sound test
Run: `Invoke-RestMethod "http://127.0.0.1:8767/api/native-sound-test?kind=high"`
A two-tone High Value alert should play immediately without selecting the app tab.
Repeat with `kind=research` and `kind=craftable`.

## Test C - Background EverQuest test
1. Leave the browser tab in the background.
2. Put EverQuest in the foreground.
3. Loot a verified High Value component.
4. Confirm the alert plays at loot time, not when returning to the browser.
5. Confirm returning to the browser does not produce a delayed duplicate tone.

## Test D - Mute / volume / override
- Use Mute Sounds / Attention Alerts and confirm native alerts stop after the saved state syncs.
- Change Sound Volume and confirm subsequent native tones change accordingly.
- Mark an item Not Valuable and confirm its normal High Value/Research attention sound is suppressed while its verified Research uses remain visible.

## Test E - Class-only mode
Enable Only selected class. Exact alert classification remains browser-side in this mode; verify there are no incorrect native alerts for other classes.

## Regression
- Desktop shortcut launches demo.3 from the selected root.
- Reboot test still launches the selected root.
- Live Loot, Observed History, sessions, Magelo, corpse recovery, and portable/Desktop migration remain unchanged.
