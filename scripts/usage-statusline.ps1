param(
    [string]$SnapshotPath = $env:CLAUDE_USAGE_SNAPSHOT_PATH,
    [string]$ConfigPath = $env:CLAUDE_STATUSLINE_CONFIG_PATH,
    [string]$StateRoot = $env:CLAUDE_STATUSLINE_STATE_ROOT,
    [switch]$NoColor,
    [switch]$Plain
)

$ErrorActionPreference = "Stop"

try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [Console]::OutputEncoding = $utf8NoBom
    $OutputEncoding = $utf8NoBom
}
catch {
    # Keep the statusline functional if the host does not allow encoding changes.
}

if ([string]::IsNullOrWhiteSpace($SnapshotPath)) {
    $SnapshotPath = Join-Path $HOME ".claude/usage-snapshot.json"
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path (Split-Path -Parent $PSScriptRoot) "config/statusline-config.json"
}

if ([string]::IsNullOrWhiteSpace($StateRoot)) {
    $claudeConfigRoot = $env:CLAUDE_CONFIG_DIR
    if ([string]::IsNullOrWhiteSpace($claudeConfigRoot)) {
        $claudeConfigRoot = Join-Path $HOME ".claude"
    }
    $StateRoot = Join-Path $claudeConfigRoot "statusline-state"
}

$ClaudeConfigRoot = Split-Path -Parent $StateRoot

function Get-DefaultConfig {
    return [pscustomobject]@{
        thresholds = [pscustomobject]@{
            warn = 70
            critical = 85
        }
        display = [pscustomobject]@{
            mode = "full"
            use_symbol = $true
            symbol_style = "solid"
            symbol_code_point = 9608
            ascii_symbol = "*"
            usage_filled_code_point = 9608
            usage_empty_code_point = 9617
            usage_ascii_filled = "#"
            usage_ascii_empty = "-"
            usage_bar_segments = 12
            two_line = $true
            shorten_critical = $false
        }
        colors = [pscustomobject]@{
            enabled = $true
        }
    }
}

function Get-SymbolPreset {
    param([string]$Name)

    $presets = @{
        circle         = @{ filled = 9679;  empty = 9675 }  # ● ○
        bullet         = @{ filled = 8226;  empty = 9702 }  # • ◦
        fisheye        = @{ filled = 9673;  empty = 9678 }  # ◉ ◎
        square         = @{ filled = 9632;  empty = 9633 }  # ■ □
        solid          = @{ filled = 9608;  empty = 9617 }  # █ ░
        "small-square" = @{ filled = 9642;  empty = 9643 }  # ▪ ▫
        diamond        = @{ filled = 9670;  empty = 9671 }  # ◆ ◇
        triangle       = @{ filled = 9650;  empty = 9651 }  # ▲ △
        star           = @{ filled = 9733;  empty = 9734 }  # ★ ☆
        "large-circle" = @{ filled = 11044; empty = 9711 }  # ⬤ ◯
        "dot-operator" = @{ filled = 8857;  empty = 9675 }  # ⊙ ○
    }

    $key = $Name.ToLowerInvariant().Trim()
    if ($presets.ContainsKey($key)) {
        return $presets[$key]
    }

    return $null
}

