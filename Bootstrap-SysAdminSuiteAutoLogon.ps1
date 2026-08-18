#Requires -Version 5.1
<#
.SYNOPSIS
Launch the crash-safe AutoLogon field lane from a pre-staged short runtime.

.DESCRIPTION
Protected-network execution is deliberately Git-free. This bootstrap never invokes Git, never acquires
repository data, and never mutates checkout state after the operator transitions to the protected network.
The exact C:\SASAL runtime must already have been staged by `sas refresh` while on Guest/Internet and
sealed by scripts\Prepare-SasAutoLogonShortRuntime.ps1.

The bootstrap verifies the local staging manifest, exact prepared commit, and SHA-256 hashes for every
tracked runtime file using ordinary filesystem APIs. It then establishes DomainAuthenticated VPN/LAN
authority, runs the canonical protected-network gate, and starts the crash-safe AutoLogon field transaction.
The normal field transaction independently repeats network, canonical resolution, and eligibility validation
before any target mutation.

Legacy evidence fallback is opt-in only through -LegacyEvidenceRoot. The protected runtime never scans the
operator Desktop/OneDrive tree to discover another checkout implicitly.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [string]$RuntimeRoot = 'C:\SASAL',

    [string]$LegacyEvidenceRoot,

    [string]$ExpectedCommit,

    [switch]$ConfirmLocalTargetAuthorization,

    [switch]$ConfirmVpnPosture
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$statePath = Join-Path (Join-Path $env:LOCALAPPDATA 'SysAdminSuite') 'autologon-short-runtime.json'

Write-Host 'PROTECTED AUTOLOGON RUNTIME VERIFICATION' -ForegroundColor Cyan
Write-Host "Short AutoLogon runtime: $RuntimeRoot"
Write-Host 'Git activity after protected-network transition: NONE' -ForegroundColor Green
Write-Host 'Checkout mutation: DISABLED' -ForegroundColor Green

if (-not (Test-Path -LiteralPath $RuntimeRoot -PathType Container)) {
    throw "AUTOLOGON_RUNTIME_NOT_PREPARED: $RuntimeRoot does not exist. Run 'sas refresh' on Guest/Internet first."
}
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw "AUTOLOGON_RUNTIME_NOT_PREPARED: staging manifest missing: $statePath. Run 'sas refresh' on Guest/Internet first."
}

try { $runtimeState = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw "AUTOLOGON_RUNTIME_NOT_PREPARED: staging manifest is unreadable: $($_.Exception.Message)" }

if ([string]$runtimeState.schema_version -ne 'sas-autologon-short-runtime/v2') {
    throw "AUTOLOGON_RUNTIME_NOT_PREPARED: unsupported staging manifest schema: $($runtimeState.schema_version). Refresh on Guest/Internet to create a Git-free protected-runtime seal."
}

$manifestRoot = [IO.Path]::GetFullPath([string]$runtimeState.runtime_root)
if (-not $manifestRoot.TrimEnd('\').Equals($RuntimeRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
    throw "AUTOLOGON_RUNTIME_NOT_PREPARED: manifest runtime mismatch. Manifest=$manifestRoot Runtime=$RuntimeRoot"
}
if ([string]$runtimeState.preparation_network_classification -ne 'GUEST_INTERNET') {
    throw "AUTOLOGON_RUNTIME_NOT_PREPARED: runtime was not sealed on Guest/Internet. Classification=$($runtimeState.preparation_network_classification)"
}
if ([string]$runtimeState.runtime_git_transport -ne 'LOCAL_FILESYSTEM_ONLY' -or
    -not [bool]$runtimeState.runtime_remotes_removed -or
    [bool]$runtimeState.protected_bootstrap_git_network_allowed) {
    throw 'AUTOLOGON_RUNTIME_NOT_PREPARED: staging manifest does not prove local-only sealed runtime posture.'
}

$preparedCommit = ([string]$runtimeState.prepared_commit).Trim()
if ([string]::IsNullOrWhiteSpace($preparedCommit)) {
    throw 'AUTOLOGON_RUNTIME_NOT_PREPARED: staging manifest has no prepared commit.'
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit) -and $preparedCommit -ne $ExpectedCommit.Trim()) {
    throw "AUTOLOGON_RUNTIME_COMMIT_MISMATCH: expected $($ExpectedCommit.Trim()); staged runtime is $preparedCommit. Refresh on Guest/Internet before protected deployment."
}

