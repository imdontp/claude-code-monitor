param(
    [string]$ConfigPath = $env:CLAUDE_STATUSLINE_CONFIG_PATH,
    [switch]$NoColor
)

$ErrorActionPreference = "Stop"

try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [Console]::OutputEncoding = $utf8NoBom
    $OutputEncoding = $utf8NoBom
}
catch {}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path (Split-Path -Parent $PSScriptRoot) "config/statusline-config.json"
}

function Get-Value {
    param([object]$Object, [string]$Name, [object]$Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function Format-Elapsed {
    param([object]$StartTime)
    if ($null -eq $StartTime -or $StartTime -eq "") { return "--:--" }
    try {
        $start = if ($StartTime -is [ValueType]) {
            [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$StartTime)
        }
        else {
            [DateTimeOffset]::Parse([string]$StartTime)
        }
        $elapsed = [DateTimeOffset]::Now - $start
        if ($elapsed.TotalSeconds -lt 0) { return "00:00" }
        if ($elapsed.TotalHours -ge 1) {
            return ("{0}:{1:D2}:{2:D2}" -f [math]::Floor($elapsed.TotalHours), $elapsed.Minutes, $elapsed.Seconds)
        }
        return ("{0:D2}:{1:D2}" -f [math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds)
    }
    catch { return "--:--" }
}

function Colorize {
    param([string]$Text, [string]$Code)
    if ($NoColor -or $env:NO_COLOR) { return $Text }
    $esc = [char]27
    return "$esc[$($Code)m$Text$esc[0m"
}

$mode = "full"
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
        $configuredMode = [string](Get-Value (Get-Value $config "display" $null) "mode" "full")
        if ($configuredMode -in @("full", "compact")) { $mode = $configuredMode }
    }
    catch {}
}

$inputJson = [Console]::In.ReadToEnd()
$inputJson = $inputJson.TrimStart([char]0xFEFF)
if ([string]::IsNullOrWhiteSpace($inputJson)) { exit 0 }
try { $data = $inputJson | ConvertFrom-Json }
catch { exit 0 }

foreach ($task in @(Get-Value $data "tasks" @())) {
    $id = [string](Get-Value $task "id" "")
    if ([string]::IsNullOrWhiteSpace($id)) { continue }

    $status = ([string](Get-Value $task "status" "running")).ToLowerInvariant()
    $name = [string](Get-Value $task "name" (Get-Value $task "type" "agent"))
    $description = [string](Get-Value $task "label" (Get-Value $task "description" "Working"))
    $elapsed = Format-Elapsed (Get-Value $task "startTime" $null)
    $tokens = Get-Value $task "tokenCount" $null

    switch -Regex ($status) {
        'fail|error' { $icon = Colorize ([string][char]10007) "31;1" }
        'complete|done|success' { $icon = Colorize ([string][char]10003) "32" }
        'idle|wait' { $icon = Colorize ([string][char]8987) "33" }
        default { $icon = Colorize ([string][char]9679) "36" }
    }

    if ($mode -eq "compact") {
        $content = "$icon $name $elapsed"
    }
    else {
        if ($description.Length -gt 48) { $description = $description.Substring(0, 45) + "..." }
        $tokenText = if ($null -ne $tokens -and $tokens -ne "") { " | $tokens tok" } else { "" }
        $content = "$icon $name | $description | $elapsed$tokenText"
    }

    [pscustomobject]@{ id = $id; content = $content } | ConvertTo-Json -Compress
}
