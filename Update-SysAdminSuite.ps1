<#
.SYNOPSIS
    Field-facing SysAdminSuite repair/update entrypoint with stage progress.

.DESCRIPTION
    Makes a field install path match the official SysAdminSuite main branch.
    This is the explicit repair lane for techs who need a clean official copy.
    It is separate from tools/update/Invoke-SysAdminSuiteUpdate.ps1, which keeps
    the dashboard launcher's safe approved fast-forward update behavior.

    Git network operations stream their own output. The progress display is
    stage-based so it does not pretend to know byte-level clone/fetch progress.
#>
[CmdletBinding()]
param(
    [string]$RepoUrl = 'https://github.com/EndeavorEverlasting/SysAdminSuite.git',
    [string]$InstallRoot = (Join-Path $env:USERPROFILE 'Desktop\SysAdminSuite'),
    [switch]$NoLaunch,
    [switch]$SkipConfirm
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Activity = 'SysAdminSuite Update'
$script:InstallRootWasExplicit = $PSBoundParameters.ContainsKey('InstallRoot')
$script:ProgressHelper = Join-Path $PSScriptRoot 'tools\update\Show-SysAdminSuiteProgress.ps1'
if (-not (Test-Path -LiteralPath $script:ProgressHelper)) {
    throw "Missing progress helper: $script:ProgressHelper"
}
. $script:ProgressHelper

function Resolve-FullPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-SafeInstallRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [bool]$ExplicitInstallRoot
    )

    $full = Resolve-FullPath -Path $Path
    $root = [System.IO.Path]::GetPathRoot($full)
    $leaf = Split-Path -Leaf $full

    if ($full.TrimEnd('\') -eq $root.TrimEnd('\')) {
        throw "Refusing to update a drive root: $full"
    }

    foreach ($blocked in @($env:USERPROFILE, $env:WINDIR)) {
        if ($blocked) {
            $blockedFull = Resolve-FullPath -Path $blocked
            if ($full.TrimEnd('\') -ieq $blockedFull.TrimEnd('\')) {
                throw "Refusing to update protected folder: $full"
            }
        }
    }

    if ((-not $ExplicitInstallRoot) -and ($leaf -ne 'SysAdminSuite')) {
        throw "Default install path must end in SysAdminSuite: $full"
    }

    if ([string]::IsNullOrWhiteSpace($leaf)) {
        throw "Install path must name a SysAdminSuite folder: $full"
    }

    return $full
}

function Confirm-RepairIntent {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if ($SkipConfirm) {
        Write-Host "Confirmation skipped by -SkipConfirm."
        return
    }

    Write-Host ''
    Write-Host 'This updater makes the local SysAdminSuite folder match official origin/main.' -ForegroundColor Yellow
    Write-Host 'Local edits and untracked files inside that repo can be discarded by reset --hard and clean -fd.' -ForegroundColor Yellow
    Write-Host "Target: $Path"
    $answer = Read-Host 'Continue? Type YES to update'
    if ($answer -ne 'YES') {
        throw 'Update cancelled by user.'
    }
}

function Invoke-UpdateGit {
    [CmdletBinding()]
    param(
        [string]$Root,
        [string[]]$Arguments,
        [string]$FailureMessage
    )

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git is not available on PATH. Install Git for Windows or use the packaged dashboard field release.'
    }

    if ($Root) {
        & git -C $Root @Arguments
    } else {
        & git @Arguments
    }

    if ($LASTEXITCODE -ne 0) {
        throw $FailureMessage
    }
}

function Invoke-CloneInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$Url
    )

    $parent = Split-Path -Parent $TargetPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Invoke-UpdateGit -Arguments @('clone', $Url, $TargetPath) -FailureMessage 'Git clone failed.'
}

function Invoke-BackupNonGitFolder {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TargetPath)

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = "$TargetPath.old.$timestamp"
    Rename-Item -LiteralPath $TargetPath -NewName (Split-Path -Leaf $backupPath)
    return $backupPath
}

