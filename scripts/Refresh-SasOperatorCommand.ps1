#Requires -Version 5.1
<#
.SYNOPSIS
Refresh the SysAdminSuite operator surface on Guest/Internet and seal the protected AutoLogon runtime.

.DESCRIPTION
The caller checkout is used only to locate the network classifier and this refresh entrypoint. All remote
Git operations are isolated to %LOCALAPPDATA%\SysAdminSuite\sync-cache and are blocked unless the current
network classifies as GUEST_INTERNET. A clean field-ready worktree is derived from that cache, stale dirty
generated C:\SASAL content is preserved intact before replacement, the installed `sas` dispatcher is refreshed
from field-ready, and C:\SASAL is then staged by local filesystem Git transfer and stripped of remotes for
protected-network use.

No target contact or target mutation occurs in this script.
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$Ref,
    [string]$RepoUrl = 'https://github.com/EndeavorEverlasting/SysAdminSuite.git'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
} else {
    $RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
}

$operatorStateRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite'
$syncCache = Join-Path $operatorStateRoot 'sync-cache'
$preferredFieldReady = Join-Path $operatorStateRoot 'field-ready'
$persistedRefPath = Join-Path $operatorStateRoot 'repo-ref.txt'
$returnNetworkPath = Join-Path $operatorStateRoot 'return-network.json'
New-Item -ItemType Directory -Path $operatorStateRoot -Force | Out-Null

function Resolve-SasGitExecutable {
    $command = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { $command = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if ($command -and $command.Source) { return [IO.Path]::GetFullPath([string]$command.Source) }
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),
        (Join-Path $env:ProgramFiles 'Git\bin\git.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [IO.Path]::GetFullPath($candidate) }
    }
    throw 'Git for Windows is required to refresh the SysAdminSuite sync cache.'
}

$script:SasGitExe = Resolve-SasGitExecutable

function Invoke-SasRefreshGit {
    param(
        [AllowNull()][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage,
        [switch]$Quiet
    )

    $stderrPath = Join-Path $env:TEMP ('sas-refresh-git-' + [guid]::NewGuid().ToString('N') + '.err')
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $stdout = @()
        $exitCode = 0
        if ([string]::IsNullOrWhiteSpace($Root)) {
            $stdout = @(& $script:SasGitExe @Arguments 2> $stderrPath)
            $exitCode = [int]$global:LASTEXITCODE
        } else {
            $stdout = @(& $script:SasGitExe -C $Root @Arguments 2> $stderrPath)
            $exitCode = [int]$global:LASTEXITCODE
        }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    $stderr = ''
    if (Test-Path -LiteralPath $stderrPath) {
        try {
            $stderrRaw = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
            if ($null -ne $stderrRaw) {
                $stderr = ([string]$stderrRaw).Trim()
            }
        }
        finally { Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue }
    }
    $stdoutRaw = @($stdout | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    $stdoutText = ''
    if ($null -ne $stdoutRaw) {
        $stdoutText = ([string]$stdoutRaw).Trim()
    }
    if ($exitCode -ne 0) {
        $detail = @($stdoutText,$stderr | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = '(git produced no diagnostic text)' }
        throw "$FailureMessage (git exit $exitCode)`n$detail"
    }
    if (-not $Quiet) {
        if (-not [string]::IsNullOrWhiteSpace($stdoutText)) { Write-Host $stdoutText }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) { Write-Host $stderr -ForegroundColor DarkGray }
    }
    return @($stdout | ForEach-Object { [string]$_ })
}

function Get-SasRefreshGitScalar {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )
    $lines = @(Invoke-SasRefreshGit -Root $Root -Arguments $Arguments -FailureMessage $FailureMessage -Quiet)
    $value = [string]($lines | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($value)) { throw "$FailureMessage (empty git output)" }
    return $value.Trim()
}

function Test-SasExpectedOrigin {
    param([Parameter(Mandatory = $true)][string]$Url)
    $normalized = $Url.Trim().TrimEnd('/').ToLowerInvariant()
    return $normalized -in @(
        'https://github.com/endeavoreverlasting/sysadminsuite.git',
        'https://github.com/endeavoreverlasting/sysadminsuite',
        'git@github.com:endeavoreverlasting/sysadminsuite.git'
    )
}

$networkModule = Join-Path $RepositoryRoot 'scripts\SasOperatorSession.psm1'
if (-not (Test-Path -LiteralPath $networkModule -PathType Leaf)) {
    throw "Operator network classifier is missing from the bootstrap checkout: $networkModule"
}
Import-Module $networkModule -Force
$preRefreshNetwork = Get-SasOperatorNetworkClassification -RepoRoot $RepositoryRoot

