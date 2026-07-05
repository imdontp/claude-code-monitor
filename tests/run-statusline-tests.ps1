$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot "scripts/usage-statusline.ps1"
$snapshotPath = Join-Path $repoRoot "tests/tmp/usage-snapshot.json"

if (Test-Path -LiteralPath (Split-Path -Parent $snapshotPath)) {
    Remove-Item -LiteralPath (Split-Path -Parent $snapshotPath) -Recurse -Force
}

New-Item -ItemType Directory -Path (Split-Path -Parent $snapshotPath) -Force | Out-Null

function Invoke-Statusline {
    param([string]$Fixture)

    $fixturePath = Join-Path $repoRoot "tests/fixtures/$Fixture.json"
    $env:CLAUDE_USAGE_SNAPSHOT_PATH = $snapshotPath
    try {
        return Get-Content -Raw -LiteralPath $fixturePath | powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -NoColor
    }
    finally {
        Remove-Item Env:\CLAUDE_USAGE_SNAPSHOT_PATH -ErrorAction SilentlyContinue
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

$normal = Invoke-Statusline "normal"
Assert-Contains $normal "Opus" "normal model"
Assert-Contains $normal "eff high" "normal effort"
Assert-Contains $normal "think on" "normal thinking"
Assert-Contains $normal "5h 62%" "normal five-hour usage"
Assert-Contains $normal "W 18%" "normal weekly usage"
Assert-Contains $normal "ctx 41%" "normal context"
Assert-Contains $normal "fresh" "normal state"

$warn = Invoke-Statusline "warn"
Assert-Contains $warn "eff med" "medium effort abbreviation"
Assert-Contains $warn "warn" "warning state"

$critical = Invoke-Statusline "critical"
Assert-Contains $critical "eff max" "max effort"
Assert-Contains $critical "critical" "critical state"

$missing = Invoke-Statusline "missing-fields"
Assert-Contains $missing "Haiku" "missing fields model"
Assert-Contains $missing "eff -" "missing effort fallback"
Assert-Contains $missing "5h --" "missing rate limit fallback"
Assert-Contains $missing "waiting" "missing fields state"

$snapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
if ($snapshot.model -ne "Haiku") {
    throw "Assertion failed: snapshot model was '$($snapshot.model)'"
}

Write-Output "All statusline tests passed."
