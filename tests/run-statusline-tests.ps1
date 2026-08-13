$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot "scripts/usage-statusline.ps1"
$stateScriptPath = Join-Path $repoRoot "scripts/statusline-state.ps1"
$subagentScriptPath = Join-Path $repoRoot "scripts/subagent-statusline.ps1"
$toggleScriptPath = Join-Path $repoRoot "scripts/toggle-statusline-mode.ps1"
$tmpDir = Join-Path $env:TEMP ("claude-code-statusline-tests-{0}-{1}" -f $PID, [guid]::NewGuid().ToString("N"))
$snapshotPath = Join-Path $tmpDir "usage-snapshot.json"
$stateRoot = Join-Path $tmpDir "state"
$baseConfigPath = Join-Path $tmpDir "base-config.json"

New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
@{
    display = @{
        mode = "full"
        symbol_style = "solid"
        usage_bar_segments = 12
    }
    colors = @{ enabled = $true }
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $baseConfigPath -Encoding UTF8

function Invoke-Statusline {
    param(
        [string]$Fixture,
        [string[]]$ExtraArgs = @(),
        [string]$ConfigPath = $null
    )

    $fixturePath = Join-Path $repoRoot "tests/fixtures/$Fixture.json"
    $hadSnapshotPath = Test-Path Env:\CLAUDE_USAGE_SNAPSHOT_PATH
    $previousSnapshotPath = $env:CLAUDE_USAGE_SNAPSHOT_PATH
    $hadStateRoot = Test-Path Env:\CLAUDE_STATUSLINE_STATE_ROOT
    $previousStateRoot = $env:CLAUDE_STATUSLINE_STATE_ROOT
    $hadConfigPath = Test-Path Env:\CLAUDE_STATUSLINE_CONFIG_PATH
    $previousConfigPath = $env:CLAUDE_STATUSLINE_CONFIG_PATH
    $env:CLAUDE_USAGE_SNAPSHOT_PATH = $snapshotPath
    $env:CLAUDE_STATUSLINE_STATE_ROOT = $stateRoot
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = $baseConfigPath }
    $env:CLAUDE_STATUSLINE_CONFIG_PATH = $ConfigPath

    try {
        $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath) + $ExtraArgs
        $output = Get-Content -Raw -LiteralPath $fixturePath | powershell @arguments
        return ($output -join "`n")
    }
    finally {
        if ($hadSnapshotPath) { $env:CLAUDE_USAGE_SNAPSHOT_PATH = $previousSnapshotPath }
        else { Remove-Item Env:\CLAUDE_USAGE_SNAPSHOT_PATH -ErrorAction SilentlyContinue }
        if ($hadConfigPath) { $env:CLAUDE_STATUSLINE_CONFIG_PATH = $previousConfigPath }
        else { Remove-Item Env:\CLAUDE_STATUSLINE_CONFIG_PATH -ErrorAction SilentlyContinue }
        if ($hadStateRoot) { $env:CLAUDE_STATUSLINE_STATE_ROOT = $previousStateRoot }
        else { Remove-Item Env:\CLAUDE_STATUSLINE_STATE_ROOT -ErrorAction SilentlyContinue }
    }
}

function Assert-Contains {
    param(
        [string]$Actual,
        [string]$Expected,
        [string]$Name
    )

    if (-not $Actual.Contains($Expected)) {
        throw "Assertion failed: $Name. Expected '$Expected' in '$Actual'"
    }
}

function Assert-Equal {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Name
    )

    if ($Actual -ne $Expected) {
        throw "Assertion failed: $Name. Expected '$Expected', got '$Actual'"
    }
}

$filledUsageSymbol = [string][char]9608
$emptyUsageSymbol = [string][char]9617
$stateWorkingIcon = [string][char]9679
$normalFiveHourBar = ($filledUsageSymbol * 7) + ($emptyUsageSymbol * 5)
$normalWeeklyBar = ($filledUsageSymbol * 2) + ($emptyUsageSymbol * 10)
$normalContextBar = ($filledUsageSymbol * 5) + ($emptyUsageSymbol * 7)
$companyFiveHourBar = ($filledUsageSymbol * 8) + ($emptyUsageSymbol * 4)
$companyWeeklyBar = ($filledUsageSymbol * 3) + ($emptyUsageSymbol * 9)
$emptyUsageBar = $emptyUsageSymbol * 12