if ([string]$runtimeState.tracked_file_hash_algorithm -ne 'SHA256') {
    throw "AUTOLOGON_RUNTIME_NOT_PREPARED: unsupported tracked-file hash algorithm: $($runtimeState.tracked_file_hash_algorithm)"
}
$sealEntries = @($runtimeState.tracked_file_hashes)
$declaredSealCount = [int]$runtimeState.tracked_file_count
if ($declaredSealCount -lt 1 -or $sealEntries.Count -ne $declaredSealCount) {
    throw "AUTOLOGON_RUNTIME_NOT_PREPARED: tracked-file seal count mismatch. Declared=$declaredSealCount Actual=$($sealEntries.Count)"
}

$runtimePrefix = $RuntimeRoot.TrimEnd('\') + '\'
$verifiedCount = 0
foreach ($entry in $sealEntries) {
    $relative = [string]$entry.path
    $expectedHash = ([string]$entry.sha256).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative)) {
        throw "AUTOLOGON_RUNTIME_SEAL_INVALID: invalid tracked path '$relative'."
    }
    if ($expectedHash -notmatch '^[0-9a-f]{64}$') {
        throw "AUTOLOGON_RUNTIME_SEAL_INVALID: invalid SHA-256 for '$relative'."
    }

    $relativeWindows = $relative.Replace('/', '\')
    try { $fullPath = [IO.Path]::GetFullPath((Join-Path $RuntimeRoot $relativeWindows)) }
    catch { throw "AUTOLOGON_RUNTIME_SEAL_INVALID: invalid tracked path '$relative': $($_.Exception.Message)" }

    if (-not $fullPath.StartsWith($runtimePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "AUTOLOGON_RUNTIME_SEAL_INVALID: tracked path escapes runtime root: '$relative'."
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "AUTOLOGON_RUNTIME_SEAL_MISMATCH: tracked runtime file is missing: $relative"
    }

    $actualHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "AUTOLOGON_RUNTIME_SEAL_MISMATCH: tracked runtime file changed after Guest staging: $relative"
    }
    $verifiedCount++
}

Write-Host "Prepared runtime commit: $preparedCommit" -ForegroundColor Green
Write-Host "Prepared on: $($runtimeState.preparation_network_classification) [$($runtimeState.preparation_network_label)]" -ForegroundColor Green
Write-Host "PASS: sealed tracked runtime content verified without Git ($verifiedCount files)." -ForegroundColor Green
Write-Host 'PASS: staging manifest records runtime remotes removed before protected transition.' -ForegroundColor Green

