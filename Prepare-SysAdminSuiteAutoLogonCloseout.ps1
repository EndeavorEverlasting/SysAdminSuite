#Requires -Version 5.1
<#
.SYNOPSIS
Prepare a current sealed SysAdminSuite AutoLogon runtime and one-command protected deployment handoff.

.DESCRIPTION
Run this on Guest / ordinary Internet. The script owns only controller preparation: it maintains a dedicated
machine-local closeout controller, refreshes it to current origin/main without touching historical operator
checkouts, delegates runtime staging to the canonical Refresh-SasOperatorCommand.ps1 workflow, runs the canonical
full runtime seal audit, and generates a pinned protected-network handoff.

It performs no target contact and no target mutation. The generated handoff invokes only the existing protected
AutoLogon bootstrap, which retains all network, eligibility, recovery, apply, restart, and evidence gates.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [string]$Ref = 'main',

    [string]$RepoUrl = 'https://github.com/EndeavorEverlasting/SysAdminSuite.git',

    [string]$RuntimeRoot = 'C:\SASAL',

    [switch]$ControllerMode,

    [string]$ExpectedCurrentHead
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$stateRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite'
$controllerRoot = Join-Path $stateRoot 'autologon-closeout-controller'
$preservationRoot = Join-Path $stateRoot 'autologon-closeout-controller-preservation'
$closeoutRoot = Join-Path $stateRoot 'autologon-closeout'
$verificationReceipt = Join-Path $stateRoot 'autologon-runtime-verification.json'
$manifestPath = Join-Path $stateRoot 'autologon-short-runtime.json'
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Assert-SasTargetShape {
    param([Parameter(Mandatory = $true)][string]$Target)
    $value = $Target.Trim()
    if ($value.Length -lt 1 -or $value.Length -gt 253) {
        throw 'AUTOLOGON_CLOSEOUT_TARGET_INVALID: target length must be between 1 and 253 characters.'
    }
    foreach ($label in @($value.Split('.'))) {
        if ($label.Length -lt 1 -or $label.Length -gt 63 -or
            $label -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$') {
            throw "AUTOLOGON_CLOSEOUT_TARGET_INVALID: '$Target' is not a valid short hostname or FQDN shape."
        }
    }
    return $value
}

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
    throw 'Git for Windows is required for AutoLogon closeout preparation.'
}

$script:SasGitExe = Resolve-SasGitExecutable

