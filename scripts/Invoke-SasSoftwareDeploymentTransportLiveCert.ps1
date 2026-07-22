#Requires -Version 5.1
<#
.SYNOPSIS
Certifies one authorized Kerberos SMB/Task Scheduler transport with a harmless task.
.DESCRIPTION
Consumes one fresh schema-valid SMB-ready preflight result. Live mode requires
separate network and target-mutation acknowledgements, creates one run-scoped
noninteractive SYSTEM task, retrieves its nonce-bound result, and verifies task
and staging teardown. Fixture mode performs no network activity or target mutation.
The command cannot install software and accepts no credentials or payload command.
.PARAMETER ComputerName
The one explicitly authorized fully qualified DNS name. It remains only in ignored
operator-local lifecycle evidence and is not emitted in the closed source result.
.PARAMETER PreflightResultPath
Fresh P02 result produced by Test-SasSoftwareDeploymentTransport.ps1.
.PARAMETER AllowNetworkActivity
Required acknowledgement for live SMB and Remote Task Scheduler activity.
.PARAMETER AllowTargetMutation
Required acknowledgement for the harmless run-scoped task and staging directory.
.PARAMETER FixtureMode
Runs a deterministic zero-network, zero-target-mutation lifecycle simulation.
.PARAMETER FixtureScenario
The bounded fixture lifecycle to simulate.
.PARAMETER OutputRoot
Approved ignored local output root. Defaults to survey/output/runs.
.PARAMETER PassThru
Returns the run root and generated artifact paths.
#>