if (-not [string]::IsNullOrWhiteSpace($LegacyEvidenceRoot)) {
    try { $legacyRoot = [IO.Path]::GetFullPath($LegacyEvidenceRoot) }
    catch { throw "Legacy evidence root is invalid: $LegacyEvidenceRoot" }
    if (-not (Test-Path -LiteralPath $legacyRoot -PathType Container)) {
        throw "Explicit legacy evidence root does not exist: $legacyRoot"
    }
    if ($legacyRoot.TrimEnd('\').Equals($RuntimeRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Legacy evidence root must be different from the protected runtime.'
    }
    $env:SAS_REPO_ROOT = $legacyRoot
    Write-Host "Legacy evidence fallback: $legacyRoot" -ForegroundColor Cyan
}
else {
    Remove-Item Env:SAS_REPO_ROOT -ErrorAction SilentlyContinue
    Write-Host 'Legacy evidence fallback: disabled.' -ForegroundColor DarkGray
}

$crashSafeScript = Join-Path $RuntimeRoot 'scripts\Invoke-SasAutoLogonCrashSafeFieldRun.ps1'
$onsiteScript = Join-Path $RuntimeRoot 'scripts\Invoke-SasAutoLogonOnsite.ps1'
$networkGate = Join-Path $RuntimeRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'
$networkBootstrap = Join-Path $RuntimeRoot 'scripts\Enable-SasNorthwellVpnNetworkGuard.ps1'
$targetModule = Join-Path $RuntimeRoot 'scripts\SasTargetNameResolution.psm1'
$hostAuthorizer = Join-Path $RuntimeRoot 'scripts\Set-SasHostEligibilityLocalTarget.ps1'
foreach ($required in @($crashSafeScript,$onsiteScript,$networkGate,$networkBootstrap,$targetModule,$hostAuthorizer)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required field deployment surface is missing: $required"
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($required,[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        $parseErrors | Format-List * | Out-Host
        throw "PowerShell parser gate failed: $required"
    }
}

if ($ConfirmVpnPosture) {
    Write-Host ''
    Write-Host 'ESTABLISHING EXACT CURRENT DOMAIN-AUTHENTICATED VPN/LAN AUTHORITY' -ForegroundColor Cyan
    $authority = @(& $networkBootstrap -ConfirmVpnPosture) | Select-Object -Last 1
    if ($null -eq $authority) { throw 'Domain transport authority bootstrap returned no structured result.' }
    if ([string]$authority.classification -ne 'SAS_VPN_NETWORK_GUARD_READY') {
        throw "Domain transport authority bootstrap did not complete: $($authority.classification)"
    }
    if ([bool]$authority.target_contact_performed -or [bool]$authority.target_mutation_performed) {
        throw 'Domain transport authority bootstrap violated the no-target-contact safety contract.'
    }
    $authorityConfig = [string]$authority.config_path
    if ([string]::IsNullOrWhiteSpace($authorityConfig) -or -not (Test-Path -LiteralPath $authorityConfig -PathType Leaf)) {
        throw "Domain transport authority config was not created: $authorityConfig"
    }
    $env:SAS_NETWORK_GUARD_CONFIG = $authorityConfig
    Write-Host "Exact current domain transport authority activated: $authorityConfig" -ForegroundColor Green
    Write-Host 'The canonical field guard will independently verify this posture before target contact.' -ForegroundColor Green
}
else {
    Remove-Item Env:SAS_NETWORK_GUARD_CONFIG -ErrorAction SilentlyContinue
}

if ($ConfirmLocalTargetAuthorization) {
    if (-not $ConfirmVpnPosture) {
        throw 'Exact canonical target authorization requires -ConfirmVpnPosture so protected-network admission precedes DNS resolution.'
    }

    Write-Host ''
    Write-Host 'PROVING NETWORK BEFORE CANONICAL TARGET AUTHORIZATION' -ForegroundColor Cyan
    $LASTEXITCODE = 0
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $networkGate `
        -Purpose "AutoLogon bootstrap authorization for $ComputerName"
    if ($LASTEXITCODE -ne 0) {
        throw "Canonical target authorization stopped by the protected network gate with exit code $LASTEXITCODE."
    }

    Import-Module $targetModule -Force
    $authorizationResolution = Resolve-SasCanonicalTargetFqdn -TargetName $ComputerName
    if (@($authorizationResolution.addresses).Count -lt 1) {
        throw 'Canonical target authorization resolution returned no address.'
    }
    $resolvedAuthorizationTarget = [string]$authorizationResolution.fqdn
    if ([string]::IsNullOrWhiteSpace($resolvedAuthorizationTarget)) {
        throw 'Canonical target authorization resolution returned an empty FQDN.'
    }

    Write-Host ''
    Write-Host 'AUTHORIZING EXACT CANONICAL AUTOLOGON TARGET' -ForegroundColor Cyan
    $authorization = & $hostAuthorizer -Target $resolvedAuthorizationTarget -ExecContext remote `
        -RepoRoot $RuntimeRoot -ConfirmLocalAuthorization -PassThru
    if ($null -eq $authorization -or -not [bool]$authorization.eligible -or
        [string]$authorization.decision -ne 'allowed') {
        throw "Exact canonical target authorization failed for $resolvedAuthorizationTarget."
    }
    Write-Host "Canonical target authorized: $resolvedAuthorizationTarget" -ForegroundColor Green
    Write-Host "Operator-local policy: $($authorization.policy_path)" -ForegroundColor Green
    Write-Host 'The field transaction will independently re-resolve and revalidate this exact target.' -ForegroundColor Green
}

Write-Host ''
Write-Host 'PRE-STAGED RUNTIME VERIFIED - STARTING CRASH-SAFE AUTOLOGON FIELD TRANSACTION' -ForegroundColor Green
Write-Host "Runtime commit: $preparedCommit" -ForegroundColor Green
Write-Host 'Protected-side Git activity: NONE' -ForegroundColor Green

$LASTEXITCODE = 0
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $crashSafeScript `
    -ComputerName $ComputerName -RepositoryRoot $RuntimeRoot -RepositoryHead $preparedCommit -ConfirmDeployment
$deploymentExit = [int]$LASTEXITCODE

$latestPointer = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\last-autologon-field-run.json'
Write-Host ''
Write-Host "Crash-safe latest pointer: $latestPointer" -ForegroundColor Cyan
Write-Host "Short runtime retained:     $RuntimeRoot" -ForegroundColor Cyan
Write-Host "Runtime commit:             $preparedCommit" -ForegroundColor Cyan

exit $deploymentExit
