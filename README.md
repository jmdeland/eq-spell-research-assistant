# EverQuest Research & Loot Tool by Bromm

**Live Loot · Inventory Mapping · Spell Research**

A Windows companion tool built for **Bastion** players who want to spend less time digging through bags, banks, spreadsheets, and recipe pages — and more time actually playing EverQuest.

The app combines **live loot monitoring**, **Bastion Magelo inventory tracking**, **spell Research planning**, and **reverse item lookup** in one place.

> Loot something → immediately know if it matters → see what it can make → find the pieces in your bags or bank → research the spell.

## Download

**Latest stable release: v0.16.0**

- [Download EverQuest Research & Loot Tool v0.16.0](https://github.com/jmdeland/eq-spell-research-assistant/releases/download/v0.16.0/eq_spell_research_assistant_v0.16.0.zip)
- [View the latest GitHub Release](https://github.com/jmdeland/eq-spell-research-assistant/releases/latest)

SHA-256 for v0.16.0:

```text
050f3d21c80d21cc7502b52948d97a8132b4f39adcaf8668332b483a618f41be
```

## What it does

The tool watches your EverQuest log in real time and identifies useful Research drops as they happen.

When something is looted, you can immediately see:

- what was looted
- who looted it
- whether it is useful for Research
- how many verified Research uses it has
- whether the item is considered high value
- whether that drop just completed a spell recipe you can now make

It also connects to your **Bastion Magelo** inventory and compares your carried inventory, bank, and shared bank against known Research recipes.

Instead of asking:

> Do I already have all the pieces for this?

The tool can tell you:

> **You can make this now.**

And when possible, it also tells you where the ingredient is stored — for example **Inventory Bag 7** or **Bank Bag 2**.

## Features

### Live Loot Monitor

- Watches your active EQ log in real time
- Shows the looter name for every tracked loot event
- Automatically identifies verified Research items
- Distinguishes normal loot, Research loot, and high-value Research components
- Supports Group / Personal and Raid / Observation ownership modes
- Can provisionally count newly looted items toward inventory until Magelo confirms them
- Alerts when a newly looted component makes a spell craftable
- Session Research loot summary
- CSV export of session loot

### Bastion Magelo Inventory Integration

- Loads inventory, bank, shared bank, and gear from a Bastion Magelo character page
- Uses exact item IDs when available
- Correctly reads stacked item quantities
- Tracks ingredient placement by inventory/bank bag
- Reconciles provisional live-loot counts after a Magelo refresh
- Provides a player-friendly inventory summary instead of raw database IDs

### Spell Research Planner

- Browse Researchable spells
- Filter by class, level, Research skill, and readiness
- See exact ingredients required for each recipe
- See how many of each ingredient you currently own
- See where owned ingredients are stored
- See how many combines your current inventory supports
- Uses the actual default EverQuest spell icons from the ROF2/Bastion client data

### Item Lookup

Ever look at something like:

> `Part of Finnok's Treatise Pg. 2`

and wonder whether you should keep it?

Search the item and see every verified spell or Research use mapped to it.

This is designed to answer the practical question:

> **Keep it or vendor it?**

High-value Research items are clearly identified.

### Fast Search & Autocomplete

Autocomplete is available in **Quick Loot Lookup**, **Item Lookup**, and **Researchable Spells**.

Type a partial name such as:

```text
Rune of Z
```

and matching suggestions appear automatically.

Keyboard controls:

- **Up / Down** — move through suggestions
- **Tab** — complete the highlighted or first suggestion
- **Enter** — select or run the relevant action
- **Esc** — dismiss suggestions

Exact item IDs still work too.

### Research Alerts

Optional sound alerts are available for:

- high-value Research components
- any verified Research item
- a spell becoming craftable

Volume and the high-value threshold are configurable in Settings.

### Inventory Intelligence

The main Inventory workspace summarizes useful information such as:

- total Research pieces owned
- distinct high-value components
- ready recipes
- carried vs banked vs shared-bank totals

### Built-in Updating

The application can update itself from GitHub Releases.

The updater:

- checks for a newer stable release
- downloads the official release ZIP
- verifies the GitHub-provided SHA-256 digest
- creates a timestamped full-folder backup
- preserves local `monitor-config.json`
- installs the new version
- restarts automatically
- restores the backup if replacement fails
- keeps rollback backups available

Updating is optional. Older installed releases do **not** expire just because a newer version exists.

### Appearance Options

The app currently includes four appearance choices:

- **Default** — dark charcoal / black / grey
- **EQBlue**
- **EQGold**
- **EQRed**

All themes use the same workspace layout so visual styling can evolve without changing functionality.

## Installation

1. Download the ZIP from the official GitHub Release page.
2. Extract the **entire ZIP** to a permanent folder.
3. Do **not** run the application from inside the ZIP file.
4. Run `INSTALL-DESKTOP-SHORTCUT.bat` once if you want a desktop shortcut.
5. Launch **EverQuest Research & Loot Tool** from the desktop shortcut or `START-RESEARCH-TOOL.bat`.
6. On first launch, choose your active EverQuest `eqlog_*.txt` file when prompted.
7. Enter your Bastion character name in the Inventory section and choose **Load / Refresh Magelo**.
8. Leave the tray companion running while you play.

The older `START-LIVE-MONITOR.bat` remains available for troubleshooting.

## Windows SmartScreen / Unknown Publisher

This is a hobby project and the launcher is **not code-signed**.

Windows may display an **Unknown publisher** or Microsoft Defender SmartScreen warning.

Only continue when you downloaded the files from this repository's official GitHub Release page.

## System Tray Companion

The recommended launcher starts the monitor quietly and places a small tray icon near the Windows clock.

The tray menu provides access to:

- Open Research Tool
- Monitor Status
- Restart Monitor
- Exit

Choosing Exit warns that live loot monitoring will stop until the tool is started again.

## Accuracy

Accuracy is a core design goal.

The tool prefers exact item IDs and verified Bastion recipe evidence whenever possible. Items with the same visible name but different IDs are kept distinct where the data supports it.

If the tool does not have enough verified information to identify a Research use confidently, it is designed to avoid inventing one.

Bastion Magelo is the preferred inventory source. The parser preserves exact item IDs, rendered stack quantities, and verified inventory/bank bag placement.

## Current Scope

The application is currently focused on **Bastion** Research and the supported spell/recipe dataset through the current project scope.

The data architecture is intentionally designed so coverage can continue to expand over time.

## Privacy

The app runs locally on your computer.

Local settings, inventory state, and monitor configuration remain on your PC unless you explicitly export or share them.

The application contacts public Bastion pages for requested Magelo/data synchronization and GitHub Releases for update checks/downloads.

## Screenshots

The recommended screenshot order for posts or documentation is:

1. **Live Loot Monitor** — real-time loot classification and craftable-spell alert
2. **Spell Planner** — Researchable spell list and selected recipe readiness
3. **Inventory + Research Filters** — Magelo inventory intelligence
4. **Item Lookup** — reverse Research-component lookup
5. **Settings & Configuration** — alerts, monitoring, Bastion data, themes, and updates

> Repository screenshots can be added later under `docs/images/` without changing the application itself.

## Development Channels

- `main` — stable production
- `demo` — experimental/testing builds

## Feedback

This project is actively evolving. If you find a recipe/data mismatch, UI issue, or behavior that does not match Bastion/EverQuest, please report it with as much detail as possible so it can be verified and corrected.
