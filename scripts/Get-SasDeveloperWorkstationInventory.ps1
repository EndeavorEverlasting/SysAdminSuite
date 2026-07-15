#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$LifecycleOutputPath,
    [ValidateSet('', 'no-wsl', 'docker-only-wsl', 'wsl-stops', 'keepalive-healthy', 'keepalive-stale', 'tmux-session-healthy', 'windows-bridge-only', 'wsl-native-agent', 'invalid-font', 'cli-gui-mismatch')]
    [string]$Fixture = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-CommandState {
    param([string[]]$Names, [string[]]$VersionArguments = @('--version'))
    $command = $null
    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { break }
    }
    if (-not $command) {
        return [ordered]@{ present = $false; version = $null; path_class = 'missing' }
    }
    $version = $null
    try {
        $version = (& $command.Source @VersionArguments 2>$null | Select-Object -First 1).ToString().Trim()
        if (-not $version) { $version = $null }
    } catch { $version = $null }
    $pathClass = if ($command.Source -match 'WindowsApps|Users') { 'user-path' } else { 'system-path' }
    return [ordered]@{ present = $true; version = $version; path_class = $pathClass }
}

function New-AgentState {
    param([string]$AgentId)
    $command = Get-Command $AgentId -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        return [ordered]@{
            agent_id = $AgentId; resolution_kind = 'missing'; backend = 'missing';
            command_path_class = 'missing'; version = $null; authentication_readiness = 'unknown';
            interactive_smoke = [ordered]@{ attempted = $false; status = 'not-attempted' }
        }
    }
    $kind = switch -Regex ($command.CommandType.ToString()) {
        'Alias' { 'alias'; break }
        'Function' { 'function'; break }
        'ExternalScript' { 'wrapper'; break }
        default { 'executable' }
    }
    $pathClass = if ($kind -in @('alias', 'function')) { 'alias-only' }
        elseif ($command.Source -match '\.cmd$|\.exe$') { 'system-path' }
        elseif ($command.Source -match 'Users') { 'user-path' }
        else { 'system-path' }
    return [ordered]@{
        agent_id = $AgentId; resolution_kind = $kind; backend = 'native';
        command_path_class = $pathClass; version = $null; authentication_readiness = 'unknown';
        interactive_smoke = [ordered]@{ attempted = $false; status = 'not-attempted' }
    }
}

function New-MissingAgentStates {
    return @('opencode', 'agy', 'goose') | ForEach-Object {
        [ordered]@{
            agent_id = $_; resolution_kind = 'missing'; backend = 'missing'; command_path_class = 'missing';
            version = $null; authentication_readiness = 'unknown';
            interactive_smoke = [ordered]@{ attempted = $false; status = 'not-attempted' }
        }
    }
}

function New-TmuxState {
    param([bool]$Present = $false, [string]$Version = $null, [string]$Socket = 'unknown', [string[]]$Sessions = @(), [bool]$Inside = $false)
    return [ordered]@{ present = $Present; version = $Version; server_socket = $Socket; sessions = @($Sessions); inside_tmux = $Inside }
}

