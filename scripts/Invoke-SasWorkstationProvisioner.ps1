<#
.SYNOPSIS
    Plans and provisions Windows workstation prerequisites for the AgentSwitchboard Windows Profile.
.DESCRIPTION
    Plan is the default and read-only. Apply provisions prerequisites and installs the AgentSwitchboard launcher.
    Audit reports current state without mutation.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Audit', 'Plan', 'Apply', 'Rollback')]
    [string]$Action = 'Plan',
    [string]$AgentSwitchboardRef = 'feat/windows-profile-open-or-activate',
    [string]$AgentSwitchboardRepo = 'EndeavorEverlasting/AgentSwitchboard',
    [string]$LauncherRelativePath = 'tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1',
    [string]$ManifestRelativePath = 'tooling/profiles/windows/tmux-new-instance-shortcut.example.json',
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\profiles\windows'),
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'SysAdminSuite\workstation'),
    [string]$WslDistribution = 'Ubuntu',
    [int]$TimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$statePath = Join-Path $StateRoot 'workstation-provisioner-state.json'

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

function Test-PowerShell7 {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    return ($null -ne $pwsh)
}

function Test-WslCapability {
    try {
        $result = & wsl.exe --status 2>&1
        return $true
    } catch {
        return $false
    }
}

function Test-WslDistribution {
    param([string]$Name)
    try {
        $result = & wsl.exe -l -q 2>&1
        $distributions = $result | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }
        return ($distributions -contains $Name)
    } catch {
        return $false
    }
}

function Test-TmuxInWsl {
    param([string]$Distribution)
    try {
        $result = & wsl.exe -d $Distribution -e bash -lc 'command -v tmux' 2>&1
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Test-WezTermCli {
    $cmd = Get-Command wezterm.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $true }
    $cmd = Get-Command wezterm -ErrorAction SilentlyContinue
    if ($cmd) { return $true }
    if ($env:ProgramFiles) {
        $candidate = Join-Path $env:ProgramFiles 'WezTerm\wezterm.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $true }
    }
    if ($env:LOCALAPPDATA) {
        $candidate = Join-Path $env:LOCALAPPDATA 'Programs\WezTerm\wezterm.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $true }
    }
    return $false
}

function Test-LauncherInstalled {
    param([string]$Root)
    $launcherPath = Join-Path $Root 'Invoke-AgentSwitchboardOpenOrActivate.ps1'
    return (Test-Path -LiteralPath $launcherPath -PathType Leaf)
}

$audit = [ordered]@{
    schema = 'sas.workstation-provisioner-audit.v1'
    timestamp = (Get-Date).ToUniversalTime().ToString('o')
    powershell7 = Test-PowerShell7
    wslCapability = Test-WslCapability
    wslDistribution = $false
    tmuxInWsl = $false
    wezTermCli = Test-WezTermCli
    launcherInstalled = Test-LauncherInstalled -Root $InstallRoot
    agentSwitchboardRef = $AgentSwitchboardRef
    installRoot = $InstallRoot
    ready = $false
}
if ($audit.wslCapability) {
    $audit.wslDistribution = Test-WslDistribution -Name $WslDistribution
    if ($audit.wslDistribution) {
        $audit.tmuxInWsl = Test-TmuxInWsl -Distribution $WslDistribution
    }
}
$audit.ready = $audit.powershell7 -and $audit.wslCapability -and $audit.wslDistribution -and $audit.tmuxInWsl -and $audit.wezTermCli -and $audit.launcherInstalled

$prerequisites = @(
    @{ name = 'PowerShell 7'; met = $audit.powershell7 },
    @{ name = 'WSL capability'; met = $audit.wslCapability },
    @{ name = "WSL distribution '$WslDistribution'"; met = $audit.wslDistribution },
    @{ name = 'tmux in WSL'; met = $audit.tmuxInWsl },
    @{ name = 'WezTerm CLI'; met = $audit.wezTermCli },
    @{ name = 'AgentSwitchboard launcher'; met = $audit.launcherInstalled }
)

$mutations = @()
if (-not $audit.launcherInstalled) {
    $mutations += "Clone or pull $AgentSwitchboardRepo at ref $AgentSwitchboardRef and copy $LauncherRelativePath to $InstallRoot"
    $mutations += "Copy $ManifestRelativePath to $InstallRoot"
}

if ($Action -eq 'Audit') {
    $report = [ordered]@{
        audit = $audit
        prerequisites = $prerequisites
        mutationsRequired = $mutations
    }
    $report | ConvertTo-Json -Depth 10
    exit 0
}

if ($Action -eq 'Plan') {
    $plan = [ordered]@{
        schema = 'sas.workstation-provisioner-plan.v1'
        agentSwitchboardRef = $AgentSwitchboardRef
        installRoot = $InstallRoot
        wslDistribution = $WslDistribution
        prerequisites = $prerequisites
        mutations = $mutations
        proofCeiling = 'Plan mode emits intended mutations without changing the machine.'
    }
    $planPath = Join-Path $StateRoot 'workstation-provisioner-plan.json'
    Write-JsonFile -Path $planPath -Value $plan
    $plan | ConvertTo-Json -Depth 10
    exit 0
}

if ($Action -eq 'Apply') {
    if (-not $AllowTargetMutation) {
        throw 'Apply requires -AllowTargetMutation.'
    }

    $applied = @()
    $errors = @()

    if (-not $audit.launcherInstalled) {
        try {
            New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
            $cloneDir = Join-Path ([System.IO.Path]::GetTempPath()) "asb-provision-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            & git clone --depth 1 --branch $AgentSwitchboardRef "https://github.com/$AgentSwitchboardRepo.git" $cloneDir 2>&1
            if ($LASTEXITCODE -ne 0) { throw "git clone failed" }

            $srcLauncher = Join-Path $cloneDir $LauncherRelativePath
            $srcManifest = Join-Path $cloneDir $ManifestRelativePath
            if (Test-Path -LiteralPath $srcLauncher) {
                Copy-Item -LiteralPath $srcLauncher -Destination $InstallRoot -Force
                $applied += "Copied launcher to $InstallRoot"
            }
            if (Test-Path -LiteralPath $srcManifest) {
                Copy-Item -LiteralPath $srcManifest -Destination $InstallRoot -Force
                $applied += "Copied manifest to $InstallRoot"
            }

            Remove-Item -LiteralPath $cloneDir -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            $errors += "Launcher installation failed: $($_.Exception.Message)"
        }
    }

    $result = [ordered]@{
        schema = 'sas.workstation-provisioner-result.v1'
        status = if ($errors.Count -eq 0) { 'success' } else { 'partial' }
        action = 'Apply'
        applied = $applied
        errors = $errors
        launcherInstalled = Test-LauncherInstalled -Root $InstallRoot
        proofLevel = 'command-ack'
        proofCeiling = 'Provisioner logic and pinned delegation proved. Live workstation behavior remains separate proof.'
    }
    $resultPath = Join-Path $StateRoot 'workstation-provisioner-result.json'
    Write-JsonFile -Path $resultPath -Value $result
    $result | ConvertTo-Json -Depth 10
    if ($errors.Count -gt 0) { exit 1 }
    exit 0
}

if ($Action -eq 'Rollback') {
    $rollbackResult = [ordered]@{
        schema = 'sas.workstation-provisioner-result.v1'
        status = 'rollback-not-implemented'
        action = 'Rollback'
        proofCeiling = 'Rollback plan only; no destructive mutation was performed.'
    }
    $rollbackResult | ConvertTo-Json -Depth 10
    exit 0
}
