$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot "scripts/usage-statusline.ps1"
$tmpDir = Join-Path $repoRoot "tests/tmp"
$snapshotPath = Join-Path $tmpDir "usage-snapshot.json"

if (Test-Path -LiteralPath $tmpDir) {
    Remove-Item -LiteralPath $tmpDir -Recurse -Force
}

New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

function Invoke-Statusline {
    param(
        [string]$Fixture,
        [string[]]$ExtraArgs = @(),
        [string]$ConfigPath = $null
    )

    $fixturePath = Join-Path $repoRoot "tests/fixtures/$Fixture.json"
    $env:CLAUDE_USAGE_SNAPSHOT_PATH = $snapshotPath
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $env:CLAUDE_STATUSLINE_CONFIG_PATH = $ConfigPath
    }

    try {
        $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath) + $ExtraArgs
        return Get-Content -Raw -LiteralPath $fixturePath | powershell @arguments
    }
    finally {
        Remove-Item Env:\CLAUDE_USAGE_SNAPSHOT_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:\CLAUDE_STATUSLINE_CONFIG_PATH -ErrorAction SilentlyContinue
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

$normal = Invoke-Statusline "normal" -ExtraArgs @("-NoColor")
Assert-Contains $normal "Opus" "normal model"
Assert-Contains $normal "eff high" "normal effort"
Assert-Contains $normal "think on" "normal thinking"
Assert-Contains $normal "5h 62%" "normal five-hour usage"
Assert-Contains $normal "W 18%" "normal weekly usage"
Assert-Contains $normal "ctx 41%" "normal context"
Assert-Contains $normal "fresh" "normal state"

$snapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
Assert-Equal $snapshot.schema_version 2 "snapshot schema version"
Assert-Equal $snapshot.status_reason "ok" "normal status reason"
Assert-Equal $snapshot.display.context "ctx 41%" "snapshot display context"

$warn = Invoke-Statusline "warn" -ExtraArgs @("-NoColor")
Assert-Contains $warn "eff med" "medium effort abbreviation"
Assert-Contains $warn "warn" "warning state"

$snapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
Assert-Equal $snapshot.status_reason "five_hour_high" "warn status reason"

$weeklyWarn = Invoke-Statusline "weekly-warn" -ExtraArgs @("-NoColor")
Assert-Contains $weeklyWarn "warn" "weekly warning state"

$snapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
Assert-Equal $snapshot.status_reason "weekly_high" "weekly status reason"

$contextWarn = Invoke-Statusline "context-warn" -ExtraArgs @("-NoColor")
Assert-Contains $contextWarn "ctx 71%" "context warning output"

$snapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
Assert-Equal $snapshot.status_reason "context_high" "context status reason"

$critical = Invoke-Statusline "critical" -ExtraArgs @("-NoColor")
Assert-Contains $critical "eff max" "max effort"
Assert-Contains $critical "critical" "critical state"

$snapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
Assert-Equal $snapshot.status_reason "five_hour_high" "critical status reason"

$missing = Invoke-Statusline "missing-fields" -ExtraArgs @("-NoColor")
Assert-Contains $missing "Haiku" "missing fields model"
Assert-Contains $missing "eff -" "missing effort fallback"
Assert-Contains $missing "5h --" "missing rate limit fallback"
Assert-Contains $missing "waiting" "missing fields state"

$snapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
Assert-Equal $snapshot.model "Haiku" "missing fields snapshot model"
Assert-Equal $snapshot.status_reason "waiting" "missing fields status reason"

$plain = Invoke-Statusline "normal" -ExtraArgs @("-Plain")
Assert-Contains $plain "* Opus" "plain ASCII status symbol"
Assert-Contains $plain "think on" "plain keeps thinking label explicit"

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
Assert-Contains $override "+ Sonnet" "config ASCII symbol override"
Assert-Contains $override "fresh" "threshold override state"

$invalidConfigPath = Join-Path $tmpDir "invalid-config.json"
Set-Content -LiteralPath $invalidConfigPath -Value "{ invalid json" -Encoding UTF8
$invalid = Invoke-Statusline "warn" -ExtraArgs @("-NoColor") -ConfigPath $invalidConfigPath
Assert-Contains $invalid "warn" "invalid config falls back to defaults"

$missingConfig = Invoke-Statusline "warn" -ExtraArgs @("-NoColor") -ConfigPath (Join-Path $tmpDir "missing-config.json")
Assert-Contains $missingConfig "warn" "missing config falls back to defaults"

Write-Output "All statusline tests passed."
