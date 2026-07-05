param(
    [string]$SnapshotPath = $env:CLAUDE_USAGE_SNAPSHOT_PATH,
    [switch]$NoColor
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SnapshotPath)) {
    $SnapshotPath = Join-Path $HOME ".claude/usage-snapshot.json"
}

function Get-Field {
    param(
        [object]$Object,
        [string]$Path,
        [object]$Default = $null
    )

    $current = $Object
    foreach ($part in $Path.Split(".")) {
        if ($null -eq $current) {
            return $Default
        }

        $property = $current.PSObject.Properties[$part]
        if ($null -eq $property) {
            return $Default
        }

        $current = $property.Value
    }

    if ($null -eq $current) {
        return $Default
    }

    return $current
}

function Format-Percent {
    param([object]$Value)

    if ($null -eq $Value -or $Value -eq "") {
        return "--"
    }

    try {
        return "$([math]::Round([double]$Value))%"
    }
    catch {
        return "--"
    }
}

function Format-Countdown {
    param([object]$EpochSeconds)

    if ($null -eq $EpochSeconds -or $EpochSeconds -eq "") {
        return "--"
    }

    try {
        $reset = [DateTimeOffset]::FromUnixTimeSeconds([int64]$EpochSeconds).ToLocalTime()
        $remaining = $reset - [DateTimeOffset]::Now
        if ($remaining.TotalSeconds -lt 0) {
            return "now"
        }

        if ($remaining.TotalDays -ge 1) {
            return ("{0}d{1}h" -f [math]::Floor($remaining.TotalDays), $remaining.Hours)
        }

        return ("{0}h{1:D2}m" -f [math]::Floor($remaining.TotalHours), $remaining.Minutes)
    }
    catch {
        return "--"
    }
}

function Format-ResetDay {
    param([object]$EpochSeconds)

    if ($null -eq $EpochSeconds -or $EpochSeconds -eq "") {
        return "--"
    }

    try {
        $reset = [DateTimeOffset]::FromUnixTimeSeconds([int64]$EpochSeconds).ToLocalTime()
        return $reset.ToString("ddd HH:mm")
    }
    catch {
        return "--"
    }
}

function Get-Severity {
    param([object[]]$Values)

    $hasKnownValue = $false
    $max = 0.0

    foreach ($value in $Values) {
        if ($null -eq $value -or $value -eq "") {
            continue
        }

        try {
            $hasKnownValue = $true
            $numeric = [double]$value
            if ($numeric -gt $max) {
                $max = $numeric
            }
        }
        catch {
            continue
        }
    }

    if (-not $hasKnownValue) {
        return "waiting"
    }

    if ($max -ge 85) {
        return "critical"
    }

    if ($max -ge 70) {
        return "warn"
    }

    return "fresh"
}

function Get-EffortLabel {
    param([object]$Value)

    if ($null -eq $Value -or $Value -eq "") {
        return "-"
    }

    switch ([string]$Value) {
        "medium" { return "med" }
        default { return [string]$Value }
    }
}

function Get-ThinkingLabel {
    param([object]$Value)

    if ($null -eq $Value -or $Value -eq "") {
        return "-"
    }

    if ([bool]$Value) {
        return "on"
    }

    return "off"
}

function Get-ColorCode {
    param(
        [string]$Kind,
        [object]$Value
    )

    switch ($Kind) {
        "state" {
            switch ($Value) {
                "fresh" { return "32" }
                "warn" { return "33" }
                "critical" { return "31;1" }
                default { return "90" }
            }
        }
        "effort" {
            switch ($Value) {
                "low" { return "32" }
                "med" { return "36" }
                "high" { return "33" }
                "xhigh" { return "35" }
                "max" { return "31;1" }
                default { return "90" }
            }
        }
        "percentage" {
            if ($null -eq $Value -or $Value -eq "") {
                return "90"
            }

            try {
                $numeric = [double]$Value
                if ($numeric -ge 85) { return "31;1" }
                if ($numeric -ge 70) { return "33" }
                return "32"
            }
            catch {
                return "90"
            }
        }
        "context" {
            if ($null -eq $Value -or $Value -eq "") {
                return "90"
            }

            try {
                $numeric = [double]$Value
                if ($numeric -ge 85) { return "31;1" }
                if ($numeric -ge 70) { return "33" }
                return "36"
            }
            catch {
                return "90"
            }
        }
        default {
            return "0"
        }
    }
}

