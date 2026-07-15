<#
.SYNOPSIS
    Plans and manages the persistent Windows WezTerm to WSL tmux workspace.
.DESCRIPTION
    Plan is the default and is read-only. Apply and Repair require
    -AllowTargetMutation. Start and Stop are explicit lifecycle operations.
    FixturePath selects a fake process adapter and never launches host processes.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Plan', 'Apply', 'Start', 'Status', 'Stop', 'Repair', 'Rollback')]
    [string]$Action = 'Plan',
    [string]$UserConfigDir = $env:USERPROFILE,
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'SysAdminSuite\workstation'),
    [string]$FixturePath,
    [string]$OutputPath,
    [switch]$AllowTargetMutation,
    [switch]$LaunchGui,
    [int]$StartupTimeoutSeconds = 10
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$sessionName = 'dev'
$managedStart = '-- BEGIN SYSADMINSUITE WINDOWS TMUX WORKSPACE'
$managedEnd = '-- END SYSADMINSUITE WINDOWS TMUX WORKSPACE'
$statePath = Join-Path $StateRoot 'windows-tmux-workspace-state.json'
$manifestPath = Join-Path $StateRoot 'windows-tmux-workspace-backup.json'
$sasLuaPath = Join-Path $UserConfigDir '.wezterm-sysadminsuite.lua'
$userLuaPath = Join-Path $UserConfigDir '.wezterm.lua'
$templatePath = Join-Path $repoRoot 'Config\wezterm-windows-tmux.lua.template'
$desktopRoot = if ($FixturePath) { Join-Path $UserConfigDir 'Desktop' } else { [Environment]::GetFolderPath('Desktop') }
$shortcutPath = Join-Path $desktopRoot 'WezTerm tmux.lnk'

function Get-Value {
    param($Object, [string]$Name, $Default = $null)
    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Write-JsonFile {
    param([string]$Path, $Value)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 12) + "`n"), [System.Text.UTF8Encoding]::new($false))
}

function New-Artifact {
    param([string]$Role, [bool]$Fixture, [bool]$LiveData = $false)
    [pscustomobject]@{
        role = $Role
        path_class = if ($Fixture) { 'temporary-fixture' } else { 'repo-ignored-run' }
        tracked = $false
        contains_live_data = $LiveData
    }
}

function New-LifecycleResult {
    param(
        [string]$Operation,
        [string]$Outcome,
        [string]$State,
        [string[]]$Reasons,
        [string]$Message,
        [object[]]$Artifacts = @(),
        [bool]$ConfigApplied = $false,
        [bool]$LauncherStarted = $false
    )
    if ($Outcome -eq 'success') { $Reasons = @('none') }
    $result = [pscustomobject]@{
        schema_version = 'sas-developer-workstation-lifecycle-result/v1'
        workflow_id = 'developer-workstation'
        run_id = 'developer-workstation-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
        operation = $Operation
        outcome = $Outcome
        lifecycle_state = $State
        reason_codes = @($Reasons)
        message = $Message
        artifacts = @($Artifacts)
        proof = [pscustomobject]@{
            install_completed = $false
            config_applied = $ConfigApplied
            launcher_started = $LauncherStarted
            tmux_attached = $false
            command_acknowledged = $false
            behavior_observed = $false
            persistence_observed = $false
            live_runtime = $false
            operator_accepted = $false
        }
    }
    if ($OutputPath) { Write-JsonFile -Path $OutputPath -Value $result }
    return $result
}

function Get-ExactOwnedKeepalive {
    param([string]$PidPath, [string]$Distro)
    if (-not (Test-Path -LiteralPath $PidPath)) { return [pscustomobject]@{ running = $false; stale = $false; pid = $null } }
    $rawPid = (Get-Content -Raw -LiteralPath $PidPath).Trim()
    if ($rawPid -notmatch '^\d+$') { return [pscustomobject]@{ running = $false; stale = $true; pid = $null } }
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $rawPid" -ErrorAction SilentlyContinue
    $owned = $process -and $process.Name -ieq 'wsl.exe' -and $process.CommandLine -like '*sas-workstation-keepalive*' -and $process.CommandLine -like "*$Distro*"
    return [pscustomobject]@{ running = [bool]$owned; stale = -not [bool]$owned; pid = [int]$rawPid }
}

