#Requires -Version 5.1
<#
.SYNOPSIS
Launch the crash-safe AutoLogon field lane from a pre-staged short runtime.

.DESCRIPTION
Protected-network execution is deliberately local-only. This bootstrap never acquires repository data,
never updates the checkout, and never performs Git network I/O. The exact C:\SASAL runtime must already
have been staged by `sas refresh` while on Guest/Internet and sealed by
scripts\Prepare-SasAutoLogonShortRuntime.ps1.

The bootstrap verifies the local staging manifest, exact commit, clean worktree, and absence of Git remotes
before it establishes DomainAuthenticated VPN/LAN authority. It then runs the canonical protected-network
gate, resolves the requested target to its canonical FQDN, writes only that exact FQDN into the gitignored
operator-local host eligibility policy, and starts the crash-safe AutoLogon field transaction. The normal
field transaction independently repeats network, canonical resolution, and eligibility validation before
any target mutation.

Existing unexpected or dirty runtime content is never reset, cleaned, removed, or overwritten.
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

function Resolve-SasGitExecutable {
    foreach ($candidate in @(
        (Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),
        (Join-Path $env:ProgramFiles 'Git\bin\git.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and
            (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [IO.Path]::GetFullPath([string]$candidate)
        }
    }
    throw 'Git for Windows could not be resolved for local runtime verification.'
}

$script:SasGitExe = Resolve-SasGitExecutable

function Invoke-SasLocalGit {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage,
        [switch]$Quiet
    )

    $stderrPath = Join-Path $env:TEMP ('sas-local-git-' + [guid]::NewGuid().ToString('N') + '.err')
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $LASTEXITCODE = 0
        $stdout = @(& $script:SasGitExe -C $Root @Arguments 2> $stderrPath)
        $exitCode = [int]$LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    $stderr = if (Test-Path -LiteralPath $stderrPath) {
        try { (Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue).Trim() }
        finally { Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue }
    } else { '' }
    $stdoutText = (@($stdout | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()

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

function Get-SasLocalGitScalar {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )
    $lines = @(Invoke-SasLocalGit -Root $Root -Arguments $Arguments -FailureMessage $FailureMessage -Quiet)
    $value = [string]($lines | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($value)) { throw "$FailureMessage (empty git output)" }
    return $value.Trim()
}

function Resolve-SasLegacyEvidenceRoot {
    param([string]$RequestedRoot,[string]$Runtime)

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    foreach ($candidate in @($RequestedRoot, [string](Get-Location))) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $candidates.Contains($candidate)) {
            [void]$candidates.Add($candidate)
        }
    }

    $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
    if (-not [string]::IsNullOrWhiteSpace($desktop)) {
        $durable = Join-Path (Join-Path $desktop 'dev') 'SysAdminSuite'
        if (-not $candidates.Contains($durable)) { [void]$candidates.Add($durable) }
    }

    foreach ($candidate in $candidates) {
        try { $full = [IO.Path]::GetFullPath($candidate) } catch { continue }
        if ($full.TrimEnd('\').Equals($Runtime.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { continue }
        if (-not (Test-Path -LiteralPath $full -PathType Container)) { continue }
        if ((Test-Path -LiteralPath (Join-Path $full 'survey\output') -PathType Container) -or
            (Test-Path -LiteralPath (Join-Path $full 'Config') -PathType Container) -or
            (Test-Path -LiteralPath (Join-Path $full 'scripts\Invoke-SasAutoLogonFieldDeployment.ps1') -PathType Leaf)) {
            return $full
        }
    }
    return $null
}

$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$statePath = Join-Path (Join-Path $env:LOCALAPPDATA 'SysAdminSuite') 'autologon-short-runtime.json'

Write-Host 'PROTECTED AUTOLOGON RUNTIME VERIFICATION' -ForegroundColor Cyan
Write-Host "Short AutoLogon runtime: $RuntimeRoot"
Write-Host 'Git network I/O: DISABLED' -ForegroundColor Green
Write-Host 'Checkout mutation: DISABLED' -ForegroundColor Green

if (-not (Test-Path -LiteralPath $RuntimeRoot -PathType Container)) {
    throw "AUTOLOGON_RUNTIME_NOT_PREPARED: $RuntimeRoot does not exist. Run 'sas refresh' on Guest/Internet first."
}
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw "AUTOLOGON_RUNTIME_NOT_PREPARED: staging manifest missing: $statePath. Run 'sas refresh' on Guest/Internet first."
}

try { $runtimeState = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw "AUTOLOGON_RUNTIME_NOT_PREPARED: staging manifest is unreadable: $($_.Exception.Message)" }

if ([string]$runtimeState.schema_version -ne 'sas-autologon-short-runtime/v1') {
    throw "AUTOLOGON_RUNTIME_NOT_PREPARED: unsupported staging manifest schema: $($runtimeState.schema_version)"
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

$inside = Get-SasLocalGitScalar -Root $RuntimeRoot -Arguments @('rev-parse','--is-inside-work-tree') -FailureMessage 'Could not verify short runtime Git state.'
if ($inside -ne 'true') { throw "AUTOLOGON_RUNTIME_NOT_PREPARED: $RuntimeRoot is not a Git worktree." }

$runtimeHead = Get-SasLocalGitScalar -Root $RuntimeRoot -Arguments @('rev-parse','HEAD') -FailureMessage 'Could not resolve short runtime HEAD.'
$preparedCommit = ([string]$runtimeState.prepared_commit).Trim()
if ([string]::IsNullOrWhiteSpace($preparedCommit) -or $runtimeHead -ne $preparedCommit) {
    throw "AUTOLOGON_RUNTIME_NOT_PREPARED: runtime HEAD differs from sealed commit. Runtime=$runtimeHead Prepared=$preparedCommit"
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit) -and $runtimeHead -ne $ExpectedCommit.Trim()) {
    throw "AUTOLOGON_RUNTIME_COMMIT_MISMATCH: expected $($ExpectedCommit.Trim()); staged runtime is $runtimeHead. Refresh on Guest/Internet before protected deployment."
}

$dirty = @(Invoke-SasLocalGit -Root $RuntimeRoot -Arguments @('status','--porcelain') -FailureMessage 'Could not inspect short runtime worktree state.' -Quiet)
if (@($dirty | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
    $dirty | Out-Host
    throw "AUTOLOGON_RUNTIME_DIRTY: $RuntimeRoot contains local work. Nothing was reset or cleaned."
}
$remotes = @(Invoke-SasLocalGit -Root $RuntimeRoot -Arguments @('remote') -FailureMessage 'Could not inspect short runtime remotes.' -Quiet)
if (@($remotes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
    throw 'AUTOLOGON_RUNTIME_UNSEALED: protected deployment requires a runtime with no Git remotes. Run sas refresh on Guest/Internet.'
}

Write-Host "Prepared runtime HEAD: $runtimeHead" -ForegroundColor Green
Write-Host "Prepared on: $($runtimeState.preparation_network_classification) [$($runtimeState.preparation_network_label)]" -ForegroundColor Green
Write-Host 'PASS: no remote Git endpoint is configured in the protected runtime.' -ForegroundColor Green

$legacyRoot = Resolve-SasLegacyEvidenceRoot -RequestedRoot $LegacyEvidenceRoot -Runtime $RuntimeRoot
if ($legacyRoot) {
    $env:SAS_REPO_ROOT = $legacyRoot
    Write-Host "Legacy evidence fallback: $legacyRoot" -ForegroundColor Cyan
} else {
    Remove-Item Env:SAS_REPO_ROOT -ErrorAction SilentlyContinue
    Write-Host 'Legacy evidence fallback: none resolved.' -ForegroundColor DarkGray
}

$crashSafeScript = Join-Path $RuntimeRoot 'scripts\Invoke-SasAutoLogonCrashSafeFieldRun.ps1'
$onsiteScript = Join-Path $RuntimeRoot 'scripts\Invoke-SasAutoLogonOnsite.ps1'
$networkGate = Join-Path $RuntimeRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'
$networkBootstrap = Join-Path $RuntimeRoot 'scripts\Enable-SasNorthwellVpnNetworkGuard.ps1'
$targetModule = Join-Path $RuntimeRoot 'scripts\SasTargetNameResolution.psm1'
$hostAuthorizer = Join-Path $RuntimeRoot 'scripts\Set-SasHostEligibilityLocalTarget.ps1'
foreach ($required in @($crashSafeScript,$onsiteScript,$networkGate,$networkBootstrap,$targetModule,$hostAuthorizer)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required field deployment surface is missing: $required" }

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
} else {
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
Write-Host "Runtime HEAD: $runtimeHead" -ForegroundColor Green
Write-Host 'Protected-side repository network activity: NONE' -ForegroundColor Green

$LASTEXITCODE = 0
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $crashSafeScript `
    -ComputerName $ComputerName -RepositoryRoot $RuntimeRoot -ConfirmDeployment
$deploymentExit = [int]$LASTEXITCODE

$latestPointer = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\last-autologon-field-run.json'
Write-Host ''
Write-Host "Crash-safe latest pointer: $latestPointer" -ForegroundColor Cyan
Write-Host "Short runtime retained:     $RuntimeRoot" -ForegroundColor Cyan
Write-Host "Runtime commit:             $runtimeHead" -ForegroundColor Cyan

exit $deploymentExit
