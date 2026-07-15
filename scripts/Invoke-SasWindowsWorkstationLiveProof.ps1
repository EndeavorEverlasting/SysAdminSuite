#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$AgentResultPath,
    [string]$Distro = 'Ubuntu',
    [string]$SessionName = 'dev',
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'SysAdminSuite\workstation'),
    [int]$TimeoutSeconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$service = Join-Path $PSScriptRoot 'Invoke-SasWindowsTmuxWorkspace.ps1'
$statePath = Join-Path $StateRoot 'windows-tmux-workspace-state.json'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'WezTerm tmux.lnk'
$schemaPath = Join-Path $repoRoot 'schemas\harness\developer-workstation-live-proof.schema.json'

function Write-JsonFile {
    param([string]$Path, $Value)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 12) + "`n"), [Text.UTF8Encoding]::new($false))
}

function Invoke-Wsl {
    param([string[]]$Arguments, [switch]$AllowFailure)
    $lines = @(& wsl.exe -d $Distro --exec @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    $code = $LASTEXITCODE
    if ($code -ne 0 -and -not $AllowFailure) { throw "WSL command failed with exit code $code" }
    return [pscustomobject]@{ exit_code = $code; lines = $lines }
}

function Get-TmuxSnapshot {
    $session = Invoke-Wsl -Arguments @('tmux', 'display-message', '-p', '-t', $SessionName, 'session=#{session_name}|attached=#{session_attached}|windows=#{session_windows}')
    $windows = Invoke-Wsl -Arguments @('tmux', 'list-windows', '-t', $SessionName, '-F', '#{window_index}|#{window_name}|#{pane_current_command}')
    return [pscustomobject]@{ session = @($session.lines)[0]; windows = @($windows.lines) }
}

function Get-ExactGuiProcess {
    param([Nullable[int]]$ProcessId)
    if (-not $ProcessId) { return $null }
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
    if (-not $process -or $process.Name -ine 'wezterm-gui.exe' -or $process.CommandLine -notlike '*start --always-new-process*') { return $null }
    return $process
}

if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw 'workspace state is absent; run Start first' }
if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) { throw 'generated WezTerm tmux shortcut is absent' }
if (-not (Test-Path -LiteralPath $AgentResultPath -PathType Leaf)) { throw 'AgentSwitchboard result is absent' }
$agentResult = Get-Content -Raw -LiteralPath $AgentResultPath | ConvertFrom-Json
$state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
$ownedGuiPid = if ($null -ne $state.PSObject.Properties['gui_pid']) { [Nullable[int]]$state.gui_pid } else { $null }
$initial = Get-TmuxSnapshot
Write-JsonFile -Path (Join-Path $OutputRoot 'tmux-before.json') -Value $initial

$agentRows = [Collections.Generic.List[object]]::new()
foreach ($agent in @('opencode', 'agy', 'goose')) {
    $windowName = "sas-$agent"
    $target = "${SessionName}:$windowName"
    $exists = (Invoke-Wsl -Arguments @('tmux', 'list-windows', '-t', $SessionName, '-F', '#{window_name}')).lines -contains $windowName
    if (-not $exists) { Invoke-Wsl -Arguments @('tmux', 'new-window', '-d', '-t', $SessionName, '-n', $windowName) | Out-Null }
    $marker = ([guid]::NewGuid().ToString('N').Substring(0, 12))
    $begin = "__SAS_${marker}_BEGIN__"
    $end = "__SAS_${marker}_END__"
    $command = "export PATH=`"`$HOME/.local/agent-switchboard/bin:`$PATH`"; printf '$begin\n'; $agent --help >/dev/null 2>&1; rc=`$?; printf '$end rc=%s\n' `"`$rc`""
    Invoke-Wsl -Arguments @('tmux', 'send-keys', '-t', $target, '-l', '--', $command) | Out-Null
    Invoke-Wsl -Arguments @('tmux', 'send-keys', '-t', $target, 'Enter') | Out-Null
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $capture = ''
    do {
        Start-Sleep -Milliseconds 200
        $capture = ((Invoke-Wsl -Arguments @('tmux', 'capture-pane', '-p', '-J', '-t', $target, '-S', '-100')).lines -join "`n")
    } until ($capture.Contains("$end rc=") -or (Get-Date) -ge $deadline)
    $acknowledged = $capture.Contains($begin) -and $capture.Contains("$end rc=")
    $helpSucceeded = [regex]::IsMatch($capture, [regex]::Escape($end) + '\s+rc=0')
    $row = $agentResult.agents.$agent
    $agentRows.Add([pscustomobject]@{
        agent = $agent
        canonical_wrapper = $agent
        selected_backend = $row.selected_backend
        command_acknowledged = $acknowledged
        help_interaction_observed = $helpSucceeded
        provider_response_observed = $false
        authentication_observed = $false
    })
}
Write-JsonFile -Path (Join-Path $OutputRoot 'agent-resolution.json') -Value @($agentRows)

