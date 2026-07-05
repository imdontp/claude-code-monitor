param(
    [string]$SnapshotPath = $env:CLAUDE_USAGE_SNAPSHOT_PATH,
    [string]$ConfigPath = $env:CLAUDE_STATUSLINE_CONFIG_PATH,
    [switch]$NoColor,
    [switch]$Plain
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SnapshotPath)) {
    $SnapshotPath = Join-Path $HOME ".claude/usage-snapshot.json"
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path (Split-Path -Parent $PSScriptRoot) "config/statusline-config.json"
}

function Get-DefaultConfig {
    return [pscustomobject]@{
        thresholds = [pscustomobject]@{
            warn = 70
            critical = 85
        }
        display = [pscustomobject]@{
            use_symbol = $true
            symbol_code_point = 9679
            ascii_symbol = "*"
            shorten_critical = $false
        }
        colors = [pscustomobject]@{
            enabled = $true
        }
    }
}

function Get-Config {
    param([string]$Path)

    $config = Get-DefaultConfig

    if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
        try {
            $loaded = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
            foreach ($section in @("thresholds", "display", "colors")) {
                $loadedSection = $loaded.PSObject.Properties[$section]
                if ($null -eq $loadedSection -or $null -eq $loadedSection.Value) {
                    continue
                }

                foreach ($property in $loadedSection.Value.PSObject.Properties) {
                    if ($null -ne $config.$section.PSObject.Properties[$property.Name]) {
                        $config.$section.($property.Name) = $property.Value
                    }
                }
            }
        }
        catch {
            return $config
        }
    }

    return $config
}

$config = Get-Config -Path $ConfigPath

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

function Get-StatusInfo {
    param(
        [object]$FiveHour,
        [object]$SevenDay,
        [object]$Context,
        [double]$WarnThreshold,
        [double]$CriticalThreshold
    )

    $hasKnownValue = $false
    $status = "fresh"
    $reason = "ok"

    foreach ($entry in @(
        @{ name = "five_hour"; value = $FiveHour },
        @{ name = "weekly"; value = $SevenDay },
        @{ name = "context"; value = $Context }
    )) {
        $value = $entry.value
        if ($null -eq $value -or $value -eq "") {
            continue
        }

        try {
            $hasKnownValue = $true
            $numeric = [double]$value
            if ($numeric -ge $CriticalThreshold) {
                return [pscustomobject]@{
                    status = "critical"
                    reason = "$($entry.name)_high"
                }
            }

            if ($numeric -ge $WarnThreshold -and $status -ne "warn") {
                $status = "warn"
                $reason = "$($entry.name)_high"
            }
        }
        catch {
            continue
        }
    }

    if (-not $hasKnownValue) {
        return [pscustomobject]@{
            status = "waiting"
            reason = "waiting"
        }
    }

    return [pscustomobject]@{
        status = $status
        reason = $reason
    }
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
                if ($numeric -ge [double]$config.thresholds.critical) { return "31;1" }
                if ($numeric -ge [double]$config.thresholds.warn) { return "33" }
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
                if ($numeric -ge [double]$config.thresholds.critical) { return "31;1" }
                if ($numeric -ge [double]$config.thresholds.warn) { return "33" }
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

    if ($Plain -or $NoColor -or $env:NO_COLOR -or -not [bool]$config.colors.enabled) {
        return $Text
    }

    $esc = [char]27
    return "$esc[$($Code)m$Text$esc[0m"
}

function Get-StatusSymbol {
    param([object]$Config)

    if ($Plain -or -not [bool]$Config.display.use_symbol) {
        return [string]$Config.display.ascii_symbol
    }

    try {
        return [char][int]$Config.display.symbol_code_point
    }
    catch {
        return [string]$Config.display.ascii_symbol
    }
}

function Format-StatusLabel {
    param([string]$Status)

    if ([bool]$config.display.shorten_critical -and $Status -eq "critical") {
        return "crit"
    }

    return $Status
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
        schema_version = 2
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
        status_reason = $Status
        display = [ordered]@{
            five_hour = "5h --"
            seven_day = "W --"
            context = "ctx --"
        }
    }
}

$inputJson = [Console]::In.ReadToEnd()

if ([string]::IsNullOrWhiteSpace($inputJson)) {
    $snapshot = New-FallbackSnapshot -Status "waiting"
    Write-Snapshot -Path $SnapshotPath -Snapshot $snapshot
    $dot = Colorize (Get-StatusSymbol $config) (Get-ColorCode "state" "waiting")
    Write-Output "$dot - | eff - | think - | 5h -- | W -- | ctx -- | waiting"
    exit 0
}

try {
    $data = $inputJson | ConvertFrom-Json
}
catch {
    $snapshot = New-FallbackSnapshot -Status "stale"
    Write-Snapshot -Path $SnapshotPath -Snapshot $snapshot
    $dot = Colorize (Get-StatusSymbol $config) (Get-ColorCode "state" "stale")
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
$statusInfo = Get-StatusInfo -FiveHour $fiveHourUsed -SevenDay $sevenDayUsed -Context $contextUsed -WarnThreshold ([double]$config.thresholds.warn) -CriticalThreshold ([double]$config.thresholds.critical)
$status = $statusInfo.status
$statusReason = $statusInfo.reason

$dot = Colorize (Get-StatusSymbol $config) (Get-ColorCode "state" $status)
$effortText = Colorize "eff $effort" (Get-ColorCode "effort" $effort)
$fiveHourText = Colorize ("5h {0}" -f (Format-Percent $fiveHourUsed)) (Get-ColorCode "percentage" $fiveHourUsed)
$sevenDayText = Colorize ("W {0}" -f (Format-Percent $sevenDayUsed)) (Get-ColorCode "percentage" $sevenDayUsed)
$contextText = Colorize ("ctx {0}" -f (Format-Percent $contextUsed)) (Get-ColorCode "context" $contextUsed)
$statusLabel = Format-StatusLabel $status
$statusText = Colorize $statusLabel (Get-ColorCode "state" $status)
$fiveHourCountdown = Format-Countdown $fiveHourReset
$sevenDayResetText = Format-ResetDay $sevenDayReset

$snapshot = [ordered]@{
    updated_at = [DateTimeOffset]::Now.ToString("o")
    schema_version = 2
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
    status_reason = $statusReason
    display = [ordered]@{
        five_hour = "5h $(Format-Percent $fiveHourUsed) $fiveHourCountdown"
        seven_day = "W $(Format-Percent $sevenDayUsed) $sevenDayResetText"
        context = "ctx $(Format-Percent $contextUsed)"
    }
}

Write-Snapshot -Path $SnapshotPath -Snapshot $snapshot
Write-Output "$dot $model | $effortText | think $thinking | $fiveHourText $fiveHourCountdown | $sevenDayText $sevenDayResetText | $contextText | $statusText"
