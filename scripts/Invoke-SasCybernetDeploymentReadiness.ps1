#Requires -Version 5.1
<#
.SYNOPSIS
Runs the one-target low-noise readiness chain used by Cybernet software deployment.
.DESCRIPTION
Checks the local Northwell network posture, resolves one authorized hostname through the
canonical repository target resolver, and runs only the Kerberos SMB plus Remote Task Scheduler
transport preflight. The command creates no remote task, writes nothing to the target, installs
no software, and never broadens to WinRM or automatic transport discovery.
#>
[CmdletBinding(DefaultParameterSetName = 'Live')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [Parameter(Mandatory = $true, ParameterSetName = 'Live')]
    [switch]$AllowNetworkActivity,

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

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$networkGatePath = Join-Path $PSScriptRoot 'Confirm-SasNorthwellNetwork.ps1'
$transportPath = Join-Path $PSScriptRoot 'Test-SasSoftwareDeploymentTransport.ps1'
$transportModulePath = Join-Path $PSScriptRoot 'SasSoftwareDeploymentTransport.psm1'
$targetResolutionModulePath = Join-Path $PSScriptRoot 'SasTargetNameResolution.psm1'
$runContextModulePath = Join-Path $PSScriptRoot 'SasRunContext.psm1'
foreach ($requiredPath in @($networkGatePath, $transportPath, $transportModulePath, $targetResolutionModulePath, $runContextModulePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Missing Cybernet deployment-readiness dependency: $requiredPath"
    }
}
Import-Module $transportModulePath -Force
Import-Module $targetResolutionModulePath -Force
Import-Module $runContextModulePath -Force

$targetInput = $ComputerName.Trim().TrimEnd('.')
$inputIsFqdn = $targetInput.Contains('.')
if ($inputIsFqdn) {
    if (-not (Test-SasCanonicalFqdn -Value $targetInput)) {
        throw 'Target name is not a valid fully qualified DNS name.'
    }
}
elseif (-not (Test-SasDnsHostLabel -Value $targetInput)) {
    throw 'Target name must be one valid short hostname or fully qualified DNS name.'
}
if ($PSCmdlet.ParameterSetName -eq 'Live' -and -not $AllowNetworkActivity) {
    throw 'Live Cybernet deployment readiness requires explicit -AllowNetworkActivity acknowledgement.'
}
if ($PSCmdlet.ParameterSetName -eq 'Fixture' -and -not (Test-Path -LiteralPath $FixturePath -PathType Leaf)) {
    throw "Fixture file not found: $FixturePath"
}
if ($FixtureMode -and -not $inputIsFqdn) {
    throw 'Fixture mode requires one syntactically valid FQDN and performs no DNS lookup.'
}

function Get-SasTargetFingerprint {
    param([Parameter(Mandatory = $true)][string]$TargetValue)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($TargetValue.ToLowerInvariant())
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha.Dispose()
    }
}

$targetFqdn = if ($FixtureMode) { $targetInput.ToLowerInvariant() } else { $null }
$networkActivityDescription = if ($FixtureMode) {
    'No network activity performed.'
}
else {
    'Bounded canonical DNS resolution plus Kerberos SMB and Task Scheduler readiness observations for one authorized target.'
}
$requestSummary = if ($FixtureMode) {
    'Offline sanitized Cybernet software deployment readiness fixture.'
}
else {
    'One-target low-noise Cybernet software deployment readiness probe.'
}
$contextParameters = @{
    WorkflowId = 'cybernet-deployment-readiness'
    RepoRoot = $repoRoot
    Survey = $true
    RequestSummary = $requestSummary
    CreatedBy = 'Invoke-SasCybernetDeploymentReadiness'
}
if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) { $contextParameters.OutputRoot = $OutputRoot }
$context = New-SasRunContext @contextParameters
$resultPath = Join-Path $context.directories.artifacts 'cybernet_deployment_readiness_result.json'
$summaryPath = Join-Path $context.directories.reports 'english_summary.txt'

