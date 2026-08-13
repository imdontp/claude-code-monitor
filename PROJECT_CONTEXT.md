# Project Context

## Goal

Create a Claude Code statusline for Windows that monitors usage/reset limits without adding dependencies.

## V1 Scope

- PowerShell statusline script.
- One-line balanced display.
- ANSI color support.
- Missing-field tolerant parsing.
- Snapshot JSON for future monitor surfaces.
- Configurable thresholds/display options with dependency-free defaults.
- Plain/debug output for encoding or ANSI issues.

## Out of Scope

- Windows tray mascot app.
- Local web dashboard.
- Package installation or external dependencies.

## Future Direction

- V2 can read `usage-snapshot.json` from a Windows tray mascot.
- V3 can expose the same snapshot data in a local monitoring dashboard.

## Rollback Baseline

- GitHub baseline commit: `d63e8b8 feat: add Claude Code usage statusline`.
- If runtime behavior breaks, first remove or restore the `statusLine` block in `C:\Users\TH12367283\.claude\settings.json`.
