#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$Ref
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot=(Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
}
else {
    $RepositoryRoot=(Resolve-Path -LiteralPath $RepositoryRoot).Path
}

$git=Get-Command git.exe -ErrorAction SilentlyContinue
if (-not $git) { $git=Get-Command git -ErrorAction SilentlyContinue }
if (-not $git) { throw 'Git for Windows is required to refresh the field-ready SysAdminSuite checkout.' }
& $git.Source -C $RepositoryRoot rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) { throw "Not a Git working tree: $RepositoryRoot" }

function Get-SasPersistedRefreshRef {
    $state=Join-Path -Path $env:LOCALAPPDATA -ChildPath 'SysAdminSuite'
    $refPath=Join-Path -Path $state -ChildPath 'repo-ref.txt'
    if (Test-Path -LiteralPath $refPath -PathType Leaf) {
        try {
            $value=(Get-Content -LiteralPath $refPath -Raw -Encoding ASCII).Trim()
            if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
        }
        catch { }
    }
    return $null
}

function Resolve-SasRefreshBranch {
    param([AllowNull()][string]$RequestedRef)

    if (-not [string]::IsNullOrWhiteSpace($RequestedRef)) {
        $candidate=$RequestedRef.Trim()
    }
    else {
        $candidate=(& $git.Source -C $RepositoryRoot branch --show-current 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and $candidate) { $candidate=([string]$candidate).Trim() }

        # A field-ready checkout is deliberately detached. Recover the exact remote branch that
        # currently points at HEAD instead of silently falling back to main and discarding a live PR lane.
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
            $remoteMatches=@(
                & $git.Source -C $RepositoryRoot branch -r --points-at HEAD --format='%(refname:short)' 2>$null |
                    ForEach-Object { ([string]$_).Trim() } |
                    Where-Object { $_ -match '^origin/.+' -and $_ -notmatch '^origin/HEAD\s*->' } |
                    ForEach-Object { $_.Substring('origin/'.Length) } |
                    Sort-Object -Unique
            )
            if ($LASTEXITCODE -eq 0 -and $remoteMatches.Count -eq 1) { $candidate=$remoteMatches[0] }
        }

        # Terminal/worktree churn can advance the shared remote-tracking ref away from a detached
        # checkout's HEAD. Preserve the last explicitly refreshed branch before considering main.
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) { $candidate=Get-SasPersistedRefreshRef }

        # Main is only the final fallback for an old checkout with no branch provenance at all.
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) { $candidate='main' }
    }

    $candidate=([string]$candidate).Trim()
    & $git.Source check-ref-format --branch $candidate *> $null
    if ($LASTEXITCODE -ne 0) { throw "Refresh ref is not a valid branch name: $candidate" }
    return $candidate
}

$refreshBranch=Resolve-SasRefreshBranch -RequestedRef $Ref
$remoteTrackingRef="refs/remotes/origin/$refreshBranch"
$remoteDisplay="origin/$refreshBranch"

Write-Host 'NETWORK REQUIRED: GUEST / INTERNET' -ForegroundColor Cyan
Write-Host "Refreshing SysAdminSuite operator surface from $remoteDisplay..." -ForegroundColor Cyan

# Do not force-update the remote-tracking ref. A non-fast-forward remote rewrite fails closed so
# field deployment cannot silently replace the operator's trusted branch provenance.
& $git.Source -C $RepositoryRoot fetch --prune origin "refs/heads/${refreshBranch}:${remoteTrackingRef}"
if ($LASTEXITCODE -ne 0) { throw "git fetch origin $refreshBranch failed with exit code $LASTEXITCODE" }
$remoteHead=(& $git.Source -C $RepositoryRoot rev-parse $remoteDisplay).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remoteHead)) { throw "Could not resolve $remoteDisplay after fetch." }

$stateRoot=Join-Path -Path $env:LOCALAPPDATA -ChildPath 'SysAdminSuite'
$preferred=Join-Path -Path $stateRoot -ChildPath 'field-ready'
$refStatePath=Join-Path -Path $stateRoot -ChildPath 'repo-ref.txt'
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

function Test-SameRepository([string]$Candidate) {
    if (-not (Test-Path -LiteralPath $Candidate -PathType Container)) { return $false }
    try {
        $candidateOrigin=(& $git.Source -C $Candidate remote get-url origin 2>$null | Select-Object -First 1)
        $sourceOrigin=(& $git.Source -C $RepositoryRoot remote get-url origin 2>$null | Select-Object -First 1)
        return ($LASTEXITCODE -eq 0 -and $candidateOrigin -and $sourceOrigin -and
            ([string]$candidateOrigin).Trim().Equals(([string]$sourceOrigin).Trim(),[StringComparison]::OrdinalIgnoreCase))
    }
    catch { return $false }
}