# Keep the child transport run under a bounded repo-local output root rather than nesting a
# second workflow/run-id tree beneath the readiness run. Windows PowerShell 5.1 field paths can
# otherwise exceed the legacy path boundary before request.json is written, even when the parent
# deployment already uses a short-path alias.
$transportOutputRoot = Join-Path $repoRoot 'survey\output\t'
New-Item -ItemType Directory -Path $transportOutputRoot -Force | Out-Null

$result = [ordered]@{
    schema_version = 'sas-cybernet-deployment-readiness-result/v1'
    run_id = $context.run_id
    target_scope = [ordered]@{
        target_count = 1
        target_fingerprint = Get-SasTargetFingerprint -TargetValue $(if ($FixtureMode) { $targetFqdn } else { $targetInput })
        identifier_emitted = $false
        input_was_fqdn = $inputIsFqdn
    }
    evidence_class = if ($FixtureMode) { 'sanitized_fixture' } else { 'operator_local_live' }
    network_gate_required = (-not $FixtureMode)
    network_gate_passed = $null
    transport_intent = 'kerberos_smb_task'
    transport_result_path = $null
    transport_classification = $null
    selected_transport = 'none'
    tested_ports = @()
    transport_preflight_complete = $false
    transport_authorization_proven = $false
    network_activity_performed = $false
    target_mutation_performed = $false
    ready_for_deployment = $false
    status = 'STARTED'
    reason = $null
    result_path = $resultPath
    proof_ceiling = 'Read-only one-target deployment transport readiness only; no task creation, software execution, target mutation, restart, or runtime acceptance is proven.'
}

$script:artifactRegistered = $false
function Save-SasReadinessResult {
    $result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}
function Register-SasReadinessArtifact {
    if ($script:artifactRegistered) { return }
    Register-SasArtifact -RegistryPath $context.artifact_registry_path -Role 'cybernet_deployment_readiness' -Path $resultPath -Tracked $false -LiveData (-not $FixtureMode) -Generated $true -Description 'One-target low-noise Cybernet deployment readiness classification without target identifiers.' -NetworkActivity $networkActivityDescription -CreatedBy 'Invoke-SasCybernetDeploymentReadiness' | Out-Null
    $script:artifactRegistered = $true
}
Save-SasReadinessResult

