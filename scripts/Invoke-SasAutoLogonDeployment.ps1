#Requires -Version 5.1
<#
.SYNOPSIS
Run the bounded SysAdminSuite AutoLogon deployment workflow.

.DESCRIPTION
Builds one closed validated software-deployment request per eligible target and routes
AutoLogon only through Invoke-SasValidatedSoftwareDeployment.ps1. The live application
sequence is:

  validate package/request/preflight -> Before state -> final-step gate
  -> canonical Kerberos/SMB scheduled-task deployment -> After state -> canonical results

The script never delegates directly to Invoke-SasSoftwareInstall.ps1. That older WinRM
surface remains an internal compatibility implementation of the generic validated front
door and has no direct AutoLogon authority.

-WhatIf validates the closed request and canonical transport choice without target reads.
-FixtureMode uses sanitized synthetic targets, state, preflight, and failure adapters. It
never contacts a share or target and never proves installer, task, cleanup, reboot, sign-in,
current-token access, or application behavior.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string[]]$ComputerName = @(),
    [string]$TargetsCsv,

    [ValidateSet('autologon')]
    [string]$PackageId = 'autologon',
    [string]$PackageName = 'NW AutoLogon Setup x64',
    [string]$SoftwareShareRoot,
    [string]$InstallerRelativePath,
    [string]$InstallerSha256,
    [string[]]$InstallerArguments = @(),
    [string]$InstallerArgumentsReference,

    [ValidateSet('CopyThenInstall')]
    [string]$InstallMode = 'CopyThenInstall',

    [string]$AuthorizedBy,
    [string]$RequestReference,
    [string]$ChangeReference,
    [string]$TicketReference,
    [switch]$RequireValidSignature,
    [string]$ExpectedSignerThumbprint,

    [ValidateSet('Auto', 'SmbScheduledTask')]
    [string]$Transport = 'Auto',
    [string[]]$TransportPreflightPath = @(),
    [ValidateRange(1, 1440)]
    [int]$PreflightMaxAgeMinutes = 15,
    [ValidateRange(10, 7200)]
    [int]$ResultTimeoutSeconds = 1800,

    [string]$ApprovedAppsPath,
    [string]$HostEligibilityPolicyPath,
    [string]$TechnicianLabel,
    [string]$OutputRoot,

    [ValidateRange(1, 25)]
    [int]$MaxTargets = 25,

    [switch]$AllowTargetMutation,
    [switch]$FixtureMode,

    [ValidateSet(
        'ready',
        'blocked',
        'already_configured',
        'hash_mismatch',
        'transport_rejection',
        'task_failure',
        'validation_failure',
        'teardown_failure'
    )]
    [string]$FixtureScenario = 'ready'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-SasAutoLogonJson {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force -WhatIf:$false | Out-Null
    }
    $Value | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $Path -Encoding UTF8 -WhatIf:$false
}

function Get-SasAutoLogonTargets {
    param([string[]]$DirectTargets, [string]$CsvPath, [int]$Limit)
    $items = New-Object System.Collections.Generic.List[string]
    foreach ($target in @($DirectTargets)) {
        if (-not [string]::IsNullOrWhiteSpace($target)) { $items.Add($target.Trim()) }
    }
    if (-not [string]::IsNullOrWhiteSpace($CsvPath)) {
        if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) { throw "TargetsCsv not found: $CsvPath" }
        foreach ($row in @(Import-Csv -LiteralPath $CsvPath)) {
            foreach ($column in @('ComputerName', 'HostName', 'Hostname', 'Target')) {
                if ($row.PSObject.Properties.Name -contains $column) {
                    $candidate = [string]$row.$column
                    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                        $items.Add($candidate.Trim())
                        break
                    }
                }
            }
        }
    }
    $targets = @($items | Sort-Object -Unique)
    if ($targets.Count -eq 0) { throw 'No explicit targets were supplied. Use -ComputerName or -TargetsCsv.' }
    if ($targets.Count -gt $Limit) { throw "Target count $($targets.Count) exceeds MaxTargets $Limit." }
    return $targets
}

