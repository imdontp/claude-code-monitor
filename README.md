# Claude Code Usage Statusline

A dependency-free PowerShell statusline for Claude Code on Windows. It shows live main-agent activity, subagents, background work, the current model, selected reasoning effort, session cost, 5-hour usage/reset, weekly usage/reset, and context usage.

Default output:

```text
Main:    ✓ READY | Opus | High
Context: 41% █████░░░░░░░ (82k/200k) | Cost: $0.0123
5h:      62% ███████░░░░░ | reset in 2h13m
Weekly:  18% ██░░░░░░░░░░ | reset Tue 09:00
```

Compact output keeps the same percent-before-bar order and repositions the segments onto one line:

```text
Main: ✓ READY | Opus | High | Context: 41% █████░░░░░░░ (82k/200k) | Cost: $0.0123 | 5h: 62% ███████░░░░░ 2h13m | Weekly: 18% ██░░░░░░░░░░ Tue 09:00
```

## What It Shows

- `model.display_name`
- `effort.level`
- `cost.total_cost_usd`
- `rate_limits.five_hour.used_percentage`
- `rate_limits.five_hour.resets_at`
- `rate_limits.seven_day.used_percentage`
- `rate_limits.seven_day.resets_at`
- `context_window.used_percentage`
- `context_window.total_input_tokens` and `context_window.context_window_size` when available

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
- `display.mode`: `full` or `compact`
- `display.use_symbol`: use the configured status symbol when true
- `display.symbol_style`: named glyph preset applied to both the status dot and the usage bar, default `solid`. One of `solid`, `circle`, `bullet`, `fisheye`, `square`, `small-square`, `diamond`, `triangle`, `star`, `large-circle`, `dot-operator`. Switch styles by changing this one field — see the [symbol reference](#symbol-reference) below.
- `display.symbol_code_point` / `display.usage_filled_code_point` / `display.usage_empty_code_point`: advanced override — an explicit Unicode code point here always wins over `symbol_style`, for glyphs outside the presets
- `display.ascii_symbol`: fallback symbol for plain/debug output
- `display.usage_ascii_filled`: filled usage-bar segment for `-Plain`, default `#`
- `display.usage_ascii_empty`: empty usage-bar segment for `-Plain`, default `-`
- `display.usage_bar_segments`: usage-bar segment count, default `12`
- `display.two_line`: legacy layout option retained for configuration compatibility
- `display.shorten_critical`: optionally render `critical` as `crit`
- `colors.enabled`: enable ANSI color output

The script still works if the config file is missing or invalid; it falls back to built-in defaults.

Progress-bar alternatives are previewed in [docs/progress-bar-preview.md](docs/progress-bar-preview.md); the active style is the solid-block `█░` bar.

Switch modes without editing JSON:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\toggle-statusline-mode.ps1
```

Set a mode explicitly with `-Mode full` or `-Mode compact`.

### Symbol Reference

Set `display.symbol_style` to switch both the status dot and the usage-bar glyph together, no code points needed:

| `symbol_style` | filled | empty |
| --- | --- | --- |
| `solid` (default) | `█` | `░` |
| `circle` | `●` | `○` |
| `bullet` | `•` | `◦` |
| `fisheye` | `◉` | `◎` |
| `square` | `■` | `□` |
| `small-square` | `▪` | `▫` |
| `diamond` | `◆` | `◇` |
| `triangle` | `▲` | `△` |
| `star` | `★` | `☆` |
| `large-circle` | `⬤` | `◯` |
| `dot-operator` | `⊙` | `○` |

An unrecognized `symbol_style` is ignored and falls back to `solid`. To use a glyph outside this list, set `symbol_code_point` / `usage_filled_code_point` / `usage_empty_code_point` directly — those always take priority over `symbol_style`.

## Runtime Behavior

- The script runs after Claude Code statusline update events and every two seconds. Main, sub-agent, background, and task rows use stable key-state icons so the display does not flicker between refreshes.
- `UserPromptSubmit`, `Stop`, `StopFailure`, `SubagentStart`, and `SubagentStop` hooks maintain per-session activity under `~/.claude/statusline-state/`.
- `subagentStatusLine` uses Claude Code's native task rows and status values; full mode shows description, elapsed time, and token count, while compact mode shows name and elapsed time.
- Background Bash/PowerShell commands started with `run_in_background` are recorded by `PreToolUse`. Completion is reconciled from Claude Code's task notifications in the session transcript, with a six-hour stale-state safety limit.
- In-progress task-list items are read from `~/.claude/tasks/<session-id>/`.
- Animated spinners are intentionally not used: Claude Code refreshes statusline commands at event/timer intervals and captures each command result, so a smooth sub-second animation is not available here.
- Some fields are missing at startup. The script falls back cleanly:

  ```text
  Main:    ✓ READY | Opus | -
  Context: -- ░░░░░░░░░░░░ | Cost: --
  5h:      -- ░░░░░░░░░░░░ | reset in --
  Weekly:  -- ░░░░░░░░░░░░ | reset --
  ```

- `thinking.enabled` remains in snapshot data for consumers but is intentionally hidden from the rendered statusline.
- `cost.total_cost_usd` renders as `Cost: $0.0123`; missing values render as `Cost: --`.
- Context renders as `Context: <percent> <bar>` and includes `<input>/<window>` token counts when Claude Code provides them.
- `rate_limits` appears only for supported Claude.ai subscriber sessions after the first API response.
- Company/profile-shaped usage payloads are supported through common aliases such as `claude_company.rate_limits`, `usage.rate_limits`, and camelCase `rateLimits`.
- 5-hour, weekly, and context usage render as 12-symbol bars. Filled segments and their percentages use one semantic color: green at 0-59%, yellow at 60-74%, orange at 75-89%, and red at 90-100%; empty segments render gray.
- `effort` appears only when the active model/session supports reasoning effort.
- Colors are ANSI escape codes. Set `NO_COLOR=1`, pass `-NoColor`, or set `colors.enabled` to `false` to disable them.
- Pass `-Plain` to force no ANSI color and the ASCII status symbol.

## Snapshot JSON

Each run writes a snapshot for future tray mascot or dashboard work:

```text
C:\Users\TH12367283\.claude\usage-snapshot.json
```

The snapshot includes `schema_version`, raw reset timestamps, cost, context token metadata, formatted display text, `status`, and `status_reason` so external monitors do not need to parse the statusline text.

Override the path for tests or custom monitors:

```powershell
$env:CLAUDE_USAGE_SNAPSHOT_PATH = "C:\path\to\usage-snapshot.json"
```

## Troubleshooting

- Dot looks corrupted: run the script with `-Plain`, or set `display.use_symbol` to `false`.
- Usage bar shows `?`: the script forces UTF-8 output for Windows PowerShell. If your terminal font still cannot render the symbols, run with `-Plain` or set `usage_ascii_filled`/`usage_ascii_empty`.
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