try {
    if (-not $FixtureMode) {
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $networkGatePath -Purpose 'Cybernet software deployment readiness' -NoOpenWifiSettings
        $gateExit = [int]$LASTEXITCODE
        if ($gateExit -ne 0) {
            $result.network_gate_passed = $false
            throw "Northwell network posture gate stopped the readiness probe with exit code $gateExit."
        }
        $result.network_gate_passed = $true
        Save-SasReadinessResult

        $result.network_activity_performed = $true
        Save-SasReadinessResult
        $targetResolution = Resolve-SasCanonicalTargetFqdn -TargetName $targetInput
        if ([string]$targetResolution.disposition -ne 'UNIQUE_CANONICAL_FQDN' -or [string]::IsNullOrWhiteSpace([string]$targetResolution.fqdn)) {
            throw 'Canonical target resolution did not produce exactly one approved FQDN.'
        }
        $targetFqdn = ([string]$targetResolution.fqdn).Trim().TrimEnd('.').ToLowerInvariant()
        $result.target_scope.target_fingerprint = Get-SasTargetFingerprint -TargetValue $targetFqdn
        Save-SasReadinessResult
    }

    $transportParameters = @{
        TransportIntent = 'kerberos_smb_task'
        TimeoutSeconds = $TimeoutSeconds
        OutputRoot = $transportOutputRoot
        PassThru = $true
    }
    if ($FixtureMode) {
        $transportParameters.FixtureMode = $true
        $transportParameters.FixturePath = $FixturePath
    }
    else {
        $transportParameters.ComputerName = $targetFqdn
        $transportParameters.AllowNetworkActivity = $true
    }

    $transport = & $transportPath @transportParameters
    $result.transport_result_path = [string]$transport.result_path
    $result.transport_classification = [string]$transport.result.decision.classification
    $result.selected_transport = [string]$transport.result.decision.selected_transport
    $result.transport_preflight_complete = [bool]$transport.result.proof.preflight_complete
    $result.transport_authorization_proven = [bool]$transport.result.proof.transport_authorization_proven
    $result.network_activity_performed = [bool]$transport.result.network_activity_performed

    $testedPorts = New-Object 'System.Collections.Generic.List[int]'
    foreach ($port in @(5985, 5986, 445, 135)) {
        $property = 'port_{0}' -f $port
        if ([bool]$transport.result.observations.tcp.$property.tested) { [void]$testedPorts.Add($port) }
    }
    $result.tested_ports = @($testedPorts)
    if (@($result.tested_ports | Where-Object { $_ -in @(5985, 5986) }).Count -gt 0) {
        throw 'The Cybernet readiness probe broadened into WinRM ports. Stop before deployment.'
    }

    $transportReady = (
        $result.transport_classification -eq 'kerberos_smb_task_ready' -and
        $result.selected_transport -eq 'kerberos_smb_task' -and
        $result.transport_preflight_complete -and
        $result.transport_authorization_proven
    )

    if ($FixtureMode) {
        $result.ready_for_deployment = $false
        $result.status = if ($transportReady) { 'CYBERNET_DEPLOYMENT_READINESS_FIXTURE_READY' } else { 'ACTION_REQUIRED' }
        if (-not $transportReady) { $result.reason = 'The sanitized fixture did not satisfy the Kerberos SMB plus Task Scheduler readiness contract.' }
    }
    elseif ($transportReady -and [bool]$result.network_gate_passed) {
        $result.ready_for_deployment = $true
        $result.status = 'CYBERNET_DEPLOYMENT_READINESS_READY'
    }
    else {
        $result.status = 'ACTION_REQUIRED'
        $result.reason = 'The one-target Kerberos SMB plus Task Scheduler readiness chain did not pass. Do not broaden ports or retry without reviewing the emitted evidence.'
    }

    Save-SasReadinessResult
    Register-SasReadinessArtifact

    $summary = @(
        'Cybernet software deployment readiness'
        "Evidence class: $($result.evidence_class)"
        "Status: $($result.status)"
        "Transport classification: $($result.transport_classification)"
        "Selected transport: $($result.selected_transport)"
        "Ports actually tested: $(@($result.tested_ports) -join ', ')"
        "Network activity performed: $($result.network_activity_performed)"
        'Target mutation performed: False'
        "Ready for deployment: $($result.ready_for_deployment)"
        "Evidence: $resultPath"
        "Proof ceiling: $($result.proof_ceiling)"
    )
    $summary | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    $summary | Set-Content -LiteralPath $context.operator_handoff_path -Encoding UTF8
    Register-SasArtifact -RegistryPath $context.artifact_registry_path -Role 'english_summary' -Path $summaryPath -Tracked $false -LiveData (-not $FixtureMode) -Generated $true -Description 'Technician-readable readiness status, tested port subset, and proof ceiling.' -NetworkActivity $networkActivityDescription -CreatedBy 'Invoke-SasCybernetDeploymentReadiness' | Out-Null

    $statusColor = if ($result.status -like '*READY') { 'Green' } else { 'Yellow' }
    Write-Host "`nCYBERNET DEPLOYMENT READINESS: $($result.status)" -ForegroundColor $statusColor
    Write-Host "Transport: $($result.transport_classification)"
    Write-Host "Ports tested: $(@($result.tested_ports) -join ', ')"
    Write-Host "Evidence: $resultPath"

    if ($result.status -eq 'ACTION_REQUIRED') {
        throw $result.reason
    }

    if ($PassThru) {
        $output = [ordered]@{}
        foreach ($key in $result.Keys) { $output[$key] = $result[$key] }
        $output.resolved_fqdn = $targetFqdn
        return [pscustomobject]$output
    }
}
catch {
    if ($result.status -eq 'STARTED') { $result.status = 'ACTION_REQUIRED' }
    if ([string]::IsNullOrWhiteSpace([string]$result.reason)) { $result.reason = $_.Exception.Message }
    Save-SasReadinessResult
    Register-SasReadinessArtifact
    Write-Host "`nACTION REQUIRED: $($result.reason)" -ForegroundColor Yellow
    Write-Host "Evidence: $resultPath"
    Write-Host 'Run sas evidence before any repeated probe if the console output is incomplete.' -ForegroundColor Yellow
    throw
}

exit 0
