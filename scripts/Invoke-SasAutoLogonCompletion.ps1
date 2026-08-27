#Requires -Version 5.1
<#
.SYNOPSIS
Complete one AutoLogon deployment only after a fresh read-only transport admission succeeds.

.DESCRIPTION
Runs entirely from the already sealed machine-local AutoLogon runtime. Before any target contact it
resolves the runtime-local manifest authority and performs the canonical full SHA-256 seal audit. It
then establishes the exact active DomainAuthenticated VPN/LAN authority, proves the protected network,
canonicalizes the one explicit target, and runs one bounded read-only kerberos_smb_task preflight with
a VPN-tolerant 15-second per-observation budget.

Only a fresh kerberos_smb_task_ready result with no timeout and no target mutation may advance into the
existing sealed crash-safe AutoLogon bootstrap. The completion gate does not implement staging, package
installation, registry mutation, task creation, restart, or recovery itself.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [string]$RuntimeRoot = 'C:\SASAL',

    [ValidateRange(5,30)]
    [int]$PreflightTimeoutSeconds = 15
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$stateRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite'
$runtimeManifest = Join-Path $RuntimeRoot '.git\sas-autologon-short-runtime.json'
$manifestResolver = Join-Path $RuntimeRoot 'scripts\Resolve-SasAutoLogonManifestAuthority.ps1'
$sealAuditor = Join-Path $RuntimeRoot 'scripts\Test-SasAutoLogonRuntimeSeal.ps1'
$networkBootstrap = Join-Path $RuntimeRoot 'scripts\Enable-SasNorthwellVpnNetworkGuard.ps1'
$networkGate = Join-Path $RuntimeRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'
$targetModule = Join-Path $RuntimeRoot 'scripts\SasTargetNameResolution.psm1'
$transportPreflight = Join-Path $RuntimeRoot 'scripts\Test-SasSoftwareDeploymentTransport.ps1'
$deploymentBootstrap = Join-Path $RuntimeRoot 'Bootstrap-SysAdminSuiteAutoLogon.cmd'

foreach ($required in @(
    $manifestResolver,$sealAuditor,$networkBootstrap,$networkGate,$targetModule,$transportPreflight,$deploymentBootstrap
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "AUTOLOGON_COMPLETION_RUNTIME_INCOMPLETE: required sealed-runtime surface is missing: $required"
    }
}

New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

Write-Host ''
Write-Host '=== AUTOLOGON COMPLETION: SEALED RUNTIME ADMISSION ===' -ForegroundColor Cyan
Write-Host "Runtime: $RuntimeRoot"
Write-Host 'Git network activity: NONE' -ForegroundColor Green
Write-Host 'Target contact before seal audit: NONE' -ForegroundColor Green

$LASTEXITCODE = 0
& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $manifestResolver `
    -RuntimeRoot $RuntimeRoot -RequireManifest
if ($LASTEXITCODE -ne 0) {
    throw "AUTOLOGON_COMPLETION_MANIFEST_BLOCKED: manifest authority resolver exited $LASTEXITCODE."
}
if (-not (Test-Path -LiteralPath $runtimeManifest -PathType Leaf)) {
    throw "AUTOLOGON_COMPLETION_MANIFEST_BLOCKED: runtime-local manifest was not hydrated: $runtimeManifest"
}

try { $runtimeState = Get-Content -LiteralPath $runtimeManifest -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw "AUTOLOGON_COMPLETION_MANIFEST_BLOCKED: runtime-local manifest is unreadable: $($_.Exception.Message)" }
$preparedCommit = ([string]$runtimeState.prepared_commit).Trim()
if ([string]::IsNullOrWhiteSpace($preparedCommit)) {
    throw 'AUTOLOGON_COMPLETION_MANIFEST_BLOCKED: prepared commit is missing.'
}

$sealReceipt = Join-Path $stateRoot 'autologon-completion-runtime-seal.json'
$LASTEXITCODE = 0
& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $sealAuditor `
    -RuntimeRoot $RuntimeRoot -ManifestPath $runtimeManifest -ReceiptPath $sealReceipt -ExpectedCommit $preparedCommit
if ($LASTEXITCODE -ne 0) {
    throw "AUTOLOGON_COMPLETION_RUNTIME_SEAL_BLOCKED: full seal audit exited $LASTEXITCODE."
}