$normal = Invoke-Statusline "normal" -ExtraArgs @("-NoColor")
Assert-Contains $normal "Opus" "normal model"
Assert-Contains $normal "High" "normal effort"
Assert-Contains $normal "Main:    " "full main label aligns with context"
Assert-Contains $normal "5h:      62% $normalFiveHourBar | reset in" "normal full five-hour usage bar"
Assert-Contains $normal "Weekly:  18% $normalWeeklyBar | reset" "normal full weekly usage bar"
Assert-Contains $normal "Context: 41% $normalContextBar (82k/200k)" "normal full context usage"
Assert-Contains $normal 'Cost: $0.0123' "normal session cost"
Assert-Equal $normal.Contains("think on") $false "thinking is hidden from display"
Assert-Contains $normal "READY" "normal activity state"

$snapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
Assert-Equal $snapshot.schema_version 2 "snapshot schema version"
Assert-Equal $snapshot.status_reason "ok" "normal status reason"
Assert-Equal $snapshot.display.five_hour.StartsWith("5h:      62% $normalFiveHourBar") $true "snapshot display five-hour bar"
Assert-Equal $snapshot.display.context "Context: 41% $normalContextBar (82k/200k)" "snapshot display context bar"
Assert-Equal $snapshot.display.cost 'Cost: $0.0123' "snapshot display cost"

