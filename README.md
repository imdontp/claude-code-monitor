# Claude Code Usage Statusline

A dependency-free PowerShell statusline for Claude Code on Windows. It shows the current model, reasoning effort, thinking state, 5-hour usage/reset, weekly usage/reset, context usage, and overall status.

Default output:

```text
● Opus | eff high | think on | 5h 62% 2h13m | W 18% Tue 09:00 | ctx 41% | fresh
```

## What It Shows

- `model.display_name`
- `effort.level`
- `thinking.enabled`
- `rate_limits.five_hour.used_percentage`
- `rate_limits.five_hour.resets_at`
- `rate_limits.seven_day.used_percentage`
- `rate_limits.seven_day.resets_at`
- `context_window.used_percentage`

Status thresholds:

- `fresh`: all known percentages are below 70%
- `warn`: any known percentage is 70-84%
- `critical`: any known percentage is 85% or higher
- `waiting`: usage data has not arrived yet
- `stale`: invalid JSON was received

## Install

1. Keep this repository at:

   ```text
   C:\Users\TH12367283\Projects\claude-code-plug-in
   ```

2. Add the statusline config from `examples/settings.json` to:

   ```text
   C:\Users\TH12367283\.claude\settings.json
   ```

3. Start Claude Code:

   ```powershell
   claude
   ```

Claude Code will run `scripts/usage-statusline.ps1`, pass session JSON on stdin, and display the printed line as the statusline.

## Runtime Behavior

- The script runs after Claude Code statusline update events and every 30 seconds because `refreshInterval` is set.
- Some fields are missing at startup. The script falls back cleanly:

  ```text
  ● Opus | eff - | think - | 5h -- | W -- | ctx -- | waiting
  ```

- `rate_limits` appears only for supported Claude.ai subscriber sessions after the first API response.
- `effort` appears only when the active model/session supports reasoning effort.
- Colors are ANSI escape codes. Set `NO_COLOR=1` or pass `-NoColor` to disable them.

## Snapshot JSON

Each run writes a snapshot for future tray mascot or dashboard work:

```text
C:\Users\TH12367283\.claude\usage-snapshot.json
```

Override it for tests or custom monitors:

```powershell
$env:CLAUDE_USAGE_SNAPSHOT_PATH = "C:\path\to\usage-snapshot.json"
```

## Test

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-statusline-tests.ps1
```

The test runner uses mock Claude Code statusline JSON and writes snapshots under `tests/tmp`.
