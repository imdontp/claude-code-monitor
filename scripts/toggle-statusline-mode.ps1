param(
    [ValidateSet("toggle", "full", "compact")]
    [string]$Mode = "toggle",
    [string]$ConfigPath = $env:CLAUDE_STATUSLINE_CONFIG_PATH
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path (Split-Path -Parent $PSScriptRoot) "config/statusline-config.json"
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Statusline config not found: $ConfigPath"
}

$raw = Get-Content -Raw -LiteralPath $ConfigPath
$modePattern = '("mode"\s*:\s*")(full|compact)(")'
$modeMatch = [regex]::Match($raw, $modePattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$current = if ($modeMatch.Success) { $modeMatch.Groups[2].Value.ToLowerInvariant() } else { "full" }
$next = if ($Mode -eq "toggle") {
    if ($current -eq "full") { "compact" } else { "full" }
}
else { $Mode }

if ($modeMatch.Success) {
    $updated = [regex]::Replace(
        $raw,
        $modePattern,
        { param($match) $match.Groups[1].Value + $next + $match.Groups[3].Value },
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase,
        [TimeSpan]::FromSeconds(1)
    )
}
else {
    $displayPattern = '("display"\s*:\s*\{)'
    if (-not [regex]::IsMatch($raw, $displayPattern)) {
        throw "Config does not contain a display object: $ConfigPath"
    }
    $updated = [regex]::Replace($raw, $displayPattern, "`$1`r`n    `"mode`": `"$next`",", 1)
}

$tempPath = "$ConfigPath.tmp.$PID"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tempPath, $updated, $utf8NoBom)
Move-Item -LiteralPath $tempPath -Destination $ConfigPath -Force
Write-Output "Claude statusline mode: $current -> $next"