function New-FixtureInventory {
    param([string]$Scenario)
    $missing = New-MissingAgentStates
    $windows = [ordered]@{
        id = 'windows-native'; available = $true; health = 'healthy'; shell = 'pwsh';
        backend = [ordered]@{ kind = 'windows-native'; distribution = $null; distribution_state = 'not-applicable'; docker_only = $false; tmux = New-TmuxState -Socket 'not-applicable' };
        agents = $missing
    }
    $wsl = [ordered]@{
        id = 'windows-wsl'; available = $true; health = 'healthy'; shell = 'bash';
        backend = [ordered]@{ kind = 'wsl'; distribution = 'Ubuntu'; distribution_state = 'running'; docker_only = $false; tmux = New-TmuxState -Present $true -Version 'tmux 3.6' -Socket 'present' -Sessions @('dev') };
        agents = New-MissingAgentStates
    }
    $inventory = [ordered]@{
        schema_version = 'sas-developer-workstation-inventory/v2'; generated_at = '2026-07-15T00:00:00Z';
        host_platform = 'windows'; detected_context = 'windows-native';
        terminal = [ordered]@{
            wezterm_cli = [ordered]@{ present = $true; version = 'fixture'; path_class = 'system-path' };
            wezterm_gui = [ordered]@{ present = $true; version = 'fixture'; path_class = 'system-path' };
            config_path_class = 'user-home'; default_workspace = [ordered]@{ configured = $true; name = 'tmux: Development' };
            font = [ordered]@{ configured_name = $null; availability = 'not-configured' }
        };
        domains = @($windows, $wsl);
        workspace_service = [ordered]@{ keepalive = 'healthy'; pid_file = 'healthy'; shortcut = 'present'; start_script = 'present'; stop_script = 'present' };
        selected_backend = 'windows-wsl';
        lifecycle = [ordered]@{ outcome = 'success'; state = 'session-running'; reason_codes = @('none') };
        proof_ceiling = 'Read-only inventory proves detected state only; command presence is not authentication, session presence is not persistence, and no interactive smoke was attempted.'
    }
    switch ($Scenario) {
        'no-wsl' {
            $wsl.available = $false; $wsl.health = 'unavailable'; $wsl.backend.distribution = $null; $wsl.backend.distribution_state = 'unknown'; $wsl.backend.tmux = New-TmuxState
            $inventory.selected_backend = $null; $inventory.lifecycle = [ordered]@{ outcome = 'action-required'; state = 'absent'; reason_codes = @('no-wsl-distro') }
        }
        'docker-only-wsl' {
            $wsl.available = $false; $wsl.health = 'unavailable'; $wsl.backend.distribution = 'docker-desktop'; $wsl.backend.docker_only = $true; $wsl.backend.tmux = New-TmuxState
            $inventory.selected_backend = $null; $inventory.lifecycle = [ordered]@{ outcome = 'action-required'; state = 'absent'; reason_codes = @('docker-only-distro') }
        }
        'wsl-stops' {
            $wsl.health = 'degraded'; $wsl.backend.distribution_state = 'stopped'; $wsl.backend.tmux = New-TmuxState
            $inventory.lifecycle = [ordered]@{ outcome = 'partial'; state = 'installed'; reason_codes = @('wsl-stopped') }
        }
        'keepalive-stale' {
            $inventory.workspace_service.keepalive = 'stale'; $inventory.workspace_service.pid_file = 'stale'
            $inventory.lifecycle = [ordered]@{ outcome = 'partial'; state = 'session-running'; reason_codes = @('keepalive-stale') }
        }
        'windows-bridge-only' {
            $wsl.agents[0] = [ordered]@{ agent_id = 'opencode'; resolution_kind = 'wrapper'; backend = 'bridge'; command_path_class = 'windows-interop'; version = 'fixture'; authentication_readiness = 'unknown'; interactive_smoke = [ordered]@{ attempted = $false; status = 'not-attempted' } }
            $inventory.lifecycle = [ordered]@{ outcome = 'partial'; state = 'session-running'; reason_codes = @('windows-only-agent-bridge') }
        }
        'wsl-native-agent' {
            $wsl.agents[0] = [ordered]@{ agent_id = 'opencode'; resolution_kind = 'executable'; backend = 'native'; command_path_class = 'system-path'; version = 'fixture'; authentication_readiness = 'unknown'; interactive_smoke = [ordered]@{ attempted = $false; status = 'not-attempted' } }
        }
        'invalid-font' {
            $inventory.terminal.font = [ordered]@{ configured_name = 'JetBrainsMono Nerd Font'; availability = 'unavailable' }
            $inventory.lifecycle = [ordered]@{ outcome = 'partial'; state = 'session-running'; reason_codes = @('unavailable-font') }
        }
        'cli-gui-mismatch' {
            $inventory.terminal.wezterm_gui = [ordered]@{ present = $false; version = $null; path_class = 'missing' }
            $inventory.lifecycle = [ordered]@{ outcome = 'failure'; state = 'failed'; reason_codes = @('wezterm-cli-gui-confusion') }
        }
        default { }
    }
    return $inventory
}