[CmdletBinding(DefaultParameterSetName = 'Live')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Live')]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [Parameter(Mandatory = $true, ParameterSetName = 'Live')]
    [Parameter(Mandatory = $true, ParameterSetName = 'Fixture')]
    [ValidateNotNullOrEmpty()]
    [string]$PreflightResultPath,

    [Parameter(Mandatory = $true, ParameterSetName = 'Live')]
    [switch]$AllowNetworkActivity,

    [Parameter(Mandatory = $true, ParameterSetName = 'Live')]
    [switch]$AllowTargetMutation,

    [Parameter(Mandatory = $true, ParameterSetName = 'Fixture')]
    [switch]$FixtureMode,

    [Parameter(Mandatory = $false, ParameterSetName = 'Fixture')]
    [ValidateSet('success','worker_hash_mismatch','task_creation_failure','task_run_failure','result_timeout','malformed_result','not_system','wrong_nonce','task_deletion_failure','staging_deletion_failure')]
    [string]$FixtureScenario = 'success',

    [ValidateRange(1, 1440)]
    [int]$PreflightMaxAgeMinutes = 15,

    [ValidateRange(10, 600)]
    [int]$ResultTimeoutSeconds = 120,

    [string]$OutputRoot,
    [string]$RunId,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$adapterModulePath = Join-Path $PSScriptRoot 'SasSoftwareDeploymentAdapter.psm1'
$liveCertModulePath = Join-Path $PSScriptRoot 'SasSoftwareDeploymentLiveCert.psm1'
$runContextModulePath = Join-Path $PSScriptRoot 'SasRunContext.psm1'
Import-Module $adapterModulePath -Force
Import-Module $liveCertModulePath -Force
Import-Module $runContextModulePath -Force

if ($PSCmdlet.ParameterSetName -eq 'Live') {
    if (-not (Test-SasLiveCertFqdn -ComputerName $ComputerName)) { throw 'ComputerName must be the one authorized fully qualified DNS name.' }
    if (-not $AllowNetworkActivity) { throw 'Live certification requires explicit -AllowNetworkActivity acknowledgement.' }
    if (-not $AllowTargetMutation) { throw 'Live certification requires explicit -AllowTargetMutation acknowledgement.' }
}
if (-not (Test-Path -LiteralPath $PreflightResultPath -PathType Leaf)) { throw "Transport preflight result not found: $PreflightResultPath" }

$allowFixturePreflight = ($PSCmdlet.ParameterSetName -eq 'Fixture')
$preflight = Read-SasDeploymentTransportPreflight `
    -Path $PreflightResultPath `
    -MaxAgeMinutes $PreflightMaxAgeMinutes `
    -AllowFixture:$allowFixturePreflight
if ([string]$preflight.decision.classification -ne 'kerberos_smb_task_ready' -or
    [string]$preflight.decision.selected_transport -ne 'kerberos_smb_task' -or
    -not [bool]$preflight.proof.preflight_complete -or
    -not [bool]$preflight.proof.transport_authorization_proven) {
    throw 'Live certification requires one schema-valid kerberos_smb_task_ready P02 result selected for kerberos_smb_task.'
}
if ($PSCmdlet.ParameterSetName -eq 'Live') {
    if ([string]$preflight.evidence_class -ne 'operator_local_live' -or -not [bool]$preflight.network_activity_performed) {
        throw 'Live certification cannot consume sanitized fixture or non-live preflight evidence.'
    }
}
elseif ([string]$preflight.evidence_class -ne 'sanitized_fixture') {
    throw 'Fixture certification requires sanitized fixture preflight evidence.'
}

if (-not $RunId) { $RunId = New-SasRunId -Prefix 'transport-live-cert' }
if ($RunId -notmatch '^transport-live-cert-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$') { throw 'RunId must use the transport-live-cert timestamp and random-suffix format.' }

$requestSummary = if ($FixtureMode) {
    "Offline harmless transport live-cert fixture: $FixtureScenario."
}
else {
    'Authorized one-target harmless Kerberos SMB scheduled-task transport certification.'
}
$contextParameters = @{
    WorkflowId = 'software-deployment-transport-live-cert'
    RunId = $RunId
    RepoRoot = $repoRoot
    Survey = $true
    RequestSummary = $requestSummary
    SourceArtifact = (Resolve-Path -LiteralPath $PreflightResultPath).Path
    CreatedBy = 'Invoke-SasSoftwareDeploymentTransportLiveCert'
}
if ($OutputRoot) { $contextParameters.OutputRoot = $OutputRoot }
$context = New-SasRunContext @contextParameters

if ($FixtureMode) {
    $fixtureRoot = Join-Path $context.directories.evidence 'fixture-lifecycle'
    $lifecycle = Invoke-SasSoftwareDeploymentTransportLiveCertFixture `
        -FixtureRoot $fixtureRoot `
        -Scenario $FixtureScenario `
        -RunId $RunId
}
else {
    $lifecycle = Invoke-SasSoftwareDeploymentTransportLiveCert `
        -ComputerName $ComputerName `
        -RunId $RunId `
        -LocalRunRoot $context.directories.evidence `
        -ResultTimeoutSeconds $ResultTimeoutSeconds
}

$sourceResult = New-SasSoftwareDeploymentTransportLiveCertResult -Lifecycle $lifecycle -Preflight $preflight
$sourceResultPath = Join-Path $context.directories.artifacts 'operator_local_transport_live_cert_result.json'
$lifecyclePath = Join-Path $context.directories.evidence 'private_lifecycle_result.json'
$summaryPath = Join-Path $context.directories.reports 'english_summary.txt'
$sourceResult | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $sourceResultPath -Encoding UTF8
$lifecycle | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $lifecyclePath -Encoding UTF8

$certification = $sourceResult.certification
$sourcePass = ($certification.task_created -and $certification.executed_as_system -and
    $certification.result_retrieved -and $certification.task_deleted -and
    $certification.staging_deleted -and $certification.zero_remnants_verified -and
    -not $certification.software_installation_performed -and $certification.harmless_payload_only)
