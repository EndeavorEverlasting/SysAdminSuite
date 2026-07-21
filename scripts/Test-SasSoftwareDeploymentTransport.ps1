#Requires -Version 5.1
<#
.SYNOPSIS
Classifies one authorized FQDN for an explicitly selected deployment transport.
.DESCRIPTION
Runs bounded, read-only observations with the current Windows token by default.
Kerberos SMB plus Task Scheduler is the narrow default. WinRM is explicit, and
broad auto-discovery must be requested deliberately. Use -Credential only to
supply a runtime-only PSCredential. Fixture mode loads sanitized observations
and performs no network activity.
.PARAMETER ComputerName
One authorized fully qualified DNS name. The identifier is never written to the
sanitized result or English summary.
.PARAMETER AllowNetworkActivity
Required acknowledgement for live read-only observation.
.PARAMETER TransportIntent
The exact transport question to answer. Defaults to kerberos_smb_task. Select
winrm for a WinRM-only preflight. Select auto only when broad discovery across
both supported transports is justified.
.PARAMETER Credential
Optional runtime-only credential. It is never prompted for or serialized.
.PARAMETER TimeoutSeconds
Per-observation timeout from 1 through 30 seconds.
.PARAMETER FixtureMode
Selects offline fixture execution. Cannot be combined with live parameters.
.PARAMETER FixturePath
Path to a sanitized JSON fixture containing an observations object.
.PARAMETER OutputRoot
Approved ignored local output root. Defaults to survey/output/runs.
.PARAMETER PassThru
Returns the run context, result, and artifact paths.
#>

[CmdletBinding(DefaultParameterSetName = 'Live')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Live')]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [Parameter(Mandatory = $true, ParameterSetName = 'Live')]
    [switch]$AllowNetworkActivity,

    [ValidateSet('kerberos_smb_task', 'winrm', 'auto')]
    [string]$TransportIntent = 'kerberos_smb_task',

    [Parameter(Mandatory = $false, ParameterSetName = 'Live')]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory = $true, ParameterSetName = 'Fixture')]
    [switch]$FixtureMode,

    [Parameter(Mandatory = $true, ParameterSetName = 'Fixture')]
    [ValidateNotNullOrEmpty()]
    [string]$FixturePath,

    [ValidateRange(1, 30)]
    [int]$TimeoutSeconds = 5,

    [string]$OutputRoot,

    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$transportModulePath = Join-Path $PSScriptRoot 'SasSoftwareDeploymentTransport.psm1'
$lowNoiseTransportModulePath = Join-Path $PSScriptRoot 'SasSoftwareDeploymentLowNoise.psm1'
$lowNoisePolicyModulePath = Join-Path $PSScriptRoot 'SasLowNoisePolicy.psm1'
$runContextModulePath = Join-Path $PSScriptRoot 'SasRunContext.psm1'
Import-Module $transportModulePath -Force
Import-Module $lowNoiseTransportModulePath -Force
Import-Module $lowNoisePolicyModulePath -Force
Import-Module $runContextModulePath -Force

if ($PSCmdlet.ParameterSetName -eq 'Live' -and -not (Test-SasFqdn -ComputerName $ComputerName)) {
    throw 'ComputerName must be a fully qualified DNS name.'
}
if ($PSCmdlet.ParameterSetName -eq 'Live' -and -not $AllowNetworkActivity) {
    throw 'Live preflight requires explicit -AllowNetworkActivity acknowledgement.'
}
if ($PSCmdlet.ParameterSetName -eq 'Fixture' -and -not (Test-Path -LiteralPath $FixturePath -PathType Leaf)) {
    throw "Fixture file not found: $FixturePath"
}

$requestSummary = if ($FixtureMode) {
    "Offline sanitized software deployment transport fixture classification for intent $TransportIntent."
}
else {
    "Authorized bounded read-only software deployment transport preflight for intent $TransportIntent."
}

$contextParameters = @{
    WorkflowId = 'software-deployment-transport'
    RepoRoot = $repoRoot
    Survey = $true
    RequestSummary = $requestSummary
    CreatedBy = 'Test-SasSoftwareDeploymentTransport'
}
if ($OutputRoot) { $contextParameters.OutputRoot = $OutputRoot }
$context = New-SasRunContext @contextParameters

if ($FixtureMode) {
    $fixture = Get-Content -LiteralPath $FixturePath -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($null -eq $fixture.observations) { throw 'Fixture must contain an observations object.' }
    $observations = $fixture.observations
    $evidenceClass = 'sanitized_fixture'
    $networkActivity = $false
}
else {
    $observationParameters = @{
        ComputerName = $ComputerName
        TimeoutSeconds = $TimeoutSeconds
    }
    if ($PSBoundParameters.ContainsKey('Credential')) { $observationParameters.Credential = $Credential }

    if ($TransportIntent -eq 'auto') {
        $observations = Invoke-SasSoftwareDeploymentTransportObservation @observationParameters
    }
    else {
        $observationParameters.TransportIntent = $TransportIntent
        $observations = Invoke-SasSoftwareDeploymentLowNoiseObservation @observationParameters
    }
    $evidenceClass = 'operator_local_live'
    $networkActivity = $true
}

