#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$Ref
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
}
else {
    $RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
}

$git = Get-Command git.exe -ErrorAction SilentlyContinue
if (-not $git) { $git = Get-Command git -ErrorAction SilentlyContinue }
if (-not $git) { throw 'Git for Windows is required to refresh the field-ready SysAdminSuite checkout.' }
& $git.Source -C $RepositoryRoot rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) { throw "Not a Git working tree: $RepositoryRoot" }

# Remote Git maintenance is Guest/Internet-only. Prove that posture before any
# ls-remote or fetch so the protected Northwell/VPN phase never performs repo acquisition.
$preRefreshNetworkModule = Join-Path $RepositoryRoot 'scripts\SasOperatorSession.psm1'
if (-not (Test-Path -LiteralPath $preRefreshNetworkModule -PathType Leaf)) {
    throw "Operator network classifier is missing: $preRefreshNetworkModule"
}
Import-Module $preRefreshNetworkModule -Force
$preRefreshNetwork = Get-SasOperatorNetworkClassification -RepoRoot $RepositoryRoot
Write-Host 'NETWORK REQUIRED: GUEST / INTERNET' -ForegroundColor Cyan
Write-Host "CURRENT NETWORK: $($preRefreshNetwork.classification) [$($preRefreshNetwork.label)]"
if ([string]$preRefreshNetwork.classification -ne 'GUEST_INTERNET') {
    throw "SAS_REFRESH_REMOTE_GIT_BLOCKED: GitHub sync is Guest/Internet-only. Current classification: $($preRefreshNetwork.classification); label: $($preRefreshNetwork.label). No remote Git operation was started."
}
Write-Host 'PASS: remote repository maintenance is allowed on the current Guest/Internet network.' -ForegroundColor Green

$operatorStateRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'SysAdminSuite'
$persistedRefPath = Join-Path -Path $operatorStateRoot -ChildPath 'repo-ref.txt'

function Get-SasPersistedRefreshRef {
    if (Test-Path -LiteralPath $persistedRefPath -PathType Leaf) {
        try {
            $value = (Get-Content -LiteralPath $persistedRefPath -Raw -Encoding ASCII).Trim()
            if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
        }
        catch { }
    }
    return $null
}

function Clear-SasPersistedRefreshRef {
    try {
        if (Test-Path -LiteralPath $persistedRefPath -PathType Leaf) {
            Remove-Item -LiteralPath $persistedRefPath -Force
        }
    }
    catch {
        Write-Warning "Could not clear stale persisted refresh ref: $($_.Exception.Message)"
    }
}

function Test-SasRemoteRefreshBranch {
    param([Parameter(Mandatory = $true)][string]$Branch)
    & $git.Source -C $RepositoryRoot ls-remote --exit-code --heads origin "refs/heads/$Branch" *> $null
    return ($LASTEXITCODE -eq 0)
}

function Resolve-SasRefreshBranch {
    param([AllowNull()][string]$RequestedRef)

    $candidateSource = 'explicit'
    if (-not [string]::IsNullOrWhiteSpace($RequestedRef)) {
        $candidate = $RequestedRef.Trim()
    }
    else {
        $candidateSource = 'current_branch'
        $candidate = (& $git.Source -C $RepositoryRoot branch --show-current 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and $candidate) { $candidate = ([string]$candidate).Trim() }

        if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
            $candidateSource = 'unique_remote_at_head'
            $remoteMatches = @(
                & $git.Source -C $RepositoryRoot branch -r --points-at HEAD --format='%(refname:short)' 2>$null |
                    ForEach-Object { ([string]$_).Trim() } |
                    Where-Object { $_ -match '^origin/.+' -and $_ -notmatch '^origin/HEAD\s*->' } |
                    ForEach-Object { $_.Substring('origin/'.Length) } |
                    Sort-Object -Unique
            )
            if ($LASTEXITCODE -eq 0 -and $remoteMatches.Count -eq 1) { $candidate = $remoteMatches[0] }
        }
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
            $candidateSource = 'persisted'
            $candidate = Get-SasPersistedRefreshRef
        }
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
            $candidateSource = 'default_main'
            $candidate = 'main'
        }
    }

    $candidate = ([string]$candidate).Trim()
    & $git.Source check-ref-format --branch $candidate *> $null
    if ($LASTEXITCODE -ne 0) { throw "Refresh ref is not a valid branch name: $candidate" }

    if (-not (Test-SasRemoteRefreshBranch -Branch $candidate)) {
        if ($candidateSource -eq 'persisted') {
            Clear-SasPersistedRefreshRef
            $candidate = 'main'
            if (-not (Test-SasRemoteRefreshBranch -Branch $candidate)) {
                throw 'Persisted refresh ref was stale and origin/main could not be verified.'
            }
            Write-Warning 'Persisted refresh ref was stale; cleared it and repaired refresh provenance to origin/main.'
        }
        else {
            throw "Refresh branch does not exist on origin: $candidate"
        }
    }
    return $candidate
}