function Get-Config {
    param([string]$Path)

    $config = Get-DefaultConfig

    if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
        try {
            $loaded = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json

            $styleName = $null
            $loadedDisplay = $loaded.PSObject.Properties["display"]
            if ($null -ne $loadedDisplay -and $null -ne $loadedDisplay.Value) {
                $styleProperty = $loadedDisplay.Value.PSObject.Properties["symbol_style"]
                if ($null -ne $styleProperty) {
                    $styleName = $styleProperty.Value
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($styleName)) {
                $preset = Get-SymbolPreset -Name ([string]$styleName)
                if ($null -ne $preset) {
                    $config.display.symbol_code_point = $preset.filled
                    $config.display.usage_filled_code_point = $preset.filled
                    $config.display.usage_empty_code_point = $preset.empty
                }
            }

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

function Get-FirstField {
    param(
        [object]$Object,
        [string[]]$Paths,
        [object]$Default = $null
    )

    foreach ($path in $Paths) {
        $value = Get-Field $Object $path $null
        if ($null -ne $value -and $value -ne "") {
            return $value
        }
    }

    return $Default
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

function Format-Cost {
    param([object]$Value)

    if ($null -eq $Value -or $Value -eq "") {
        return "--"
    }

    try {
        $numeric = [double]::Parse(
            [string]$Value,
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture
        )
        if ($numeric -lt 0) { return "--" }
        return ('$' + $numeric.ToString("0.####", [Globalization.CultureInfo]::InvariantCulture))
    }
    catch {
        return "--"
    }
}

function Format-TokenCount {
    param([object]$Value)

    if ($null -eq $Value -or $Value -eq "") {
        return "--"
    }

    try {
        $numeric = [double]$Value
        if ($numeric -lt 0) { return "--" }
        if ($numeric -ge 1000000) {
            return (($numeric / 1000000).ToString("0.#", [Globalization.CultureInfo]::InvariantCulture) + "M")
        }
        if ($numeric -ge 1000) {
            return (($numeric / 1000).ToString("0.#", [Globalization.CultureInfo]::InvariantCulture) + "k")
        }
        return ([math]::Round($numeric)).ToString([Globalization.CultureInfo]::InvariantCulture)
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

    $normalized = ([string]$Value).ToLowerInvariant()
    switch ($normalized) {
        "low" { return "Low" }
        "medium" { return "Medium" }
        "med" { return "Medium" }
        "high" { return "High" }
        "xhigh" { return "XHigh" }
        "max" { return "Max" }
        default {
            $text = [string]$Value
            if ($text.Length -eq 0) { return "-" }
            return ($text.Substring(0, 1).ToUpperInvariant() + $text.Substring(1))
        }
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
            switch (([string]$Value).ToLowerInvariant()) {
                "low" { return "32" }
                "medium" { return "36" }
                "med" { return "36" }
                "high" { return "33" }
                "xhigh" { return "35" }
                "max" { return "31;1" }
                default { return "90" }
            }
        }
        "cost" {
            if ($null -eq $Value -or $Value -eq "") { return "90" }
            return "36"
        }
        "percentage" {
            return Get-UsageLevelColorCode $Value
        }
        "context" {
            return Get-UsageLevelColorCode $Value
        }
        default {
            return "0"
        }
    }
}

function Get-UsageLevelColorCode {
    param([object]$Value)

    if ($null -eq $Value -or $Value -eq "") {
        return "90"
    }

    try {
        $numeric = [double]$Value
        if ($numeric -ge 90) { return "31;1" }
        if ($numeric -ge 75) { return "38;5;208" }
        if ($numeric -ge 60) { return "33" }
        return "32"
    }
    catch {
        return "90"
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

function Get-UsageSymbol {
    param(
        [object]$Config,
        [bool]$Filled
    )

    if ($Plain) {
        if ($Filled) {
            return [string]$Config.display.usage_ascii_filled
        }

        return [string]$Config.display.usage_ascii_empty
    }

    try {
        if ($Filled) {
            return [char][int]$Config.display.usage_filled_code_point
        }

        return [char][int]$Config.display.usage_empty_code_point
    }
    catch {
        if ($Filled) {
            return [string]$Config.display.usage_ascii_filled
        }

        return [string]$Config.display.usage_ascii_empty
    }
}

function Get-UsageBarColorCode {
    param(
        [double]$Percentage,
        [bool]$Filled
    )

    if (-not $Filled) {
        return "90"
    }

    return Get-UsageLevelColorCode $Percentage
}

function Format-UsageBar {
    param(
        [object]$Value,
        [switch]$NoAnsi
    )

    $segments = [int]$config.display.usage_bar_segments
    if ($segments -lt 1) {
        $segments = 12
    }

    $numeric = 0
    $filledSegments = 0
    if ($null -ne $Value -and $Value -ne "") {
        try {
            $numeric = [double]$Value
            if ($numeric -lt 0) {
                $numeric = 0
            }
            if ($numeric -gt 100) {
                $numeric = 100
            }

            $filledSegments = [int][math]::Round(($numeric / 100) * $segments, [System.MidpointRounding]::AwayFromZero)
        }
        catch {
            $filledSegments = 0
        }
    }

    $bar = ""
    for ($index = 1; $index -le $segments; $index++) {
        $filled = $index -le $filledSegments
        $symbol = Get-UsageSymbol -Config $config -Filled $filled
        if ($NoAnsi) {
            $bar += $symbol
        }
        else {
            $bar += Colorize $symbol (Get-UsageBarColorCode -Percentage $numeric -Filled $filled)
        }
    }

    return $bar
}

function Format-ContextText {
    param(
        [object]$Value,
        [object]$InputTokens,
        [object]$WindowSize,
        [switch]$NoAnsi
    )

    $percent = Format-Percent $Value
    $bar = if ($NoAnsi) { Format-UsageBar $Value -NoAnsi } else { Format-UsageBar $Value }
    $percentText = if ($NoAnsi) { $percent } else { Colorize $percent (Get-ColorCode "context" $Value) }
    $text = "Context: $percentText $bar"

    if ($null -ne $InputTokens -and $InputTokens -ne "" -and $null -ne $WindowSize -and $WindowSize -ne "") {
        $inputText = Format-TokenCount $InputTokens
        $windowText = Format-TokenCount $WindowSize
        if ($inputText -ne "--" -and $windowText -ne "--") {
            $text += " ($inputText/$windowText)"
        }
    }

    return $text
}

function Format-StatusLabel {
    param([string]$Status)

    if ([bool]$config.display.shorten_critical -and $Status -eq "critical") {
        return "crit"
    }

    return $Status
}

function Format-Elapsed {
    param([object]$StartedAt)

    if ($null -eq $StartedAt -or $StartedAt -eq "") {
        return ""
    }

    try {
        $start = [DateTimeOffset]::Parse([string]$StartedAt)
        $elapsed = [DateTimeOffset]::Now - $start
        if ($elapsed.TotalSeconds -lt 0) { return "00:00" }
        if ($elapsed.TotalHours -ge 1) {
            return ("{0}:{1:D2}:{2:D2}" -f [math]::Floor($elapsed.TotalHours), $elapsed.Minutes, $elapsed.Seconds)
        }
        return ("{0:D2}:{1:D2}" -f [math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds)
    }
    catch {
        return ""
    }
}

function Get-ActivityIcon {
    param([string]$Status)

    switch ($Status) {
        "working" { return Colorize ([string][char]9679) "36" }
        "waiting" { return Colorize ([string][char]9676) "33" }
        "failed" { return Colorize ([string][char]10007) "31;1" }
        default { return Colorize ([string][char]10003) "32" }
    }
}

function Get-ActivityLabel {
    param([string]$Status)

    $label = switch ($Status) {
        "working" { "WORKING" }
        "waiting" { "WAITING" }
        "failed" { "ATTENTION" }
        default { "READY" }
    }

    $code = switch ($Status) {
        "working" { "36" }
        "waiting" { "33" }
        "failed" { "31;1" }
        default { "32" }
    }
    return Colorize $label $code
}

function Test-Recent {
    param([object]$Timestamp, [double]$Hours = 6)

    if ($null -eq $Timestamp -or $Timestamp -eq "") { return $false }
    try {
        return (([DateTimeOffset]::Now - [DateTimeOffset]::Parse([string]$Timestamp)).TotalHours -le $Hours)
    }
    catch { return $false }
}

function Set-ProcessCompletion {
    param([string]$SessionId, [string]$ProcessId, [string]$Status)

    if ([string]::IsNullOrWhiteSpace($SessionId) -or [string]::IsNullOrWhiteSpace($ProcessId)) { return }
    $statePath = Join-Path $StateRoot "$SessionId.json"
    if (-not (Test-Path -LiteralPath $statePath)) { return }

    $mutexName = "ClaudeStatusline_" + ($SessionId -replace '[^A-Za-z0-9_-]', '_')
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(500) }
        catch [System.Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { return }

        $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
        $changed = $false
        foreach ($process in @($state.processes)) {
            if ([string](Get-Field $process "id" "") -eq $ProcessId) {
                $process.status = $Status
                $process.updated_at = [DateTimeOffset]::Now.ToString("o")
                $changed = $true
            }
        }
        if ($changed) {
            $state.updated_at = [DateTimeOffset]::Now.ToString("o")
            $tempPath = "$statePath.tmp.$PID"
            $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tempPath -Encoding UTF8
            Move-Item -LiteralPath $tempPath -Destination $statePath -Force
        }
    }
    catch {}
    finally {
        if ($locked) { try { $mutex.ReleaseMutex() } catch {} }
        $mutex.Dispose()
    }
}

function Get-ActivityInfo {
    param([object]$Data)

    $sessionId = [string](Get-Field $Data "session_id" "")
    $transcriptPath = [string](Get-Field $Data "transcript_path" "")
    $mainStatus = "ready"
    $mainStartedAt = $null
    $agents = @()
    $processes = @()
    $failedProcesses = @()
    $tasks = @()

    if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
        $statePath = Join-Path $StateRoot "$sessionId.json"
        if (Test-Path -LiteralPath $statePath) {
            try {
                $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
                $candidateStatus = [string](Get-Field $state "main.status" "ready")
                if ($candidateStatus -in @("ready", "working", "failed")) { $mainStatus = $candidateStatus }
                $mainStartedAt = Get-Field $state "main.started_at" $null

                $agents = @($state.agents | Where-Object {
                    ([string](Get-Field $_ "status" "") -eq "running") -and
                    (Test-Recent (Get-Field $_ "updated_at" (Get-Field $_ "started_at" $null)))
                })
                $processes = @($state.processes | Where-Object {
                    ([string](Get-Field $_ "status" "") -eq "running") -and
                    (Test-Recent (Get-Field $_ "updated_at" (Get-Field $_ "started_at" $null)))
                })
                $failedProcesses = @($state.processes | Where-Object {
                    ([string](Get-Field $_ "status" "") -eq "failed") -and
                    (Test-Recent (Get-Field $_ "updated_at" $null) 0.25)
                })
            }
            catch {
                # A hook may be replacing the state file. Treat that tick as ready.
            }
        }

        $taskDirectory = Join-Path (Join-Path $ClaudeConfigRoot "tasks") $sessionId
        if (Test-Path -LiteralPath $taskDirectory) {
            foreach ($taskFile in @(Get-ChildItem -LiteralPath $taskDirectory -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
                try {
                    $task = Get-Content -Raw -LiteralPath $taskFile.FullName | ConvertFrom-Json
                    if ([string](Get-Field $task "status" "") -eq "in_progress") { $tasks += $task }
                }
                catch {}
            }
        }
    }

    if ($processes.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($transcriptPath) -and (Test-Path -LiteralPath $transcriptPath)) {
        try {
            $tail = (Get-Content -LiteralPath $transcriptPath -Tail 350 -ErrorAction Stop) -join "`n"
            $stillRunning = @()
            foreach ($process in $processes) {
                $id = [regex]::Escape([string](Get-Field $process "id" ""))
                $completion = $null
                foreach ($block in @($tail -split '</task-notification>')) {
                    if ($block -match "<tool-use-id>$id</tool-use-id>" -and $block -match '<status>(completed|failed|stopped)</status>') {
                        $completion = $Matches[1]
                    }
                }
                if ($null -eq $completion) {
                    $stillRunning += $process
                }
                elseif ($completion -eq "failed") {
                    $failedProcesses += $process
                    Set-ProcessCompletion -SessionId $sessionId -ProcessId ([string](Get-Field $process "id" "")) -Status "failed"
                }
                else {
                    Set-ProcessCompletion -SessionId $sessionId -ProcessId ([string](Get-Field $process "id" "")) -Status $completion
                }
            }
            $processes = @($stillRunning)
        }
        catch {}
    }

    if ($mainStatus -eq "working" -and -not (Test-Recent $mainStartedAt)) {
        $mainStatus = "ready"
        $mainStartedAt = $null
    }

    $externalCount = $agents.Count + $processes.Count + $tasks.Count
    if ($mainStatus -eq "working") {
        $displayStatus = "working"
    }
    elseif ($mainStatus -eq "failed" -or $failedProcesses.Count -gt 0) {
        $displayStatus = "failed"
    }
    elseif ($externalCount -gt 0) {
        $displayStatus = "waiting"
    }
    else {
        $displayStatus = "ready"
    }

    $startedCandidates = @()
    if ($displayStatus -eq "working" -and $null -ne $mainStartedAt) { $startedCandidates += $mainStartedAt }
    foreach ($item in @($agents) + @($processes)) {
        $started = Get-Field $item "started_at" $null
        if ($null -ne $started) { $startedCandidates += $started }
    }
    $elapsedFrom = if ($startedCandidates.Count -gt 0) { $startedCandidates[0] } else { $null }

    return [pscustomobject]@{
        status = $displayStatus
        elapsed = Format-Elapsed $elapsedFrom
        agent_count = $agents.Count
        process_count = $processes.Count
        task_count = $tasks.Count
        agents = @($agents)
        processes = @($processes)
        tasks = @($tasks)
        failed_count = $failedProcesses.Count
    }
}

function Get-ActivitySummary {
    param([object]$Activity)

    $parts = @()
    if ($Activity.agent_count -gt 0) {
        $parts += "Sub-agent:  $($Activity.agent_count)"
    }
    if ($Activity.process_count -gt 0) {
        $parts += "Background: $($Activity.process_count)"
    }
    if ($Activity.task_count -gt 0) {
        $parts += "Task: $($Activity.task_count)"
    }
    if ($Activity.failed_count -gt 0) {
        $parts += "Failed: $($Activity.failed_count)"
    }

    return ($parts -join " | ")
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
            five_hour = "5h: --"
            seven_day = "Weekly: --"
            context = "Context: --"
        }
        cost = [ordered]@{
            total_cost_usd = $null
            display = "--"
        }
    }
}

$inputJson = [Console]::In.ReadToEnd()
$inputJson = $inputJson.TrimStart([char]0xFEFF)

if ([string]::IsNullOrWhiteSpace($inputJson)) {
    $snapshot = New-FallbackSnapshot -Status "waiting"
    Write-Snapshot -Path $SnapshotPath -Snapshot $snapshot
    $emptyUsageBar = Format-UsageBar $null
    if (([string]$config.display.mode).ToLowerInvariant() -eq "compact") {
        Write-Output "Main: $(Get-ActivityIcon 'ready') $(Get-ActivityLabel 'ready') | - | Context: -- $emptyUsageBar | Cost: -- | 5h: -- $emptyUsageBar -- | Weekly: -- $emptyUsageBar --"
    }
    else {
        Write-Output "Main:    $(Get-ActivityIcon 'ready') $(Get-ActivityLabel 'ready') | - | -`nContext: -- $emptyUsageBar | Cost: --`n5h:      -- $emptyUsageBar | reset in --`nWeekly:  -- $emptyUsageBar | reset --"
    }
    exit 0
}

try {
    $data = $inputJson | ConvertFrom-Json
}
catch {
    $snapshot = New-FallbackSnapshot -Status "stale"
    Write-Snapshot -Path $SnapshotPath -Snapshot $snapshot
    $emptyUsageBar = Format-UsageBar $null
    if (([string]$config.display.mode).ToLowerInvariant() -eq "compact") {
        Write-Output "Main: $(Get-ActivityIcon 'failed') $(Get-ActivityLabel 'failed') | - | Context: -- $emptyUsageBar | Cost: -- | 5h: -- $emptyUsageBar -- | Weekly: -- $emptyUsageBar --"
    }
    else {
        Write-Output "Main:    $(Get-ActivityIcon 'failed') $(Get-ActivityLabel 'failed') | - | -`nContext: -- $emptyUsageBar | Cost: --`n5h:      -- $emptyUsageBar | reset in --`nWeekly:  -- $emptyUsageBar | reset --"
    }
    exit 0
}

$model = Get-FirstField $data @(
    "model.display_name",
    "model.name",
    "model",
    "session.model.display_name",
    "session.model.name"
) "-"
$effort = Get-EffortLabel (Get-Field $data "effort.level" $null)
$thinking = Get-ThinkingLabel (Get-Field $data "thinking.enabled" $null)
$fiveHourUsed = Get-FirstField $data @(
    "rate_limits.five_hour.used_percentage",
    "rate_limits.five_hour.percentage_used",
    "rateLimits.fiveHour.usedPercentage",
    "usage.rate_limits.five_hour.used_percentage",
    "usage.five_hour.used_percentage",
    "usage.five_hour.percentage_used",
    "usage.limits.five_hour.used_percentage",
    "claude_company.rate_limits.five_hour.used_percentage",
    "claude_company.usage.five_hour.used_percentage"
) $null
$fiveHourReset = Get-FirstField $data @(
    "rate_limits.five_hour.resets_at",
    "rate_limits.five_hour.reset_at",
    "rate_limits.five_hour.reset_time",
    "rateLimits.fiveHour.resetsAt",
    "usage.rate_limits.five_hour.resets_at",
    "usage.five_hour.resets_at",
    "usage.five_hour.reset_at",
    "usage.limits.five_hour.resets_at",
    "claude_company.rate_limits.five_hour.resets_at",
    "claude_company.usage.five_hour.resets_at"
) $null
$sevenDayUsed = Get-FirstField $data @(
    "rate_limits.seven_day.used_percentage",
    "rate_limits.seven_day.percentage_used",
    "rate_limits.weekly.used_percentage",
    "rate_limits.week.used_percentage",
    "rateLimits.sevenDay.usedPercentage",
    "rateLimits.weekly.usedPercentage",
    "usage.rate_limits.seven_day.used_percentage",
    "usage.seven_day.used_percentage",
    "usage.weekly.used_percentage",
    "usage.limits.seven_day.used_percentage",
    "claude_company.rate_limits.seven_day.used_percentage",
    "claude_company.usage.seven_day.used_percentage"
) $null
$sevenDayReset = Get-FirstField $data @(
    "rate_limits.seven_day.resets_at",
    "rate_limits.seven_day.reset_at",
    "rate_limits.seven_day.reset_time",
    "rate_limits.weekly.resets_at",
    "rate_limits.week.resets_at",
    "rateLimits.sevenDay.resetsAt",
    "rateLimits.weekly.resetsAt",
    "usage.rate_limits.seven_day.resets_at",
    "usage.seven_day.resets_at",
    "usage.seven_day.reset_at",
    "usage.weekly.resets_at",
    "usage.limits.seven_day.resets_at",
    "claude_company.rate_limits.seven_day.resets_at",
    "claude_company.usage.seven_day.resets_at"
) $null
$contextUsed = Get-FirstField $data @(
    "context_window.used_percentage",
    "contextWindow.usedPercentage",
    "context.used_percentage",
    "context.percentage_used",
    "usage.context_window.used_percentage",
    "usage.context.used_percentage",
    "claude_company.context_window.used_percentage",
    "claude_company.usage.context.used_percentage"
) $null
$contextInputTokens = Get-FirstField $data @(
    "context_window.total_input_tokens",
    "contextWindow.totalInputTokens",
    "usage.context_window.total_input_tokens"
) $null
$contextWindowSize = Get-FirstField $data @(
    "context_window.context_window_size",
    "contextWindow.contextWindowSize",
    "usage.context_window.context_window_size"
) $null
if (($null -eq $contextUsed -or $contextUsed -eq "") -and $null -ne $contextInputTokens -and $null -ne $contextWindowSize) {
    try {
        if ([double]$contextWindowSize -gt 0) {
            $contextUsed = ([double]$contextInputTokens / [double]$contextWindowSize) * 100
        }
    }
    catch {}
}
$totalCost = Get-FirstField $data @(
    "cost.total_cost_usd",
    "cost.totalCostUsd",
    "session.cost.total_cost_usd"
) $null
$statusInfo = Get-StatusInfo -FiveHour $fiveHourUsed -SevenDay $sevenDayUsed -Context $contextUsed -WarnThreshold ([double]$config.thresholds.warn) -CriticalThreshold ([double]$config.thresholds.critical)
$status = $statusInfo.status
$statusReason = $statusInfo.reason
$activity = Get-ActivityInfo $data

    $dot = Colorize (Get-StatusSymbol $config) (Get-ColorCode "state" $status)
    $effortText = Colorize $effort (Get-ColorCode "effort" $effort)
    $fiveHourBar = Format-UsageBar $fiveHourUsed
$sevenDayBar = Format-UsageBar $sevenDayUsed
$fiveHourPercentText = Colorize (Format-Percent $fiveHourUsed) (Get-ColorCode "percentage" $fiveHourUsed)
$sevenDayPercentText = Colorize (Format-Percent $sevenDayUsed) (Get-ColorCode "percentage" $sevenDayUsed)
    $fiveHourText = "5h:      $fiveHourPercentText $fiveHourBar"
    $sevenDayText = "Weekly:  $sevenDayPercentText $sevenDayBar"
    $contextText = Format-ContextText -Value $contextUsed -InputTokens $contextInputTokens -WindowSize $contextWindowSize
    $contextPlainText = Format-ContextText -Value $contextUsed -InputTokens $contextInputTokens -WindowSize $contextWindowSize -NoAnsi
    $costDisplay = Format-Cost $totalCost
    $costText = Colorize "Cost: $costDisplay" (Get-ColorCode "cost" $totalCost)
$fiveHourCountdown = Format-Countdown $fiveHourReset
$sevenDayResetText = Format-ResetDay $sevenDayReset

$snapshot = [ordered]@{
    updated_at = [DateTimeOffset]::Now.ToString("o")
    schema_version = 2
    model = $model
    effort = $effort
    thinking = $thinking
    cost = [ordered]@{
        total_cost_usd = $totalCost
        display = $costDisplay
    }
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
        input_tokens = $contextInputTokens
        window_size = $contextWindowSize
    }
    status = $status
    status_reason = $statusReason
    activity = [ordered]@{
        status = $activity.status
        elapsed = $activity.elapsed
        agents = $activity.agent_count
        processes = $activity.process_count
        tasks = $activity.task_count
        failed = $activity.failed_count
    }
    display = [ordered]@{
        five_hour = "5h:      $(Format-Percent $fiveHourUsed) $(Format-UsageBar $fiveHourUsed -NoAnsi) $fiveHourCountdown"
        seven_day = "Weekly:  $(Format-Percent $sevenDayUsed) $(Format-UsageBar $sevenDayUsed -NoAnsi) $sevenDayResetText"
        context = $contextPlainText
        cost = "Cost: $costDisplay"
    }
}

Write-Snapshot -Path $SnapshotPath -Snapshot $snapshot
$mode = ([string]$config.display.mode).ToLowerInvariant()
if ($mode -notin @("full", "compact")) { $mode = "full" }
$activityIcon = Get-ActivityIcon $activity.status
$activityLabel = Get-ActivityLabel $activity.status
$elapsedText = if ([string]::IsNullOrWhiteSpace($activity.elapsed)) { "" } else { " $($activity.elapsed)" }
    $fiveHourSegment = "5h: $fiveHourPercentText $fiveHourBar $fiveHourCountdown"
    $weeklySegment = "Weekly: $sevenDayPercentText $sevenDayBar $sevenDayResetText"

if ($mode -eq "compact") {
    $activitySummary = Get-ActivitySummary $activity
    $summaryText = if ([string]::IsNullOrWhiteSpace($activitySummary)) { "" } else { " | $activitySummary" }
    Write-Output "Main: $activityIcon $activityLabel$elapsedText | $model | $effortText$summaryText | $contextText | $costText | $fiveHourSegment | $weeklySegment"
    exit 0
}

$lines = @(
    "Main:    $activityIcon $activityLabel$elapsedText | $model | $effortText",
    "$contextText | $costText",
    "$fiveHourText | reset in $fiveHourCountdown",
    "$sevenDayText | reset $sevenDayResetText"
)

$activitySummary = Get-ActivitySummary $activity
if (-not [string]::IsNullOrWhiteSpace($activitySummary)) {
    $lines += "  $activitySummary"
}

foreach ($process in @($activity.processes) | Select-Object -First 2) {
    $name = [string](Get-Field $process "name" "background command")
    if ($name.Length -gt 54) { $name = $name.Substring(0, 51) + "..." }
    $processElapsed = Format-Elapsed (Get-Field $process "started_at" $null)
    $gear = Colorize ([string][char]9881) "38;5;208"
    $lines += "  $gear $name | $processElapsed"
}

foreach ($task in @($activity.tasks) | Select-Object -First 2) {
    $taskName = [string](Get-FirstField $task @("activeForm", "subject") "Task in progress")
    if ($taskName.Length -gt 58) { $taskName = $taskName.Substring(0, 55) + "..." }
    $taskIcon = Colorize ([string][char]9677) "35"
    $lines += "  $taskIcon $taskName"
}

Write-Output ($lines -join "`n")