$fieldReady=$preferred
if (Test-Path -LiteralPath $fieldReady) {
    $sameRepo=Test-SameRepository -Candidate $fieldReady
    $dirty=@()
    if ($sameRepo) { $dirty=@(& $git.Source -C $fieldReady status --porcelain 2>$null) }
    if (-not $sameRepo -or $LASTEXITCODE -ne 0 -or $dirty.Count -gt 0) {
        $fieldReady=Join-Path -Path $stateRoot -ChildPath ('field-ready-'+(Get-Date).ToString('yyyyMMdd-HHmmss'))
    }
}

if (-not (Test-Path -LiteralPath $fieldReady)) {
    & $git.Source -C $RepositoryRoot worktree add --detach $fieldReady $remoteDisplay
    if ($LASTEXITCODE -ne 0) { throw "Could not create isolated field-ready worktree: $fieldReady" }
}
else {
    & $git.Source -C $fieldReady checkout --detach $remoteDisplay
    if ($LASTEXITCODE -ne 0) { throw "Could not refresh isolated field-ready worktree: $fieldReady" }
}

$head=(& $git.Source -C $fieldReady rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne $remoteHead) { throw "Field-ready HEAD mismatch for $remoteDisplay. Expected $remoteHead; got $head" }

$required=@(
    'Install-SasOperatorCommand.cmd',
    'Switch-Back-To-Previous-Network.cmd',
    'Run-AutoLogonOnsite.cmd',
    'scripts\Install-SasPortableLauncher.ps1',
    'scripts\SasPortableLauncher.ps1',
    'scripts\SasOperatorSession.psm1',
    'scripts\Show-SasOperatorContext.ps1',
    'scripts\Return-SasOperatorToPreviousNetwork.ps1',
    'scripts\Recover-SasLatestInterruptedAutoLogonS4U.ps1',
    'scripts\Complete-SasInterruptedAutoLogonS4URecovery.ps1',
    'scripts\Invoke-SasAutoLogonOnsite.ps1',
    'scripts\Invoke-SasAutoLogonS4URestartDeployment.ps1',
    'scripts\Invoke-SasAutoLogonKerberosS4UPilot.ps1',
    'scripts\Invoke-SasCybernetCoreRecovery.ps1',
    'Find-SasEvidence.cmd',
    'Deploy-CybernetSoftware.cmd',
    'Deploy-CybernetClinicalCore.cmd',
    'Deploy-CybernetProfiledClinicalCore.cmd',
    'scripts\Invoke-SasCybernetProfiledClinicalCoreDeployment.ps1',
    'scripts\Test-SasCybernetClinicalCoreSources.ps1',
    'Probe-CybernetSoftware.cmd'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path -Path $fieldReady -ChildPath $relative) -PathType Leaf)) {
        throw "Refreshed $remoteDisplay is missing required operator surface: $relative"
    }
}

$installer=Join-Path -Path $fieldReady -ChildPath 'scripts\Install-SasPortableLauncher.ps1'
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer
if ($LASTEXITCODE -ne 0) { throw "Operator-command refresh installer failed with exit code $LASTEXITCODE" }

$sessionModule=Join-Path -Path $fieldReady -ChildPath 'scripts\SasOperatorSession.psm1'
Import-Module $sessionModule -Force
$session=Read-SasOperatorSession
$targetFilter=if ($session.target_fqdn) { [string]$session.target_fqdn } else { $null }
$session=Sync-SasOperatorSessionFromEvidence -RepoRoot $fieldReady -TargetFqdn $targetFilter
$nextTarget=if ($session.target_input) { [string]$session.target_input } else { $null }
$nextCommand=if ($nextTarget) { "sas cybernet Core $nextTarget" } else { 'sas context' }
$nextNetwork=if ($nextTarget) { 'PROTECTED NORTHWELL' } else { 'ANY / OFFLINE' }
Set-Content -LiteralPath $refStatePath -Value $refreshBranch -Encoding ASCII
[void](Set-SasOperatorSessionValues -Values @{
    repo_root=$fieldReady
    repo_head=$head
    launcher_head=$head
    current_network_classification='GUEST_INTERNET'
    next_required_network=$nextNetwork
    next_command=$nextCommand
})

Write-Host ''
Write-Host 'SAS_OPERATOR_REFRESH_READY' -ForegroundColor Green
Write-Host "Field-ready repo: $fieldReady"
Write-Host "REF: $refreshBranch"
Write-Host "HEAD: $head"
Write-Host 'Existing source worktree was not reset or cleaned.' -ForegroundColor Green
Write-Host "NEXT NETWORK: $nextNetwork" -ForegroundColor Cyan
Write-Host "NEXT COMMAND: $nextCommand" -ForegroundColor Green