function Start-SysAdminSuiteDashboard {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TargetPath)

    $dashboard = Join-Path $TargetPath 'START-HERE-SysAdminSuite-Dashboard.bat'
    if (Test-Path -LiteralPath $dashboard) {
        Write-Host 'Launching dashboard...'
        Start-Process -FilePath $dashboard
        return
    }

    Write-Host "Dashboard launcher not found: $dashboard" -ForegroundColor Yellow
}

function Invoke-FieldUpdate {
    [CmdletBinding()]
    param()

    $target = Assert-SafeInstallRoot -Path $InstallRoot -ExplicitInstallRoot:$script:InstallRootWasExplicit
    if ($RepoUrl -ne 'https://github.com/EndeavorEverlasting/SysAdminSuite.git') {
        Write-Host "Using custom repository URL: $RepoUrl" -ForegroundColor Yellow
    }
    Confirm-RepairIntent -Path $target

    $exists = Test-Path -LiteralPath $target
    $isGitRepo = $exists -and (Test-Path -LiteralPath (Join-Path $target '.git'))
    $baseSteps = if ($isGitRepo) { 6 } else { 3 }
    $totalSteps = if ($NoLaunch) { $baseSteps } else { $baseSteps + 1 }

    Show-SysAdminSuiteStep -Step 1 -Total $totalSteps -Activity $script:Activity -Status 'Locate existing SysAdminSuite install'

    if (-not $exists) {
        Show-SysAdminSuiteStep -Step 2 -Total $totalSteps -Activity $script:Activity -Status 'No existing folder found'
        Show-SysAdminSuiteStep -Step 3 -Total $totalSteps -Activity $script:Activity -Status 'Clone official SysAdminSuite copy'
        Invoke-CloneInstall -TargetPath $target -Url $RepoUrl
    } elseif ($isGitRepo) {
        Show-SysAdminSuiteStep -Step 2 -Total $totalSteps -Activity $script:Activity -Status 'Existing Git repo found'
        Show-SysAdminSuiteStep -Step 3 -Total $totalSteps -Activity $script:Activity -Status 'Fetch latest official version'
        Invoke-UpdateGit -Root $target -Arguments @('fetch', 'origin') -FailureMessage 'Git fetch failed.'
        Show-SysAdminSuiteStep -Step 4 -Total $totalSteps -Activity $script:Activity -Status 'Switch to main'
        Invoke-UpdateGit -Root $target -Arguments @('checkout', 'main') -FailureMessage 'Git checkout main failed.'
        Show-SysAdminSuiteStep -Step 5 -Total $totalSteps -Activity $script:Activity -Status 'Reset local files to origin/main'
        Invoke-UpdateGit -Root $target -Arguments @('reset', '--hard', 'origin/main') -FailureMessage 'Git reset --hard origin/main failed.'
        Show-SysAdminSuiteStep -Step 6 -Total $totalSteps -Activity $script:Activity -Status 'Clean stale local files'
        Invoke-UpdateGit -Root $target -Arguments @('clean', '-fd') -FailureMessage 'Git clean -fd failed.'
    } else {
        Show-SysAdminSuiteStep -Step 2 -Total $totalSteps -Activity $script:Activity -Status 'Existing non-git folder found; backing it up'
        $backupPath = Invoke-BackupNonGitFolder -TargetPath $target
        Write-Host "Backup: $backupPath"
        Show-SysAdminSuiteStep -Step 3 -Total $totalSteps -Activity $script:Activity -Status 'Clone official SysAdminSuite copy'
        Invoke-CloneInstall -TargetPath $target -Url $RepoUrl
    }

    if (-not $NoLaunch) {
        Show-SysAdminSuiteStep -Step $totalSteps -Total $totalSteps -Activity $script:Activity -Status 'Launch dashboard'
        Start-SysAdminSuiteDashboard -TargetPath $target
    }

    Complete-SysAdminSuiteProgress -Activity $script:Activity
    Write-Host ''
    Write-Host 'SysAdminSuite update complete - 100%' -ForegroundColor Green
    Write-Host "Location: $target"
    Write-Host ''
}

try {
    Invoke-FieldUpdate
} catch {
    Complete-SysAdminSuiteProgress -Activity $script:Activity
    Write-Host ''
    Write-Host 'SysAdminSuite update failed.' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''
    Write-Host 'Send this screen to Richard / project lead for review.'
    exit 1
}
