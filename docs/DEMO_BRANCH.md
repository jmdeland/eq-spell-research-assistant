# Demo Branch

## v0.14.1-demo.4
- startup updater-result reporting
- explicit demo/stable/latest version separation
- backup discovery and two-backup retention

Based directly on production v0.14.0.

Adds:
- GitHub latest-release check and release notes
- SHA-256 verified release download to `_updates`
- guarded safe-install test
- installer runs from `%TEMP%`, outside the application directory
- complete current application folder is renamed to a timestamped sibling backup before replacement
- `monitor-config.json` is preserved
- application restarts via `START-LIVE-MONITOR.bat`
- `update-result.json` records install outcome when possible

This remains demo-only until Windows runtime testing succeeds.
