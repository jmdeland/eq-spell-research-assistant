# v0.17.4 Stable Acceptance Notes

Accepted release-candidate behavior from v0.17.4-demo.5:

- Native Windows loot alerts play immediately during real loot and direct sound tests.
- Live Event Worker reports ready and exposes startup timing.
- Correct active EverQuest client/log selection was verified.
- Observed History was consolidated/recovered and remains available.
- Persistent Desktop launcher selects the intended application root.
- Desktop launcher path encoding was verified without BOM/path corruption.
- The stale-tray failure was deliberately reproduced by stopping the demo monitor while leaving the tray alive.
- Relaunching from the Desktop icon successfully identified/recovered the orphaned tray and restarted the correct application.
- Live Loot mode presentation receives release-only high-contrast bold + underline styling.

No additional functional feature changes were introduced during stable promotion.
