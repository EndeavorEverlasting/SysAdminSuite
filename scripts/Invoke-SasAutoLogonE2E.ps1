#Requires -Version 5.1
<#
.SYNOPSIS
Runs the composed canonical AutoLogon workflow with harmless, zero-network fixtures.

.DESCRIPTION
Builds and executes the tracked harmless installer fixture, runs the real AutoLogon
application entrypoint and canonical SMB scheduled-task fixture adapter, exercises the
closed failure matrix, validates durable P09 artifacts, and emits only fixture-level
conclusions. The S-1-5-18 result is a simulated task-worker identity marker; no real task,
SYSTEM token, target, registry, reboot, sign-in, file-access, or application proof occurs.
#>

[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$OutputRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not [IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot = Join-Path $repoRoot $OutputRoot }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$approvedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'survey/output/e2e-validation')).TrimEnd('\')
if ($OutputRoot.Equals($approvedRoot, [StringComparison]::OrdinalIgnoreCase) -or
    -not $OutputRoot.StartsWith($approvedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'AutoLogon E2E output must be a journey-owned child directory under survey/output/e2e-validation.'
}

function Write-E2EJson {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Copy-E2EObject {
    param([Parameter(Mandatory = $true)]$Value)
    return ($Value | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
}

function Add-ValidationArtifact {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.Generic.List[object]]$List,
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Schema
    )
    $List.Add([pscustomobject][ordered]@{ role=$Role; path=$Path; schema=$Schema })
}

function Get-ApplicationResult {
    param([object[]]$Output)
    $matches = @($Output | Where-Object {
        $_ -and $_.PSObject.Properties.Name -contains 'deployment_result_json'
    })
    if ($matches.Count -ne 1) { throw "AutoLogon fixture entrypoint returned $($matches.Count) result objects." }
    return $matches[0]
}

function New-SanitizedGateArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$ReasonCode,
        [Parameter(Mandatory = $true)][ValidateSet('before_snapshot','approved_catalog')][string]$FailedPrerequisite,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    $templatePath = Join-Path $repoRoot 'Tests/Fixtures/autologon-contract-floor/final-gate-failure.fixture.json'
    $artifact = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $artifact.reason_codes = @($ReasonCode)
    foreach ($prerequisite in @($artifact.prerequisites)) {
        if ([string]$prerequisite.id -eq $FailedPrerequisite) {
            $prerequisite.passed = $false
            $prerequisite.reason_code = $ReasonCode
        }
        elseif ([bool]$prerequisite.mandatory) {
            $prerequisite.passed = $true
            $prerequisite.reason_code = "$(($prerequisite.id))_passed"
        }
    }
    Write-E2EJson -Path $Destination -Value $artifact
    return $Destination
}

$matrixPath = Join-Path $repoRoot 'Tests/Fixtures/autologon-canonical-e2e/scenarios.json'
$buildScript = Join-Path $repoRoot 'scripts/Build-SasSoftwareInstallFixtureExecutable.ps1'
$applicationScript = Join-Path $repoRoot 'scripts/Invoke-SasAutoLogonDeployment.ps1'
$finalGateScript = Join-Path $repoRoot 'scripts/Invoke-SasAutoLogonFinalStepGate.ps1'
$adapterModule = Join-Path $repoRoot 'scripts/SasSoftwareDeploymentAdapter.psm1'
$validatorScript = Join-Path $repoRoot 'tools/validate_autologon_e2e_artifacts.py'
$sourceEvidencePath = Join-Path $repoRoot 'Tests/Fixtures/autologon-contract-floor/source-success.fixture.json'
foreach ($requiredPath in @($matrixPath,$buildScript,$applicationScript,$finalGateScript,$adapterModule,$validatorScript,$sourceEvidencePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Missing AutoLogon E2E dependency: $requiredPath" }
}

if (Test-Path -LiteralPath $OutputRoot) { Remove-Item -LiteralPath $OutputRoot -Recurse -Force }
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$rawRoot = Join-Path $OutputRoot 'raw-fixture-evidence'
$generatedRoot = Join-Path $rawRoot 'generated-installer'
$fixtureTarget = Join-Path $rawRoot 'harmless-installer-target'
$applicationRoot = Join-Path $rawRoot 'application-scenarios'
$gateRoot = Join-Path $rawRoot 'final-gate-scenarios'
$adapterRoot = Join-Path $rawRoot 'canonical-adapter'
New-Item -ItemType Directory -Path $generatedRoot,$fixtureTarget,$applicationRoot,$gateRoot,$adapterRoot -Force | Out-Null

$matrix = Get-Content -LiteralPath $matrixPath -Raw -Encoding UTF8 | ConvertFrom-Json
$scenarioRows = New-Object Collections.Generic.List[object]
$validationArtifacts = New-Object Collections.Generic.List[object]
$failures = New-Object Collections.Generic.List[string]

# Build and execute a harmless generated Windows executable against an isolated local fixture root.
$installerPath = Join-Path $generatedRoot 'sysadminsuite-autologon-fixture.exe'
$buildOutput = @(& $buildScript -OutputPath $installerPath)
$build = @($buildOutput | Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'executable_sha256' })[-1]
$generatedHash = ([string]$build.executable_sha256).ToLowerInvariant()
$installedMarker = Join-Path $fixtureTarget 'InstalledPackages/SysAdminSuiteFixturePackage/dummy-installed.txt'
$installedManifest = Join-Path $fixtureTarget 'InstalledPackages/SysAdminSuiteFixturePackage/manifest.json'
$installerLog = Join-Path $fixtureTarget 'InstallerLogs/autologon-fixture.jsonl'
$installerArguments = @(
    ('--target-root="{0}"' -f $fixtureTarget),
    '--package-name="SysAdminSuite AutoLogon Fixture"',
    '--version="1.0.0"',
    '--dummy-relative-path="InstalledPackages\SysAdminSuiteFixturePackage\dummy-installed.txt"',
    ('--log-path="{0}"' -f $installerLog)
)
$installerProcess = Start-Process -FilePath $installerPath -ArgumentList $installerArguments -Wait -PassThru
$generatedInstallerExecuted = ($installerProcess.ExitCode -eq 0 -and
    (Test-Path -LiteralPath $installedMarker -PathType Leaf) -and
    (Test-Path -LiteralPath $installedManifest -PathType Leaf) -and
    (Test-Path -LiteralPath $installerLog -PathType Leaf))
if (-not $generatedInstallerExecuted) { $failures.Add('harmless generated installer did not produce its closed fixture state') }
$pinnedSourceHashVerified = ((Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $generatedHash)
if (-not $pinnedSourceHashVerified) { $failures.Add('generated installer hash changed after build') }

# Exercise the canonical adapter's staged hash, simulated S-1-5-18 worker result, retrieval, and teardown chain.
Import-Module $adapterModule -Force
$adapter = Invoke-SasSmbScheduledTaskDeploymentFixture -FixtureRoot $adapterRoot -Scenario success
$adapterResultPath = Join-Path $rawRoot 'canonical_adapter_result.json'
Write-E2EJson -Path $adapterResultPath -Value $adapter
$stagedHashVerified = ([bool]$adapter.hashes_verified -and
    [string]$adapter.source_sha256 -eq [string]$adapter.target_sha256 -and
    [string]$adapter.worker_source_sha256 -eq [string]$adapter.worker_target_sha256)
$adapterCleanupVerified = ([bool]$adapter.cleanup.task_deletion_succeeded -and
    [bool]$adapter.cleanup.run_root_deletion_succeeded -and
    -not [bool]$adapter.cleanup.task_remaining -and
    -not [bool]$adapter.cleanup.run_root_remaining)
$zeroRunScopedRemnants = ($adapterCleanupVerified -and [bool]$adapter.task.absent_verified)
foreach ($check in @(
    @{ passed=$stagedHashVerified; message='canonical adapter staged hashes were not verified' },
    @{ passed=[bool]$adapter.execution.as_system; message='canonical adapter did not emit its simulated SYSTEM marker' },
    @{ passed=[bool]$adapter.result_retrieval.succeeded; message='canonical adapter did not retrieve its closed fixture result' },
    @{ passed=$zeroRunScopedRemnants; message='canonical adapter did not prove fixture task/run-root removal' }
)) {
    if (-not [bool]$check.passed) { $failures.Add([string]$check.message) }
}

# Use one synthetic catalog for application scenarios and a disabled clone for the gate matrix.
$catalog = [pscustomobject][ordered]@{
    schema_version = 'sas-approved-software-catalog/v1'
    software_share_root = '\\fixture.invalid\'
    package_root_relative_path = 'packages'
    catalog_policy = [pscustomobject]@{}
    packages = @([pscustomobject][ordered]@{
        id='autologon'; display_name='NW AutoLogon Setup x64'; source_folder_relative_path='packages\AutoLogonSetup'
        installer_file='SysAdminSuiteAutoLogonFixture.exe'; default_install_mode='CopyThenInstall'
        default_installer_arguments=@(); requires_validated_installer_arguments=$true; install_enabled=$true
        readiness='sanitized_fixture'; acceptance=[pscustomobject]@{}; notes='Sanitized E2E fixture only.'
    })
}
$catalogPath = Join-Path $rawRoot 'approved-apps.fixture.json'
Write-E2EJson -Path $catalogPath -Value $catalog
$disabledCatalog = Copy-E2EObject -Value $catalog
$disabledCatalog.packages[0].install_enabled = $false
$disabledCatalogPath = Join-Path $rawRoot 'approved-apps-disabled.fixture.json'
Write-E2EJson -Path $disabledCatalogPath -Value $disabledCatalog

$hostPolicyPath = Join-Path $rawRoot 'host-policy.fixture.json'
$hostPolicy = [pscustomobject][ordered]@{
    schema_version='sas-host-eligibility-policy/v1'; policy_id='autologon-e2e-final-gate'; policy_version='1.0.0'
    patterns=@([pscustomobject][ordered]@{ name='fixture'; match_type='regex'; regex='^FIXTURE001$'; actions=@('fixture') })
}
Write-E2EJson -Path $hostPolicyPath -Value $hostPolicy
$gateRunId = 'autologon-delta-20000101-000000-00000000'
$beforePath = Join-Path $rawRoot 'before-complete.fixture.json'
Write-E2EJson -Path $beforePath -Value ([pscustomobject][ordered]@{
    run_id=$gateRunId; phase='before_complete'; targets=@([pscustomobject]@{ computer_name='FIXTURE001'; hostname='FIXTURE001' })
})

foreach ($scenario in @($matrix.scenarios)) {
    $id = [string]$scenario.id
    $classification = [string]$scenario.expected_classification
    $reasonCode = [string]$scenario.expected_reason_code
    $scenarioPassed = $false
    try {
        switch ([string]$scenario.kind) {
            'application' {
                $scenarioOutput = Join-Path $applicationRoot $id
                $applicationOutput = @(& $applicationScript `
                    -ComputerName 'FIXTURE001' `
                    -FixtureMode `
                    -FixtureScenario ([string]$scenario.application_scenario) `
                    -ApprovedAppsPath $catalogPath `
                    -InstallerSha256 $generatedHash `
                    -OutputRoot $scenarioOutput)
                $application = Get-ApplicationResult -Output $applicationOutput
                $deployment = Get-Content -LiteralPath $application.deployment_result_json -Raw -Encoding UTF8 | ConvertFrom-Json
                $summary = Get-Content -LiteralPath $application.summary_json -Raw -Encoding UTF8 | ConvertFrom-Json
                $expectedDeploymentClass = if ($id -in @('canonical_success','already_configured')) { 'fixture_contract_pass' } else { 'fixture_contract_failed' }
                $scenarioPassed = ([string]$deployment.classification -eq $expectedDeploymentClass -and
                    @($deployment.reason_codes) -contains $reasonCode -and
                    -not [bool]$deployment.network_activity_performed -and
                    -not [bool]$deployment.target_mutation_performed -and
                    [string]$deployment.proof_level -eq 'sanitized_fixture_contract')
                if ($id -eq 'canonical_success') {
                    $scenarioPassed = ($scenarioPassed -and [bool]$deployment.deployment.final_gate_passed -and
                        [bool]$deployment.transport.canonical_front_door_used -and [int]$summary.fixture_adapter_result_count -eq 1)
                }
                elseif ($id -eq 'cleanup_failure') {
                    $scenarioPassed = ($scenarioPassed -and [int]$summary.cleanup_failure_count -eq 1 -and
                        [int]$summary.repo_artifact_remaining_count -eq 1)
                }
                elseif ($id -in @('state_mismatch','missing_password_presence')) {
                    $state = Get-Content -LiteralPath $application.state_result_json -Raw -Encoding UTF8 | ConvertFrom-Json
                    $scenarioPassed = ($scenarioPassed -and [string]$state.classification -eq 'fixture_contract_failed' -and
                        -not [bool]$state.proof.expected_account_match -and -not [bool]$state.safety.default_password_value_collected)
                    if ($id -eq 'missing_password_presence') {
                        $afterSnapshots = @(Get-ChildItem -LiteralPath $application.output_root -Filter '*.json' -File -Recurse |
                            Where-Object { $_.FullName -match '[\\/]after[\\/]' })
                        $passwordSignalMissing = $false
                        foreach ($snapshotPath in $afterSnapshots) {
                            $snapshot = Get-Content -LiteralPath $snapshotPath.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                            if ($snapshot.PSObject.Properties.Name -contains 'autologon' -and
                                $snapshot.autologon.PSObject.Properties.Name -contains 'default_password_present' -and
                                -not [bool]$snapshot.autologon.default_password_present -and
                                -not [bool]$snapshot.autologon.default_password_value_collected) {
                                $passwordSignalMissing = $true
                            }
                        }
                        $scenarioPassed = ($scenarioPassed -and $passwordSignalMissing)
                    }
                }
                Add-ValidationArtifact -List $validationArtifacts -Role "$id-deployment" -Path ([string]$application.deployment_result_json) `
                    -Schema 'schemas/harness/autologon-deployment-result.schema.json'
                if ($application.final_gate_result_json) {
                    Add-ValidationArtifact -List $validationArtifacts -Role "$id-final-gate" -Path ([string]$application.final_gate_result_json) `
                        -Schema 'schemas/harness/autologon-final-step-gate-result.schema.json'
                }
                if ($application.state_result_json) {
                    Add-ValidationArtifact -List $validationArtifacts -Role "$id-state" -Path ([string]$application.state_result_json) `
                        -Schema 'schemas/harness/autologon-state-proof-result.schema.json'
                }
            }
            'request_rejection' {
                $caught = $null
                try {
                    & $applicationScript -ComputerName 'FIXTURE001' -FixtureMode -FixtureScenario 'ready' `
                        -ApprovedAppsPath $catalogPath -InstallerSha256 $generatedHash -AuthorizedBy 'x' `
                        -OutputRoot (Join-Path $applicationRoot $id) | Out-Null
                }
                catch { $caught = $_.Exception.Message }
                $scenarioPassed = (-not [string]::IsNullOrWhiteSpace($caught) -and $caught -match 'AUTHORIZATION_FIELD_INVALID:authorized_by')
            }
            'final_gate' {
                $gateOutput = Join-Path $gateRoot $id
                $gateParams = @{
                    Target='FIXTURE001'; RunId=$gateRunId; ApprovedAppsPath=$catalogPath
                    HostEligibilityPolicyPath=$hostPolicyPath; OutputRoot=$gateOutput; ExecContext='fixture'; FixtureMode=$true
                }
                if ($id -eq 'missing_before_evidence') { $gateParams.BeforeSnapshotPath = (Join-Path $rawRoot 'missing-before.json') }
                else { $gateParams.BeforeSnapshotPath = $beforePath; $gateParams.ApprovedAppsPath = $disabledCatalogPath }
                $legacyGate = & $finalGateScript @gateParams
                $failedId = if ($id -eq 'missing_before_evidence') { 'before_snapshot' } else { 'approved_catalog' }
                $scenarioPassed = (-not [bool]$legacyGate.overall_pass -and
                    @($legacyGate.prerequisites | Where-Object { [string]$_.id -eq $failedId -and -not [bool]$_.passed }).Count -eq 1)
                $gateArtifactPath = Join-Path $gateOutput 'autologon_final_step_gate_result.json'
                New-SanitizedGateArtifact -ReasonCode $reasonCode -FailedPrerequisite $failedId -Destination $gateArtifactPath | Out-Null
                Add-ValidationArtifact -List $validationArtifacts -Role "$id-final-gate" -Path $gateArtifactPath `
                    -Schema 'schemas/harness/autologon-final-step-gate-result.schema.json'
            }
            default { throw "Unknown AutoLogon E2E scenario kind: $($scenario.kind)" }
        }
    }
    catch {
        $failures.Add("$id failed unexpectedly: $($_.Exception.Message)")
        $scenarioPassed = $false
    }
    if (-not $scenarioPassed) { $failures.Add("$id did not reach $classification/$reasonCode") }
    $scenarioRows.Add([pscustomobject][ordered]@{
        id=$id; status=$(if ($scenarioPassed) { 'PASS' } else { 'FAIL' })
        classification=$classification; reason_codes=@($reasonCode)
    })
}

# Hash the sanitized P09 source fixture in place and emit a receipt that is structurally unable to become live proof.
$sourceEvidence = Get-Content -LiteralPath $sourceEvidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
$receiptPath = Join-Path $OutputRoot 'autologon_proof_receipt.json'
$receipt = [pscustomobject][ordered]@{
    schema_version='sas-autologon-proof-receipt/v1'
    source_evidence_sha256=(Get-FileHash -LiteralPath $sourceEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    source_evidence_size_bytes=(Get-Item -LiteralPath $sourceEvidencePath).Length
    classification='contract_only'
    proof_level='sanitized_fixture_contract'
    reason_codes=@('sanitized_fixture_contract')
    operator_confirmed=$false
    privacy_status='public_safe_source_hashed_not_copied'
}
Write-E2EJson -Path $receiptPath -Value $receipt
Add-ValidationArtifact -List $validationArtifacts -Role 'receipt-source-fixture' -Path $sourceEvidencePath `
    -Schema 'schemas/harness/autologon-proof-source-evidence.schema.json'
Add-ValidationArtifact -List $validationArtifacts -Role 'public-safe-receipt' -Path $receiptPath `
    -Schema 'schemas/harness/autologon-proof-receipt.schema.json'
if ([string]$sourceEvidence.classification -ne 'fixture_contract_only' -or [bool]$sourceEvidence.operator_confirmation -or
    [string]$receipt.classification -ne 'contract_only') {
    $failures.Add('sanitized receipt ingestion promoted fixture evidence beyond contract_only')
}

# Remove the harmless installed fixture state after proving the executable behavior.
if (Test-Path -LiteralPath $fixtureTarget) { Remove-Item -LiteralPath $fixtureTarget -Recurse -Force }
if (Test-Path -LiteralPath $fixtureTarget) { $failures.Add('harmless installer fixture target survived E2E teardown') }

$scenarioFailed = @($scenarioRows | Where-Object { $_.status -ne 'PASS' }).Count
$resultPath = Join-Path $OutputRoot 'autologon_canonical_e2e_result.json'
$result = [pscustomobject][ordered]@{
    schema_version='sas-autologon-canonical-e2e-result/v1'
    status=$(if ($failures.Count -eq 0 -and $scenarioFailed -eq 0) { 'PASS' } else { 'FAIL' })
    profile_id='autologon'
    journey_id='autologon-canonical-fixture-e2e'
    proof_class='composed-sanitized-fixture-e2e'
    counts=[pscustomobject][ordered]@{ total=$scenarioRows.Count; passed=($scenarioRows.Count - $scenarioFailed); failed=$scenarioFailed }
    safety=[pscustomobject][ordered]@{
        external_network_activity_performed=$false; live_target_mutation_performed=$false; real_scheduled_task_created=$false
        reboot_performed=$false; automatic_sign_in_observed=$false; current_token_access_proven=$false
        application_behavior_proven=$false; default_password_value_read=$false; secret_value_emitted=$false
    }
    fixture_execution=[pscustomobject][ordered]@{
        generated_installer_executed=[bool]$generatedInstallerExecuted
        generated_installer_sha256=$generatedHash
        pinned_source_hash_verified=[bool]$pinnedSourceHashVerified
        staged_hash_verified=[bool]$stagedHashVerified
        fixture_task_lifecycle_simulated=$true
        simulated_execution_identity_sid='S-1-5-18'
        system_execution_is_simulated=$true
        closed_result_retrieved=[bool]$adapter.result_retrieval.succeeded
        cleanup_verified=[bool]$adapterCleanupVerified
        zero_run_scoped_remnants_verified=[bool]$zeroRunScopedRemnants
    }
    receipt=[pscustomobject][ordered]@{
        classification='contract_only'; proof_level='sanitized_fixture_contract'
        source_evidence_copied=$false; live_proof_promoted=$false
    }
    # Windows PowerShell 5.1 can throw "Argument types do not match" when @(...)
    # directly wraps a generic List[T]. Materialize an ordinary array explicitly.
    scenarios=$scenarioRows.ToArray()
    proof_ceiling='Composed sanitized fixture E2E only. No real package deployment, target contact, scheduled task, SYSTEM token, Winlogon mutation, reboot, automatic sign-in, current-token access, application behavior, or operator acceptance is proven.'
}
Write-E2EJson -Path $resultPath -Value $result
Add-ValidationArtifact -List $validationArtifacts -Role 'autologon-canonical-e2e-result' -Path $resultPath `
    -Schema 'schemas/harness/autologon-canonical-e2e-result.schema.json'

$artifactManifestPath = Join-Path $rawRoot 'durable-artifact-validation-manifest.json'
Write-E2EJson -Path $artifactManifestPath -Value ([pscustomobject][ordered]@{
    schema_version='sas-autologon-e2e-artifact-validation/v1'; artifacts=$validationArtifacts.ToArray()
})
$python = Get-Command python -ErrorAction SilentlyContinue
$pythonArguments = @($validatorScript,'--manifest',$artifactManifestPath)
if (-not $python) {
    $python = Get-Command py -ErrorAction SilentlyContinue
    if (-not $python) { throw 'Python 3 is required to validate durable AutoLogon E2E artifacts.' }
    $pythonArguments = @('-3') + $pythonArguments
}
$validationOutput = @(& $python.Source @pythonArguments 2>&1 | ForEach-Object { $_.ToString() })
if ($LASTEXITCODE -ne 0) { throw "Durable AutoLogon artifact validation failed: $($validationOutput -join ' ')" }

$matrixOutputPath = Join-Path $OutputRoot 'autologon_e2e_matrix.txt'
$matrixLines = New-Object Collections.Generic.List[string]
$matrixLines.Add('SYSADMINSUITE AUTOLOGON CANONICAL FIXTURE E2E')
$matrixLines.Add('Profile: autologon')
$matrixLines.Add('Journey: autologon-canonical-fixture-e2e')
$matrixLines.Add('Proof class: composed-sanitized-fixture-e2e')
$matrixLines.Add('Live target proof: false')
$matrixLines.Add('SYSTEM identity: simulated fixture marker only')
$matrixLines.Add('')
foreach ($row in $scenarioRows) { $matrixLines.Add("[$($row.status)] $($row.id) - $($row.classification)") }
$matrixLines.Add('')
$matrixLines.Add("Result: $($result.counts.passed) passed / $($result.counts.failed) failed")
$matrixLines.Add([string]$result.proof_ceiling)
$matrixLines | Set-Content -LiteralPath $matrixOutputPath -Encoding UTF8

foreach ($line in $matrixLines) { Write-Host $line }
if ([string]$result.status -ne 'PASS') {
    foreach ($failure in $failures) { Write-Error $failure }
    exit 1
}