function Start-OwnedKeepaliveProcess {
    param([string]$Distro)
    $wsl = Get-Command wsl.exe -ErrorAction Stop
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $wsl.Source
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    foreach ($argument in @('-d', $Distro, '--exec', 'bash', '-lc', 'exec -a sas-workstation-keepalive sleep infinity')) {
        [void]$startInfo.ArgumentList.Add($argument)
    }
    return [Diagnostics.Process]::Start($startInfo)
}

function Start-IndependentWezTermGui {
    param([string]$GuiPath)
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GuiPath
    # Shell execution prevents the GUI from inheriting redirected orchestrator
    # stdout/stderr handles, so no parent PowerShell process must remain.
    $startInfo.UseShellExecute = $true
    [void]$startInfo.ArgumentList.Add('start')
    [void]$startInfo.ArgumentList.Add('--always-new-process')
    return [Diagnostics.Process]::Start($startInfo)
}

function Get-LiveInventory {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    $distros = @()
    if ($wsl) {
        $distros = @(& $wsl.Source --list --quiet 2>$null | ForEach-Object { ("$_" -replace "`0", '').Trim() } | Where-Object { $_ -and $_ -notmatch '(?i)docker' })
    }
    $distro = @($distros)[0]
    $tmuxAvailable = $false
    $tmuxVersion = $null
    $sessionExists = $false
    if ($distro) {
        $tmuxVersion = (& $wsl.Source -d $distro -- sh -lc 'command -v tmux >/dev/null 2>&1 && tmux -V' 2>$null | Select-Object -First 1)
        $tmuxAvailable = [bool]$tmuxVersion
        if ($tmuxAvailable) {
            & $wsl.Source -d $distro -- tmux has-session -t $sessionName 2>$null
            $sessionExists = $LASTEXITCODE -eq 0
        }
    }
    $guiCandidates = @(
        (Get-Command wezterm-gui.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
        (Join-Path $env:ProgramFiles 'WezTerm\wezterm-gui.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\WezTerm\wezterm-gui.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    $gui = @($guiCandidates)[0]
    $pidPath = Join-Path $StateRoot 'wsl-keepalive.pid'
    $keepalive = if ($distro) { Get-ExactOwnedKeepalive -PidPath $pidPath -Distro $distro } else { [pscustomobject]@{ running = $false; stale = $false; pid = $null } }
    [pscustomobject]@{
        distro = $distro
        docker_only = [bool]($wsl -and -not $distro)
        tmux_available = $tmuxAvailable
        tmux_version = "$tmuxVersion"
        wezterm_gui_available = [bool]$gui
        wezterm_gui_path = $gui
        keepalive_running = $keepalive.running
        keepalive_stale = $keepalive.stale
        keepalive_pid = $keepalive.pid
        session_exists = $sessionExists
        shortcut_exists = Test-Path -LiteralPath $shortcutPath
        nested_tmux = [bool]$env:TMUX
    }
}

function Get-CurrentInventory {
    if ($FixturePath) {
        if (-not (Test-Path -LiteralPath $FixturePath)) { throw "Fixture not found: $FixturePath" }
        $inventory = Read-JsonFile -Path $FixturePath
        $saved = Read-JsonFile -Path $statePath
        foreach ($name in @('keepalive_running', 'keepalive_stale', 'keepalive_pid', 'session_exists', 'shortcut_exists', 'config_applied', 'gui_launched')) {
            if ($saved -and $null -ne $saved.PSObject.Properties[$name]) { Add-Member -InputObject $inventory -NotePropertyName $name -NotePropertyValue $saved.$name -Force }
        }
        return $inventory
    }
    return Get-LiveInventory
}

function Get-BlockingReasons {
    param($Inventory)
    $reasons = @()
    if (-not (Get-Value $Inventory 'distro')) { $reasons += $(if (Get-Value $Inventory 'docker_only' $false) { 'docker-only-distro' } else { 'no-wsl-distro' }) }
    if (-not (Get-Value $Inventory 'tmux_available' $false)) { $reasons += 'tmux-missing' }
    if (-not (Get-Value $Inventory 'wezterm_gui_available' $false)) { $reasons += 'wezterm-cli-gui-confusion' }
    if (Get-Value $Inventory 'nested_tmux' $false) { $reasons += 'nested-tmux-attempt' }
    return @($reasons | Select-Object -Unique)
}

function Get-ManagedIncludeBlock {
    @"
$managedStart
local sas_workspace = dofile((os.getenv('USERPROFILE') or os.getenv('HOME')) .. '/.wezterm-sysadminsuite.lua')
sas_workspace(config)
$managedEnd
"@
}

function Get-UpdatedUserLua {
    param([string]$Content)
    $block = Get-ManagedIncludeBlock
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return "local wezterm = require 'wezterm'`nlocal config = wezterm.config_builder()`n`n$block`n`nreturn config`n"
    }
    if ($Content.Contains($managedStart) -and $Content.Contains($managedEnd)) {
        $pattern = '(?s)' + [regex]::Escape($managedStart) + '.*?' + [regex]::Escape($managedEnd)
        return [regex]::Replace($Content, $pattern, $block)
    }
    $returnMatch = [regex]::Match($Content, '(?m)^\s*return\s+config\s*$')
    if (-not $returnMatch.Success) { throw 'invalid-lua: existing config must expose a final return config for bounded managed insertion' }
    return $Content.Insert($returnMatch.Index, "$block`n`n")
}

function Save-FixtureState {
    param($Inventory, [hashtable]$Changes)
    $state = @{}
    $existing = Read-JsonFile -Path $statePath
    if ($existing) { foreach ($property in $existing.PSObject.Properties) { $state[$property.Name] = $property.Value } }
    foreach ($name in @('keepalive_running', 'keepalive_stale', 'keepalive_pid', 'session_exists', 'shortcut_exists', 'config_applied', 'gui_launched')) {
        if (-not $state.ContainsKey($name)) { $state[$name] = Get-Value $Inventory $name $false }
    }
    foreach ($key in $Changes.Keys) { $state[$key] = $Changes[$key] }
    Write-JsonFile -Path $statePath -Value $state
}

function Apply-Configuration {
    param($Inventory)
    if (-not (Test-Path -LiteralPath $templatePath)) { throw "Template missing: $templatePath" }
    New-Item -ItemType Directory -Path $UserConfigDir -Force | Out-Null
    New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
    $userExisted = Test-Path -LiteralPath $userLuaPath
    $sasExisted = Test-Path -LiteralPath $sasLuaPath
    $existing = if ($userExisted) { Get-Content -Raw -LiteralPath $userLuaPath } else { '' }
    $priorManifest = Read-JsonFile -Path $manifestPath
    $alreadyManaged = $userExisted -and $sasExisted -and $existing.Contains($managedStart) -and $existing.Contains($managedEnd)
    if (-not ($priorManifest -and $priorManifest.schema_version -eq 'sas-windows-tmux-workspace-backup/v1' -and $alreadyManaged)) {
        $backupRoot = Join-Path $StateRoot ('backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        $userBackup = Join-Path $backupRoot 'wezterm.lua'
        $sasBackup = Join-Path $backupRoot 'wezterm-sysadminsuite.lua'
        if ($userExisted) { Copy-Item -LiteralPath $userLuaPath -Destination $userBackup }
        if ($sasExisted) { Copy-Item -LiteralPath $sasLuaPath -Destination $sasBackup }
        $manifest = [pscustomobject]@{
            schema_version = 'sas-windows-tmux-workspace-backup/v1'
            user_lua = [pscustomobject]@{ path = $userLuaPath; existed = $userExisted; backup = $userBackup }
            sas_lua = [pscustomobject]@{ path = $sasLuaPath; existed = $sasExisted; backup = $sasBackup }
            shortcut = [pscustomobject]@{ path = $shortcutPath; existed = (Test-Path -LiteralPath $shortcutPath) }
        }
        Write-JsonFile -Path $manifestPath -Value $manifest
    }
    if (Get-Value $Inventory 'apply_failure' $false) { throw 'fixture apply failure after backup' }
    if (Get-Value $Inventory 'malformed_config' $false) { $existing = 'return {' }
    $updated = Get-UpdatedUserLua -Content $existing
    $rendered = (Get-Content -Raw -LiteralPath $templatePath).Replace('@DISTRO@', [string](Get-Value $Inventory 'distro')).Replace('@SESSION@', $sessionName)
    [System.IO.File]::WriteAllText($sasLuaPath, $rendered, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($userLuaPath, $updated, [System.Text.UTF8Encoding]::new($false))
    New-Item -ItemType Directory -Path $desktopRoot -Force | Out-Null
    if ($FixturePath) {
        Save-FixtureState -Inventory $Inventory -Changes @{ config_applied = $true; shortcut_exists = $true }
    } else {
        $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if (-not $pwsh) { $pwsh = Get-Command powershell.exe -ErrorAction Stop }
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $pwsh.Source
        # Activating the generated shortcut is the explicit Start intent; do
        # not strand a hidden process on a confirmation prompt.
        $shortcut.Arguments = '-NoProfile -WindowStyle Hidden -File "{0}" -LaunchGui -Confirm:$false' -f (Join-Path $repoRoot 'scripts\Start-SasWindowsTmuxWorkspace.ps1')
        $shortcut.WorkingDirectory = $repoRoot
        $shortcut.Description = 'SysAdminSuite WezTerm tmux workspace'
        $shortcut.Save()
    }
}

function Start-Workspace {
    param($Inventory)
    if ($FixturePath) {
        Save-FixtureState -Inventory $Inventory -Changes @{ keepalive_running = $true; keepalive_stale = $false; keepalive_pid = 4242; session_exists = $true; gui_launched = [bool]$LaunchGui }
        return
    }
    New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
    $pidPath = Join-Path $StateRoot 'wsl-keepalive.pid'
    $keepalive = Get-ExactOwnedKeepalive -PidPath $pidPath -Distro $Inventory.distro
    if (-not $keepalive.running) {
        # ProcessStartInfo.ArgumentList preserves the keepalive command as one
        # bash -lc argument. Start-Process flattens the array and makes WSL exit.
        $process = Start-OwnedKeepaliveProcess -Distro $Inventory.distro
        [System.IO.File]::WriteAllText($pidPath, [string]$process.Id, [System.Text.Encoding]::ASCII)
        $deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
        do {
            Start-Sleep -Milliseconds 200
            $keepalive = Get-ExactOwnedKeepalive -PidPath $pidPath -Distro $Inventory.distro
        } until ($keepalive.running -or (Get-Date) -ge $deadline)
        if (-not $keepalive.running) { throw 'operation-timeout: keepalive did not reach an owned running state' }
    }
    & wsl.exe -d $Inventory.distro -- tmux has-session -t $sessionName 2>$null
    if ($LASTEXITCODE -ne 0) { & wsl.exe -d $Inventory.distro --exec bash -lc 'export PATH="$HOME/.local/agent-switchboard/bin:$PATH"; exec tmux new-session -d -s dev' }
    if ($LASTEXITCODE -ne 0) { throw 'tmux-socket-missing: could not create dev session' }
    & wsl.exe -d $Inventory.distro --exec bash -lc 'tmux set-environment -g PATH "$HOME/.local/agent-switchboard/bin:$PATH"'
    if ($LASTEXITCODE -ne 0) { throw 'tmux-socket-missing: could not update the dev session agent PATH' }
    $guiProcess = if ($LaunchGui) { Start-IndependentWezTermGui -GuiPath $Inventory.wezterm_gui_path } else { $null }
    Write-JsonFile -Path $statePath -Value ([pscustomobject]@{ distro = $Inventory.distro; keepalive_pid = $keepalive.pid; session_name = $sessionName; gui_launcher = $Inventory.wezterm_gui_path; gui_pid = $(if ($guiProcess) { $guiProcess.Id } else { $null }) })
}

function Stop-Workspace {
    param($Inventory)
    if ($FixturePath) {
        Save-FixtureState -Inventory $Inventory -Changes @{ keepalive_running = $false; keepalive_stale = $false; session_exists = $false; gui_launched = $false }
        return
    }
    if ($Inventory.session_exists) { & wsl.exe -d $Inventory.distro -- tmux kill-session -t $sessionName }
    $pidPath = Join-Path $StateRoot 'wsl-keepalive.pid'
    $keepalive = Get-ExactOwnedKeepalive -PidPath $pidPath -Distro $Inventory.distro
    if ($keepalive.running) { Stop-Process -Id $keepalive.pid -ErrorAction Stop }
    if (Test-Path -LiteralPath $pidPath) { Remove-Item -LiteralPath $pidPath -Force }
}

function Restore-Configuration {
    $manifest = Read-JsonFile -Path $manifestPath
    if (-not $manifest) { throw 'rollback-required: backup manifest is absent' }
    foreach ($entry in @($manifest.user_lua, $manifest.sas_lua)) {
        if ($entry.existed) { Copy-Item -LiteralPath $entry.backup -Destination $entry.path -Force }
        elseif (Test-Path -LiteralPath $entry.path) { Remove-Item -LiteralPath $entry.path -Force }
    }
    if (-not $manifest.shortcut.existed -and (Test-Path -LiteralPath $manifest.shortcut.path)) { Remove-Item -LiteralPath $manifest.shortcut.path -Force }
    if ($FixturePath) { Save-FixtureState -Inventory (Get-CurrentInventory) -Changes @{ config_applied = $false; shortcut_exists = [bool]$manifest.shortcut.existed } }
}

$inventory = Get-CurrentInventory
$blocking = @(Get-BlockingReasons -Inventory $inventory)
$fixture = [bool]$FixturePath
$liveData = -not $fixture

try {
    switch ($Action) {
        'Plan' {
            $outcome = if ($blocking.Count) { 'action-required' } else { 'success' }
            $state = if ($blocking.Count) { 'action-required' } else { 'planned' }
            return New-LifecycleResult -Operation 'plan' -Outcome $outcome -State $state -Reasons $blocking -Message "Plan: distro=$($inventory.distro); tmux=$($inventory.tmux_version); wezterm-gui=$($inventory.wezterm_gui_path); session=$($inventory.session_exists)." -Artifacts @(New-Artifact 'plan' $fixture $liveData)
        }
        'Status' {
            $reasons = @($blocking)
            if (Get-Value $inventory 'keepalive_stale' $false) { $reasons += 'keepalive-stale' }
            elseif (-not (Get-Value $inventory 'keepalive_running' $false)) { $reasons += 'keepalive-missing' }
            if (-not (Get-Value $inventory 'session_exists' $false)) { $reasons += 'tmux-socket-missing' }
            $healthy = -not $reasons.Count -and (Get-Value $inventory 'session_exists' $false)
            return New-LifecycleResult -Operation 'status' -Outcome $(if ($healthy) { 'success' } else { 'action-required' }) -State $(if ($healthy) { 'session-running' } else { 'action-required' }) -Reasons @($reasons | Select-Object -Unique) -Message "Status: keepalive=$((Get-Value $inventory 'keepalive_running' $false)); session=$((Get-Value $inventory 'session_exists' $false)); shortcut=$((Get-Value $inventory 'shortcut_exists' $false))." -Artifacts @(New-Artifact 'backend-status' $fixture $liveData; New-Artifact 'tmux-status' $fixture $liveData)
        }
        'Apply' {
            if (-not $AllowTargetMutation) { return New-LifecycleResult -Operation 'configure' -Outcome 'action-required' -State 'action-required' -Reasons @('rollback-required') -Message 'Apply requires -AllowTargetMutation.' }
            if ($blocking.Count) { return New-LifecycleResult -Operation 'configure' -Outcome 'action-required' -State 'action-required' -Reasons $blocking -Message 'Required Windows/WSL prerequisites are unavailable.' }
            if ($PSCmdlet.ShouldProcess($UserConfigDir, 'Apply bounded WezTerm configuration and managed shortcut')) { Apply-Configuration -Inventory $inventory }
            return New-LifecycleResult -Operation 'configure' -Outcome 'success' -State 'configured' -Reasons @('none') -Message 'Managed Lua include, service configuration, backup manifest, and shortcut are configured.' -Artifacts @(New-Artifact 'config-backup-manifest' $fixture $liveData; New-Artifact 'lua-validation' $fixture $liveData; New-Artifact 'launcher-result' $fixture $liveData) -ConfigApplied $true
        }
        'Start' {
            if ($blocking.Count) { return New-LifecycleResult -Operation 'start' -Outcome 'action-required' -State 'action-required' -Reasons $blocking -Message 'Workspace start is blocked by missing prerequisites.' }
            if ($PSCmdlet.ShouldProcess($sessionName, 'Start owned WSL keepalive, ensure tmux session, and optionally launch GUI')) { Start-Workspace -Inventory $inventory }
            return New-LifecycleResult -Operation 'start' -Outcome 'success' -State $(if ($LaunchGui) { 'gui-launched' } else { 'session-running' }) -Reasons @('none') -Message "Owned keepalive and tmux session '$sessionName' are running; GUI launch=$([bool]$LaunchGui)." -Artifacts @(New-Artifact 'backend-status' $fixture $liveData; New-Artifact 'tmux-status' $fixture $liveData; New-Artifact 'launcher-result' $fixture $liveData) -LauncherStarted ([bool]$LaunchGui)
        }
        'Stop' {
            if (-not (Get-Value $inventory 'distro')) { return New-LifecycleResult -Operation 'stop' -Outcome 'action-required' -State 'action-required' -Reasons @('no-wsl-distro') -Message 'No owned WSL workspace can be stopped.' }
            if ($PSCmdlet.ShouldProcess($sessionName, 'Stop exact tmux session and exact owned keepalive PID')) { Stop-Workspace -Inventory $inventory }
            return New-LifecycleResult -Operation 'stop' -Outcome 'success' -State 'stopped' -Reasons @('none') -Message "Stopped tmux session '$sessionName' and the exact owned keepalive process." -Artifacts @(New-Artifact 'backend-status' $fixture $liveData; New-Artifact 'tmux-status' $fixture $liveData)
        }
        'Repair' {
            if (-not $AllowTargetMutation) { return New-LifecycleResult -Operation 'configure' -Outcome 'action-required' -State 'action-required' -Reasons @('rollback-required') -Message 'Repair requires -AllowTargetMutation.' }
            if ($blocking.Count) { return New-LifecycleResult -Operation 'configure' -Outcome 'action-required' -State 'action-required' -Reasons $blocking -Message 'Repair is blocked by missing prerequisites.' }
            if ($PSCmdlet.ShouldProcess($UserConfigDir, 'Repair configuration and restart workspace')) { Apply-Configuration -Inventory $inventory; Start-Workspace -Inventory (Get-CurrentInventory) }
            return New-LifecycleResult -Operation 'configure' -Outcome 'success' -State 'session-running' -Reasons @('none') -Message 'Configuration, shortcut, owned keepalive, and tmux session were repaired.' -Artifacts @(New-Artifact 'config-backup-manifest' $fixture $liveData; New-Artifact 'backend-status' $fixture $liveData) -ConfigApplied $true
        }
        'Rollback' {
            if (-not $AllowTargetMutation) { return New-LifecycleResult -Operation 'rollback' -Outcome 'action-required' -State 'action-required' -Reasons @('rollback-required') -Message 'Rollback requires -AllowTargetMutation.' }
            if ($PSCmdlet.ShouldProcess($UserConfigDir, 'Restore files from the managed backup manifest')) { Restore-Configuration }
            return New-LifecycleResult -Operation 'rollback' -Outcome 'success' -State 'stopped' -Reasons @('none') -Message 'Tracked configuration and shortcut ownership were restored from the backup manifest.' -Artifacts @(New-Artifact 'rollback-result' $fixture $liveData)
        }
    }
} catch {
    $reason = if ($_.Exception.Message -match 'invalid-lua') { 'invalid-lua' } elseif ($_.Exception.Message -match 'timeout') { 'operation-timeout' } elseif ($_.Exception.Message -match 'tmux') { 'tmux-socket-missing' } else { 'rollback-required' }
    return New-LifecycleResult -Operation $(if ($Action -eq 'Rollback') { 'rollback' } elseif ($Action -in @('Apply', 'Repair')) { 'configure' } else { $Action.ToLowerInvariant() }) -Outcome 'failure' -State 'failed' -Reasons @($reason) -Message $_.Exception.Message -Artifacts @(New-Artifact 'rollback-result' $fixture $liveData)
}