function Invoke-SasCloseoutGit {
    param(
        [AllowNull()][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage,
        [switch]$Quiet
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        if ([string]::IsNullOrWhiteSpace($Root)) {
            $output = @(& $script:SasGitExe @Arguments 2>&1)
        }
        else {
            $output = @(& $script:SasGitExe -C $Root @Arguments 2>&1)
        }
        $exitCode = [int]$global:LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    $text = (@($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
    if ($exitCode -ne 0) {
        if ([string]::IsNullOrWhiteSpace($text)) { $text = '(git produced no diagnostic text)' }
        throw "$FailureMessage (git exit $exitCode)`n$text"
    }
    if (-not $Quiet -and -not [string]::IsNullOrWhiteSpace($text)) { Write-Host $text }
    return @($output | ForEach-Object { [string]$_ })
}

function Get-SasCloseoutGitScalar {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )
    $lines = @(Invoke-SasCloseoutGit -Root $Root -Arguments $Arguments -FailureMessage $FailureMessage -Quiet)
    $value = [string]($lines | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($value)) { throw "$FailureMessage (empty git output)" }
    return $value.Trim()
}

function Test-SasOfficialOrigin {
    param([Parameter(Mandatory = $true)][string]$Url)
    return $Url.Trim() -match '^(?:https://github\.com/|git@github\.com:)EndeavorEverlasting/SysAdminSuite(?:\.git)?$'
}

function Preserve-SasOwnedController {
    if (-not (Test-Path -LiteralPath $controllerRoot)) { return }
    New-Item -ItemType Directory -Path $preservationRoot -Force | Out-Null
    $destination = Join-Path $preservationRoot ('controller-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
    Move-Item -LiteralPath $controllerRoot -Destination $destination
    Write-Host "Preserved prior generated closeout controller: $destination" -ForegroundColor Yellow
}

function Initialize-SasCurrentController {
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

    $reuse = $false
    if (Test-Path -LiteralPath (Join-Path $controllerRoot '.git')) {
        try {
            $origin = Get-SasCloseoutGitScalar -Root $controllerRoot -Arguments @('remote','get-url','origin') -FailureMessage 'Could not read closeout-controller origin.'
            $status = @(Invoke-SasCloseoutGit -Root $controllerRoot -Arguments @('status','--porcelain=v1','--untracked-files=all') -FailureMessage 'Could not inspect closeout-controller status.' -Quiet)
            $reuse = (Test-SasOfficialOrigin -Url $origin) -and ($status.Count -eq 0)
        }
        catch { $reuse = $false }
    }

    if (-not $reuse -and (Test-Path -LiteralPath $controllerRoot)) {
        Preserve-SasOwnedController
    }

    if (-not (Test-Path -LiteralPath $controllerRoot)) {
        Write-Host 'Creating dedicated AutoLogon closeout controller from the official repository...' -ForegroundColor Cyan
        [void](Invoke-SasCloseoutGit -Root $null -Arguments @('clone','--branch',$Ref,'--single-branch',$RepoUrl,$controllerRoot) -FailureMessage 'Could not create the closeout controller.')
    }

    $originAfter = Get-SasCloseoutGitScalar -Root $controllerRoot -Arguments @('remote','get-url','origin') -FailureMessage 'Could not read prepared controller origin.'
    if (-not (Test-SasOfficialOrigin -Url $originAfter)) {
        Preserve-SasOwnedController
        [void](Invoke-SasCloseoutGit -Root $null -Arguments @('clone','--branch',$Ref,'--single-branch',$RepoUrl,$controllerRoot) -FailureMessage 'Could not recreate the closeout controller from the official repository.')
    }

    try {
        [void](Invoke-SasCloseoutGit -Root $controllerRoot -Arguments @('fetch','--all','--prune','--tags') -FailureMessage 'Could not refresh closeout-controller remote truth.')
    }
    catch {
        Write-Host 'Existing generated controller could not refresh; preserving it and cloning a clean replacement.' -ForegroundColor Yellow
        Preserve-SasOwnedController
        [void](Invoke-SasCloseoutGit -Root $null -Arguments @('clone','--branch',$Ref,'--single-branch',$RepoUrl,$controllerRoot) -FailureMessage 'Could not recreate the closeout controller after refresh failure.')
        [void](Invoke-SasCloseoutGit -Root $controllerRoot -Arguments @('fetch','--all','--prune','--tags') -FailureMessage 'Could not refresh the replacement closeout controller.')
    }

    [void](Invoke-SasCloseoutGit -Root $controllerRoot -Arguments @('check-ref-format','--branch',$Ref) -FailureMessage "Invalid requested ref '$Ref'." -Quiet)
    $remoteHead = Get-SasCloseoutGitScalar -Root $controllerRoot -Arguments @('rev-parse',('origin/' + $Ref)) -FailureMessage "Could not resolve origin/$Ref."

    [void](Invoke-SasCloseoutGit -Root $controllerRoot -Arguments @('checkout','--detach',$remoteHead) -FailureMessage 'Could not pin closeout controller to current remote head.')
    $statusAfter = @(Invoke-SasCloseoutGit -Root $controllerRoot -Arguments @('status','--porcelain=v1','--untracked-files=all') -FailureMessage 'Could not verify closeout-controller cleanliness.' -Quiet)
    if ($statusAfter.Count -ne 0) {
        throw 'AUTOLOGON_CLOSEOUT_CONTROLLER_DIRTY: generated closeout controller is not clean after current-head checkout.'
    }

    return $remoteHead
}

$target = Assert-SasTargetShape -Target $ComputerName
if (-not (Test-Path -LiteralPath $ps51 -PathType Leaf)) {
    throw "Windows PowerShell 5.1 was not found: $ps51"
}

if (-not $ControllerMode) {
    Write-Host ''
    Write-Host '=== SYSADMINSUITE AUTOLOGON CLOSEOUT PREPARATION ===' -ForegroundColor Cyan
    Write-Host "Target: $target"
    Write-Host 'Required network: Guest / ordinary Internet'
    Write-Host 'Historical operator checkouts: PRESERVED / NOT USED AS AUTHORITY' -ForegroundColor Green
    Write-Host 'Target contact during preparation: NONE' -ForegroundColor Green
    Write-Host ''

    $currentHead = Initialize-SasCurrentController
    $controllerScript = Join-Path $controllerRoot 'Prepare-SysAdminSuiteAutoLogonCloseout.ps1'
    if (-not (Test-Path -LiteralPath $controllerScript -PathType Leaf)) {
        throw "Current origin/$Ref does not contain the AutoLogon closeout preparer: $controllerScript"
    }

    & $ps51 -NoLogo -NoProfile -ExecutionPolicy Bypass -File $controllerScript `
        -ComputerName $target -Ref $Ref -RepoUrl $RepoUrl -RuntimeRoot $RuntimeRoot `
        -ControllerMode -ExpectedCurrentHead $currentHead
    $childExit = [int]$global:LASTEXITCODE
    exit $childExit
}

$repoRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$origin = Get-SasCloseoutGitScalar -Root $repoRoot -Arguments @('remote','get-url','origin') -FailureMessage 'Could not read closeout-controller origin.'
if (-not (Test-SasOfficialOrigin -Url $origin)) {
    throw "AUTOLOGON_CLOSEOUT_CONTROLLER_ORIGIN_INVALID: $origin"
}
$localHead = Get-SasCloseoutGitScalar -Root $repoRoot -Arguments @('rev-parse','HEAD') -FailureMessage 'Could not resolve closeout-controller HEAD.'
$status = @(Invoke-SasCloseoutGit -Root $repoRoot -Arguments @('status','--porcelain=v1','--untracked-files=all') -FailureMessage 'Could not verify closeout-controller status.' -Quiet)
if ($status.Count -ne 0) {
    throw 'AUTOLOGON_CLOSEOUT_CONTROLLER_DIRTY: controller mode requires a clean generated checkout.'
}
if ([string]::IsNullOrWhiteSpace($ExpectedCurrentHead) -or
    -not $localHead.Equals($ExpectedCurrentHead.Trim(), [StringComparison]::OrdinalIgnoreCase)) {
    throw "AUTOLOGON_CLOSEOUT_CONTROLLER_HEAD_MISMATCH: expected '$ExpectedCurrentHead'; current '$localHead'."
}

$refresh = Join-Path $repoRoot 'scripts\Refresh-SasOperatorCommand.ps1'
if (-not (Test-Path -LiteralPath $refresh -PathType Leaf)) {
    throw "Canonical sas refresh implementation is missing: $refresh"
}

Write-Host ''
Write-Host '=== CURRENT MAIN PROVEN - STAGING SEALED AUTOLOGON RUNTIME ===' -ForegroundColor Cyan
Write-Host "Controller: $repoRoot"
Write-Host "HEAD: $localHead" -ForegroundColor Green

& $ps51 -NoLogo -NoProfile -ExecutionPolicy Bypass -File $refresh `
    -RepositoryRoot $repoRoot -Ref $Ref -RepoUrl $RepoUrl
$refreshExit = [int]$global:LASTEXITCODE
if ($refreshExit -ne 0) {
    throw "AUTOLOGON_CLOSEOUT_REFRESH_FAILED: sas refresh exited $refreshExit. No protected deployment handoff was generated."
}

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "AUTOLOGON_CLOSEOUT_MANIFEST_MISSING: $manifestPath"
}
try { $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw "AUTOLOGON_CLOSEOUT_MANIFEST_UNREADABLE: $($_.Exception.Message)" }

$preparedCommit = ([string]$manifest.prepared_commit).Trim().ToLowerInvariant()
if ([string]$manifest.schema_version -ne 'sas-autologon-short-runtime/v2' -or
    -not $preparedCommit.Equals($localHead, [StringComparison]::OrdinalIgnoreCase) -or
    [string]$manifest.preparation_network_classification -ne 'GUEST_INTERNET' -or
    [string]$manifest.runtime_git_transport -ne 'LOCAL_FILESYSTEM_ONLY' -or
    -not [bool]$manifest.runtime_remotes_removed -or
    [bool]$manifest.protected_bootstrap_git_network_allowed) {
    throw 'AUTOLOGON_CLOSEOUT_MANIFEST_INVALID: refreshed runtime manifest does not prove current-head Guest staging with protected Git disabled.'
}

$audit = Join-Path ([IO.Path]::GetFullPath($RuntimeRoot)) 'scripts\Test-SasAutoLogonRuntimeSeal.ps1'
if (-not (Test-Path -LiteralPath $audit -PathType Leaf)) {
    throw "Canonical full runtime seal audit is missing: $audit"
}

Write-Host ''
Write-Host '=== VERIFYING COMPLETE SEALED RUNTIME - NO TARGET CONTACT ===' -ForegroundColor Cyan
& $ps51 -NoLogo -NoProfile -ExecutionPolicy Bypass -File $audit `
    -RuntimeRoot $RuntimeRoot -ExpectedCommit $preparedCommit -ReceiptPath $verificationReceipt
$auditExit = [int]$global:LASTEXITCODE
if ($auditExit -ne 0) {
    throw "AUTOLOGON_CLOSEOUT_SEAL_AUDIT_FAILED: runtime audit exited $auditExit. No protected deployment handoff was generated."
}

$handoffGenerator = Join-Path $repoRoot 'scripts\New-SasAutoLogonDeploymentHandoff.ps1'
if (-not (Test-Path -LiteralPath $handoffGenerator -PathType Leaf)) {
    throw "AutoLogon closeout handoff generator is missing: $handoffGenerator"
}

& $ps51 -NoLogo -NoProfile -ExecutionPolicy Bypass -File $handoffGenerator `
    -ComputerName $target -PreparedCommit $preparedCommit -RuntimeRoot $RuntimeRoot `
    -OutputRoot $closeoutRoot -RuntimeVerificationReceipt $verificationReceipt
$handoffExit = [int]$global:LASTEXITCODE
if ($handoffExit -ne 0) {
    throw "AUTOLOGON_CLOSEOUT_HANDOFF_FAILED: handoff generator exited $handoffExit."
}

$readinessReceipt = Join-Path $closeoutRoot 'autologon-closeout-readiness.json'
if (-not (Test-Path -LiteralPath $readinessReceipt -PathType Leaf)) {
    throw "AUTOLOGON_CLOSEOUT_HANDOFF_MISSING: $readinessReceipt"
}
$readiness = Get-Content -LiteralPath $readinessReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$readiness.status -ne 'READY_FOR_PROTECTED_DEPLOYMENT' -or
    -not [bool]$readiness.runtime_seal_verified -or
    [string]$readiness.prepared_commit -ne $preparedCommit -or
    [string]$readiness.requested_target -ne $target) {
    throw 'AUTOLOGON_CLOSEOUT_HANDOFF_INVALID: generated readiness receipt does not match the verified preparation.'
}

Write-Host ''
Write-Host 'AUTOLOGON_CLOSEOUT_PREPARATION_COMPLETED' -ForegroundColor Green
Write-Host "Prepared commit: $preparedCommit" -ForegroundColor Green
Write-Host "Sealed runtime: $RuntimeRoot" -ForegroundColor Green
Write-Host "Target: $target"
Write-Host 'Target contact performed: false' -ForegroundColor Green
Write-Host 'Target mutation performed: false' -ForegroundColor Green
Write-Host "NEXT NETWORK: $($readiness.next_required_network)" -ForegroundColor Cyan
Write-Host "NEXT COMMAND: $($readiness.next_command)" -ForegroundColor Green