Write-Host 'NETWORK REQUIRED: GUEST / INTERNET' -ForegroundColor Cyan
Write-Host "CURRENT NETWORK: $($preRefreshNetwork.classification) [$($preRefreshNetwork.label)]"
if ([string]$preRefreshNetwork.classification -ne 'GUEST_INTERNET') {
    throw "SAS_REFRESH_REMOTE_GIT_BLOCKED: repository sync is Guest/Internet-only. Current classification: $($preRefreshNetwork.classification); label: $($preRefreshNetwork.label). No remote Git operation was started."
}
Write-Host 'PASS: Guest/Internet proved before remote repository maintenance.' -ForegroundColor Green

$refreshBranch = if ([string]::IsNullOrWhiteSpace($Ref)) { 'main' } else { $Ref.Trim() }
$refCheck = @(Invoke-SasRefreshGit -Arguments @('check-ref-format','--branch',$refreshBranch) -FailureMessage "Refresh ref is not valid: $refreshBranch" -Quiet)
$null = $refCheck
$remoteTrackingRef = "refs/remotes/origin/$refreshBranch"
$remoteDisplay = "origin/$refreshBranch"

if (-not (Test-Path -LiteralPath $syncCache)) {
    Write-Host "Creating Guest-only SysAdminSuite sync cache: $syncCache" -ForegroundColor Cyan
    [void](Invoke-SasRefreshGit -Arguments @('clone','--origin','origin','--no-tags','--branch',$refreshBranch,'--single-branch',$RepoUrl,$syncCache) -FailureMessage 'Creating the Guest-only SysAdminSuite sync cache failed.')
} else {
    if (-not (Test-Path -LiteralPath $syncCache -PathType Container)) {
        throw "Sync-cache path exists but is not a directory: $syncCache"
    }
    $inside = Get-SasRefreshGitScalar -Root $syncCache -Arguments @('rev-parse','--is-inside-work-tree') -FailureMessage 'Existing sync cache is not a usable Git worktree.'
    if ($inside -ne 'true') { throw "Existing sync cache is not a Git worktree: $syncCache" }
    $origin = Get-SasRefreshGitScalar -Root $syncCache -Arguments @('remote','get-url','origin') -FailureMessage 'Could not resolve sync-cache origin.'
    if (-not (Test-SasExpectedOrigin -Url $origin)) { throw "Unexpected sync-cache origin: $origin" }
    $syncDirty = @(Invoke-SasRefreshGit -Root $syncCache -Arguments @('status','--porcelain') -FailureMessage 'Could not inspect sync-cache state.' -Quiet)
    if (@($syncDirty | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
        $syncDirty | Out-Host
        throw "Guest sync cache contains local work. Nothing was reset or cleaned: $syncCache"
    }
}

Write-Host "Refreshing Guest-only sync cache from $remoteDisplay..." -ForegroundColor Cyan
[void](Invoke-SasRefreshGit -Root $syncCache -Arguments @('fetch','--no-tags','--prune','origin',"refs/heads/${refreshBranch}:${remoteTrackingRef}") -FailureMessage "Fetching $remoteDisplay failed.")
$remoteHead = Get-SasRefreshGitScalar -Root $syncCache -Arguments @('rev-parse',$remoteDisplay) -FailureMessage "Could not resolve $remoteDisplay after fetch."

$fieldReady = $preferredFieldReady
if (Test-Path -LiteralPath $fieldReady) {
    $usable = $true
    try {
        $fieldInside = Get-SasRefreshGitScalar -Root $fieldReady -Arguments @('rev-parse','--is-inside-work-tree') -FailureMessage 'Field-ready checkout is not a Git worktree.'
        if ($fieldInside -ne 'true') { $usable = $false }
        $fieldDirty = @(Invoke-SasRefreshGit -Root $fieldReady -Arguments @('status','--porcelain') -FailureMessage 'Could not inspect field-ready state.' -Quiet)
        if (@($fieldDirty | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) { $usable = $false }
    }
    catch { $usable = $false }
    if (-not $usable) {
        $fieldReady = Join-Path $operatorStateRoot ('field-ready-' + (Get-Date).ToString('yyyyMMdd-HHmmss'))
    }
}

if (-not (Test-Path -LiteralPath $fieldReady)) {
    [void](Invoke-SasRefreshGit -Root $syncCache -Arguments @('worktree','add','--detach',$fieldReady,$remoteHead) -FailureMessage "Could not create isolated field-ready worktree: $fieldReady")
} else {
    [void](Invoke-SasRefreshGit -Root $fieldReady -Arguments @('checkout','--detach',$remoteHead) -FailureMessage "Could not refresh isolated field-ready worktree: $fieldReady")
}

$head = Get-SasRefreshGitScalar -Root $fieldReady -Arguments @('rev-parse','HEAD') -FailureMessage 'Could not resolve field-ready HEAD.'
if ($head -ne $remoteHead) { throw "Field-ready HEAD mismatch. Expected $remoteHead; got $head" }

$required = @(
    'Install-SasOperatorCommand.cmd',
    'Switch-Back-To-Previous-Network.cmd',
    'Run-AutoLogonOnsite.cmd',
    'Bootstrap-SysAdminSuiteAutoLogon.cmd',
    'Bootstrap-SysAdminSuiteAutoLogon.ps1',
    'scripts\Repair-SasAutoLogonShortRuntimeForRefresh.ps1',
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
    if (-not (Test-Path -LiteralPath (Join-Path $fieldReady $relative) -PathType Leaf)) {
        throw "Refreshed $remoteDisplay is missing required operator surface: $relative"
    }
}

$sessionModule = Join-Path $fieldReady 'scripts\SasOperatorSession.psm1'
$autoLogonStateModule = Join-Path $fieldReady 'scripts\SasAutoLogonOperatorState.psm1'
Import-Module $sessionModule -Force
Import-Module $autoLogonStateModule -Force
$currentNetwork = Get-SasOperatorNetworkClassification -RepoRoot $fieldReady
if ([string]$currentNetwork.classification -ne 'GUEST_INTERNET' -or
    [string]::IsNullOrWhiteSpace([string]$currentNetwork.label) -or
    [string]$currentNetwork.label -eq 'unknown') {
    throw "Guest/Internet posture changed during refresh. Current classification: $($currentNetwork.classification); label: $($currentNetwork.label). Short AutoLogon runtime was not staged."
}

$runtimeRepair = Join-Path $fieldReady 'scripts\Repair-SasAutoLogonShortRuntimeForRefresh.ps1'
Write-Host ''
Write-Host 'PREPARING GENERATED SHORT AUTOLOGON RUNTIME FOR CLEAN REFRESH' -ForegroundColor Cyan
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $runtimeRepair -RuntimeRoot 'C:\SASAL'
$runtimeRepairExitCode = [int]$global:LASTEXITCODE
if ($runtimeRepairExitCode -ne 0) {
    throw "Short AutoLogon runtime preservation failed with exit code $runtimeRepairExitCode. Nothing was reset or cleaned."
}

$runtimePreparer = Join-Path $fieldReady 'scripts\Prepare-SasAutoLogonShortRuntime.ps1'
Write-Host ''
Write-Host 'STAGING SHORT AUTOLOGON RUNTIME BEFORE LEAVING GUEST' -ForegroundColor Cyan
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $runtimePreparer `
    -SourceRoot $fieldReady -RuntimeRoot 'C:\SASAL' -ExpectedCommit $head
$runtimePreparerExitCode = [int]$global:LASTEXITCODE
if ($runtimePreparerExitCode -ne 0) {
    throw "Short AutoLogon runtime staging failed with exit code $runtimePreparerExitCode. Remain on Guest/Internet and repair before protected deployment."
}

$installer = Join-Path $fieldReady 'scripts\Install-SasPortableLauncher.ps1'
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer
$installerExitCode = [int]$global:LASTEXITCODE
if ($installerExitCode -ne 0) { throw "Operator-command refresh installer failed with exit code $installerExitCode" }

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
} else {
    $session = Sync-SasOperatorSessionFromEvidence -RepoRoot $fieldReady -TargetFqdn $targetFilter
    $nextTarget = if ($session.target_input) { [string]$session.target_input } else { $null }
    $nextCommand = if ($nextTarget) { "sas cybernet Core $nextTarget" } else { 'sas context' }
    $nextNetwork = if ($nextTarget) { 'PROTECTED NORTHWELL' } else { 'ANY / OFFLINE' }
}
Set-Content -LiteralPath $persistedRefPath -Value $refreshBranch -Encoding ASCII
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
Write-Host "Guest sync cache: $syncCache"
Write-Host "Field-ready repo: $fieldReady"
Write-Host 'Short AutoLogon runtime: C:\SASAL'
Write-Host "REF: $refreshBranch"
Write-Host "HEAD: $head"
Write-Host "RETURN NETWORK: $($currentNetwork.label)" -ForegroundColor Green
Write-Host 'Bootstrap checkout was not reset or cleaned.' -ForegroundColor Green
Write-Host 'Protected-side Git network I/O: DISABLED' -ForegroundColor Green
Write-Host "NEXT NETWORK: $nextNetwork" -ForegroundColor Cyan
Write-Host "NEXT COMMAND: $nextCommand" -ForegroundColor Green
