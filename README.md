# Claude Code Usage Statusline

A dependency-free PowerShell statusline for Claude Code on Windows. It shows the current model, reasoning effort, thinking state, 5-hour usage/reset, weekly usage/reset, context usage, and overall status.

Default output:

```text
* Opus | eff high | think on | 5h 62% 2h13m | W 18% Tue 09:00 | ctx 41% | fresh
```

The live statusline uses a colored status symbol by default. The README uses `*` so the example stays readable in any terminal or text encoding.

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

- `fresh`: all known percentages are below the warn threshold
- `warn`: any known percentage is at or above the warn threshold
- `critical`: any known percentage is at or above the critical threshold
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

## Configuration

Runtime options live in `config/statusline-config.json`:

- `thresholds.warn`: default `70`
- `thresholds.critical`: default `85`
- `display.use_symbol`: use the configured status symbol when true
- `display.symbol_code_point`: Unicode code point for the status symbol, default `9679`
- `display.ascii_symbol`: fallback symbol for plain/debug output
- `display.shorten_critical`: optionally render `critical` as `crit`
- `colors.enabled`: enable ANSI color output

The script still works if the config file is missing or invalid; it falls back to built-in defaults.

## Runtime Behavior

- The script runs after Claude Code statusline update events and every 30 seconds because `refreshInterval` is set.
- Some fields are missing at startup. The script falls back cleanly:

  ```text
  * Opus | eff - | think - | 5h -- | W -- | ctx -- | waiting
  ```

- `think on/off` is intentionally not abbreviated.
- `rate_limits` appears only for supported Claude.ai subscriber sessions after the first API response.
- `effort` appears only when the active model/session supports reasoning effort.
- Colors are ANSI escape codes. Set `NO_COLOR=1`, pass `-NoColor`, or set `colors.enabled` to `false` to disable them.
- Pass `-Plain` to force no ANSI color and the ASCII status symbol.

## Snapshot JSON

Each run writes a snapshot for future tray mascot or dashboard work:

```text
C:\Users\TH12367283\.claude\usage-snapshot.json
```

The snapshot includes `schema_version`, raw reset timestamps, formatted display text, `status`, and `status_reason` so external monitors do not need to parse the statusline text.

Override the path for tests or custom monitors:

```powershell
$env:CLAUDE_USAGE_SNAPSHOT_PATH = "C:\path\to\usage-snapshot.json"
```

## Troubleshooting

- Dot looks corrupted: run the script with `-Plain`, or set `display.use_symbol` to `false`.
- Colors do not show: check terminal ANSI support, or use `-NoColor`/`-Plain` for readable output.
- Usage is `--`: send one Claude prompt first; rate limit data may appear only after the first API response.
- Script cannot run: use the `-ExecutionPolicy Bypass` command from `examples/settings.json`.
- Need rollback: remove the `statusLine` block from `C:\Users\TH12367283\.claude\settings.json`, or restore code from the pushed baseline commit.

## Test

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-statusline-tests.ps1
```

The test runner uses mock Claude Code statusline JSON and writes snapshots under `tests/tmp`.