function Get-LiveInventory {
    $cli = New-CommandState -Names @('wezterm.exe', 'wezterm')
    $gui = New-CommandState -Names @('wezterm-gui.exe') -VersionArguments @('--version')
    $configClass = 'missing'; $workspaceConfigured = $false; $fontName = $null; $fontAvailability = 'not-configured'
    $configPath = Join-Path $HOME '.wezterm.lua'
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $configClass = 'user-home'; $configText = Get-Content -LiteralPath $configPath -Raw -ErrorAction SilentlyContinue
        if ($configText -match 'tmux:\s*Development') { $workspaceConfigured = $true }
        if ($configText -match 'font\s*=.*?"([^"]+)"') { $fontName = $Matches[1]; $fontAvailability = 'unknown' }
    }

    $windowsAgents = @('opencode', 'agy', 'goose') | ForEach-Object { New-AgentState -AgentId $_ }
    $windowsDomain = [ordered]@{
        id = 'windows-native'; available = $true; health = 'healthy'; shell = 'pwsh';
        backend = [ordered]@{ kind = 'windows-native'; distribution = $null; distribution_state = 'not-applicable'; docker_only = $false; tmux = New-TmuxState -Socket 'not-applicable' };
        agents = $windowsAgents
    }

    $wslDomain = [ordered]@{
        id = 'windows-wsl'; available = $false; health = 'unavailable'; shell = 'bash';
        backend = [ordered]@{ kind = 'wsl'; distribution = $null; distribution_state = 'unknown'; docker_only = $false; tmux = New-TmuxState };
        agents = New-MissingAgentStates
    }
    $reasons = New-Object System.Collections.Generic.List[string]
    $wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($wslCommand) {
        $lines = @(& $wslCommand.Source --list --verbose 2>$null) | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ -and $_ -notmatch '^NAME\s+STATE' }
        $distros = foreach ($line in $lines) {
            if ($line -match '^\*?\s*(.+?)\s{2,}(Running|Stopped)\s+\d+') { [pscustomobject]@{ Name = $Matches[1].Trim(); State = $Matches[2].ToLowerInvariant() } }
        }
        $nonDocker = @($distros | Where-Object { $_.Name -notmatch '^docker-desktop(?:-data)?$' })
        if ($nonDocker.Count -eq 0) {
            if (@($distros).Count -gt 0) { $wslDomain.backend.docker_only = $true; $reasons.Add('docker-only-distro') } else { $reasons.Add('no-wsl-distro') }
        } else {
            $selected = $nonDocker | Where-Object State -eq 'running' | Select-Object -First 1
            if (-not $selected) { $selected = $nonDocker | Select-Object -First 1 }
            $wslDomain.available = $true; $wslDomain.backend.distribution = $selected.Name; $wslDomain.backend.distribution_state = $selected.State
            if ($selected.State -eq 'running') {
                $tmuxVersion = (& $wslCommand.Source -d $selected.Name -- bash -lc 'command -v tmux >/dev/null 2>&1 && tmux -V || true' 2>$null | Select-Object -First 1)
                $sessions = @(& $wslCommand.Source -d $selected.Name -- bash -lc "tmux list-sessions -F '#S' 2>/dev/null || true" 2>$null) | Where-Object { $_ }
                $wslDomain.backend.tmux = New-TmuxState -Present ([bool]$tmuxVersion) -Version $tmuxVersion -Socket $(if ($sessions.Count) { 'present' } else { 'missing' }) -Sessions $sessions
                $wslDomain.health = if ($tmuxVersion) { 'healthy' } else { 'degraded' }
                if (-not $tmuxVersion) { $reasons.Add('tmux-missing') }
            } else {
                $wslDomain.health = 'degraded'; $reasons.Add('wsl-stopped')
            }
        }
    } else { $reasons.Add('no-wsl-distro') }

    $toolsRoot = Join-Path $HOME 'SysAdminTools'; $pidPath = Join-Path $toolsRoot 'state/wsl-keepalive.pid'
    $pidState = 'missing'; $keepaliveState = 'missing'
    if (Test-Path -LiteralPath $pidPath -PathType Leaf) {
        $savedPid = 0; [void][int]::TryParse((Get-Content -LiteralPath $pidPath -Raw).Trim(), [ref]$savedPid)
        if ($savedPid -gt 0 -and (Get-Process -Id $savedPid -ErrorAction SilentlyContinue)) { $pidState = 'healthy'; $keepaliveState = 'healthy' }
        else { $pidState = 'stale'; $keepaliveState = 'stale'; $reasons.Add('keepalive-stale') }
    } elseif ($wslDomain.available) { $reasons.Add('keepalive-missing') }
    $desktop = [Environment]::GetFolderPath('Desktop')
    $service = [ordered]@{
        keepalive = $keepaliveState; pid_file = $pidState;
        shortcut = $(if (Test-Path -LiteralPath (Join-Path $desktop 'WezTerm tmux.lnk')) { 'present' } else { 'missing' });
        start_script = $(if (Test-Path -LiteralPath (Join-Path $toolsRoot 'Start-WezTermTmux.ps1')) { 'present' } else { 'missing' });
        stop_script = $(if (Test-Path -LiteralPath (Join-Path $toolsRoot 'Stop-WezTermTmux.ps1')) { 'present' } else { 'missing' })
    }
    if ($cli.present -and -not $gui.present) { $reasons.Add('wezterm-cli-gui-confusion') }
    if ($fontAvailability -eq 'unavailable') { $reasons.Add('unavailable-font') }
    $uniqueReasons = @($reasons | Select-Object -Unique)
    $selectedBackend = if ($wslDomain.available) { 'windows-wsl' } else { $null }
    $outcome = if (-not $selectedBackend -or $uniqueReasons -contains 'wezterm-cli-gui-confusion') { 'action-required' } elseif ($uniqueReasons.Count) { 'partial' } else { 'success' }
    $state = if (-not $selectedBackend) { 'absent' } elseif ($wslDomain.backend.tmux.sessions -contains 'dev') { 'session-running' } elseif ($wslDomain.backend.tmux.present) { 'tmux-available' } else { 'installed' }
    return [ordered]@{
        schema_version = 'sas-developer-workstation-inventory/v2'; generated_at = (Get-Date).ToUniversalTime().ToString('o');
        host_platform = 'windows'; detected_context = 'windows-native';
        terminal = [ordered]@{ wezterm_cli = $cli; wezterm_gui = $gui; config_path_class = $configClass; default_workspace = [ordered]@{ configured = $workspaceConfigured; name = $(if ($workspaceConfigured) { 'tmux: Development' } else { $null }) }; font = [ordered]@{ configured_name = $fontName; availability = $fontAvailability } };
        domains = @($windowsDomain, $wslDomain); workspace_service = $service; selected_backend = $selectedBackend;
        lifecycle = [ordered]@{ outcome = $outcome; state = $state; reason_codes = $(if ($uniqueReasons.Count) { $uniqueReasons } else { @('none') }) };
        proof_ceiling = 'Read-only inventory proves detected state only; command presence is not authentication, session presence is not persistence, and no interactive smoke was attempted.'
    }
}