$compactConfigPath = Join-Path $tmpDir "compact-config.json"
@{
    display = @{
        mode = "compact"
        symbol_style = "solid"
    }
    colors = @{ enabled = $false }
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $compactConfigPath -Encoding UTF8

$compact = Invoke-Statusline "normal" -ExtraArgs @("-NoColor") -ConfigPath $compactConfigPath
$compactSnapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
Assert-Contains $compact "5h: 62% $normalFiveHourBar" "compact preserves five-hour usage segment"
Assert-Contains $compact "Weekly: 18% $normalWeeklyBar" "compact preserves weekly usage segment"
Assert-Contains $compact "Context: 41% $normalContextBar (82k/200k) | Cost: `$0.0123 | 5h: 62% $normalFiveHourBar" "compact repositions usage segments"
Assert-Equal (($compact -split "`n").Count) 1 "compact renders one line"

$company = Invoke-Statusline "claude-company" -ExtraArgs @("-NoColor")
Assert-Contains $company "Sonnet" "company model fallback"
Assert-Contains $company "Medium" "company effort"
Assert-Contains $company "5h:      64% $companyFiveHourBar" "company five-hour usage bar"
Assert-Contains $company "Weekly:  23% $companyWeeklyBar" "company weekly usage bar"
Assert-Contains $company "Context: 44%" "company context usage"
Assert-Equal $company.Contains("think on") $false "company thinking is hidden"
Assert-Contains $company "READY" "company activity state"

$snapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
Assert-Equal $snapshot.model "Sonnet" "company snapshot model"
Assert-Equal $snapshot.five_hour.used_percentage 64 "company snapshot five-hour usage"
Assert-Equal $snapshot.status_reason "ok" "company status reason"

$warn = Invoke-Statusline "warn" -ExtraArgs @("-NoColor")
Assert-Contains $warn "Medium" "medium effort label"

$snapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
Assert-Equal $snapshot.status_reason "five_hour_high" "warn status reason"

$weeklyWarn = Invoke-Statusline "weekly-warn" -ExtraArgs @("-NoColor")
Assert-Contains $weeklyWarn "Weekly" "weekly warning full layout"

$snapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
Assert-Equal $snapshot.status_reason "weekly_high" "weekly status reason"

$contextWarn = Invoke-Statusline "context-warn" -ExtraArgs @("-NoColor")
$contextWarnBar = ($filledUsageSymbol * 9) + ($emptyUsageSymbol * 3)
Assert-Contains $contextWarn "Context: 71%" "context warning usage"

$snapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
Assert-Equal $snapshot.status_reason "context_high" "context status reason"

$critical = Invoke-Statusline "critical" -ExtraArgs @("-NoColor")
Assert-Contains $critical "Max" "max effort"

$snapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
Assert-Equal $snapshot.status_reason "five_hour_high" "critical status reason"

$missing = Invoke-Statusline "missing-fields" -ExtraArgs @("-NoColor")
Assert-Contains $missing "Haiku" "missing fields model"
Assert-Contains $missing "Main:    " "missing main label aligns with context"
Assert-Contains $missing "| -`nContext:" "missing effort fallback"
Assert-Contains $missing "5h:      -- $emptyUsageBar" "missing rate limit bar fallback"
Assert-Contains $missing "Cost: --" "missing cost fallback"
Assert-Contains $missing "READY" "missing fields activity state"

$snapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
Assert-Equal $snapshot.model "Haiku" "missing fields snapshot model"
Assert-Equal $snapshot.status_reason "waiting" "missing fields status reason"

$plain = Invoke-Statusline "normal" -ExtraArgs @("-Plain")
Assert-Contains $plain "Opus" "plain model"
Assert-Contains $plain "5h:      62% #######-----" "plain ASCII five-hour usage bar"
Assert-Contains $plain "Weekly:  18% ##----------" "plain ASCII weekly usage bar"
Assert-Contains $plain "Context: 41% #####------- (82k/200k)" "plain context format"
Assert-Contains $plain 'Cost: $0.0123' "plain session cost"
Assert-Equal $plain.Contains("think on") $false "plain hides thinking label"

$utf8 = New-Object System.Text.UTF8Encoding($false)
$processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.FileName = "powershell"
$processInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -NoColor"
$processInfo.RedirectStandardInput = $true
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.StandardOutputEncoding = $utf8
$processInfo.UseShellExecute = $false
$null = $processInfo.EnvironmentVariables
$processEnvironment = $processInfo.EnvironmentVariables
$processEnvironment["CLAUDE_STATUSLINE_CONFIG_PATH"] = $baseConfigPath
$processEnvironment["CLAUDE_STATUSLINE_STATE_ROOT"] = $stateRoot
$process = [System.Diagnostics.Process]::Start($processInfo)
$process.StandardInput.Write((Get-Content -Raw -LiteralPath (Join-Path $repoRoot "tests/fixtures/normal.json")))
$process.StandardInput.Close()
$encodedOutput = $process.StandardOutput.ReadToEnd()
$encodedError = $process.StandardError.ReadToEnd()
$process.WaitForExit()
Assert-Equal $process.ExitCode 0 "utf8 child process exit code"
Assert-Equal $encodedError "" "utf8 child process stderr"
Assert-Contains $encodedOutput "5h:      62% $normalFiveHourBar" "utf8 child process usage bar"

$env:CLAUDE_USAGE_SNAPSHOT_PATH = $snapshotPath
$env:CLAUDE_STATUSLINE_CONFIG_PATH = $baseConfigPath
$env:CLAUDE_STATUSLINE_STATE_ROOT = $stateRoot
try {
    $bomFixturePath = Join-Path $repoRoot "tests/fixtures/normal.json"
    $bomOutput = cmd /d /c type "$bomFixturePath" | powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -NoColor
    Assert-Contains ($bomOutput -join "`n") "Opus" "UTF-8 BOM input is accepted"
}
finally {
    Remove-Item Env:\CLAUDE_USAGE_SNAPSHOT_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_STATUSLINE_CONFIG_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_STATUSLINE_STATE_ROOT -ErrorAction SilentlyContinue
}

$colorProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
$colorProcessInfo.FileName = "powershell"
$colorProcessInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$colorProcessInfo.RedirectStandardInput = $true
$colorProcessInfo.RedirectStandardOutput = $true
$colorProcessInfo.RedirectStandardError = $true
$colorProcessInfo.StandardOutputEncoding = $utf8
$colorProcessInfo.UseShellExecute = $false
$null = $colorProcessInfo.EnvironmentVariables
$colorProcessEnvironment = $colorProcessInfo.EnvironmentVariables
$colorProcessEnvironment["CLAUDE_STATUSLINE_CONFIG_PATH"] = $baseConfigPath
$colorProcessEnvironment["CLAUDE_STATUSLINE_STATE_ROOT"] = $stateRoot
$colorProcess = [System.Diagnostics.Process]::Start($colorProcessInfo)
$colorProcess.StandardInput.Write((Get-Content -Raw -LiteralPath (Join-Path $repoRoot "tests/fixtures/normal.json")))
$colorProcess.StandardInput.Close()
$colorOutput = $colorProcess.StandardOutput.ReadToEnd()
$colorError = $colorProcess.StandardError.ReadToEnd()
$colorProcess.WaitForExit()
Assert-Equal $colorProcess.ExitCode 0 "color child process exit code"
Assert-Equal $colorError "" "color child process stderr"
$esc = [char]27
$yellowFilledSegment = "$esc[33m$filledUsageSymbol$esc[0m"
$grayEmptySegment = "$esc[90m$emptyUsageSymbol$esc[0m"
$yellowPercent = "$esc[33m62%$esc[0m"
Assert-Contains $colorOutput ("5h:      " + $yellowPercent + " " + ($yellowFilledSegment * 7) + ($grayEmptySegment * 5) + " ") "usage bar applies one yellow color at 62 percent"

$orangeFilledSegment = "$esc[38;5;208m$filledUsageSymbol$esc[0m"
$orangePercent = "$esc[38;5;208m88%$esc[0m"
$criticalColorOutput = Invoke-Statusline "critical"
Assert-Contains $criticalColorOutput ("Context: " + $orangePercent + " " + ($orangeFilledSegment * 11) + $grayEmptySegment) "usage bar applies one orange color at 88 percent"

$redFilledSegment = "$esc[31;1m$filledUsageSymbol$esc[0m"
$redPercent = "$esc[31;1m91%$esc[0m"
Assert-Contains $criticalColorOutput ("5h:      " + $redPercent + " " + ($redFilledSegment * 11) + $grayEmptySegment) "usage bar applies one red color at 91 percent"

$overrideConfigPath = Join-Path $tmpDir "override-config.json"
@{
    thresholds = @{
        warn = 80
        critical = 95
    }
    display = @{
        use_symbol = $false
        ascii_symbol = "+"
        shorten_critical = $true
    }
    colors = @{
        enabled = $false
    }
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $overrideConfigPath -Encoding UTF8

$override = Invoke-Statusline "warn" -ConfigPath $overrideConfigPath
Assert-Contains $override "Sonnet" "config model with symbol override"
Assert-Contains $override "READY" "threshold override activity state"

$bulletFilled = [string][char]8226
$bulletEmpty = [string][char]9702
$bulletFiveHourBar = ($bulletFilled * 7) + ($bulletEmpty * 5)
$circleFilled = [string][char]9679
$circleEmpty = [string][char]9675
$circleFiveHourBar = ($circleFilled * 7) + ($circleEmpty * 5)

$styleConfigPath = Join-Path $tmpDir "style-config.json"
@{
    display = @{
        symbol_style = "bullet"
    }
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $styleConfigPath -Encoding UTF8

$styled = Invoke-Statusline "normal" -ExtraArgs @("-NoColor") -ConfigPath $styleConfigPath
Assert-Contains $styled "Opus" "styled model"
Assert-Contains $styled "5h:      62% $bulletFiveHourBar" "symbol_style applies to usage bar"

$styleOverrideConfigPath = Join-Path $tmpDir "style-override-config.json"
@{
    display = @{
        symbol_style = "bullet"
        usage_filled_code_point = 9679
        usage_empty_code_point = 9675
    }
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $styleOverrideConfigPath -Encoding UTF8

$styleOverride = Invoke-Statusline "normal" -ExtraArgs @("-NoColor") -ConfigPath $styleOverrideConfigPath
Assert-Contains $styleOverride "5h:      62% $circleFiveHourBar" "explicit code point wins over symbol_style"

$invalidStyleConfigPath = Join-Path $tmpDir "invalid-style-config.json"
@{
    display = @{
        symbol_style = "not-a-real-style"
    }
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $invalidStyleConfigPath -Encoding UTF8

$invalidStyle = Invoke-Statusline "normal" -ExtraArgs @("-NoColor") -ConfigPath $invalidStyleConfigPath
Assert-Contains $invalidStyle "5h:      62% $normalFiveHourBar" "unrecognized symbol_style falls back to solid default"

$invalidConfigPath = Join-Path $tmpDir "invalid-config.json"
Set-Content -LiteralPath $invalidConfigPath -Value "{ invalid json" -Encoding UTF8
$invalid = Invoke-Statusline "warn" -ExtraArgs @("-NoColor") -ConfigPath $invalidConfigPath
Assert-Contains $invalid "READY" "invalid config falls back to default full mode"

$missingConfig = Invoke-Statusline "warn" -ExtraArgs @("-NoColor") -ConfigPath (Join-Path $tmpDir "missing-config.json")
Assert-Contains $missingConfig "READY" "missing config falls back to default full mode"

New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
$promptHook = @{
    session_id = "statusline-test-session"
    hook_event_name = "UserPromptSubmit"
    prompt = "test"
} | ConvertTo-Json -Depth 4
$env:CLAUDE_STATUSLINE_STATE_ROOT = $stateRoot
try {
    $hookOutput = $promptHook | powershell -NoProfile -ExecutionPolicy Bypass -File $stateScriptPath
    Assert-Equal ($hookOutput -join "") "" "state hook stays silent"
}
finally {
    Remove-Item Env:\CLAUDE_STATUSLINE_STATE_ROOT -ErrorAction SilentlyContinue
}

$working = Invoke-Statusline "activity" -ExtraArgs @("-NoColor")
Assert-Contains $working "WORKING" "prompt hook produces working state"

$stopHook = @{
    session_id = "statusline-test-session"
    hook_event_name = "Stop"
} | ConvertTo-Json -Depth 4
$env:CLAUDE_STATUSLINE_STATE_ROOT = $stateRoot
try { $stopHook | powershell -NoProfile -ExecutionPolicy Bypass -File $stateScriptPath | Out-Null }
finally { Remove-Item Env:\CLAUDE_STATUSLINE_STATE_ROOT -ErrorAction SilentlyContinue }
$ready = Invoke-Statusline "activity" -ExtraArgs @("-NoColor")
Assert-Contains $ready "READY" "stop hook returns main state to ready"

$foregroundFailureHook = @{
    session_id = "statusline-test-session"
    hook_event_name = "PostToolUseFailure"
    tool_use_id = "foreground-command"
    tool_name = "PowerShell"
} | ConvertTo-Json -Depth 4
$env:CLAUDE_STATUSLINE_STATE_ROOT = $stateRoot
try { $foregroundFailureHook | powershell -NoProfile -ExecutionPolicy Bypass -File $stateScriptPath | Out-Null }
finally { Remove-Item Env:\CLAUDE_STATUSLINE_STATE_ROOT -ErrorAction SilentlyContinue }
$foregroundState = Get-Content -Raw -LiteralPath (Join-Path $stateRoot "statusline-test-session.json") | ConvertFrom-Json
Assert-Equal @($foregroundState.processes).Count 0 "foreground failure does not create a background process"
Assert-Contains (Invoke-Statusline "activity" -ExtraArgs @("-NoColor")) "READY" "foreground failure does not trigger attention"

$env:CLAUDE_STATUSLINE_STATE_ROOT = $stateRoot
try { $promptHook | powershell -NoProfile -ExecutionPolicy Bypass -File $stateScriptPath | Out-Null }
finally { Remove-Item Env:\CLAUDE_STATUSLINE_STATE_ROOT -ErrorAction SilentlyContinue }
$workingKeyState = Invoke-Statusline "activity" -ExtraArgs @("-NoColor")
Assert-Contains $workingKeyState ("Main:    $stateWorkingIcon WORKING") "working state uses a stable key-state icon"

$env:CLAUDE_STATUSLINE_STATE_ROOT = $stateRoot
try { $stopHook | powershell -NoProfile -ExecutionPolicy Bypass -File $stateScriptPath | Out-Null }
finally { Remove-Item Env:\CLAUDE_STATUSLINE_STATE_ROOT -ErrorAction SilentlyContinue }

$subagentStartHook = @{
    session_id = "statusline-test-session"
    hook_event_name = "SubagentStart"
    agent_id = "agent-1"
    agent_type = "tester"
    description = "Running tests"
} | ConvertTo-Json -Depth 4
$subagentStopHook = @{
    session_id = "statusline-test-session"
    hook_event_name = "SubagentStop"
    agent_id = "agent-1"
} | ConvertTo-Json -Depth 4
$env:CLAUDE_STATUSLINE_STATE_ROOT = $stateRoot
try {
    $subagentStartHook | powershell -NoProfile -ExecutionPolicy Bypass -File $stateScriptPath | Out-Null
    $subagentRunning = Invoke-Statusline "activity" -ExtraArgs @("-NoColor")
    Assert-Contains $subagentRunning "Sub-agent:  1" "sub-agent summary keeps aligned spacing"
    $subagentStopHook | powershell -NoProfile -ExecutionPolicy Bypass -File $stateScriptPath | Out-Null
}
finally { Remove-Item Env:\CLAUDE_STATUSLINE_STATE_ROOT -ErrorAction SilentlyContinue }

$backgroundStartHook = @{
    session_id = "statusline-test-session"
    hook_event_name = "PreToolUse"
    tool_use_id = "background-command"
    tool_name = "PowerShell"
    tool_input = @{ run_in_background = $true; command = "long-running command" }
} | ConvertTo-Json -Depth 6
$backgroundFailureHook = @{
    session_id = "statusline-test-session"
    hook_event_name = "PostToolUseFailure"
    tool_use_id = "background-command"
    tool_name = "PowerShell"
} | ConvertTo-Json -Depth 4
$env:CLAUDE_STATUSLINE_STATE_ROOT = $stateRoot
try {
    $backgroundStartHook | powershell -NoProfile -ExecutionPolicy Bypass -File $stateScriptPath | Out-Null
    $backgroundRunning = Invoke-Statusline "activity" -ExtraArgs @("-NoColor")
    Assert-Contains $backgroundRunning "Background: 1" "background key-state count"
    Assert-Contains $backgroundRunning (([string][char]9881) + " long-running command") "background uses a stable key-state icon"
    $backgroundFailureHook | powershell -NoProfile -ExecutionPolicy Bypass -File $stateScriptPath | Out-Null
}
finally { Remove-Item Env:\CLAUDE_STATUSLINE_STATE_ROOT -ErrorAction SilentlyContinue }
$backgroundState = Get-Content -Raw -LiteralPath (Join-Path $stateRoot "statusline-test-session.json") | ConvertFrom-Json
Assert-Equal $backgroundState.processes[0].status "failed" "registered background failure is retained"
Assert-Contains (Invoke-Statusline "activity" -ExtraArgs @("-NoColor")) "ATTENTION" "background failure triggers attention"

$sessionStartHook = @{
    session_id = "statusline-test-session"
    hook_event_name = "SessionStart"
} | ConvertTo-Json -Depth 4
$env:CLAUDE_STATUSLINE_STATE_ROOT = $stateRoot
try { $sessionStartHook | powershell -NoProfile -ExecutionPolicy Bypass -File $stateScriptPath | Out-Null }
finally { Remove-Item Env:\CLAUDE_STATUSLINE_STATE_ROOT -ErrorAction SilentlyContinue }
$resumedState = Get-Content -Raw -LiteralPath (Join-Path $stateRoot "statusline-test-session.json") | ConvertFrom-Json
Assert-Equal @($resumedState.processes).Count 0 "session start clears stale processes"

$completionStartHook = $backgroundStartHook.Replace("background-command", "completed-command")
$env:CLAUDE_STATUSLINE_STATE_ROOT = $stateRoot
try { $completionStartHook | powershell -NoProfile -ExecutionPolicy Bypass -File $stateScriptPath | Out-Null }
finally { Remove-Item Env:\CLAUDE_STATUSLINE_STATE_ROOT -ErrorAction SilentlyContinue }
$transcriptPath = Join-Path $tmpDir "completion-transcript.jsonl"
Set-Content -LiteralPath $transcriptPath -Encoding UTF8 -Value '<task-notification><tool-use-id>completed-command</tool-use-id><status>completed</status></task-notification>'
$completionInput = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "tests/fixtures/activity.json") | ConvertFrom-Json
$completionInput | Add-Member -NotePropertyName transcript_path -NotePropertyValue $transcriptPath -Force
$env:CLAUDE_USAGE_SNAPSHOT_PATH = $snapshotPath
$env:CLAUDE_STATUSLINE_CONFIG_PATH = $baseConfigPath
$env:CLAUDE_STATUSLINE_STATE_ROOT = $stateRoot
try { $completionInput | ConvertTo-Json -Depth 8 | powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -NoColor | Out-Null }
finally {
    Remove-Item Env:\CLAUDE_USAGE_SNAPSHOT_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_STATUSLINE_CONFIG_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_STATUSLINE_STATE_ROOT -ErrorAction SilentlyContinue
}
$completedState = Get-Content -Raw -LiteralPath (Join-Path $stateRoot "statusline-test-session.json") | ConvertFrom-Json
Assert-Equal $completedState.processes[0].status "completed" "transcript completion is persisted"

$companyRoot = Join-Path $tmpDir "company-profile"
$companyTaskDirectory = Join-Path (Join-Path $companyRoot "tasks") "statusline-test-session"
New-Item -ItemType Directory -Path $companyTaskDirectory -Force | Out-Null
@{ status = "in_progress"; subject = "Company task" } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $companyTaskDirectory "1.json") -Encoding UTF8
$env:CLAUDE_CONFIG_DIR = $companyRoot
$env:CLAUDE_USAGE_SNAPSHOT_PATH = $snapshotPath
$env:CLAUDE_STATUSLINE_CONFIG_PATH = $baseConfigPath
try {
    $companyTaskOutput = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "tests/fixtures/activity.json") | powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -NoColor
}
finally {
    Remove-Item Env:\CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_USAGE_SNAPSHOT_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_STATUSLINE_CONFIG_PATH -ErrorAction SilentlyContinue
}
Assert-Contains ($companyTaskOutput -join "`n") "WAITING" "alternate Claude profile reads its own tasks"
Assert-Contains ($companyTaskOutput -join "`n") "Task: " "alternate Claude profile task count"

$subagentInput = @{
    tasks = @(
        @{
            id = "agent-1"
            name = "tester"
            status = "running"
            description = "Running tests"
            startTime = [DateTimeOffset]::Now.AddSeconds(-5).ToUnixTimeMilliseconds()
            tokenCount = 123
        }
    )
} | ConvertTo-Json -Depth 5
$subagentOutput = $subagentInput | powershell -NoProfile -ExecutionPolicy Bypass -File $subagentScriptPath -NoColor
$subagentRow = ($subagentOutput -join "") | ConvertFrom-Json
Assert-Equal $subagentRow.id "agent-1" "subagent row id"
Assert-Contains $subagentRow.content "tester | Running tests" "full subagent row content"
Assert-Contains $subagentRow.content ("$stateWorkingIcon tester") "subagent uses a stable key-state icon"

$toggleConfigPath = Join-Path $tmpDir "toggle-config.json"
@{ display = @{ mode = "full" } } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $toggleConfigPath -Encoding UTF8
$toggleOutput = powershell -NoProfile -ExecutionPolicy Bypass -File $toggleScriptPath -ConfigPath $toggleConfigPath
Assert-Contains ($toggleOutput -join "") "full -> compact" "toggle reports mode change"
$toggledConfig = Get-Content -Raw -LiteralPath $toggleConfigPath | ConvertFrom-Json
Assert-Equal $toggledConfig.display.mode "compact" "toggle persists compact mode"

Write-Output "All statusline tests passed."