$refreshBranch = Resolve-SasRefreshBranch -RequestedRef $Ref
$remoteTrackingRef = "refs/remotes/origin/$refreshBranch"
$remoteDisplay = "origin/$refreshBranch"

Write-Host "Refreshing SysAdminSuite operator surface from $remoteDisplay..." -ForegroundColor Cyan

# Do not force-update the remote-tracking ref. A non-fast-forward rewrite fails closed.
& $git.Source -C $RepositoryRoot fetch --prune origin "refs/heads/${refreshBranch}:${remoteTrackingRef}"
if ($LASTEXITCODE -ne 0) { throw "git fetch origin $refreshBranch failed with exit code $LASTEXITCODE" }
$remoteHead = (& $git.Source -C $RepositoryRoot rev-parse $remoteDisplay).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remoteHead)) { throw "Could not resolve $remoteDisplay after fetch." }

$stateRoot = $operatorStateRoot
$preferred = Join-Path -Path $stateRoot -ChildPath 'field-ready'
$refStatePath = $persistedRefPath
$returnNetworkPath = Join-Path -Path $stateRoot -ChildPath 'return-network.json'
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

function Test-SameRepository([string]$Candidate) {
    if (-not (Test-Path -LiteralPath $Candidate -PathType Container)) { return $false }
    try {
        $candidateOrigin = (& $git.Source -C $Candidate remote get-url origin 2>$null | Select-Object -First 1)
        $sourceOrigin = (& $git.Source -C $RepositoryRoot remote get-url origin 2>$null | Select-Object -First 1)
        return ($LASTEXITCODE -eq 0 -and $candidateOrigin -and $sourceOrigin -and
            ([string]$candidateOrigin).Trim().Equals(([string]$sourceOrigin).Trim(),[StringComparison]::OrdinalIgnoreCase))
    }
    catch { return $false }
}

