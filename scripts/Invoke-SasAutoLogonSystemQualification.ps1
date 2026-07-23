#Requires -Version 5.1
<#
.SYNOPSIS
Qualifies one materially different AutoLogon package candidate for canonical LocalSystem execution.
.DESCRIPTION
The currently approved no-argument AutoLogon EXE returned exit code 0 as LocalSystem without
setting AutoAdminLogon=1. This lane therefore refuses the identical hash-and-arguments candidate.
It requires one exact Cybernet FQDN, a fresh Kerberos SMB scheduled-task preflight, a harmless
transport live cert, a clean read-only baseline, the canonical AutoLogon final-step gate, one
validated SYSTEM execution, post-install state capture, and complete task/staging teardown.

A successful pilot emits a qualification receipt but does not automatically promote the candidate
into the approved catalogs. Reboot and automatic sign-in remain separate runtime proof gates.
#>
[CmdletBinding(DefaultParameterSetName = 'Operator')]
param(
    [ValidateSet('Menu','Plan','Live','OpenLatest','Fixture')]
    [string]$Action = 'Menu',

    [Parameter(Mandatory = $false, ParameterSetName = 'Operator')]
    [string]$QualificationRequestPath,

    [Parameter(Mandatory = $false, ParameterSetName = 'Operator')]
    [switch]$AllowNetworkActivity,

    [Parameter(Mandatory = $false, ParameterSetName = 'Operator')]
    [switch]$AllowTargetMutation,

    [Parameter(Mandatory = $false, ParameterSetName = 'Operator')]
    [switch]$ConfirmQualification,

    [Parameter(Mandatory = $false, ParameterSetName = 'Fixture')]
    [switch]$FixtureMode,

    [Parameter(Mandatory = $false, ParameterSetName = 'Fixture')]
    [ValidateSet('success','same_failed_candidate','dirty_baseline','unsupported_postcondition','cleanup_failure')]
    [string]$FixtureScenario = 'success',

    [ValidateRange(1, 1440)]
    [int]$PreflightMaxAgeMinutes = 15,

    [ValidateRange(10, 600)]
    [int]$StateResultTimeoutSeconds = 120,

    [ValidateRange(10, 7200)]
    [int]$DeploymentResultTimeoutSeconds = 1800,

    [string]$OutputRoot,
    [switch]$PassThru,
    [switch]$NoOpen
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasQualificationProperty {
    param($Value, [Parameter(Mandatory = $true)][string]$Name, $Default = $null)
    if ($null -eq $Value) { return $Default }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Write-SasQualificationJson {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Test-SasQualificationFqdn {
    param([string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and
        $Value -match '^(?=.{1,253}$)(?=.{1,63}\.)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$')
}

function Resolve-SasQualificationInputPath {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$RepoRoot)
    $candidate = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) }
        else { [IO.Path]::GetFullPath((Join-Path $RepoRoot $Path)) }
    $approvedRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'survey\input\autologon-system-qualification')).TrimEnd('\')
    if (-not $candidate.StartsWith($approvedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Qualification requests must remain under survey/input/autologon-system-qualification.'
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw "Qualification request not found: $candidate" }
    return $candidate
}

function Resolve-SasQualificationApprovedShareRoot {
    param(
        [Parameter(Mandatory = $true)][string]$ShareRoot,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )
    $normalized = $ShareRoot.Trim().Replace('/', '\')
    if ($normalized -notmatch '^\\\\[^\\]+\\?$') { throw 'software_share_root must be a UNC server root.' }
    $normalized = $normalized.TrimEnd('\') + '\'

    $manifestPath = Join-Path $RepoRoot 'harness\api\sas-harness-api.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $approvedRoots = @($manifest.posture.approved_software_sources | ForEach-Object {
        ([string]$_).Trim().Replace('/', '\').TrimEnd('\') + '\'
    } | Sort-Object -Unique)
    if (@($approvedRoots | Where-Object {
        $_.Equals($normalized, [StringComparison]::OrdinalIgnoreCase)
    }).Count -ne 1) {
        throw "software_share_root is not approved by the harness API: $normalized"
    }
    return $normalized
}

function Resolve-SasQualificationTargetIdentity {
    param([Parameter(Mandatory = $true)][string]$TargetFqdn)
    $resolution = Resolve-SasCanonicalTargetFqdn -TargetName $TargetFqdn
    if (-not ([string]$resolution.fqdn).Equals(
        $TargetFqdn.Trim().TrimEnd('.'),
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'DNS returned a canonical target identity that differs from the approved FQDN.'
    }
    if (@($resolution.addresses).Count -ne 1) {
        throw 'The approved FQDN must resolve to exactly one target address for this one-target qualification.'
    }
    return $resolution
}

function Test-SasQualificationSnapshotIdentity {
    param(
        $Snapshot,
        [Parameter(Mandatory = $true)]$TargetResolution
    )
    if ($null -eq $Snapshot) { return $false }
    $expectedShort = [string]$TargetResolution.short_name
    $observedShort = [string]$Snapshot.computer_name
    $requestedTarget = [string]$Snapshot.requested_target
    return ($observedShort.Equals($expectedShort, [StringComparison]::OrdinalIgnoreCase) -and
        $requestedTarget.Trim().TrimEnd('.').Equals(
            [string]$TargetResolution.fqdn,
            [StringComparison]::OrdinalIgnoreCase
        ))
}

function Read-SasQualificationRequest {
    param([Parameter(Mandatory = $true)][string]$Path)
    try { $request = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Qualification request is malformed JSON: $($_.Exception.Message)" }

    $required = @(
        'schema_version','candidate_id','package_version','target_fqdn','software_share_root',
        'installer_relative_path','installer_sha256','installer_arguments','installer_arguments_reference',
        'failed_invocation','authorization','signature'
    )
    $unknown = @($request.PSObject.Properties.Name | Where-Object { $required -notcontains $_ })
    if ($unknown.Count -gt 0) { throw "Qualification request contains unknown fields: $($unknown -join ', ')" }
    foreach ($name in $required) {
        if ($request.PSObject.Properties.Name -notcontains $name) { throw "Qualification request is missing field: $name" }
    }
    if ([string]$request.schema_version -ne 'sas-autologon-system-qualification-request/v1') { throw 'Qualification request schema is unsupported.' }
    if ([string]$request.candidate_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{2,96}$') { throw 'candidate_id is invalid.' }
    if ([string]::IsNullOrWhiteSpace([string]$request.package_version) -or [string]$request.package_version -match '(?i)^replace') { throw 'A real package_version is required.' }
    if (-not (Test-SasQualificationFqdn -Value ([string]$request.target_fqdn))) { throw 'target_fqdn must be the one exact authorized FQDN.' }
    if ([string]$request.software_share_root -notmatch '^\\\\[^\\]+\\?$') { throw 'software_share_root must be a UNC server root.' }
    $relative = ([string]$request.installer_relative_path).Trim().Replace('/', '\')
    if ([IO.Path]::IsPathRooted($relative) -or $relative.StartsWith('\') -or $relative -match '(^|\\)\.\.(\\|$)') { throw 'installer_relative_path is invalid.' }
    if ([string]$request.installer_sha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'installer_sha256 must contain 64 hexadecimal characters.' }
    if ($request.installer_arguments -isnot [System.Array] -or @($request.installer_arguments).Count -gt 32) { throw 'installer_arguments must be an array with at most 32 entries.' }
    if (@($request.installer_arguments | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
        throw 'installer_arguments contains an empty or non-string value.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$request.installer_arguments_reference) -or
        [string]$request.installer_arguments_reference -match '(?i)^replace|guess|assumed') {
        throw 'installer_arguments_reference must identify vendor documentation or the package owner decision.'
    }
    if ($request.failed_invocation -isnot [pscustomobject] -or
        $request.failed_invocation.PSObject.Properties.Name.Count -ne 2 -or
        $request.failed_invocation.PSObject.Properties.Name -notcontains 'installer_sha256' -or
        $request.failed_invocation.PSObject.Properties.Name -notcontains 'installer_arguments') {
        throw 'failed_invocation must contain only installer_sha256 and installer_arguments.'
    }
    if ([string]$request.failed_invocation.installer_sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
        $request.failed_invocation.installer_arguments -isnot [System.Array]) {
        throw 'failed_invocation identity is invalid.'
    }
    foreach ($field in @('authorized_by','request_reference','change_reference','ticket_reference')) {
        if ($request.authorization.PSObject.Properties.Name -notcontains $field -or
            [string]::IsNullOrWhiteSpace([string]$request.authorization.$field) -or
            [string]$request.authorization.$field -match '(?i)^replace') {
            throw "authorization.$field is required."
        }
    }
    if ($request.signature.PSObject.Properties.Name -notcontains 'require_valid_signature' -or
        $request.signature.require_valid_signature -isnot [bool] -or
        $request.signature.PSObject.Properties.Name -notcontains 'expected_signer_thumbprint') {
        throw 'signature must contain require_valid_signature and expected_signer_thumbprint.'
    }
    if ([bool]$request.signature.require_valid_signature -and
        [string]$request.signature.expected_signer_thumbprint -notmatch '^[A-Fa-f0-9]{40,64}$') {
        throw 'A valid expected_signer_thumbprint is required when signature validation is enabled.'
    }

    $candidateArguments = @($request.installer_arguments | ForEach-Object { [string]$_ })
    $failedArguments = @($request.failed_invocation.installer_arguments | ForEach-Object { [string]$_ })
    $sameHash = ([string]$request.installer_sha256).Equals([string]$request.failed_invocation.installer_sha256, [StringComparison]::OrdinalIgnoreCase)
    $sameArguments = (($candidateArguments | ConvertTo-Json -Compress) -eq ($failedArguments | ConvertTo-Json -Compress))
    if ($sameHash -and $sameArguments) {
        throw 'Candidate is identical to the failed LocalSystem hash-and-arguments invocation. Repeating it is forbidden.'
    }
    return $request
}

function Test-SasQualificationCaptureComplete {
    param($Lifecycle)
    return ($null -ne $Lifecycle -and [string]$Lifecycle.status -eq 'completed' -and
        [bool]$Lifecycle.worker.executed_as_system -and [bool]$Lifecycle.worker.hash_verified -and
        [bool]$Lifecycle.result_retrieval.succeeded -and [bool]$Lifecycle.cleanup.task_deletion_succeeded -and
        [bool]$Lifecycle.cleanup.run_root_deletion_succeeded -and -not [bool]$Lifecycle.cleanup.task_remaining -and
        -not [bool]$Lifecycle.cleanup.run_root_remaining)
}

function Test-SasQualificationCleanBaseline {
    param($Snapshot)
    if ($null -eq $Snapshot -or [string]$Snapshot.autologon.status -ne 'not_configured') { return $false }
    $existing = @($Snapshot.installed_software | Where-Object { [string]$_.name -match '(?i)NW\s+AutoLogon\s+Setup' })
    return ($existing.Count -eq 0)
}

function Get-SasLatestQualificationRoot {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $null }
    $latest = Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($latest) { return $latest.FullName }
    return $null
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$policyPath = Join-Path $repoRoot 'configs\software-packages\autologon-system-qualification.json'
$requestDirectory = Join-Path $repoRoot 'survey\input\autologon-system-qualification'
$templatePath = Join-Path $repoRoot 'configs\software-packages\autologon-system-qualification-request.example.json'
$stateModulePath = Join-Path $PSScriptRoot 'SasAutoLogonSmbStateRecovery.psm1'
$preflightScript = Join-Path $PSScriptRoot 'Test-SasSoftwareDeploymentTransport.ps1'
$liveCertScript = Join-Path $PSScriptRoot 'Invoke-SasSoftwareDeploymentTransportLiveCert.ps1'
$validatedDeploymentScript = Join-Path $PSScriptRoot 'Invoke-SasValidatedSoftwareDeployment.ps1'
$finalGateScript = Join-Path $PSScriptRoot 'Invoke-SasAutoLogonFinalStepGate.ps1'
$networkGuardModule = Join-Path $PSScriptRoot 'SasNetworkGuard.psm1'
$targetResolutionModule = Join-Path $PSScriptRoot 'SasTargetNameResolution.psm1'
$approvedAppsPath = Join-Path $repoRoot 'configs\software-packages\autologon-system-qualification-catalog.json'
foreach ($requiredPath in @($policyPath,$stateModulePath,$preflightScript,$liveCertScript,$validatedDeploymentScript,$finalGateScript,$networkGuardModule,$targetResolutionModule,$approvedAppsPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Missing qualification dependency: $requiredPath" }
}
Import-Module $stateModulePath -Force
Import-Module $targetResolutionModule -Force

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'survey\output\runs\autologon-system-qualification'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

if ($Action -eq 'Menu') {
    Clear-Host
    Write-Host 'SysAdminSuite AutoLogon LocalSystem Qualification' -ForegroundColor Cyan
    Write-Host 'The failed no-argument candidate is blocked from canonical reuse.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '[1] Validate a qualification request (no network or target contact)'
    Write-Host '[2] Run one controlled LocalSystem qualification pilot'
    Write-Host '[3] Open latest qualification evidence'
    Write-Host '[Q] Quit'
    $choice = (Read-Host 'Choose an action').Trim().ToUpperInvariant()
    switch ($choice) {
        '1' { $Action = 'Plan' }
        '2' { $Action = 'Live' }
        '3' { $Action = 'OpenLatest' }
        'Q' { return }
        default { throw 'No valid qualification action was selected.' }
    }
}

if ($Action -eq 'OpenLatest') {
    $latest = Get-SasLatestQualificationRoot -Root $OutputRoot
    if (-not $latest) { throw 'No qualification evidence exists yet.' }
    Write-Host "Latest qualification evidence: $latest"
    if (-not $NoOpen) { Start-Process -FilePath 'explorer.exe' -ArgumentList @($latest) | Out-Null }
    return
}

if ($FixtureMode -or $Action -eq 'Fixture') {
    $Action = 'Fixture'
    $qualificationRunId = 'autologon-system-qualification-20000101-000000-00000000'
    $runRoot = Join-Path $OutputRoot $qualificationRunId
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    $classification = 'QUALIFIED_FOR_CANONICAL_SYSTEM'
    $baselineScenario = 'success'
    $afterScenario = 'success'
    if ($FixtureScenario -eq 'same_failed_candidate') { $classification = 'QUALIFICATION_BLOCKED_IDENTICAL_FAILED_CANDIDATE' }
    elseif ($FixtureScenario -eq 'dirty_baseline') { $baselineScenario = 'already_configured'; $classification = 'QUALIFICATION_BLOCKED_DIRTY_BASELINE' }
    elseif ($FixtureScenario -eq 'unsupported_postcondition') { $afterScenario = 'success'; $classification = 'CANDIDATE_UNSUPPORTED_SYSTEM_POSTCONDITION' }
    elseif ($FixtureScenario -eq 'cleanup_failure') { $afterScenario = 'cleanup_failure'; $classification = 'QUALIFICATION_CLEANUP_REVIEW_REQUIRED' }

    $baseline = Invoke-SasAutoLogonSmbStateCaptureFixture -FixtureRoot (Join-Path $runRoot 'baseline') -Phase baseline -Scenario $baselineScenario
    $after = $null
    if ($classification -notin @('QUALIFICATION_BLOCKED_IDENTICAL_FAILED_CANDIDATE','QUALIFICATION_BLOCKED_DIRTY_BASELINE')) {
        $after = Invoke-SasAutoLogonSmbStateCaptureFixture -FixtureRoot (Join-Path $runRoot 'after') -Phase after -Scenario $afterScenario
        if ($FixtureScenario -eq 'unsupported_postcondition') {
            $after.snapshot.autologon.auto_admin_logon = '0'
            $after.snapshot.autologon.default_password_present = $false
            $after.snapshot.autologon.expected_user_match = $false
            $after.snapshot.autologon.status = 'intent_only'
        }
    }
    $receipt = [pscustomobject][ordered]@{
        schema_version = 'sas-autologon-system-qualification-result/v1'
        qualification_run_id = $qualificationRunId
        classification = $classification
        fixture_mode = $true
        candidate_id = 'fixture-candidate'
        package_version = 'fixture-2.0'
        target = 'fixture-autologon.example.invalid'
        candidate_sha256 = ('2' * 64)
        candidate_arguments = @('/fixture-system')
        candidate_materially_differs_from_failed_invocation = ($FixtureScenario -ne 'same_failed_candidate')
        final_step_gate_passed = ($classification -notin @('QUALIFICATION_BLOCKED_IDENTICAL_FAILED_CANDIDATE','QUALIFICATION_BLOCKED_DIRTY_BASELINE'))
        installer_exit_code = $(if ($classification -eq 'QUALIFIED_FOR_CANONICAL_SYSTEM') { 0 } else { $null })
        executed_as_system = ($classification -notin @('QUALIFICATION_BLOCKED_IDENTICAL_FAILED_CANDIDATE','QUALIFICATION_BLOCKED_DIRTY_BASELINE'))
        baseline_clean = ($FixtureScenario -ne 'dirty_baseline')
        postcondition_auto_admin_logon = $(if ($after) { [string]$after.snapshot.autologon.auto_admin_logon } else { $null })
        postcondition_default_password_name_present = $(if ($after) { [bool]$after.snapshot.autologon.default_password_present } else { $false })
        postcondition_expected_user_match = $(if ($after) { [bool]$after.snapshot.autologon.expected_user_match } else { $false })
        collector_cleanup_verified = $(if ($after) { Test-SasQualificationCaptureComplete -Lifecycle $after } else { Test-SasQualificationCaptureComplete -Lifecycle $baseline })
        deployment_cleanup_verified = ($classification -notin @('QUALIFICATION_CLEANUP_REVIEW_REQUIRED'))
        canonical_catalog_promoted = $false
        automatic_reboot_performed = $false
        automatic_sign_in_observed = $false
        proof_level = 'sanitized_fixture_contract'
        proof_ceiling = 'Fixture proof only; no live package, target, SYSTEM execution, registry state, reboot, or automatic sign-in is proven.'
    }
    $resultPath = Join-Path $runRoot 'autologon_system_qualification_result.json'
    Write-SasQualificationJson -Path $resultPath -Value $receipt
    if ($PassThru) { return [pscustomobject]@{ classification=$classification; run_root=$runRoot; result_path=$resultPath; result=$receipt } }
    Write-Host "Fixture classification: $classification"
    if ($classification -ne 'QUALIFIED_FOR_CANONICAL_SYSTEM') { throw "Fixture qualification did not pass: $classification" }
    return
}

if ([string]::IsNullOrWhiteSpace($QualificationRequestPath)) {
    $requests = @()
    if (Test-Path -LiteralPath $requestDirectory -PathType Container) {
        $requests = @(Get-ChildItem -LiteralPath $requestDirectory -Filter '*.json' -File | Sort-Object Name)
    }
    if ($requests.Count -eq 0) {
        throw "No qualification request exists under $requestDirectory. Copy and complete the template: $templatePath"
    }
    if ($requests.Count -eq 1) { $QualificationRequestPath = $requests[0].FullName }
    else {
        Write-Host 'Qualification requests:' -ForegroundColor Cyan
        for ($index = 0; $index -lt $requests.Count; $index++) { Write-Host ('  [{0}] {1}' -f ($index + 1), $requests[$index].Name) }
        $selection = 0
        if (-not [int]::TryParse((Read-Host 'Choose the request number'), [ref]$selection) -or $selection -lt 1 -or $selection -gt $requests.Count) {
            throw 'No valid qualification request was selected.'
        }
        $QualificationRequestPath = $requests[$selection - 1].FullName
    }
}
$QualificationRequestPath = Resolve-SasQualificationInputPath -Path $QualificationRequestPath -RepoRoot $repoRoot
$request = Read-SasQualificationRequest -Path $QualificationRequestPath
$approvedSourceRoot = Resolve-SasQualificationApprovedShareRoot `
    -ShareRoot ([string]$request.software_share_root) `
    -RepoRoot $repoRoot

if ($Action -eq 'Plan') {
    $plan = [pscustomobject][ordered]@{
        schema_version = 'sas-autologon-system-qualification-plan/v1'
        classification = 'QUALIFICATION_REQUEST_VALIDATED_NO_TARGET_CONTACT'
        candidate_id = [string]$request.candidate_id
        package_version = [string]$request.package_version
        target = [string]$request.target_fqdn
        candidate_sha256 = ([string]$request.installer_sha256).ToLowerInvariant()
        candidate_arguments = @($request.installer_arguments)
        candidate_materially_differs_from_failed_invocation = $true
        network_activity_performed = $false
        target_mutation_performed = $false
        canonical_catalog_promoted = $false
        next_action = 'Review the request and use the same CMD option 2 for one authorized clean-baseline pilot.'
    }
    $planRoot = Join-Path $OutputRoot ('plan-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8)))
    New-Item -ItemType Directory -Path $planRoot -Force | Out-Null
    $planPath = Join-Path $planRoot 'autologon_system_qualification_plan.json'
    Write-SasQualificationJson -Path $planPath -Value $plan
    Write-Host 'QUALIFICATION_REQUEST_VALIDATED_NO_TARGET_CONTACT' -ForegroundColor Green
    Write-Host "Plan: $planPath"
    if ($PassThru) { return [pscustomobject]@{ classification=$plan.classification; run_root=$planRoot; result_path=$planPath; result=$plan } }
    return
}

if ($Action -ne 'Live') { throw "Unsupported qualification action: $Action" }
if (-not $AllowNetworkActivity -or -not $AllowTargetMutation -or -not $ConfirmQualification) {
    if ($PSBoundParameters.ContainsKey('QualificationRequestPath') -and $Action -eq 'Live') {
        throw 'Live qualification requires -AllowNetworkActivity, -AllowTargetMutation, and -ConfirmQualification.'
    }
}
if (-not $AllowNetworkActivity -or -not $AllowTargetMutation -or -not $ConfirmQualification) {
    Write-Host ''
    Write-Host "Candidate: $($request.candidate_id) / $($request.package_version)" -ForegroundColor Cyan
    Write-Host "Target: $($request.target_fqdn)"
    Write-Host 'This runs one materially different package candidate as LocalSystem, validates registry postconditions, and does not reboot.' -ForegroundColor Yellow
    $ack = (Read-Host 'Type QUALIFY to continue').Trim().ToUpperInvariant()
    if ($ack -ne 'QUALIFY') { throw 'Qualification acknowledgement was not supplied.' }
    $AllowNetworkActivity = $true
    $AllowTargetMutation = $true
    $ConfirmQualification = $true
}

$qualificationRunId = 'autologon-system-qualification-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8))
$stateRunId = 'autologon-recovery-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8))
$gateRunId = 'autologon-delta-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8))
$runRoot = Join-Path $OutputRoot $qualificationRunId
$actionsRoot = Join-Path $runRoot 'actions'
$evidenceRoot = Join-Path $runRoot 'evidence'
$reportsRoot = Join-Path $runRoot 'reports'
New-Item -ItemType Directory -Path $actionsRoot,$evidenceRoot,$reportsRoot -Force | Out-Null
$resultPath = Join-Path $runRoot 'autologon_system_qualification_result.json'
$receiptPath = Join-Path $runRoot 'autologon_system_qualification_receipt.json'
$summaryPath = Join-Path $reportsRoot 'english_summary.txt'

$classification = 'QUALIFICATION_FAILED'
$errorMessage = $null
$preflightPath = $null
$liveCertPath = $null
$baselinePath = $null
$afterPath = $null
$gatePath = $null
$deploymentResultPath = $null
$installSummaryPath = $null
$baseline = $null
$after = $null
$gate = $null
$deployment = $null
$installerExitCode = $null
$deploymentCleanupVerified = $false
$collectorCleanupVerified = $false
$sourceHashVerified = $false
$signatureStatus = 'not_required'
$target = [string]$request.target_fqdn
$targetResolution = $null
$targetResolutionPath = $null
$failureClassification = 'QUALIFICATION_FAILED'

try {
    Import-Module $networkGuardModule -Force
    Assert-SasNorthwellWifi

    $failureClassification = 'QUALIFICATION_TRANSPORT_BLOCKED'
    $targetResolution = Resolve-SasQualificationTargetIdentity -TargetFqdn $target
    $target = [string]$targetResolution.fqdn
    $targetResolutionPath = Join-Path $evidenceRoot 'target_resolution.json'
    Write-SasQualificationJson -Path $targetResolutionPath -Value $targetResolution

    $failureClassification = 'QUALIFICATION_SOURCE_BLOCKED'
    $sourceRoot = $approvedSourceRoot
    $installerPath = $sourceRoot + ([string]$request.installer_relative_path).Trim().Replace('/', '\').TrimStart('\')
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) { throw "Qualification candidate not found: $installerPath" }
    $observedHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $sourceHashVerified = ($observedHash -eq ([string]$request.installer_sha256).ToLowerInvariant())
    if (-not $sourceHashVerified) { throw 'Qualification candidate SHA-256 does not match the request.' }
    if ([bool]$request.signature.require_valid_signature) {
        $signature = Get-AuthenticodeSignature -FilePath $installerPath
        $signatureStatus = [string]$signature.Status
        $thumbprint = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Thumbprint } else { '' }
        if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or
            -not $thumbprint.Equals([string]$request.signature.expected_signer_thumbprint, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Qualification candidate signature or signer thumbprint is not approved.'
        }
    }

    $failureClassification = 'QUALIFICATION_TRANSPORT_BLOCKED'
    $preflight = & $preflightScript -ComputerName $target -AllowNetworkActivity -TransportIntent kerberos_smb_task `
        -OutputRoot (Join-Path $runRoot 'preflight') -PassThru
    $preflightPath = [string]$preflight.result_path
    if ([string]$preflight.result.decision.classification -ne 'kerberos_smb_task_ready') {
        throw "Qualification transport preflight did not pass: $($preflight.result.decision.classification)"
    }

    $liveCert = & $liveCertScript -ComputerName $target -PreflightResultPath $preflightPath `
        -AllowNetworkActivity -AllowTargetMutation -PreflightMaxAgeMinutes $PreflightMaxAgeMinutes `
        -OutputRoot (Join-Path $runRoot 'live-cert') -PassThru
    $liveCertPath = [string]$liveCert.result_path
    if ([string]$liveCert.disposition -ne 'LIVE CERT PASS' -or [string]$liveCert.lifecycle_status -ne 'completed') {
        throw "Qualification transport live cert failed: $($liveCert.disposition) / $($liveCert.lifecycle_status)"
    }

    $failureClassification = 'QUALIFICATION_BASELINE_FAILED'
    $baseline = Invoke-SasAutoLogonSmbStateCapture -ComputerName $target -RunId $stateRunId -Phase baseline `
        -PreflightResultPath $preflightPath -LocalRunRoot (Join-Path $evidenceRoot 'baseline') `
        -AllowNetworkActivity -AllowTargetMutation -PreflightMaxAgeMinutes $PreflightMaxAgeMinutes `
        -ResultTimeoutSeconds $StateResultTimeoutSeconds
    Write-SasQualificationJson -Path (Join-Path $evidenceRoot 'baseline_lifecycle.json') -Value $baseline
    if ($baseline.snapshot) {
        $baselinePath = Join-Path $evidenceRoot 'baseline_snapshot.json'
        Write-SasQualificationJson -Path $baselinePath -Value $baseline.snapshot
    }
    if (-not (Test-SasQualificationCaptureComplete -Lifecycle $baseline)) { throw "Qualification baseline capture or cleanup failed: $($baseline.status). $($baseline.error)" }
    if (-not (Test-SasQualificationSnapshotIdentity -Snapshot $baseline.snapshot -TargetResolution $targetResolution)) {
        throw 'Qualification baseline was returned by a different endpoint identity than the approved target.'
    }
    $collectorCleanupVerified = $true
    if (-not (Test-SasQualificationCleanBaseline -Snapshot $baseline.snapshot)) {
        $failureClassification = 'QUALIFICATION_BLOCKED_DIRTY_BASELINE'
        throw 'Qualification requires a clean baseline: AutoLogon not configured and no existing NW AutoLogon Setup uninstall entry. Use a fresh or explicitly reset pilot.'
    }

    $beforeManifest = [pscustomobject][ordered]@{
        run_id = $gateRunId
        phase = 'before_complete'
        targets = @([pscustomobject]@{ computer_name=$target; hostname=$target })
        source_snapshot = $baselinePath
    }
    $beforeManifestPath = Join-Path $actionsRoot 'qualification_before_manifest.json'
    Write-SasQualificationJson -Path $beforeManifestPath -Value $beforeManifest
    $gateOutputRoot = Join-Path $evidenceRoot 'final-gate'
    $failureClassification = 'QUALIFICATION_FINAL_GATE_BLOCKED'
    $gate = & $finalGateScript -Target $target -RunId $gateRunId -BeforeSnapshotPath $beforeManifestPath `
        -ApprovedAppsPath $approvedAppsPath -OutputRoot $gateOutputRoot -ExecContext remote `
        -TechnicianLabel "AutoLogon SYSTEM qualification $qualificationRunId"
    $gatePath = Join-Path (Join-Path $gateOutputRoot $gateRunId) 'autologon_final_step_gate.json'
    if (-not [bool]$gate.overall_pass) { throw "Canonical AutoLogon final-step gate blocked qualification: $($gate.blocked_reason)" }

    $validatedRequest = [pscustomobject][ordered]@{
        schema_version = 'sas-validated-software-deployment-request/v1'
        request_id = $qualificationRunId
        package_name = 'NW AutoLogon Setup x64 SYSTEM qualification candidate'
        software_share_root = $sourceRoot
        installer_relative_path = ([string]$request.installer_relative_path).Trim().Replace('/', '\')
        installer_sha256 = ([string]$request.installer_sha256).ToLowerInvariant()
        installer_arguments = @($request.installer_arguments | ForEach-Object { [string]$_ })
        installer_arguments_reference = [string]$request.installer_arguments_reference
        install_mode = 'CopyThenInstall'
        targets = @($target)
        authorization = [pscustomobject][ordered]@{
            authorized_by = [string]$request.authorization.authorized_by
            request_reference = [string]$request.authorization.request_reference
            change_reference = [string]$request.authorization.change_reference
            ticket_reference = [string]$request.authorization.ticket_reference
        }
        validation = [pscustomobject][ordered]@{
            checks = @(
                [pscustomobject][ordered]@{
                    id='autologon-intent'; type='RegistryValueEquals'; required=$true
                    registry_path='HKLM:\SOFTWARE\NSLIJHS\PostInstall'; value_name='SetAutoLogon'; expected_value='Autologon_YES'
                },
                [pscustomobject][ordered]@{
                    id='autologon-enabled'; type='RegistryValueEquals'; required=$true
                    registry_path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; value_name='AutoAdminLogon'; expected_value='1'
                }
            )
        }
        cleanup_policy = 'repo_owned_run_scoped_only'
    }
    if ([bool]$request.signature.require_valid_signature) {
        $validatedRequest | Add-Member -NotePropertyName require_valid_signature -NotePropertyValue $true
        $validatedRequest | Add-Member -NotePropertyName expected_signer_thumbprint -NotePropertyValue ([string]$request.signature.expected_signer_thumbprint).ToUpperInvariant()
    }
    if (@($validatedRequest.installer_arguments).Count -eq 0) {
        $validatedRequest | Add-Member -NotePropertyName installer_arguments_policy -NotePropertyValue 'approved_empty'
    }
    $validatedRequestPath = Join-Path $actionsRoot 'validated_system_qualification_request.json'
    Write-SasQualificationJson -Path $validatedRequestPath -Value $validatedRequest

    $failureClassification = 'QUALIFICATION_DEPLOYMENT_FAILED'
    try {
        $deployment = & $validatedDeploymentScript -RequestPath $validatedRequestPath `
            -OutputRoot (Join-Path $runRoot 'deployment') -Transport SmbScheduledTask `
            -TransportPreflightPath @($preflightPath) -PreflightMaxAgeMinutes $PreflightMaxAgeMinutes `
            -ResultTimeoutSeconds $DeploymentResultTimeoutSeconds -AllowTargetMutation -Confirm:$false
    }
    catch {
        $errorMessage = $_.Exception.Message
        $candidate = @(Get-ChildItem -LiteralPath (Join-Path $runRoot 'deployment') -Filter 'validated_deployment_result.json' -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
        if ($candidate.Count -gt 0) {
            $deployment = Get-Content -LiteralPath $candidate[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        else {
            throw
        }
    }

    $deploymentResultFile = @(Get-ChildItem -LiteralPath (Join-Path $runRoot 'deployment') -Filter 'validated_deployment_result.json' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
    if ($deploymentResultFile.Count -gt 0) { $deploymentResultPath = $deploymentResultFile[0].FullName }
    if ($deployment -and $deployment.PSObject.Properties.Name -contains 'install_summary_path') { $installSummaryPath = [string]$deployment.install_summary_path }
    if ($installSummaryPath -and (Test-Path -LiteralPath $installSummaryPath -PathType Leaf)) {
        $installSummary = Get-Content -LiteralPath $installSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $row = @($installSummary.results)[0]
        $installerExitCode = $row.exit_code
        $deploymentCleanupVerified = ([int]$installSummary.cleanup_failure_count -eq 0 -and [int]$installSummary.repo_artifact_remaining_count -eq 0)
    }

    $failureClassification = 'QUALIFICATION_POSTCONDITION_FAILED'
    $after = Invoke-SasAutoLogonSmbStateCapture -ComputerName $target -RunId $stateRunId -Phase after `
        -PreflightResultPath $preflightPath -LocalRunRoot (Join-Path $evidenceRoot 'after') `
        -AllowNetworkActivity -AllowTargetMutation -PreflightMaxAgeMinutes $PreflightMaxAgeMinutes `
        -ResultTimeoutSeconds $StateResultTimeoutSeconds
    Write-SasQualificationJson -Path (Join-Path $evidenceRoot 'after_lifecycle.json') -Value $after
    if ($after.snapshot) {
        $afterPath = Join-Path $evidenceRoot 'after_snapshot.json'
        Write-SasQualificationJson -Path $afterPath -Value $after.snapshot
    }
    $collectorCleanupVerified = ($collectorCleanupVerified -and (Test-SasQualificationCaptureComplete -Lifecycle $after))
    if (-not (Test-SasQualificationSnapshotIdentity -Snapshot $after.snapshot -TargetResolution $targetResolution)) {
        throw 'Qualification After state was returned by a different endpoint identity than the approved target.'
    }
    if (-not $collectorCleanupVerified -or -not $deploymentCleanupVerified) {
        $classification = 'QUALIFICATION_CLEANUP_REVIEW_REQUIRED'
    }
    else {
        $post = $after.snapshot.autologon
        $qualified = ($deployment -and [bool]$deployment.deployment_complete -and
            $null -ne $installerExitCode -and [int]$installerExitCode -in @(0, 3010) -and
            [string]$post.postinstall_set_autologon -eq 'Autologon_YES' -and [string]$post.auto_admin_logon -eq '1' -and
            [bool]$post.default_password_present -and [bool]$post.expected_user_match -and [string]$post.status -eq 'autologon_ready')
        if ($qualified) { $classification = 'QUALIFIED_FOR_CANONICAL_SYSTEM' }
        else { $classification = 'CANDIDATE_UNSUPPORTED_SYSTEM_POSTCONDITION' }
    }
}
catch {
    if (-not $errorMessage) { $errorMessage = $_.Exception.Message }
    if ($classification -eq 'QUALIFICATION_FAILED') {
        $classification = $failureClassification
    }
}

$result = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-system-qualification-result/v1'
    qualification_run_id = $qualificationRunId
    classification = $classification
    reason = $errorMessage
    fixture_mode = $false
    candidate_id = [string]$request.candidate_id
    package_version = [string]$request.package_version
    target = $target
    target_resolution_path = $targetResolutionPath
    candidate_sha256 = ([string]$request.installer_sha256).ToLowerInvariant()
    candidate_arguments = @($request.installer_arguments)
    candidate_arguments_reference = [string]$request.installer_arguments_reference
    candidate_materially_differs_from_failed_invocation = $true
    source_hash_verified = $sourceHashVerified
    signature_status = $signatureStatus
    preflight_result_path = $preflightPath
    live_cert_result_path = $liveCertPath
    baseline_snapshot_path = $baselinePath
    final_step_gate_path = $gatePath
    final_step_gate_passed = ($gate -and [bool]$gate.overall_pass)
    deployment_result_path = $deploymentResultPath
    install_summary_path = $installSummaryPath
    after_snapshot_path = $afterPath
    installer_exit_code = $installerExitCode
    executed_as_system = $(if ($deployment -and $installSummaryPath -and (Test-Path -LiteralPath $installSummaryPath)) {
        $summary = Get-Content -LiteralPath $installSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        [bool](@($summary.results)[0].execution_as_system)
    } else { $false })
    baseline_clean = $(if ($baseline -and $baseline.snapshot) { Test-SasQualificationCleanBaseline -Snapshot $baseline.snapshot } else { $false })
    postcondition_set_autologon = $(if ($after -and $after.snapshot) { [string]$after.snapshot.autologon.postinstall_set_autologon } else { $null })
    postcondition_auto_admin_logon = $(if ($after -and $after.snapshot) { [string]$after.snapshot.autologon.auto_admin_logon } else { $null })
    postcondition_default_password_name_present = $(if ($after -and $after.snapshot) { [bool]$after.snapshot.autologon.default_password_present } else { $false })
    postcondition_expected_user_match = $(if ($after -and $after.snapshot) { [bool]$after.snapshot.autologon.expected_user_match } else { $false })
    collector_cleanup_verified = $collectorCleanupVerified
    deployment_cleanup_verified = $deploymentCleanupVerified
    canonical_catalog_promoted = $false
    automatic_reboot_performed = $false
    automatic_sign_in_observed = $false
    proof_level = $(if ($classification -eq 'QUALIFIED_FOR_CANONICAL_SYSTEM') { 'controlled_system_execution_registry_postcondition_and_teardown' } else { 'insufficient_or_review_required' })
    proof_ceiling = 'Qualification can prove one candidate executed as LocalSystem, required pre-reboot registry posture, and run-scoped teardown. It does not promote catalogs automatically and does not prove reboot, automatic sign-in, current-token access, application behavior, or technician acceptance.'
}
Write-SasQualificationJson -Path $resultPath -Value $result

if ($classification -eq 'QUALIFIED_FOR_CANONICAL_SYSTEM') {
    $receipt = [pscustomobject][ordered]@{
        schema_version = 'sas-autologon-system-qualification-receipt/v1'
        candidate_id = $result.candidate_id
        package_version = $result.package_version
        installer_sha256 = $result.candidate_sha256
        installer_arguments = @($result.candidate_arguments)
        installer_arguments_reference = $result.candidate_arguments_reference
        target_scope = 'one_authorized_cybernet_fqdn'
        executed_as_system = $result.executed_as_system
        auto_admin_logon = $result.postcondition_auto_admin_logon
        default_password_value_name_present = $result.postcondition_default_password_name_present
        expected_user_match = $result.postcondition_expected_user_match
        cleanup_verified = ($result.collector_cleanup_verified -and $result.deployment_cleanup_verified)
        canonical_catalog_promoted = $false
        promotion_required = $true
        promotion_instruction = 'Review this operator-local receipt, then commit the exact qualified SHA-256, version, and arguments in a separate bounded catalog-promotion PR.'
        reboot_observed = $false
        automatic_sign_in_observed = $false
    }
    Write-SasQualificationJson -Path $receiptPath -Value $receipt
}

@(
    'SysAdminSuite AutoLogon LocalSystem qualification'
    "Classification: $classification"
    "Candidate: $($request.candidate_id)"
    "Version: $($request.package_version)"
    "Installer exit code: $installerExitCode"
    "AutoAdminLogon: $($result.postcondition_auto_admin_logon)"
    "DefaultPassword value name present: $($result.postcondition_default_password_name_present)"
    "Expected user match: $($result.postcondition_expected_user_match)"
    "Collector cleanup verified: $collectorCleanupVerified"
    "Deployment cleanup verified: $deploymentCleanupVerified"
    'Canonical catalog promoted: False'
    'Automatic reboot performed: False'
    'Automatic sign-in observed: False'
    "Result: $resultPath"
    $(if ($classification -eq 'QUALIFIED_FOR_CANONICAL_SYSTEM') { "Qualification receipt: $receiptPath" } else { "Blocker: $errorMessage" })
    "Proof ceiling: $($result.proof_ceiling)"
) | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Get-Content -LiteralPath $summaryPath | ForEach-Object { Write-Host $_ }

$output = [pscustomobject]@{
    classification = $classification
    qualification_run_id = $qualificationRunId
    run_root = $runRoot
    result_path = $resultPath
    receipt_path = $(if (Test-Path -LiteralPath $receiptPath) { $receiptPath } else { $null })
    summary_path = $summaryPath
    result = $result
}
if ($PassThru) { Write-Output $output }
if ($classification -ne 'QUALIFIED_FOR_CANONICAL_SYSTEM') {
    throw "AutoLogon LocalSystem qualification did not pass: $classification"
}