$prepared = Get-TmuxSnapshot
Invoke-Wsl -Arguments @('tmux', 'detach-client', '-s', $SessionName) -AllowFailure | Out-Null
Start-Sleep -Milliseconds 500
$detached = Get-TmuxSnapshot
Write-JsonFile -Path (Join-Path $OutputRoot 'tmux-after-detach.json') -Value $detached

$gui = Get-ExactGuiProcess -ProcessId $ownedGuiPid
if ($gui) { Stop-Process -Id $gui.ProcessId -ErrorAction Stop }
$ownedGuiClosed = -not [bool](Get-Process -Id $ownedGuiPid -ErrorAction SilentlyContinue)
$statusPath = Join-Path $OutputRoot 'workspace-status-after-detach.json'
& $service -Action Status -StateRoot $StateRoot -OutputPath $statusPath | Out-Null
$status = Get-Content -Raw -LiteralPath $statusPath | ConvertFrom-Json

Start-Process -FilePath $shortcutPath | Out-Null
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$newGui = $null
do {
    Start-Sleep -Milliseconds 250
    if (Test-Path -LiteralPath $statePath) {
        $newState = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
        $candidate = if ($null -ne $newState.PSObject.Properties['gui_pid']) { [Nullable[int]]$newState.gui_pid } else { $null }
        if ($candidate -and $candidate -ne $ownedGuiPid) { $newGui = Get-ExactGuiProcess -ProcessId $candidate }
    }
} until ($newGui -or (Get-Date) -ge $deadline)
if (-not $newGui) { throw 'generated shortcut did not produce an independently owned WezTerm GUI' }
Start-Sleep -Milliseconds 750
$reopened = Get-TmuxSnapshot
Write-JsonFile -Path (Join-Path $OutputRoot 'tmux-after-reopen.json') -Value $reopened

$beforeNames = @($prepared.windows | ForEach-Object { ($_ -split '\|', 3)[1] } | Sort-Object)
$afterNames = @($reopened.windows | ForEach-Object { ($_ -split '\|', 3)[1] } | Sort-Object)
$sameWindows = ($beforeNames -join "`n") -eq ($afterNames -join "`n")
$allAgents = @($agentRows).Count -eq 3 -and @($agentRows | Where-Object { -not $_.command_acknowledged -or -not $_.help_interaction_observed }).Count -eq 0
$detachedObserved = $detached.session -match 'attached=0'
$reattachedObserved = $reopened.session -match 'attached=[1-9]'
$statusHealthy = $status.outcome -eq 'success'
$recoverableShells = @($reopened.windows | Where-Object { $_ -match '\|sas-(opencode|agy|goose)\|bash$' }).Count -eq 3
$passed = $sameWindows -and $allAgents -and $detachedObserved -and $reattachedObserved -and $statusHealthy -and $ownedGuiClosed -and $recoverableShells
$result = [ordered]@{
    schema_version = 'sas-developer-workstation-live-proof/v1'
    platform = 'windows'; execution_domain = 'windows-wsl'; distro = $Distro; session = $SessionName
    outcome = if ($passed) { 'PASS' } else { 'FAIL' }
    agents = @($agentRows)
    observations = [ordered]@{
        independent_gui_started = [bool]$newGui; parent_powershell_required = $false
        tmux_detached = $detachedObserved; owned_gui_closed = $ownedGuiClosed
        backend_status_healthy_after_detach = $statusHealthy
        same_session_windows_reopened = $sameWindows -and $reattachedObserved
        recoverable_shells_observed = $recoverableShells
    }
    proof = [ordered]@{
        live_runtime = $true; command_acknowledged = $allAgents; behavior_observed = $allAgents
        persistence_observed = $sameWindows -and $detachedObserved -and $reattachedObserved
        agent_interaction_observed = $allAgents
        agent_interaction_scope = 'canonical-wrapper-help-command-only'
        provider_response_observed = $false; authentication_observed = $false; operator_accepted = $false
    }
}
$json = $result | ConvertTo-Json -Depth 12
if (-not ($json | Test-Json -SchemaFile $schemaPath)) { throw 'live proof did not validate against its schema' }
Write-JsonFile -Path (Join-Path $OutputRoot 'windows-live-proof.json') -Value $result
$result | ConvertTo-Json -Depth 12
if (-not $passed) { exit 1 }
