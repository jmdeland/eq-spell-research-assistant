# v0.17.2-demo.3 Test Notes

## Scope

This demo contains two focused changes on top of v0.17.2-demo.2:

1. In-zone corpse-recovery detection for Bastion resurrection sequences that emit `Returning to Resurrect, please wait...` without a new `You have entered <zone>` line.
2. Persistent player loot-value overrides (Default / High Value / Keep / Not Valuable).

## Corpse Recovery Test

Expected sequence:

- Player dies (`You have been slain by ...`).
- Resurrection restores experience.
- Bastion logs either a normal zone-entry return or `Returning to Resurrect, please wait...`.
- Self-looted corpse items are marked `CORPSE RECOVERY — not counted as a new drop`.
- Corpse items remain visible in the current session but do not increase provisional ownership, Research readiness, alerts, or permanent Observed Loot History.

Confirm ordinary self-loot after the recovery window is classified normally.

## Loot Value Override Test

- Click a Live Loot row to open item details.
- Set Player Value to `Not Valuable` for an item such as Bone Chips.
- Confirm future drops show `NOT VALUABLE` and do not trigger value/Research attention sounds.
- Confirm verified Research uses are still displayed and recipe readiness data is not removed.
- Restart the app and confirm the override remains.
- Open Settings > Loot Value Overrides and confirm the item is listed.
- Use `Use Default` and confirm automatic classification returns.

## Regression Checks

- Two-character Magelo still loads and aggregates correctly.
- Shared Bank deduplication remains intact.
- Session persistence and recovery remain functional.
- Observed Loot History continues writing normal loot.
- Port 8767 Live Event Worker latency remains unaffected.
