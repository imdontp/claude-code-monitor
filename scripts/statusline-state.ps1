param(
    [string]$Event,
    [string]$StateRoot = $env:CLAUDE_STATUSLINE_STATE_ROOT
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($StateRoot)) {
    $claudeConfigRoot = $env:CLAUDE_CONFIG_DIR
    if ([string]::IsNullOrWhiteSpace($claudeConfigRoot)) {
        $claudeConfigRoot = Join-Path $HOME ".claude"
    }
    $StateRoot = Join-Path $claudeConfigRoot "statusline-state"
}

function Get-Value {
    param([object]$Object, [string]$Name, [object]$Default = $null)

    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function New-State {
    param([string]$SessionId)

    return [ordered]@{
        schema_version = 1
        session_id = $SessionId
        updated_at = [DateTimeOffset]::Now.ToString("o")
        main = [ordered]@{
            status = "ready"
            started_at = $null
            updated_at = [DateTimeOffset]::Now.ToString("o")
            error = $null
        }
        agents = @()
        processes = @()
    }
}

function Upsert-Item {
    param(
        [object[]]$Items,
        [string]$Id,
        [hashtable]$Values
    )

    $result = @()
    $found = $false
    foreach ($item in @($Items)) {
        if ([string](Get-Value $item "id" "") -eq $Id) {
            foreach ($key in $Values.Keys) {
                $property = $item.PSObject.Properties[$key]
                if ($null -eq $property) {
                    $item | Add-Member -NotePropertyName $key -NotePropertyValue $Values[$key]
                }
                else {
                    $property.Value = $Values[$key]
                }
            }
            $result += $item
            $found = $true
        }
        else {
            $result += $item
        }
    }

    if (-not $found) {
        $entry = [ordered]@{ id = $Id }
        foreach ($key in $Values.Keys) { $entry[$key] = $Values[$key] }
        $result += [pscustomobject]$entry
    }

    return @($result)
}

function Test-ItemExists {
    param([object[]]$Items, [string]$Id)

    foreach ($item in @($Items)) {
        if ([string](Get-Value $item "id" "") -eq $Id) { return $true }
    }
    return $false
}

$inputJson = [Console]::In.ReadToEnd()
$inputJson = $inputJson.TrimStart([char]0xFEFF)
if ([string]::IsNullOrWhiteSpace($inputJson)) { exit 0 }

try { $data = $inputJson | ConvertFrom-Json }
catch { exit 0 }

$sessionId = [string](Get-Value $data "session_id" "")
if ([string]::IsNullOrWhiteSpace($sessionId)) { exit 0 }
if ([string]::IsNullOrWhiteSpace($Event)) {
    $Event = [string](Get-Value $data "hook_event_name" "")
}

New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
$statePath = Join-Path $StateRoot "$sessionId.json"
$mutexName = "ClaudeStatusline_" + ($sessionId -replace '[^A-Za-z0-9_-]', '_')
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
$locked = $false

try {
    try { $locked = $mutex.WaitOne(2000) }
    catch [System.Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { exit 0 }

    $state = $null
    if (Test-Path -LiteralPath $statePath) {
        try { $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json }
        catch { $state = $null }
    }
    if ($null -eq $state) { $state = [pscustomobject](New-State $sessionId) }

    $now = [DateTimeOffset]::Now.ToString("o")
    $main = Get-Value $state "main" $null
    if ($null -eq $main) {
        $state | Add-Member -NotePropertyName main -NotePropertyValue ([pscustomobject](New-State $sessionId).main) -Force
        $main = $state.main
    }
    if ($null -eq $state.PSObject.Properties["agents"]) { $state | Add-Member agents @() }
    if ($null -eq $state.PSObject.Properties["processes"]) { $state | Add-Member processes @() }

    switch ($Event) {
        "SessionStart" {
            $main.status = "ready"
            $main.started_at = $null
            $main.error = $null
            # A resumed session may not have emitted stop events before the prior
            # process exited. Never carry those running entries into a new run.
            $state.agents = @()
            $state.processes = @()
        }
        "UserPromptSubmit" {
            $main.status = "working"
            $main.started_at = $now
            $main.error = $null
        }
        "Stop" {
            $main.status = "ready"
            $main.started_at = $null
        }
        "StopFailure" {
            $main.status = "failed"
            $main.started_at = $null
            $main.error = [string](Get-Value $data "error" "unknown")
        }
        "SessionEnd" {
            $main.status = "ready"
            $main.started_at = $null
            $state.agents = @()
            $state.processes = @()
        }
        "SubagentStart" {
            $agentId = [string](Get-Value $data "agent_id" (Get-Value $data "tool_use_id" ([guid]::NewGuid().ToString())))
            $agentName = [string](Get-Value $data "agent_type" "agent")
            $state.agents = @(Upsert-Item -Items $state.agents -Id $agentId -Values @{
                name = $agentName
                description = [string](Get-Value $data "description" "Working")
                status = "running"
                started_at = $now
                updated_at = $now
            })
        }
        "SubagentStop" {
            $agentId = [string](Get-Value $data "agent_id" "")
            if (-not [string]::IsNullOrWhiteSpace($agentId)) {
                $state.agents = @(Upsert-Item -Items $state.agents -Id $agentId -Values @{
                    status = "completed"
                    updated_at = $now
                })
            }
        }
        "PreToolUse" {
            $toolName = [string](Get-Value $data "tool_name" "")
            $toolInput = Get-Value $data "tool_input" $null
            $background = [bool](Get-Value $toolInput "run_in_background" $false)
            if ($background -and $toolName -match '^(Bash|PowerShell)$') {
                $toolUseId = [string](Get-Value $data "tool_use_id" ([guid]::NewGuid().ToString()))
                $label = [string](Get-Value $toolInput "description" "")
                if ([string]::IsNullOrWhiteSpace($label)) {
                    $label = [string](Get-Value $toolInput "command" "background command")
                    if ($label.Length -gt 64) { $label = $label.Substring(0, 61) + "..." }
                }
                $state.processes = @(Upsert-Item -Items $state.processes -Id $toolUseId -Values @{
                    name = $label
                    status = "running"
                    started_at = $now
                    updated_at = $now
                })
            }
        }
        "PostToolUseFailure" {
            $toolUseId = [string](Get-Value $data "tool_use_id" "")
            # Only background commands are registered by PreToolUse. A normal
            # foreground command failure must not create a phantom process.
            if (-not [string]::IsNullOrWhiteSpace($toolUseId) -and
                (Test-ItemExists -Items $state.processes -Id $toolUseId)) {
                $state.processes = @(Upsert-Item -Items $state.processes -Id $toolUseId -Values @{
                    status = "failed"
                    updated_at = $now
                })
            }
        }
    }

    $main.updated_at = $now
    $state.updated_at = $now
    $tempPath = "$statePath.tmp.$PID"
    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tempPath -Encoding UTF8
    Move-Item -LiteralPath $tempPath -Destination $statePath -Force
}
catch {
    # Hooks must never interrupt Claude Code because status tracking failed.
    exit 0
}
finally {
    if ($locked) { try { $mutex.ReleaseMutex() } catch {} }
    $mutex.Dispose()
}

exit 0
