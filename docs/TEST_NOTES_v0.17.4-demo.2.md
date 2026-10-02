# v0.17.4-demo.4 Test Notes

## Focus
Desktop shortcut / persistent launcher path encoding.

1. Exit the tray app completely.
2. Run `START HERE.bat` and choose Desktop Mode.
3. Confirm Desktop Setup completes and creates/refreshed the shortcut.
4. Launch only from the desktop shortcut.
5. Confirm the app starts from the demo.2 folder.
6. Reboot Windows and launch only from the desktop shortcut again.
7. Confirm the app still starts from the demo.2 folder.
8. Run `/api/status` and confirm version `0.17.4-demo.4`, channel `demo`, and the expected root.
9. Inspect `%LOCALAPPDATA%\EverQuest Research & Loot Tool\install-root.txt`; it should contain only the application folder path with no leading `ï»¿`.

Also recheck background alert timing and the version-specific desktop icon.