function Get-SasApprovedAutoLogonPackage {
    param(
        [Parameter(Mandatory = $true)][string]$CatalogPath,
        [Parameter(Mandatory = $true)][string]$ExpectedPackageId,
        [Parameter(Mandatory = $true)][string]$ExpectedPackageName,
        [string]$RequestedShareRoot,
        [string]$RequestedRelativePath,
        [string]$RequestedInstallMode
    )
    if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) { throw "Approved apps catalog not found: $CatalogPath" }
    try { $catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Approved apps catalog is malformed: $($_.Exception.Message)" }
    if ([string]$catalog.schema_version -ne 'sas-approved-software-catalog/v1') { throw 'Approved apps catalog schema is unsupported.' }
    $matches = @($catalog.packages | Where-Object { [string]$_.id -eq $ExpectedPackageId })
    if ($matches.Count -ne 1) { throw "Approved package identity '$ExpectedPackageId' is missing or ambiguous." }
    $package = $matches[0]
    if (-not [bool]$package.install_enabled) { throw "Approved package '$ExpectedPackageId' is not enabled for installation." }
    if ([string]$package.display_name -ne $ExpectedPackageName) { throw 'PackageName does not match the approved AutoLogon catalog identity.' }
    if ([string]::IsNullOrWhiteSpace([string]$package.installer_file)) { throw 'Approved AutoLogon installer_file is not pinned.' }

    $approvedRoot = ([string]$catalog.software_share_root).Trim().Replace('/', '\')
    if (-not $approvedRoot.EndsWith('\')) { $approvedRoot += '\' }
    if (-not [string]::IsNullOrWhiteSpace($RequestedShareRoot)) {
        $candidateRoot = $RequestedShareRoot.Trim().Replace('/', '\')
        if (-not $candidateRoot.EndsWith('\')) { $candidateRoot += '\' }
        if (-not $candidateRoot.Equals($approvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'SoftwareShareRoot is not an approved software source for AutoLogon.'
        }
    }

    $approvedRelative = ('{0}\{1}' -f ([string]$package.source_folder_relative_path).TrimEnd('\'), [string]$package.installer_file)
    if (-not [string]::IsNullOrWhiteSpace($RequestedRelativePath) -and
        -not $RequestedRelativePath.Trim().Replace('/', '\').Equals($approvedRelative, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'InstallerRelativePath does not match the pinned AutoLogon catalog entry.'
    }
    if ([string]$package.default_install_mode -ne $RequestedInstallMode) { throw 'InstallMode does not match the approved AutoLogon catalog entry.' }

    return [pscustomobject][ordered]@{
        id = [string]$package.id
        display_name = [string]$package.display_name
        software_share_root = $approvedRoot
        installer_relative_path = $approvedRelative
        install_mode = [string]$package.default_install_mode
    }
}

function Get-SasBaselineEligibility {
    param([Parameter(Mandatory = $true)][string]$BeforeDirectory)
    $rows = foreach ($file in @(Get-ChildItem -LiteralPath $BeforeDirectory -Filter '*.json' -File -ErrorAction Stop)) {
        try {
            $snapshot = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $status = if ($snapshot.autologon) { [string]$snapshot.autologon.status } else { 'unknown' }
            $decision = if ([string]$snapshot.collection_status -ne 'success') { 'SKIP_BASELINE_COLLECTION_FAILED' }
                elseif ($status -eq 'autologon_ready') { 'SKIP_ALREADY_CONFIGURED' }
                else { 'ELIGIBLE_FOR_INSTALL' }
            [pscustomobject]@{
                computer_name = [string]$snapshot.requested_target
                collection_status = [string]$snapshot.collection_status
                autologon_status = $status
                eligibility_decision = $decision
                baseline_path = $file.FullName
                error = [string]$snapshot.error
            }
        }
        catch {
            [pscustomobject]@{
                computer_name = $file.BaseName
                collection_status = 'failed'
                autologon_status = 'unknown'
                eligibility_decision = 'SKIP_BASELINE_COLLECTION_FAILED'
                baseline_path = $file.FullName
                error = $_.Exception.Message
            }
        }
    }
    return @($rows)
}

function Set-SasFixtureAlreadyConfigured {
    param([Parameter(Mandatory = $true)][string]$BeforeDirectory)
    foreach ($file in @(Get-ChildItem -LiteralPath $BeforeDirectory -Filter '*.json' -File)) {
        $snapshot = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $snapshot.autologon.postinstall_set_autologon = 'Autologon_YES'
        $snapshot.autologon.auto_admin_logon = '1'
        $snapshot.autologon.default_user_name = ([string]$snapshot.requested_target).ToUpperInvariant()
        $snapshot.autologon.default_password_present = $true
        $snapshot.autologon.expected_user_match = $true
        $snapshot.autologon.status = 'autologon_ready'
        Write-SasAutoLogonJson -Path $file.FullName -Value $snapshot
    }
}

function New-SasAutoLogonValidatedRequest {
    param(
        [string]$RequestId,
        [string]$Target,
        $Package,
        [string]$Sha256,
        [string[]]$Arguments,
        [string]$ArgumentsReference,
        [string]$Approver,
        [string]$RequestRef,
        [string]$ChangeRef,
        [string]$TicketRef,
        [bool]$SignatureRequired,
        [string]$SignerThumbprint
    )
    $request = [pscustomobject][ordered]@{
        schema_version = 'sas-validated-software-deployment-request/v1'
        request_id = $RequestId
        package_name = [string]$Package.display_name
        software_share_root = [string]$Package.software_share_root
        installer_relative_path = [string]$Package.installer_relative_path
        installer_sha256 = $Sha256.ToLowerInvariant()
        installer_arguments = @($Arguments)
        installer_arguments_reference = $ArgumentsReference
        install_mode = [string]$Package.install_mode
        targets = @($Target)
        authorization = [pscustomobject][ordered]@{
            authorized_by = $Approver
            request_reference = $RequestRef
            change_reference = $ChangeRef
            ticket_reference = $TicketRef
        }
        validation = [pscustomobject][ordered]@{
            checks = @(
                [pscustomobject][ordered]@{
                    id = 'autologon-intent'
                    type = 'RegistryValueEquals'
                    required = $true
                    registry_path = 'HKLM:\SOFTWARE\NSLIJHS\PostInstall'
                    value_name = 'SetAutoLogon'
                    expected_value = 'Autologon_YES'
                },
                [pscustomobject][ordered]@{
                    id = 'autologon-enabled'
                    type = 'RegistryValueEquals'
                    required = $true
                    registry_path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
                    value_name = 'AutoAdminLogon'
                    expected_value = '1'
                }
            )
        }
        cleanup_policy = 'repo_owned_run_scoped_only'
    }
    if ($SignatureRequired) { $request | Add-Member -NotePropertyName require_valid_signature -NotePropertyValue $true }
    if (-not [string]::IsNullOrWhiteSpace($SignerThumbprint)) {
        $request | Add-Member -NotePropertyName expected_signer_thumbprint -NotePropertyValue $SignerThumbprint.ToUpperInvariant()
    }
    return $request
}

function New-SasFixturePreflight {
    param([string]$Scenario, [string]$Destination, [string]$RepoRoot)
    $name = if ($Scenario -eq 'transport_rejection') { 'no-supported-transport.fixture.json' } else { 'kerberos-smb-task-ready.fixture.json' }
    $source = Join-Path $RepoRoot "Tests\Fixtures\software-deployment-transport\$name"
    $fixture = Get-Content -LiteralPath $source -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-SasAutoLogonJson -Path $Destination -Value $fixture
    return $Destination
}

function New-SasFixtureHostPolicy {
    param([string[]]$Targets, [string]$Scenario, [string]$Destination)
    $pattern = if ($Scenario -eq 'blocked') { '^fixture-host-never-matches$' }
        else { '^(?:{0})$' -f ((@($Targets | ForEach-Object { [regex]::Escape($_) })) -join '|') }
    $policy = [pscustomobject][ordered]@{
        schema_version = 'sas-host-eligibility-policy/v1'
        policy_id = 'autologon-canonical-fixture'
        policy_version = '1.0.0'
        patterns = @([pscustomobject][ordered]@{
            name = 'fixture-targets'
            match_type = 'regex'
            regex = $pattern
            actions = @('fixture')
        })
    }
    Write-SasAutoLogonJson -Path $Destination -Value $policy
    return $Destination
}

function ConvertTo-SasCanonicalGateResult {
    param([object[]]$LegacyResults, [bool]$IsFixture)
    $prerequisites = @()
    foreach ($id in @('run_id_format','host_eligibility','approved_catalog','before_snapshot','runtime_proof','file_access_posture')) {
        $items = @($LegacyResults | ForEach-Object { @($_.prerequisites | Where-Object { [string]$_.id -eq $id }) })
        if ($items.Count -gt 0) {
            $passed = @($items | Where-Object { -not [bool]$_.passed }).Count -eq 0
            $mandatory = @($items | Where-Object { [bool]$_.mandatory }).Count -gt 0
            $prerequisites += [pscustomobject][ordered]@{
                id = $id
                mandatory = $mandatory
                passed = $passed
                reason_code = if ($passed) { "${id}_passed" } else { "${id}_blocked" }
            }
        }
    }
    $overall = ($LegacyResults.Count -gt 0 -and @($LegacyResults | Where-Object { -not [bool]$_.overall_pass }).Count -eq 0)
    return [pscustomobject][ordered]@{
        schema_version = 'sas-autologon-final-step-gate-result/v1'
        gate_id = 'autologon-final-step'
        gate_version = '1.0.0'
        evidence_class = if ($IsFixture) { 'sanitized_fixture' } else { 'operator_local' }
        classification = if ($IsFixture) { $(if ($overall) { 'fixture_gate_passed' } else { 'fixture_gate_blocked' }) }
            else { $(if ($overall) { 'gate_passed' } else { 'gate_blocked' }) }
        reason_codes = @($(if ($overall) { 'all_mandatory_prerequisites_passed' } else { 'mandatory_prerequisite_blocked' }))
        fixture_mode = $IsFixture
        target_identifier_emitted = $false
        prerequisites = @($prerequisites)
        overall_pass = $overall
        default_password_value_read = $false
        secret_value_emitted = $false
        proof_level = if ($IsFixture) { 'sanitized_fixture_contract' } else { $(if ($overall) { 'operator_local_gate' } else { 'insufficient' }) }
        proof_ceiling = if ($IsFixture) {
            'Sanitized final-gate fixture only; no target contact, installer execution, reboot, sign-in, or runtime behavior is proven.'
        } else {
            'Operator-local prerequisite decision only; passing does not prove installer execution, state transition, reboot, sign-in, or runtime behavior.'
        }
    }
}

function New-SasCanonicalStateResult {
    param(
        [bool]$IsFixture,
        [int]$TargetCount,
        [int]$BaselineFailureCount,
        [int]$AlreadyConfiguredCount,
        $BeforeResult,
        $AfterResult,
        $AfterSummary,
        [bool]$FixturePassed
    )
    $confirmed = if ($AfterSummary) { [int]$AfterSummary.confirmed_state_transition_count } else { 0 }
    $partial = if ($AfterSummary) { [int]$AfterSummary.partial_change_review_count } else { 0 }
    $regression = if ($AfterSummary) { [int]$AfterSummary.regression_review_count } else { 0 }
    $inconclusive = if ($AfterSummary) { [int]$AfterSummary.inconclusive_count } else { 0 }
    $expectedMatches = if ($AfterSummary) { @($AfterSummary.results | Where-Object { [bool]$_.ExpectedUserMatch }).Count } else { 0 }
    $classification = if ($IsFixture) {
        if ($FixturePassed) { 'fixture_contract_pass' } else { 'fixture_contract_failed' }
    }
    elseif (-not $AfterResult) { 'baseline_captured' }
    elseif ($regression -gt 0) { 'regression_review' }
    elseif ($partial -gt 0) { 'partial_change_review' }
    elseif ($inconclusive -gt 0 -or $BaselineFailureCount -gt 0) { 'inconclusive' }
    elseif ($confirmed -gt 0) { 'confirmed_state_transition' }
    elseif ($AlreadyConfiguredCount -eq $TargetCount) { 'already_configured_before' }
    else { 'no_material_change' }
    return [pscustomobject][ordered]@{
        schema_version = 'sas-autologon-state-proof-result/v1'
        operation_id = 'autologon.state_proof'
        evidence_class = if ($IsFixture) { 'sanitized_fixture' } else { 'operator_local' }
        classification = $classification
        reason_codes = @($(if ($classification -eq 'fixture_contract_pass') { 'synthetic_state_path_validated' }
            elseif ($classification -eq 'fixture_contract_failed') { 'synthetic_state_path_incomplete' }
            else { $classification }))
        fixture_mode = $IsFixture
        target_count = $TargetCount
        proof = [pscustomobject][ordered]@{
            before_snapshot_captured = ($null -ne $BeforeResult -and $BaselineFailureCount -eq 0)
            after_snapshot_captured = ($null -ne $AfterResult)
            state_change_observed = ($confirmed -gt 0 -or $partial -gt 0 -or $regression -gt 0)
            expected_account_match = ($null -ne $AfterResult -and ($expectedMatches + $AlreadyConfiguredCount) -ge ($TargetCount - $BaselineFailureCount))
            reboot_observed = $false
            automatic_sign_in_observed = $false
        }
        safety = [pscustomobject][ordered]@{
            collector_target_mutation_performed = $false
            target_side_sysadminsuite_artifacts_written = $false
            default_password_value_collected = $false
            human_actor_attribution_claimed = $false
        }
        proof_level = if ($IsFixture) { 'sanitized_fixture_contract' } elseif ($AfterResult) { 'operator_local_state_delta' } else { 'insufficient' }
        proof_ceiling = if ($IsFixture) {
            'Sanitized state fixture only; no live registry state, reboot, automatic sign-in, current-token access, or human attribution is proven.'
        } else {
            'Operator-local before/after state evidence only; reboot, automatic sign-in, current-token access, application behavior, and actor identity remain unproven.'
        }
    }
}

function Complete-SasAutoLogonRun {
    param($Context, $DeploymentResult, $GateResult, $StateResult, $Summary)
    $deploymentPath = Join-Path $Context.directories.artifacts 'autologon_deployment_result.json'
    Write-SasAutoLogonJson -Path $deploymentPath -Value $DeploymentResult
    Register-SasArtifact -RegistryPath $Context.artifact_registry_path -Role 'autologon_deployment_result' -Path $deploymentPath `
        -Tracked $false -LiveData (-not [bool]$DeploymentResult.fixture_mode) -Generated $true `
        -Description 'Canonical AutoLogon deployment result composed from transport, gate, finalization, state, and teardown evidence.' `
        -NetworkActivity $(if ([bool]$DeploymentResult.network_activity_performed) { 'Bounded authorized workflow activity performed.' } else { 'No network activity performed.' }) `
        -CreatedBy 'Invoke-SasAutoLogonDeployment' | Out-Null

    $gatePath = $null
    if ($GateResult) {
        $gatePath = Join-Path $Context.directories.artifacts 'autologon_final_step_gate_result.json'
        Write-SasAutoLogonJson -Path $gatePath -Value $GateResult
        Register-SasArtifact -RegistryPath $Context.artifact_registry_path -Role 'autologon_final_step_gate_result' -Path $gatePath `
            -Tracked $false -LiveData (-not [bool]$GateResult.fixture_mode) -Generated $true `
            -Description 'Identifier-free normalized AutoLogon final-step gate result.' -CreatedBy 'Invoke-SasAutoLogonDeployment' | Out-Null
    }

    $statePath = $null
    if ($StateResult) {
        $statePath = Join-Path $Context.directories.artifacts 'autologon_state_proof_result.json'
        Write-SasAutoLogonJson -Path $statePath -Value $StateResult
        Register-SasArtifact -RegistryPath $Context.artifact_registry_path -Role 'autologon_state_proof_result' -Path $statePath `
            -Tracked $false -LiveData (-not [bool]$StateResult.fixture_mode) -Generated $true `
            -Description 'Canonical AutoLogon state-proof result normalized from the legacy state-delta collector.' `
            -CreatedBy 'Invoke-SasAutoLogonDeployment' | Out-Null
    }

    $registry = Get-Content -LiteralPath $Context.artifact_registry_path -Raw -Encoding UTF8 | ConvertFrom-Json
    $Summary.artifact_count = @($registry.artifacts).Count
    Write-SasAutoLogonJson -Path $Context.summary_path -Value $Summary
    @(
        'SysAdminSuite canonical AutoLogon deployment',
        "Run ID: $($Context.run_id)",
        "Status: $($Summary.status)",
        "Classification: $($DeploymentResult.classification)",
        "Targets: $($Summary.target_count)",
        "Eligible: $($Summary.eligible_install_count)",
        "Final gate passed: $($DeploymentResult.deployment.final_gate_passed)",
        "Canonical front door used: $($DeploymentResult.transport.canonical_front_door_used)",
        "Cleanup verified: $($DeploymentResult.deployment.cleanup_verified)",
        "Zero SysAdminSuite remnants verified: $($DeploymentResult.deployment.zero_remnants_verified)",
        "Deployment result: $deploymentPath",
        "State result: $(if ($statePath) { $statePath } else { '[not emitted]' })",
        '',
        $DeploymentResult.proof_ceiling
    ) | Set-Content -LiteralPath $Context.operator_handoff_path -Encoding UTF8 -WhatIf:$false

    return [pscustomobject][ordered]@{
        workflow_id = $Context.run_id
        status = [string]$Summary.status
        target_count = [int]$Summary.target_count
        eligible_install_count = [int]$Summary.eligible_install_count
        output_root = $Context.run_root
        summary_json = $Context.summary_path
        deployment_result_json = $deploymentPath
        final_gate_result_json = $gatePath
        state_result_json = $statePath
        artifact_registry = $Context.artifact_registry_path
        handoff = $Context.operator_handoff_path
    }
}

if ($FixtureMode -and $AllowTargetMutation) { throw 'FixtureMode is offline and cannot be combined with -AllowTargetMutation.' }
if (-not $FixtureMode -and -not $WhatIfPreference -and -not $AllowTargetMutation) {
    throw 'Refusing target mutation without -AllowTargetMutation. Use -WhatIf for request validation or -FixtureMode for offline fixture proof.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$runContextModule = Join-Path $PSScriptRoot 'SasRunContext.psm1'
$requestModule = Join-Path $PSScriptRoot 'SasSoftwareInstallFinalization.psm1'
$transportModule = Join-Path $PSScriptRoot 'SasSoftwareDeploymentAdapter.psm1'
$stateDeltaScript = Join-Path $PSScriptRoot 'Invoke-SasAutoLogonStateDelta.ps1'
$finalGateScript = Join-Path $PSScriptRoot 'Invoke-SasAutoLogonFinalStepGate.ps1'
$validatedDeploymentScript = Join-Path $PSScriptRoot 'Invoke-SasValidatedSoftwareDeployment.ps1'
foreach ($path in @($runContextModule,$requestModule,$transportModule,$stateDeltaScript,$finalGateScript,$validatedDeploymentScript)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required AutoLogon workflow dependency: $path" }
}
Import-Module $runContextModule -Force
Import-Module $requestModule -Force
Import-Module $transportModule -Force

if ([string]::IsNullOrWhiteSpace($ApprovedAppsPath)) {
    $ApprovedAppsPath = Join-Path $repoRoot 'configs\software-packages\approved-apps.json'
}
$package = Get-SasApprovedAutoLogonPackage -CatalogPath $ApprovedAppsPath -ExpectedPackageId $PackageId `
    -ExpectedPackageName $PackageName -RequestedShareRoot $SoftwareShareRoot `
    -RequestedRelativePath $InstallerRelativePath -RequestedInstallMode $InstallMode

if ($FixtureMode) {
    if ([string]::IsNullOrWhiteSpace($InstallerSha256)) { $InstallerSha256 = ('0' * 64) }
    if (@($InstallerArguments).Count -eq 0) { $InstallerArguments = @('/fixture-quiet', '/fixture-no-restart') }
    if ([string]::IsNullOrWhiteSpace($InstallerArgumentsReference)) { $InstallerArgumentsReference = 'sanitized fixture packaging record' }
    if ([string]::IsNullOrWhiteSpace($AuthorizedBy)) { $AuthorizedBy = 'fixture approver' }
    if ([string]::IsNullOrWhiteSpace($RequestReference)) { $RequestReference = 'FIXTURE-REQUEST' }
    if ([string]::IsNullOrWhiteSpace($ChangeReference)) { $ChangeReference = 'FIXTURE-CHANGE' }
    if ([string]::IsNullOrWhiteSpace($TicketReference)) { $TicketReference = 'FIXTURE-TICKET' }
}
else {
    if ([string]::IsNullOrWhiteSpace($InstallerSha256) -or $InstallerSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
        throw 'A pinned 64-character -InstallerSha256 is required.'
    }
    if (@($InstallerArguments).Count -eq 0) { throw 'Explicit vendor-validated -InstallerArguments are required.' }
    if ([string]::IsNullOrWhiteSpace($InstallerArgumentsReference)) { throw '-InstallerArgumentsReference is required.' }
    foreach ($entry in @{
        AuthorizedBy = $AuthorizedBy; RequestReference = $RequestReference; ChangeReference = $ChangeReference; TicketReference = $TicketReference
    }.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) { throw "-$($entry.Key) is required." }
    }
}
if ($InstallerSha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'InstallerSha256 must contain exactly 64 hexadecimal characters.' }
if ($RequireValidSignature -and [string]::IsNullOrWhiteSpace($ExpectedSignerThumbprint)) {
    throw '-RequireValidSignature requires -ExpectedSignerThumbprint.'
}

$targets = @(Get-SasAutoLogonTargets -DirectTargets $ComputerName -CsvPath $TargetsCsv -Limit $MaxTargets)
$runId = 'autologon-deploy-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$contextParameters = @{
    WorkflowId = 'autologon-proof'
    RunId = $runId
    RepoRoot = $repoRoot
    Survey = $true
    RequestSummary = 'Validate, gate, and route AutoLogon through the canonical deployment front door.'
    SourceArtifact = 'scripts/Invoke-SasAutoLogonDeployment.ps1'
    CreatedBy = 'Invoke-SasAutoLogonDeployment'
}
if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) { $contextParameters.OutputRoot = $OutputRoot }
$context = New-SasRunContext @contextParameters

if (-not $FixtureMode -and $TransportPreflightPath.Count -ne $targets.Count) {
    throw "$Transport requires one fresh P02 result path per target, in the same order as the explicit targets."
}

$requestPaths = @()
$preflightPaths = @()
$transportDecisions = @()
$transportFailure = $null
for ($index = 0; $index -lt $targets.Count; $index++) {
    $canonicalTarget = if ($FixtureMode) { "fixture-$($index + 1).autologon.invalid" } else { $targets[$index] }
    $request = New-SasAutoLogonValidatedRequest `
        -RequestId ("$runId-$($index + 1)") `
        -Target $canonicalTarget `
        -Package $package `
        -Sha256 $InstallerSha256 `
        -Arguments @($InstallerArguments) `
        -ArgumentsReference $InstallerArgumentsReference `
        -Approver $AuthorizedBy `
        -RequestRef $RequestReference `
        -ChangeRef $ChangeReference `
        -TicketRef $TicketReference `
        -SignatureRequired ([bool]$RequireValidSignature) `
        -SignerThumbprint $ExpectedSignerThumbprint
    $errors = @(Test-SasValidatedDeploymentRequest -Request $request)
    if ($errors.Count -gt 0) { throw "Canonical AutoLogon request failed closed: $($errors -join ', ')" }
    $requestPath = Join-Path $context.directories.actions ("validated_deployment_request_{0}.json" -f ($index + 1))
    Write-SasAutoLogonJson -Path $requestPath -Value $request
    $requestPaths += $requestPath

    $preflightPath = if ($FixtureMode) {
        New-SasFixturePreflight -Scenario $FixtureScenario `
            -Destination (Join-Path $context.directories.actions ("transport_preflight_{0}.json" -f ($index + 1))) `
            -RepoRoot $repoRoot
    } else { [string]$TransportPreflightPath[$index] }
    $preflightPaths += $preflightPath
    try {
        $decision = Resolve-SasSoftwareDeploymentTransport -Transport $Transport -PreflightResultPath $preflightPath `
            -PreflightMaxAgeMinutes $PreflightMaxAgeMinutes -AllowFixturePreflight:$FixtureMode
        if ([string]$decision.selected_transport -ne 'SmbScheduledTask') {
            throw 'AutoLogon requires the canonical Kerberos/SMB scheduled-task transport; WinRM selection is not authorized.'
        }
        $transportDecisions += $decision
    }
    catch {
        $transportFailure = $_.Exception.Message
        break
    }
}

if ($transportFailure) {
    $deployment = [pscustomobject][ordered]@{
        schema_version = 'sas-autologon-deployment-result/v1'
        operation_id = 'autologon.admin_deploy'
        evidence_class = if ($FixtureMode) { 'sanitized_fixture' } else { 'operator_local' }
        classification = if ($FixtureMode) { 'fixture_contract_failed' } else { 'deployment_blocked' }
        reason_codes = @('transport_preflight_rejected')
        fixture_mode = [bool]$FixtureMode
        target_scope = [pscustomobject]@{ target_count = $targets.Count; identifiers_emitted = $false }
        transport = [pscustomobject]@{ preflight_classification = 'no_supported_transport'; selected_transport = 'none'; canonical_front_door_used = $false }
        authorization = [pscustomobject]@{ administrator_approved = (-not $FixtureMode); target_mutation_approved = [bool]$AllowTargetMutation }
        deployment = [pscustomobject]@{ final_gate_passed = $false; task_created = $false; executed_as_system = $false; installer_executed = $false; result_retrieved = $false; cleanup_verified = $false; zero_remnants_verified = $false }
        network_activity_performed = $false
        target_mutation_performed = $false
        proof_level = if ($FixtureMode) { 'sanitized_fixture_contract' } else { 'insufficient' }
        proof_ceiling = 'Transport selection was rejected before baseline reads or mutation; no installer, task, cleanup, reboot, sign-in, or runtime behavior is proven.'
    }
    $summary = [pscustomobject][ordered]@{
        schema_version = 'sas-run-summary/v1'; workflow_id = 'autologon-proof'; run_id = $runId
        status = if ($FixtureMode) { 'FIXTURE_FAIL' } else { 'BLOCKED' }
        target_count = $targets.Count; eligible_install_count = 0; install_planned_count = 0; install_completed_count = 0
        confirmed_state_transition_count = 0; cleanup_failure_count = 0; repo_artifact_remaining_count = 0
        target_mutation_performed = $false; startup_persistence_created = $false; default_password_value_collected = $false
        review_required = $true; artifact_count = 0; blocker = $transportFailure
    }
    Complete-SasAutoLogonRun -Context $context -DeploymentResult $deployment -GateResult $null -StateResult $null -Summary $summary
    return
}

$canonicalResults = @()
$canonicalFrontDoorUsed = $false
if ($WhatIfPreference -and -not $FixtureMode) {
    for ($index = 0; $index -lt $targets.Count; $index++) {
        $targetOutput = Join-Path $context.directories.actions ("canonical_plan_{0}" -f ($index + 1))
        $canonicalResults += & $validatedDeploymentScript -RequestPath $requestPaths[$index] -OutputRoot $targetOutput `
            -Transport $Transport -TransportPreflightPath @($preflightPaths[$index]) `
            -PreflightMaxAgeMinutes $PreflightMaxAgeMinutes -ResultTimeoutSeconds $ResultTimeoutSeconds -WhatIf
        $canonicalFrontDoorUsed = $true
    }
    $deployment = [pscustomobject][ordered]@{
        schema_version = 'sas-autologon-deployment-result/v1'; operation_id = 'autologon.admin_deploy'; evidence_class = 'operator_local'
        classification = 'deployment_planned'; reason_codes = @('validated_request_planned'); fixture_mode = $false
        target_scope = [pscustomobject]@{ target_count = $targets.Count; identifiers_emitted = $false }
        transport = [pscustomobject]@{ preflight_classification = 'kerberos_smb_task_ready'; selected_transport = 'kerberos_smb_task'; canonical_front_door_used = $canonicalFrontDoorUsed }
        authorization = [pscustomobject]@{ administrator_approved = $true; target_mutation_approved = $false }
        deployment = [pscustomobject]@{ final_gate_passed = $false; task_created = $false; executed_as_system = $false; installer_executed = $false; result_retrieved = $false; cleanup_verified = $false; zero_remnants_verified = $false }
        network_activity_performed = $false; target_mutation_performed = $false; proof_level = 'planned'
        proof_ceiling = 'Closed requests and canonical Kerberos/SMB transport selection were validated locally; no target read, mutation, installer, cleanup, reboot, sign-in, or runtime behavior is proven.'
    }
    $summary = [pscustomobject][ordered]@{
        schema_version = 'sas-run-summary/v1'; workflow_id = 'autologon-proof'; run_id = $runId; status = 'PLANNED_WHATIF'
        target_count = $targets.Count; eligible_install_count = 0; install_planned_count = $targets.Count; install_completed_count = 0
        confirmed_state_transition_count = 0; cleanup_failure_count = 0; repo_artifact_remaining_count = 0
        target_mutation_performed = $false; startup_persistence_created = $false; default_password_value_collected = $false
        review_required = $false; artifact_count = 0
    }
    Complete-SasAutoLogonRun -Context $context -DeploymentResult $deployment -GateResult $null -StateResult $null -Summary $summary
    return
}

$stateRunId = 'autologon-delta-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$stateOutputRoot = Join-Path $context.directories.evidence 'state'
$beforeParams = @{
    Mode = 'Before'; ComputerName = $targets; RunId = $stateRunId; OutputRoot = $stateOutputRoot
    TechnicianLabel = $TechnicianLabel; MaxTargets = $MaxTargets
}
if ($FixtureMode) { $beforeParams.FixtureMode = $true }
$before = & $stateDeltaScript @beforeParams
$beforeDirectory = Join-Path $before.output_root 'before'
if ($FixtureMode -and $FixtureScenario -eq 'already_configured') { Set-SasFixtureAlreadyConfigured -BeforeDirectory $beforeDirectory }
$eligibility = @(Get-SasBaselineEligibility -BeforeDirectory $beforeDirectory)
$eligibleTargets = @($eligibility | Where-Object { $_.eligibility_decision -eq 'ELIGIBLE_FOR_INSTALL' } | ForEach-Object { $_.computer_name })
$baselineFailureTargets = @($eligibility | Where-Object { $_.eligibility_decision -eq 'SKIP_BASELINE_COLLECTION_FAILED' } | ForEach-Object { $_.computer_name })
$alreadyConfiguredTargets = @($eligibility | Where-Object { $_.eligibility_decision -eq 'SKIP_ALREADY_CONFIGURED' } | ForEach-Object { $_.computer_name })

$gateInputPath = Join-Path $context.directories.actions 'autologon_final_step_gate_input.json'
$gateInput = [pscustomobject][ordered]@{
    run_id = $stateRunId
    phase = 'before_complete'
    targets = @($eligibleTargets | ForEach-Object { [pscustomobject]@{ computer_name = $_; hostname = $_ } })
}
Write-SasAutoLogonJson -Path $gateInputPath -Value $gateInput
$effectiveHostPolicy = $HostEligibilityPolicyPath
if ($FixtureMode) {
    $effectiveHostPolicy = New-SasFixtureHostPolicy -Targets $targets -Scenario $FixtureScenario `
        -Destination (Join-Path $context.directories.actions 'fixture_host_eligibility_policy.json')
}

$gateResults = @()
for ($index = 0; $index -lt $eligibleTargets.Count; $index++) {
    $gateParams = @{
        Target = $eligibleTargets[$index]; RunId = $stateRunId; BeforeSnapshotPath = $gateInputPath
        ApprovedAppsPath = $ApprovedAppsPath; OutputRoot = (Join-Path $context.directories.evidence ("final_gate_{0}" -f ($index + 1)))
        TechnicianLabel = $TechnicianLabel; ExecContext = $(if ($FixtureMode) { 'fixture' } else { 'remote' })
    }
    if (-not [string]::IsNullOrWhiteSpace($effectiveHostPolicy)) { $gateParams.HostEligibilityPolicyPath = $effectiveHostPolicy }
    if ($FixtureMode) { $gateParams.FixtureMode = $true }
    $gateResults += & $finalGateScript @gateParams
}
$canonicalGate = if ($gateResults.Count -gt 0) { ConvertTo-SasCanonicalGateResult -LegacyResults $gateResults -IsFixture ([bool]$FixtureMode) } else { $null }
$gatePassedTargets = @()
for ($index = 0; $index -lt $gateResults.Count; $index++) {
    if ([bool]$gateResults[$index].overall_pass) { $gatePassedTargets += $eligibleTargets[$index] }
}

$canonicalErrors = @()
for ($gateIndex = 0; $gateIndex -lt $gatePassedTargets.Count; $gateIndex++) {
    $target = $gatePassedTargets[$gateIndex]
    $originalIndex = [array]::IndexOf($targets, $target)
    if ($originalIndex -lt 0) { throw "Internal target/preflight mapping failed for $target" }
    if (-not $FixtureMode -and -not $PSCmdlet.ShouldProcess($target, "Deploy approved AutoLogon package through canonical Kerberos/SMB scheduled task")) {
        $canonicalErrors += 'mutation_cancelled_before_canonical_front_door'
        continue
    }
    $targetOutput = Join-Path $context.directories.actions ("canonical_deployment_{0}" -f ($originalIndex + 1))
    try {
        if ($FixtureMode) {
            $canonicalResults += & $validatedDeploymentScript -RequestPath $requestPaths[$originalIndex] -OutputRoot $targetOutput `
                -Transport $Transport -TransportPreflightPath @($preflightPaths[$originalIndex]) `
                -PreflightMaxAgeMinutes $PreflightMaxAgeMinutes -ResultTimeoutSeconds $ResultTimeoutSeconds `
                -AllowFixtures -WhatIf
        }
        else {
            $canonicalResults += & $validatedDeploymentScript -RequestPath $requestPaths[$originalIndex] -OutputRoot $targetOutput `
                -Transport $Transport -TransportPreflightPath @($preflightPaths[$originalIndex]) `
                -PreflightMaxAgeMinutes $PreflightMaxAgeMinutes -ResultTimeoutSeconds $ResultTimeoutSeconds `
                -AllowTargetMutation -Confirm:$false
        }
        $canonicalFrontDoorUsed = $true
    }
    catch {
        $canonicalErrors += $_.Exception.Message
        $candidate = @(Get-ChildItem -LiteralPath $targetOutput -Filter 'validated_deployment_result.json' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
        if ($candidate.Count -gt 0) {
            $canonicalResults += Get-Content -LiteralPath $candidate[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $canonicalFrontDoorUsed = $true
        }
    }
}

$captureAfter = (-not $FixtureMode) -or $FixtureScenario -in @('ready','already_configured','validation_failure','teardown_failure')
$after = $null
$afterSummary = $null
if ($captureAfter) {
    $afterParams = @{
        Mode = 'After'; ComputerName = $targets; RunId = $stateRunId; OutputRoot = $stateOutputRoot
        TechnicianLabel = $TechnicianLabel; MaxTargets = $MaxTargets
    }
    if ($FixtureMode) { $afterParams.FixtureMode = $true }
    $after = & $stateDeltaScript @afterParams
    $afterSummary = Get-Content -LiteralPath $after.summary_json -Raw -Encoding UTF8 | ConvertFrom-Json
}

$installRows = @()
foreach ($canonical in @($canonicalResults)) {
    if ($canonical.PSObject.Properties.Name -contains 'install_summary_path' -and
        -not [string]::IsNullOrWhiteSpace([string]$canonical.install_summary_path) -and
        (Test-Path -LiteralPath ([string]$canonical.install_summary_path) -PathType Leaf)) {
        $installSummary = Get-Content -LiteralPath ([string]$canonical.install_summary_path) -Raw -Encoding UTF8 | ConvertFrom-Json
        $installRows += @($installSummary.results)
    }
}
$allRows = $installRows.Count -gt 0 -and $installRows.Count -eq $gatePassedTargets.Count
$taskCreated = $allRows -and @($installRows | Where-Object { -not [bool]$_.task_created }).Count -eq 0
$executedAsSystem = $allRows -and @($installRows | Where-Object { -not [bool]$_.execution_as_system }).Count -eq 0
$installerExecuted = $allRows -and @($installRows | Where-Object { [string]$_.status -ne 'completed' }).Count -eq 0
$resultRetrieved = $allRows -and @($installRows | Where-Object { -not [bool]$_.result_retrieved }).Count -eq 0
$cleanupVerified = $allRows -and @($installRows | Where-Object { -not [bool]$_.cleanup_succeeded }).Count -eq 0
$zeroRemnants = $allRows -and @($installRows | Where-Object { [bool]$_.repo_artifact_remaining }).Count -eq 0
$gatePassed = $gateResults.Count -gt 0 -and $gateResults.Count -eq $eligibleTargets.Count -and @($gateResults | Where-Object { -not [bool]$_.overall_pass }).Count -eq 0

$confirmedCount = if ($afterSummary) { [int]$afterSummary.confirmed_state_transition_count } else { 0 }
$reviewCount = if ($afterSummary) {
    [int]$afterSummary.partial_change_review_count + [int]$afterSummary.regression_review_count + [int]$afterSummary.inconclusive_count
} else { 0 }
$liveCanonicalComplete = (-not $FixtureMode -and $canonicalResults.Count -eq $gatePassedTargets.Count -and $canonicalResults.Count -gt 0 -and
    @($canonicalResults | Where-Object { -not [bool]$_.deployment_complete }).Count -eq 0)
$liveSuccess = ($liveCanonicalComplete -and $gatePassed -and $taskCreated -and $executedAsSystem -and $installerExecuted -and
    $resultRetrieved -and $cleanupVerified -and $zeroRemnants -and $baselineFailureTargets.Count -eq 0 -and
    $confirmedCount -eq $eligibleTargets.Count -and $reviewCount -eq 0)
$fixturePass = ($FixtureMode -and (($FixtureScenario -eq 'ready' -and $canonicalFrontDoorUsed -and $gatePassed -and
    $confirmedCount -eq $eligibleTargets.Count -and $reviewCount -eq 0) -or
    ($FixtureScenario -eq 'already_configured' -and $eligibleTargets.Count -eq 0 -and $alreadyConfiguredTargets.Count -eq $targets.Count)))

$reasonCode = if ($FixtureMode) {
    switch ($FixtureScenario) {
        'ready' { 'fixture_canonical_path_validated' }
        'blocked' { 'final_step_gate_blocked' }
        'already_configured' { 'already_configured_skipped' }
        'hash_mismatch' { 'installer_hash_mismatch' }
        'transport_rejection' { 'transport_preflight_rejected' }
        'task_failure' { 'scheduled_task_execution_failed' }
        'validation_failure' { 'package_validation_failed' }
        'teardown_failure' { 'run_scoped_teardown_failed' }
    }
}
elseif ($liveSuccess) { 'canonical_deployment_validated_and_finalized' }
elseif ($alreadyConfiguredTargets.Count -eq $targets.Count) { 'all_targets_already_configured' }
elseif (-not $gatePassed) { 'final_step_gate_blocked' }
elseif ($canonicalErrors.Count -gt 0) { 'canonical_deployment_failed' }
elseif (-not $cleanupVerified -or -not $zeroRemnants) { 'run_scoped_teardown_failed' }
else { 'state_or_validation_incomplete' }

$classification = if ($FixtureMode) { $(if ($fixturePass) { 'fixture_contract_pass' } else { 'fixture_contract_failed' }) }
    elseif ($liveSuccess) { 'deployment_succeeded' }
    elseif ($canonicalResults.Count -eq 0) { 'deployment_blocked' }
    else { 'deployment_failed' }
$deployment = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-deployment-result/v1'
    operation_id = 'autologon.admin_deploy'
    evidence_class = if ($FixtureMode) { 'sanitized_fixture' } else { 'operator_local' }
    classification = $classification
    reason_codes = @($reasonCode)
    fixture_mode = [bool]$FixtureMode
    target_scope = [pscustomobject]@{ target_count = $targets.Count; identifiers_emitted = $false }
    transport = [pscustomobject]@{
        preflight_classification = 'kerberos_smb_task_ready'
        selected_transport = 'kerberos_smb_task'
        canonical_front_door_used = $canonicalFrontDoorUsed
    }
    authorization = [pscustomobject]@{
        administrator_approved = (-not $FixtureMode)
        target_mutation_approved = (-not $FixtureMode -and [bool]$AllowTargetMutation)
    }
    deployment = [pscustomobject]@{
        final_gate_passed = $gatePassed
        task_created = $(if ($FixtureMode) { $false } else { $taskCreated })
        executed_as_system = $(if ($FixtureMode) { $false } else { $executedAsSystem })
        installer_executed = $(if ($FixtureMode) { $false } else { $installerExecuted })
        result_retrieved = $(if ($FixtureMode) { $false } else { $resultRetrieved })
        cleanup_verified = $(if ($FixtureMode) { $false } else { $cleanupVerified })
        zero_remnants_verified = $(if ($FixtureMode) { $false } else { $zeroRemnants })
    }
    network_activity_performed = (-not $FixtureMode)
    target_mutation_performed = (-not $FixtureMode -and @($canonicalResults | Where-Object { [bool]$_.target_mutation_performed }).Count -gt 0)
    proof_level = if ($FixtureMode) { 'sanitized_fixture_contract' } elseif ($liveSuccess) { 'deployment_execution' } else { 'insufficient' }
    proof_ceiling = if ($FixtureMode) {
        'Sanitized canonical application fixture only; no target contact, task, installer, cleanup, reboot, automatic sign-in, current-token access, or application behavior is proven.'
    } else {
        'Canonical administrator deployment and state-delta evidence only; reboot, automatic sign-in, current-token file access, application behavior, and operator acceptance remain unproven.'
    }
}

$stateResult = New-SasCanonicalStateResult -IsFixture ([bool]$FixtureMode) -TargetCount $targets.Count `
    -BaselineFailureCount $baselineFailureTargets.Count -AlreadyConfiguredCount $alreadyConfiguredTargets.Count `
    -BeforeResult $before -AfterResult $after -AfterSummary $afterSummary -FixturePassed $fixturePass
$summaryStatus = if ($FixtureMode) { $(if ($fixturePass) { 'FIXTURE_PASS' } else { 'FIXTURE_FAIL' }) }
    elseif ($liveSuccess) { 'COMPLETED' }
    elseif ($classification -eq 'deployment_blocked') { 'BLOCKED' }
    else { 'COMPLETED_WITH_REVIEW' }
$summary = [pscustomobject][ordered]@{
    schema_version = 'sas-run-summary/v1'
    workflow_id = 'autologon-proof'
    run_id = $runId
    status = $summaryStatus
    target_count = $targets.Count
    eligible_install_count = $eligibleTargets.Count
    baseline_failure_count = $baselineFailureTargets.Count
    already_configured_count = $alreadyConfiguredTargets.Count
    install_planned_count = if ($FixtureMode -and $canonicalFrontDoorUsed) { $gatePassedTargets.Count } else { 0 }
    install_completed_count = if ($FixtureMode) { 0 } else { @($installRows | Where-Object { [string]$_.status -eq 'completed' }).Count }
    confirmed_state_transition_count = $confirmedCount
    cleanup_failure_count = if ($FixtureMode -and $FixtureScenario -eq 'teardown_failure') { 1 } else { @($installRows | Where-Object { -not [bool]$_.cleanup_succeeded }).Count }
    repo_artifact_remaining_count = if ($FixtureMode -and $FixtureScenario -eq 'teardown_failure') { 1 } else { @($installRows | Where-Object { [bool]$_.repo_artifact_remaining }).Count }
    target_mutation_performed = [bool]$deployment.target_mutation_performed
    startup_persistence_created = $false
    default_password_value_collected = $false
    canonical_front_door_used = $canonicalFrontDoorUsed
    final_gate_passed = $gatePassed
    deployment_result_classification = $classification
    state_result_classification = [string]$stateResult.classification
    review_required = ($classification -notin @('fixture_contract_pass','deployment_succeeded'))
    artifact_count = 0
}

Complete-SasAutoLogonRun -Context $context -DeploymentResult $deployment -GateResult $canonicalGate -StateResult $stateResult -Summary $summary