$result = New-SasSoftwareDeploymentTransportResult `
    -Observations $observations `
    -EvidenceClass $evidenceClass `
    -NetworkActivityPerformed $networkActivity

$testedPorts = @()
foreach ($port in @(5985, 5986, 445, 135)) {
    $name = "port_$port"
    if ([bool]$observations.tcp.$name.tested) { $testedPorts += $port }
}

$nextAction = if ($result.decision.classification -in @('kerberos_smb_task_ready', 'winrm_ready')) {
    'Review the schema-valid result and obtain separate authorization before any target mutation.'
}
else {
    'Review the fail-closed classification; do not broaden ports or retry without a recorded reason.'
}
$lowNoiseContext = New-SasLowNoiseContextObject `
    -ProfileId 'admin_surface_reachability' `
    -ProfileSource 'explicit_subset_override' `
    -EvidenceSource "software_install.transport_preflight:$TransportIntent" `
    -Disposition $result.decision.classification `
    -Reason (@($result.decision.reason_codes) -join ',') `
    -NetworkActivityPerformed $networkActivity `
    -TargetMutationPerformed $false `
    -NextAction $nextAction `
    -EffectivePorts $testedPorts

$resultPath = Join-Path $context.directories.artifacts 'software_deployment_transport_result.json'
$observationPath = Join-Path $context.directories.evidence 'sanitized_transport_observations.json'
$lowNoisePath = Join-Path $context.directories.evidence 'low_noise_context.json'
$summaryPath = Join-Path $context.directories.reports 'english_summary.txt'

$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
[pscustomobject]@{
    schema_version = 'sas-software-deployment-transport-observations/v1'
    evidence_class = $evidenceClass
    transport_intent = $TransportIntent
    observations = $observations
    network_activity_performed = $networkActivity
    target_mutation_performed = $false
    privacy = [pscustomobject]@{
        target_identifier_emitted = $false
        username_emitted = $false
        credential_emitted = $false
        ticket_bytes_emitted = $false
        raw_faults_emitted = $false
    }
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $observationPath -Encoding UTF8
$lowNoiseContext | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $lowNoisePath -Encoding UTF8

$englishSummary = @(
    'Software deployment transport preflight'
    "Transport intent: $TransportIntent"
    "Ports actually tested: $($testedPorts -join ', ')"
    "Classification: $($result.decision.classification)"
    "Selected transport: $($result.decision.selected_transport)"
    "Reason codes: $(@($result.decision.reason_codes) -join ', ')"
    "Evidence class: $($result.evidence_class)"
    "Network activity performed: $($result.network_activity_performed)"
    'Target mutation performed: False'
    'Target identifier emitted: False'
    "Proof ceiling: $($result.proof_ceiling)"
    ''
) + (Get-SasLowNoiseOperatorLines)
$englishSummary | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$englishSummary | Set-Content -LiteralPath $context.operator_handoff_path -Encoding UTF8

$networkDescription = if ($networkActivity) {
    "Authorized bounded read-only observations for intent $TransportIntent; tested ports: $($testedPorts -join ',')."
}
else {
    'No network activity performed.'
}
Register-SasArtifact -RegistryPath $context.artifact_registry_path -Role 'transport_result' -Path $resultPath -Tracked $false -LiveData (-not $FixtureMode) -Generated $true -Description 'Schema-valid sanitized transport observations and fail-closed decision.' -NetworkActivity $networkDescription -CreatedBy 'Test-SasSoftwareDeploymentTransport' | Out-Null
Register-SasArtifact -RegistryPath $context.artifact_registry_path -Role 'sanitized_observations' -Path $observationPath -Tracked $false -LiveData (-not $FixtureMode) -Generated $true -Description 'Sanitized observation evidence without identifiers, credentials, ticket bytes, or raw faults.' -NetworkActivity $networkDescription -CreatedBy 'Test-SasSoftwareDeploymentTransport' | Out-Null
Register-SasArtifact -RegistryPath $context.artifact_registry_path -Role 'low_noise_context' -Path $lowNoisePath -Tracked $false -LiveData (-not $FixtureMode) -Generated $true -Description 'Canonical low-noise rationale and exact effective port subset.' -NetworkActivity $networkDescription -CreatedBy 'Test-SasSoftwareDeploymentTransport' | Out-Null
Register-SasArtifact -RegistryPath $context.artifact_registry_path -Role 'english_summary' -Path $summaryPath -Tracked $false -LiveData (-not $FixtureMode) -Generated $true -Description 'Concise English rendering of the transport decision, low-noise context, and proof ceiling.' -NetworkActivity $networkDescription -CreatedBy 'Test-SasSoftwareDeploymentTransport' | Out-Null

$summary = Get-Content -LiteralPath $context.summary_path -Raw | ConvertFrom-Json
$summary.network_activity = $networkDescription
$summary.artifact_count = 4
$summary.review_required = ($result.decision.classification -in @('inconclusive', 'transport_reachable_authorization_denied'))
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $context.summary_path -Encoding UTF8

$contextPath = Join-Path $context.run_root 'context.json'
$storedContext = Get-Content -LiteralPath $contextPath -Raw | ConvertFrom-Json
$storedContext.network_activity = $networkDescription
$storedContext | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $contextPath -Encoding UTF8

$output = [pscustomobject]@{
    run_root = $context.run_root
    result_path = $resultPath
    observations_path = $observationPath
    low_noise_context_path = $lowNoisePath
    english_summary_path = $summaryPath
    artifact_registry_path = $context.artifact_registry_path
    result = $result
}

if ($PassThru) {
    return $output
}

$englishSummary