$fieldReady = $preferred
if (Test-Path -LiteralPath $fieldReady) {
    $sameRepo = Test-SameRepository -Candidate $fieldReady
    $dirty = @()
    if ($sameRepo) { $dirty = @(& $git.Source -C $fieldReady status --porcelain 2>$null) }
    if (-not $sameRepo -or $LASTEXITCODE -ne 0 -or $dirty.Count -gt 0) {
        $fieldReady = Join-Path -Path $stateRoot -ChildPath ('field-ready-' + (Get-Date).ToString('yyyyMMdd-HHmmss'))
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

$head = (& $git.Source -C $fieldReady rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne $remoteHead) { throw "Field-ready HEAD mismatch for $remoteDisplay. Expected $remoteHead; got $head" }

$required = @(
    'Install-SasOperatorCommand.cmd',
    'Switch-Back-To-Previous-Network.cmd',
    'Run-AutoLogonOnsite.cmd',
    'Bootstrap-SysAdminSuiteAutoLogon.cmd',
    'Bootstrap-SysAdminSuiteAutoLogon.ps1',
    'scripts\Prepare-SasAutoLogonShortRuntime.ps1',
    'scripts\Install-SasPortableLauncher.ps1',
    'scripts\SasPortableLauncher.ps1',
    'scripts\SasOperatorSession.psm1',
    'scripts\SasAutoLogonOperatorState.psm1',
    'scripts\SasTargetNameResolution.psm1',
    'scripts\Show-SasOperatorContext.ps1',
    'scripts\Return-SasOperatorToPreviousNetwork.ps1',
    'scripts\Recover-SasLatestInterruptedAutoLogonS4U.ps1',
    'scripts\Complete-SasInterruptedAutoLogonS4URecovery.ps1',
    'scripts\Invoke-SasAutoLogonOnsite.ps1',
    'scripts\Invoke-SasAutoLogonFieldDeployment.ps1',
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

$installer = Join-Path -Path $fieldReady -ChildPath 'scripts\Install-SasPortableLauncher.ps1'
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer
if ($LASTEXITCODE -ne 0) { throw "Operator-command refresh installer failed with exit code $LASTEXITCODE" }

$sessionModule = Join-Path -Path $fieldReady -ChildPath 'scripts\SasOperatorSession.psm1'
$autoLogonStateModule = Join-Path -Path $fieldReady -ChildPath 'scripts\SasAutoLogonOperatorState.psm1'
Import-Module $sessionModule -Force
Import-Module $autoLogonStateModule -Force
$currentNetwork = Get-SasOperatorNetworkClassification -RepoRoot $fieldReady
if ([string]$currentNetwork.classification -ne 'GUEST_INTERNET' -or [string]::IsNullOrWhiteSpace([string]$currentNetwork.label) -or [string]$currentNetwork.label -eq 'unknown') {
    throw "Guest/Internet posture changed during refresh. Current classification: $($currentNetwork.classification); label: $($currentNetwork.label). Short AutoLogon runtime was not staged."
}

$runtimePreparer = Join-Path $fieldReady 'scripts\Prepare-SasAutoLogonShortRuntime.ps1'
Write-Host ''
Write-Host 'STAGING SHORT AUTOLOGON RUNTIME BEFORE LEAVING GUEST' -ForegroundColor Cyan
$LASTEXITCODE = 0
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $runtimePreparer `
    -SourceRoot $fieldReady -RuntimeRoot 'C:\SASAL' -ExpectedCommit $head
if ($LASTEXITCODE -ne 0) {
    throw "Short AutoLogon runtime staging failed with exit code $LASTEXITCODE. Remain on Guest/Internet and repair before protected deployment."
}

$returnBookmark = [pscustomobject][ordered]@{
    schema_version='sas-operator-return-network/v1'
    classification='GUEST_INTERNET'
    label=[string]$currentNetwork.label
    recorded_utc=(Get-Date).ToUniversalTime().ToString('o')
    recorded_by='Refresh-SasOperatorCommand'
    target_contact_performed=$false
    target_mutation_performed=$false
    secret_material_collected=$false
}
$returnBookmark | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $returnNetworkPath -Encoding UTF8

$session = Read-SasOperatorSession
$targetFilter = [string](Get-SasObjectPropertyValue $session 'resolved_target_fqdn' (
    Get-SasObjectPropertyValue $session 'target_fqdn' $null
))
if (Get-Command -Name Sync-SasAutoLogonOperatorState -ErrorAction SilentlyContinue) {
    $session = Sync-SasAutoLogonOperatorState -RepoRoot $fieldReady -Target $targetFilter
    $nextCommand = [string](Get-SasObjectPropertyValue $session 'next_command' 'sas context')
    $nextNetwork = [string](Get-SasObjectPropertyValue $session 'next_required_network' 'ANY / OFFLINE')
}
else {
    $session = Sync-SasOperatorSessionFromEvidence -RepoRoot $fieldReady -TargetFqdn $targetFilter
    $nextTarget = if ($session.target_input) { [string]$session.target_input } else { $null }
    $nextCommand = if ($nextTarget) { "sas cybernet Core $nextTarget" } else { 'sas context' }
    $nextNetwork = if ($nextTarget) { 'PROTECTED NORTHWELL' } else { 'ANY / OFFLINE' }
}
Set-Content -LiteralPath $refStatePath -Value $refreshBranch -Encoding ASCII
[void](Set-SasOperatorSessionValues -Values @{
    repo_root=$fieldReady
    repo_head=$head
    repo_branch=$refreshBranch
    launcher_head=$head
    current_network_classification='GUEST_INTERNET'
    current_network_label=[string]$currentNetwork.label
    next_required_network=$nextNetwork
    next_command=$nextCommand
})

Write-Host ''
Write-Host 'SAS_OPERATOR_REFRESH_READY' -ForegroundColor Green
Write-Host "Field-ready repo: $fieldReady"
Write-Host 'Short AutoLogon runtime: C:\SASAL'
Write-Host "REF: $refreshBranch"
Write-Host "HEAD: $head"
Write-Host "RETURN NETWORK: $($currentNetwork.label)" -ForegroundColor Green
Write-Host 'Existing source worktree was not reset or cleaned.' -ForegroundColor Green
Write-Host 'Protected-side Git network I/O: DISABLED' -ForegroundColor Green
Write-Host "NEXT NETWORK: $nextNetwork" -ForegroundColor Cyan
Write-Host "NEXT COMMAND: $nextCommand" -ForegroundColor Green