$inventory = if ($Fixture) { New-FixtureInventory -Scenario $Fixture } else { Get-LiveInventory }
$json = $inventory | ConvertTo-Json -Depth 12
if ($OutputPath) {
    $parent = Split-Path -Parent $OutputPath; if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8
} else { $json }

if ($LifecycleOutputPath) {
    $lifecycleResult = [ordered]@{
        schema_version = 'sas-developer-workstation-lifecycle-result/v1'; workflow_id = 'developer-workstation'; run_id = $(if ($Fixture) { "fixture-$Fixture" } else { "inventory-$((Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))" });
        operation = 'inventory'; outcome = $inventory.lifecycle.outcome; lifecycle_state = $inventory.lifecycle.state; reason_codes = $inventory.lifecycle.reason_codes;
        message = 'Read-only developer workstation inventory completed.';
        artifacts = @([ordered]@{ role = 'inventory'; path_class = $(if ($Fixture) { 'temporary-fixture' } else { 'repo-ignored-run' }); tracked = $false; contains_live_data = (-not [bool]$Fixture) });
        proof = [ordered]@{ install_completed = $false; config_applied = $false; launcher_started = $false; tmux_attached = $false; command_acknowledged = $false; behavior_observed = $false; persistence_observed = $false; live_runtime = $false; operator_accepted = $false }
    }
    $parent = Split-Path -Parent $LifecycleOutputPath; if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $lifecycleResult | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $LifecycleOutputPath -Encoding UTF8
}
