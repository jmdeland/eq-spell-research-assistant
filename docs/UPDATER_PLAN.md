# Updater Plan

The intended updater will use GitHub Releases, not the mutable `main` branch.

## Phase 1 — Check for updates
The app reads a stable JSON manifest and compares `app-version.json` to the published version. If newer, it shows release notes and a download action.

## Phase 2 — Verified download
The PowerShell companion downloads the release ZIP, computes SHA-256, and refuses installation if the checksum does not match the manifest.

## Phase 3 — One-click install
The updater extracts to a temporary directory, preserves user-specific configuration/data, replaces program files after the running companion exits, and restarts the application.

## Separation rule
Program files and user-specific state should remain separate so upgrades never overwrite local settings, selected character, or future local caches.