$proofDisposition = if ($FixtureMode) { 'CONTRACT FIXTURE ONLY' } elseif ($sourcePass) { 'LIVE CERT PASS' } else { 'LIVE CERT FAILED' }
$activityDescription = if ($FixtureMode) {
    'No network activity or target mutation performed; sanitized fixture lifecycle only.'
}
else {
    'Authorized network activity and harmless run-scoped target mutation were bounded to one FQDN.'
}
$englishSummary = @(
    'Software deployment transport live certification'
    "Disposition: $proofDisposition"
    'Selected transport: kerberos_smb_task'
    "Lifecycle status: $($lifecycle.status)"
    "Task created: $($certification.task_created)"
    "Executed as SYSTEM: $($certification.executed_as_system)"
    "Result retrieved before teardown: $($certification.result_retrieved)"
    "Task deleted: $($certification.task_deleted)"
    "Staging deleted: $($certification.staging_deleted)"
    "Zero remnants verified: $($certification.zero_remnants_verified)"
    'Software installation performed: False'
    'Harmless payload only: True'
    "Network activity performed: $($sourceResult.network_activity_performed)"
    "Target mutation performed: $($sourceResult.target_mutation_performed)"
    "Proof ceiling: $($sourceResult.proof_ceiling)"
)
$englishSummary | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$handoff = @($englishSummary)
if (-not $FixtureMode) {
    $handoff += ''
    $handoff += 'If the disposition is LIVE CERT PASS, review the private lifecycle evidence and explicitly confirm it before local receipt ingest:'
    $handoff += ".\scripts\Invoke-SasTransportProofIngest.ps1 -SourcePath `"$sourceResultPath`" -OperatorConfirmed"
}
else {
    $handoff += ''
    $handoff += 'Fixture output cannot be promoted to live certification proof.'
}
$handoff | Set-Content -LiteralPath $context.operator_handoff_path -Encoding UTF8

Register-SasArtifact -RegistryPath $context.artifact_registry_path -Role 'operator_local_transport_live_cert_result' -Path $sourceResultPath -Tracked $false -LiveData (-not $FixtureMode) -Generated $true -Description 'Closed identifier-free live-cert source result for local proof ingest.' -SourceArtifact $PreflightResultPath -NetworkActivity $activityDescription -CreatedBy 'Invoke-SasSoftwareDeploymentTransportLiveCert' | Out-Null
Register-SasArtifact -RegistryPath $context.artifact_registry_path -Role 'private_transport_live_cert_lifecycle' -Path $lifecyclePath -Tracked $false -LiveData (-not $FixtureMode) -Generated $true -Description 'Ignored operator-local lifecycle evidence; may contain the authorized target identifier.' -SourceArtifact $PreflightResultPath -NetworkActivity $activityDescription -CreatedBy 'Invoke-SasSoftwareDeploymentTransportLiveCert' | Out-Null
Register-SasArtifact -RegistryPath $context.artifact_registry_path -Role 'transport_live_cert_english_summary' -Path $summaryPath -Tracked $false -LiveData (-not $FixtureMode) -Generated $true -Description 'Identifier-free certification summary and proof ceiling.' -SourceArtifact $PreflightResultPath -NetworkActivity $activityDescription -CreatedBy 'Invoke-SasSoftwareDeploymentTransportLiveCert' | Out-Null

$runSummary = Get-Content -LiteralPath $context.summary_path -Raw | ConvertFrom-Json
$runSummary.network_activity = $activityDescription
$runSummary.artifact_count = 3
$runSummary.review_required = (-not $FixtureMode)
$runSummary | Add-Member -NotePropertyName disposition -NotePropertyValue $proofDisposition -Force
$runSummary | Add-Member -NotePropertyName lifecycle_status -NotePropertyValue ([string]$lifecycle.status) -Force
$runSummary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $context.summary_path -Encoding UTF8

$contextPath = Join-Path $context.run_root 'context.json'
$storedContext = Get-Content -LiteralPath $contextPath -Raw | ConvertFrom-Json
$storedContext.network_activity = $activityDescription
$storedContext | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $contextPath -Encoding UTF8

$output = [pscustomobject]@{
    workflow_id = 'software-deployment-transport-live-cert'
    run_id = $context.run_id
    run_root = $context.run_root
    disposition = $proofDisposition
    lifecycle_status = [string]$lifecycle.status
    result_path = $sourceResultPath
    lifecycle_path = $lifecyclePath
    english_summary_path = $summaryPath
    artifact_registry_path = $context.artifact_registry_path
    operator_handoff_path = $context.operator_handoff_path
    result = $sourceResult
}

if ($PassThru) { return $output }
$englishSummary