Write-Host ''
Write-Host '=== AUTOLOGON COMPLETION: CURRENT PROTECTED AUTHORITY ===' -ForegroundColor Cyan
$authority = @(& $networkBootstrap -ConfirmVpnPosture) | Select-Object -Last 1
if ($null -eq $authority -or [string]$authority.classification -ne 'SAS_VPN_NETWORK_GUARD_READY') {
    throw 'AUTOLOGON_COMPLETION_NETWORK_BLOCKED: exact DomainAuthenticated VPN/LAN authority was not established.'
}
if ([bool]$authority.target_contact_performed -or [bool]$authority.target_mutation_performed) {
    throw 'AUTOLOGON_COMPLETION_NETWORK_BLOCKED: network-authority bootstrap violated the no-target-contact contract.'
}
$authorityConfig = [string]$authority.config_path
if ([string]::IsNullOrWhiteSpace($authorityConfig) -or -not (Test-Path -LiteralPath $authorityConfig -PathType Leaf)) {
    throw "AUTOLOGON_COMPLETION_NETWORK_BLOCKED: exact network-guard config is unavailable: $authorityConfig"
}
$env:SAS_NETWORK_GUARD_CONFIG = $authorityConfig

$LASTEXITCODE = 0
& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $networkGate `
    -Purpose "AutoLogon completion preflight for $ComputerName" -NonInteractive
if ($LASTEXITCODE -ne 0) {
    throw "AUTOLOGON_COMPLETION_NETWORK_BLOCKED: canonical protected-network gate exited $LASTEXITCODE."
}

Import-Module $targetModule -Force
$resolution = Resolve-SasCanonicalTargetFqdn -TargetName $ComputerName
if (@($resolution.addresses).Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$resolution.fqdn)) {
    throw 'AUTOLOGON_COMPLETION_TARGET_BLOCKED: canonical target resolution returned no usable FQDN/address.'
}
$resolvedTarget = [string]$resolution.fqdn

Write-Host ''
Write-Host '=== AUTOLOGON COMPLETION: FRESH READ-ONLY TRANSPORT ADMISSION ===' -ForegroundColor Cyan
Write-Host "Canonical target: $resolvedTarget"
Write-Host "Per-observation timeout: $PreflightTimeoutSeconds seconds"
Write-Host 'Target mutation allowed by this gate: NO' -ForegroundColor Green

$preflightRoot = Join-Path $RuntimeRoot 'runs\autologon-completion-preflight'
New-Item -ItemType Directory -Path $preflightRoot -Force | Out-Null
$preflight = & $transportPreflight -ComputerName $resolvedTarget -AllowNetworkActivity `
    -TransportIntent kerberos_smb_task -TimeoutSeconds $PreflightTimeoutSeconds `
    -OutputRoot $preflightRoot -PassThru

if ($null -eq $preflight -or $null -eq $preflight.result) {
    throw 'AUTOLOGON_COMPLETION_TRANSPORT_BLOCKED: canonical preflight returned no structured result.'
}
if ([bool]$preflight.result.target_mutation_performed) {
    throw 'AUTOLOGON_COMPLETION_TRANSPORT_BLOCKED: read-only preflight unexpectedly reported target mutation.'
}

$classification = [string]$preflight.result.decision.classification
$timeoutStage = [string]$preflight.probe_diagnostic.timeout_stage
Write-Host "Transport classification: $classification"
Write-Host ("Transport timeout stage: {0}" -f $(if ([string]::IsNullOrWhiteSpace($timeoutStage)) { 'none' } else { $timeoutStage }))
Write-Host "Transport result: $($preflight.result_path)"
Write-Host "Transport summary: $($preflight.english_summary_path)"

if ($classification -ne 'kerberos_smb_task_ready' -or -not [string]::IsNullOrWhiteSpace($timeoutStage)) {
    Write-Host ''
    Write-Host 'AUTOLOGON_COMPLETION_TRANSPORT_BLOCKED' -ForegroundColor Yellow
    if (Test-Path -LiteralPath $preflight.english_summary_path -PathType Leaf) {
        Get-Content -LiteralPath $preflight.english_summary_path -Encoding UTF8 | Out-Host
    }
    Write-Host 'No AutoLogon deployment bootstrap was started by the completion gate.' -ForegroundColor Yellow
    exit 21
}

Write-Host ''
Write-Host 'AUTOLOGON_COMPLETION_PREFLIGHT_READY' -ForegroundColor Green
Write-Host 'Fresh read-only Kerberos SMB + Task Scheduler admission passed; entering the existing sealed crash-safe deployment.' -ForegroundColor Green
Write-Host "Prepared runtime commit: $preparedCommit" -ForegroundColor Green

# Carry the exact current network-guard file into the existing bootstrap process tree. The bootstrap
# still re-resolves manifest/seal/network/target authority and its field transaction independently
# repeats transport admission before any mutation.
$env:SAS_EXPLICIT_REMOTE_TARGET_REQUEST = $ComputerName
& $deploymentBootstrap $ComputerName $preparedCommit
$deploymentExit = [int]$LASTEXITCODE

if ($deploymentExit -eq 0) {
    Write-Host ''
    Write-Host 'AUTOLOGON_COMPLETION_COMMAND_FINISHED' -ForegroundColor Green
}
else {
    Write-Host ''
    Write-Host "AUTOLOGON_COMPLETION_DEPLOYMENT_STOPPED: sealed crash-safe bootstrap exited $deploymentExit." -ForegroundColor Yellow
}
exit $deploymentExit