function Colorize {
    param(
        [string]$Text,
        [string]$Code
    )

    if ($NoColor -or $env:NO_COLOR) {
        return $Text
    }

    $esc = [char]27
    return "$esc[$($Code)m$Text$esc[0m"
}

function Write-Snapshot {
    param(
        [string]$Path,
        [object]$Snapshot
    )

    try {
        $directory = Split-Path -Parent $Path
        if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        $Snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
    }
    catch {
        # Statusline output is more important than snapshot persistence.
    }
}

function New-FallbackSnapshot {
    param([string]$Status)

    return [ordered]@{
        updated_at = [DateTimeOffset]::Now.ToString("o")
        model = "-"
        effort = "-"
        thinking = "-"
        five_hour = [ordered]@{
            used_percentage = $null
            resets_at = $null
            reset_in = "--"
        }
        seven_day = [ordered]@{
            used_percentage = $null
            resets_at = $null
            reset_at = "--"
        }
        context = [ordered]@{
            used_percentage = $null
        }
        status = $Status
    }
}

$inputJson = [Console]::In.ReadToEnd()

if ([string]::IsNullOrWhiteSpace($inputJson)) {
    $snapshot = New-FallbackSnapshot -Status "waiting"
    Write-Snapshot -Path $SnapshotPath -Snapshot $snapshot
    $dot = Colorize "●" (Get-ColorCode "state" "waiting")
    Write-Output "$dot - | eff - | think - | 5h -- | W -- | ctx -- | waiting"
    exit 0
}

try {
    $data = $inputJson | ConvertFrom-Json
}
catch {
    $snapshot = New-FallbackSnapshot -Status "stale"
    Write-Snapshot -Path $SnapshotPath -Snapshot $snapshot
    $dot = Colorize "●" (Get-ColorCode "state" "stale")
    Write-Output "$dot - | eff - | think - | 5h -- | W -- | ctx -- | stale"
    exit 0
}

$model = Get-Field $data "model.display_name" "-"
$effort = Get-EffortLabel (Get-Field $data "effort.level" $null)
$thinking = Get-ThinkingLabel (Get-Field $data "thinking.enabled" $null)
$fiveHourUsed = Get-Field $data "rate_limits.five_hour.used_percentage" $null
$fiveHourReset = Get-Field $data "rate_limits.five_hour.resets_at" $null
$sevenDayUsed = Get-Field $data "rate_limits.seven_day.used_percentage" $null
$sevenDayReset = Get-Field $data "rate_limits.seven_day.resets_at" $null
$contextUsed = Get-Field $data "context_window.used_percentage" $null
$status = Get-Severity @($fiveHourUsed, $sevenDayUsed, $contextUsed)

$dot = Colorize "●" (Get-ColorCode "state" $status)
$effortText = Colorize "eff $effort" (Get-ColorCode "effort" $effort)
$fiveHourText = Colorize ("5h {0}" -f (Format-Percent $fiveHourUsed)) (Get-ColorCode "percentage" $fiveHourUsed)
$sevenDayText = Colorize ("W {0}" -f (Format-Percent $sevenDayUsed)) (Get-ColorCode "percentage" $sevenDayUsed)
$contextText = Colorize ("ctx {0}" -f (Format-Percent $contextUsed)) (Get-ColorCode "context" $contextUsed)
$statusText = Colorize $status (Get-ColorCode "state" $status)
$fiveHourCountdown = Format-Countdown $fiveHourReset
$sevenDayResetText = Format-ResetDay $sevenDayReset

$snapshot = [ordered]@{
    updated_at = [DateTimeOffset]::Now.ToString("o")
    model = $model
    effort = $effort
    thinking = $thinking
    five_hour = [ordered]@{
        used_percentage = $fiveHourUsed
        resets_at = $fiveHourReset
        reset_in = $fiveHourCountdown
    }
    seven_day = [ordered]@{
        used_percentage = $sevenDayUsed
        resets_at = $sevenDayReset
        reset_at = $sevenDayResetText
    }
    context = [ordered]@{
        used_percentage = $contextUsed
    }
    status = $status
}

Write-Snapshot -Path $SnapshotPath -Snapshot $snapshot
Write-Output "$dot $model | $effortText | think $thinking | $fiveHourText $fiveHourCountdown | $sevenDayText $sevenDayResetText | $contextText | $statusText"
