#Requires -Version 5.1
<#
.SYNOPSIS
Verify that a sealed AutoLogon runtime is usable from the intended cross-user operator surface.

.DESCRIPTION
This verifier is local-only. It does not accept a target, contact a target, or start deployment.
It proves the current account is a true non-administrator when requested, can discover and execute the
machine-wide sas platform command, can use the bounded ignored runtime evidence root, can verify the exact
Public Desktop AutoLogon delegate, can resolve the machine-portable sealed manifest, and can pass the
canonical full runtime seal audit.

The Public Documents receipts are intentionally non-authoritative. Deployment continues to trust only
the existing sealed runtime, manifest authority, network gates, and crash-safe AutoLogon transaction.
#>
[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'C:\SASAL',
    [string]$InstallRoot,
    [string]$ReceiptRoot,
    [switch]$RequireStandardUser
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Test-SasPathContains {
    param(
        [AllowNull()][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$Expected
    )
    $expectedNormalized = $Expected.Trim().TrimEnd('\')
    foreach ($segment in @(([string]$PathValue) -split ';')) {
        $candidate = $segment.Trim().Trim('"').TrimEnd('\')
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and
            $candidate.Equals($expectedNormalized,[StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Test-SasReadableFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = $null
    try {
        $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        return $true
    }
    catch { return $false }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
}

function Get-SasSha256Hex {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    $stream = $null
    $sha256 = $null
    try {
        $stream = [IO.File]::Open(
            $LiteralPath,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::ReadWrite
        )
        $sha256 = [Security.Cryptography.SHA256]::Create()
        $bytes = $sha256.ComputeHash($stream)
        return ([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
    }
    finally {
        if ($null -ne $sha256) { $sha256.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

$programData = if ([string]::IsNullOrWhiteSpace([string]$env:ProgramData)) { 'C:\ProgramData' } else { $env:ProgramData }
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Join-Path $programData 'SysAdminSuite\bin'
}
else {
    $InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
}
$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$runRoot = Join-Path $RuntimeRoot 'runs'
$commonDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
if ([string]::IsNullOrWhiteSpace($commonDesktop)) { $commonDesktop = 'C:\Users\Public\Desktop' }
$commonDocuments = [Environment]::GetFolderPath('CommonDocuments')
if ([string]::IsNullOrWhiteSpace($commonDocuments)) { $commonDocuments = 'C:\Users\Public\Documents' }
if ([string]::IsNullOrWhiteSpace($ReceiptRoot)) {
    $ReceiptRoot = Join-Path $commonDocuments 'SysAdminSuite'
}
else {
    $ReceiptRoot = [IO.Path]::GetFullPath($ReceiptRoot)
}

$checks = New-Object 'System.Collections.Generic.List[object]'
function Add-SasReadinessCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Classification,
        [string]$Detail
    )
    [void]$script:checks.Add([pscustomobject][ordered]@{
        name = $Name
        passed = $Passed
        classification = $Classification
        detail = $Detail
    })
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$localAdministratorsSid = 'S-1-5-32-544'
$isLocalAdministratorMember = $false
foreach ($group in @($identity.Groups)) {
    if ($null -ne $group -and [string]$group.Value -eq $localAdministratorsSid) {
        $isLocalAdministratorMember = $true
        break
    }
}
if ($RequireStandardUser) {
    $standardUserReady = (-not $isAdministrator -and -not $isLocalAdministratorMember)
    Add-SasReadinessCheck -Name 'standard_user_token' -Passed $standardUserReady `
        -Classification $(if ($standardUserReady) { 'STANDARD_USER_TOKEN_CONFIRMED' } else { 'LOCAL_ADMINISTRATOR_ACCOUNT_NOT_ALLOWED' }) `
        -Detail 'RequireStandardUser rejects elevated tokens and UAC-filtered accounts that still belong to BUILTIN\Administrators.'
}
else {
    Add-SasReadinessCheck -Name 'token_posture_recorded' -Passed $true `
        -Classification $(if ($isAdministrator) { 'ADMINISTRATOR_TOKEN' } elseif ($isLocalAdministratorMember) { 'FILTERED_ADMINISTRATOR_TOKEN' } else { 'STANDARD_USER_TOKEN' }) `
        -Detail 'Token posture was recorded; use -RequireStandardUser for true non-administrator cross-user acceptance.'
}

$machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
$machinePathReady = Test-SasPathContains -PathValue $machinePath -Expected $InstallRoot
Add-SasReadinessCheck -Name 'machine_path' -Passed $machinePathReady `
    -Classification $(if ($machinePathReady) { 'MACHINE_PATH_READY' } else { 'MACHINE_PATH_MISSING' }) `
    -Detail 'Machine PATH must expose the installer-owned ProgramData launcher to new user sessions.'

$sasCmd = Join-Path $InstallRoot 'sas.cmd'
$networkAware = Join-Path $InstallRoot 'Invoke-SasNetworkAwareField.ps1'
$installedFilesReady = (Test-SasReadableFile -Path $sasCmd) -and (Test-SasReadableFile -Path $networkAware)
Add-SasReadinessCheck -Name 'machine_launcher_readable' -Passed $installedFilesReady `
    -Classification $(if ($installedFilesReady) { 'MACHINE_LAUNCHER_READABLE' } else { 'MACHINE_LAUNCHER_UNREADABLE' }) `
    -Detail 'Current token must be able to read the trusted installed launcher and network-aware entrypoint.'

$resolvedSas = Get-Command sas.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$resolvedSasPath = ''
if ($null -ne $resolvedSas) {
    if ($null -ne $resolvedSas.PSObject.Properties['Path']) { $resolvedSasPath = [string]$resolvedSas.Path }
    elseif ($null -ne $resolvedSas.PSObject.Properties['Source']) { $resolvedSasPath = [string]$resolvedSas.Source }
}
$processPathReady = (-not [string]::IsNullOrWhiteSpace($resolvedSasPath) -and
    ([IO.Path]::GetFullPath($resolvedSasPath)).Equals([IO.Path]::GetFullPath($sasCmd),[StringComparison]::OrdinalIgnoreCase))
Add-SasReadinessCheck -Name 'process_path_resolution' -Passed $processPathReady `
    -Classification $(if ($processPathReady) { 'PROCESS_PATH_RESOLVES_MACHINE_SAS' } else { 'PROCESS_PATH_NOT_REFRESHED' }) `
    -Detail 'Run from a new standard-user shell so process PATH resolves the ProgramData sas.cmd.'

$platformExit = 99
if ($installedFilesReady) {
    & $sasCmd platform | Out-Host
    $platformExit = [int]$global:LASTEXITCODE
}
$platformReady = ($platformExit -eq 0)
Add-SasReadinessCheck -Name 'standard_command_execution' -Passed $platformReady `
    -Classification $(if ($platformReady) { 'SAS_PLATFORM_EXECUTED' } else { 'SAS_PLATFORM_FAILED' }) `
    -Detail "Exact installed sas.cmd platform exit code: $platformExit"

$runRootWritable = $false
$runRootProbePath = ''
$runRootDetail = 'Bounded deployment run root is missing or not writable by the current token.'
try {
    if (-not (Test-Path -LiteralPath $runRoot -PathType Container)) {
        throw "Run root is missing: $runRoot"
    }
    $runRootProbePath = Join-Path $runRoot ('.sas-operator-readiness-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $probeText = 'SAS_AUTOLOGON_OPERATOR_READINESS_WRITE_PROBE'
    [IO.File]::WriteAllText($runRootProbePath,$probeText,(New-Object Text.UTF8Encoding($false)))
    $roundTrip = [IO.File]::ReadAllText($runRootProbePath,[Text.Encoding]::UTF8)
    if ($roundTrip -ne $probeText) { throw 'Run-root write probe did not round-trip exactly.' }
    Remove-Item -LiteralPath $runRootProbePath -Force -ErrorAction Stop
    if (Test-Path -LiteralPath $runRootProbePath -PathType Leaf) { throw 'Run-root write probe could not be removed.' }
    $runRootWritable = $true
    $runRootDetail = 'Create/write/read/delete probe succeeded inside the ignored C:\SASAL\runs evidence subtree.'
}
catch {
    $runRootDetail = "Run-root write probe failed: $($_.Exception.Message)"
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($runRootProbePath) -and (Test-Path -LiteralPath $runRootProbePath -PathType Leaf)) {
        Remove-Item -LiteralPath $runRootProbePath -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $runRootProbePath -PathType Leaf) {
            $runRootWritable = $false
            $runRootDetail = 'Run-root write probe cleanup failed; readiness is blocked.'
        }
    }
}
Add-SasReadinessCheck -Name 'deployment_run_root' -Passed $runRootWritable `
    -Classification $(if ($runRootWritable) { 'AUTOLOGON_RUN_ROOT_WRITABLE' } else { 'AUTOLOGON_RUN_ROOT_NOT_WRITABLE' }) `
    -Detail $runRootDetail

$desktopCmdPath = Join-Path $commonDesktop 'SysAdminSuite - AutoLogon Remote.cmd'
$canonicalDesktopDelegate = Join-Path $InstallRoot 'SasAutoLogonPublicDesktop.cmd'
$desktopDelegateHash = ''
$canonicalDelegateHash = ''
$desktopDelegateReady = $false
$desktopDelegateDetail = 'Public Desktop delegate or canonical installed template is unreadable.'
if ((Test-SasReadableFile -Path $desktopCmdPath) -and (Test-SasReadableFile -Path $canonicalDesktopDelegate)) {
    try {
        $desktopDelegateHash = Get-SasSha256Hex -LiteralPath $desktopCmdPath
        $canonicalDelegateHash = Get-SasSha256Hex -LiteralPath $canonicalDesktopDelegate
        $delegateText = [IO.File]::ReadAllText($canonicalDesktopDelegate,[Text.Encoding]::UTF8)
        $delegateMarkersReady = (
            $delegateText.Contains('set "SAS_AUTOLOGON_ENTRYPOINT=%ProgramData%\SysAdminSuite\bin\Invoke-SasNetworkAwareField.ps1"') -and
            $delegateText.Contains('$env:SAS_AUTOLOGON_TARGET') -and
            $delegateText.Contains("& `$env:SAS_AUTOLOGON_ENTRYPOINT 'autologon' 'Remote' `$t") -and
            -not $delegateText.Contains('-Confirm:$false') -and
            -not $delegateText.Contains('Get-Credential') -and
            -not $delegateText.Contains('Invoke-SasAutoLogonCrashSafeFieldRun.ps1')
        )
        $desktopDelegateReady = (
            $desktopDelegateHash.Equals($canonicalDelegateHash,[StringComparison]::OrdinalIgnoreCase) -and
            $delegateMarkersReady
        )
        $desktopDelegateDetail = if ($desktopDelegateReady) {
            "Exact SHA-256 match to canonical installed delegate: $desktopDelegateHash"
        }
        elseif (-not $delegateMarkersReady) {
            'Canonical installed delegate is missing the fixed network-aware AutoLogon Remote routing contract.'
        }
        else {
            "Public Desktop delegate hash mismatch. Expected=$canonicalDelegateHash Actual=$desktopDelegateHash"
        }
    }
    catch {
        $desktopDelegateDetail = "Delegate validation failed: $($_.Exception.Message)"
    }
}
Add-SasReadinessCheck -Name 'public_desktop_delegate' -Passed $desktopDelegateReady `
    -Classification $(if ($desktopDelegateReady) { 'PUBLIC_DESKTOP_DELEGATE_VERIFIED' } else { 'PUBLIC_DESKTOP_DELEGATE_INVALID' }) `
    -Detail $desktopDelegateDetail

$resolver = Join-Path $RuntimeRoot 'scripts\Resolve-SasAutoLogonManifestAuthority.ps1'
$sealAuditor = Join-Path $RuntimeRoot 'scripts\Test-SasAutoLogonRuntimeSeal.ps1'
$runtimeManifest = Join-Path $RuntimeRoot '.git\sas-autologon-short-runtime.json'
$runtimePrereqsReady = (Test-SasReadableFile -Path $resolver) -and
    (Test-SasReadableFile -Path $sealAuditor) -and
    (Test-SasReadableFile -Path $runtimeManifest)
Add-SasReadinessCheck -Name 'sealed_runtime_prerequisites' -Passed $runtimePrereqsReady `
    -Classification $(if ($runtimePrereqsReady) { 'SEALED_RUNTIME_PREREQUISITES_READABLE' } else { 'SEALED_RUNTIME_PREREQUISITES_UNREADABLE' }) `
    -Detail 'Current token must read the machine-portable manifest authority and canonical full seal auditor.'

$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$manifestExit = 99
if ($runtimePrereqsReady) {
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $resolver `
        -RuntimeRoot $RuntimeRoot -RequireManifest
    $manifestExit = [int]$global:LASTEXITCODE
}
$manifestReady = ($manifestExit -eq 0)
Add-SasReadinessCheck -Name 'manifest_authority' -Passed $manifestReady `
    -Classification $(if ($manifestReady) { 'MANIFEST_AUTHORITY_READY' } else { 'MANIFEST_AUTHORITY_FAILED' }) `
    -Detail "Machine-portable manifest resolver exit code: $manifestExit"

if (-not (Test-Path -LiteralPath $ReceiptRoot -PathType Container)) {
    try { New-Item -ItemType Directory -Path $ReceiptRoot -Force | Out-Null } catch { }
}
$sealReceiptPath = Join-Path $ReceiptRoot 'autologon-runtime-seal-verification.json'
$sealExit = 99
if ($runtimePrereqsReady -and $manifestReady) {
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $sealAuditor `
        -RuntimeRoot $RuntimeRoot -ManifestPath $runtimeManifest -ReceiptPath $sealReceiptPath
    $sealExit = [int]$global:LASTEXITCODE
}
$sealReceipt = $null
if ($sealExit -eq 0 -and (Test-Path -LiteralPath $sealReceiptPath -PathType Leaf)) {
    try { $sealReceipt = Get-Content -LiteralPath $sealReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $sealReceipt = $null }
}
$sealReady = ($null -ne $sealReceipt -and
    [string]$sealReceipt.classification -eq 'AUTOLOGON_RUNTIME_SEAL_VERIFIED' -and
    [string]$sealReceipt.status -eq 'PASS')
Add-SasReadinessCheck -Name 'full_runtime_seal' -Passed $sealReady `
    -Classification $(if ($sealReady) { 'AUTOLOGON_RUNTIME_SEAL_VERIFIED' } else { 'AUTOLOGON_RUNTIME_SEAL_NOT_VERIFIED' }) `
    -Detail "Canonical full-seal audit exit code: $sealExit"

$failedChecks = @($checks | Where-Object { -not $_.passed })
$allPassed = ($failedChecks.Count -eq 0)
$classification = if ($allPassed -and $RequireStandardUser) {
    'AUTOLOGON_OPERATOR_READINESS_VERIFIED'
}
elseif ($allPassed) {
    'AUTOLOGON_OPERATOR_READINESS_ADMIN_CHECK_VERIFIED'
}
else {
    'AUTOLOGON_OPERATOR_READINESS_FAILED'
}
$preparedCommit = if ($null -eq $sealReceipt) { $null } else { [string]$sealReceipt.prepared_commit }

$receipt = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-operator-readiness/v1'
    created_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    status = if ($allPassed) { 'PASS' } else { 'FAILED' }
    classification = $classification
    require_standard_user = [bool]$RequireStandardUser
    current_token_is_administrator = [bool]$isAdministrator
    current_account_is_local_administrator_member = [bool]$isLocalAdministratorMember
    install_root = $InstallRoot
    runtime_root = $RuntimeRoot
    deployment_run_root = $runRoot
    deployment_run_root_write_probe_passed = [bool]$runRootWritable
    public_desktop_command = $desktopCmdPath
    public_desktop_delegate_sha256 = if ([string]::IsNullOrWhiteSpace($desktopDelegateHash)) { $null } else { $desktopDelegateHash }
    seal_receipt_path = $sealReceiptPath
    prepared_commit = $preparedCommit
    check_count = $checks.Count
    failed_check_count = $failedChecks.Count
    checks = $checks
    receipt_is_authority = $false
    protected_git_activity = 'NONE'
    network_activity_performed = $false
    target_contact_performed = $false
    target_mutation_performed = $false
    deployment_started = $false
}

$receiptPath = Join-Path $ReceiptRoot 'autologon-operator-readiness.json'
try {
    if (-not (Test-Path -LiteralPath $ReceiptRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $ReceiptRoot -Force | Out-Null
    }
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
}
catch {
    Write-Error "AUTOLOGON_OPERATOR_READINESS_RECEIPT_WRITE_FAILED: $($_.Exception.Message)"
    exit 11
}

Write-Host "AutoLogon operator-readiness receipt: $receiptPath" -ForegroundColor Cyan
Write-Host "Runtime seal receipt: $sealReceiptPath" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "PASS: $classification" -ForegroundColor Green
    Write-Host 'No target was contacted and no AutoLogon deployment was started.' -ForegroundColor Green
    exit 0
}

Write-Host "FAILED: $classification ($($failedChecks.Count) failed check(s))." -ForegroundColor Red
foreach ($check in $failedChecks) {
    Write-Host ("  [{0}] {1}: {2}" -f $check.classification,$check.name,$check.detail) -ForegroundColor Yellow
}
Write-Host 'No target was contacted and no AutoLogon deployment was started.' -ForegroundColor Yellow
exit 10
