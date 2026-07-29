#Requires -Version 5.1
<#
.SYNOPSIS
Runs the one-target low-noise readiness chain used by Cybernet software deployment.
.DESCRIPTION
Checks the local Northwell network posture, resolves a short authorized hostname to the
current domain FQDN without a discovery scan, and runs only the Kerberos SMB plus Remote
Task Scheduler transport preflight. The command creates no remote task, writes nothing to
the target, installs no software, and never broadens to WinRM or automatic transport discovery.
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
$runContextModulePath = Join-Path $PSScriptRoot 'SasRunContext.psm1'
foreach ($requiredPath in @($networkGatePath, $transportPath, $transportModulePath, $runContextModulePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Missing Cybernet deployment-readiness dependency: $requiredPath"
    }
}
Import-Module $transportModulePath -Force
Import-Module $runContextModulePath -Force

$targetInput = $ComputerName.Trim().TrimEnd('.')
if ($targetInput -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') {
    throw "Invalid Cybernet hostname or FQDN: $targetInput"
}
if ($PSCmdlet.ParameterSetName -eq 'Live' -and -not $AllowNetworkActivity) {
    throw 'Live Cybernet deployment readiness requires explicit -AllowNetworkActivity acknowledgement.'
}
if ($PSCmdlet.ParameterSetName -eq 'Fixture' -and -not (Test-Path -LiteralPath $FixturePath -PathType Leaf)) {
    throw "Fixture file not found: $FixturePath"
}

function Resolve-SasAuthorizedTargetFqdn {
    param([Parameter(Mandatory = $true)][string]$Target)

    if ($Target.Contains('.')) {
        if (-not (Test-SasFqdn -ComputerName $Target)) {
            throw 'The supplied target contains a dot but is not a valid fully qualified DNS name.'
        }
        return $Target.ToLowerInvariant()
    }

    $suffix = [string]$env:USERDNSDOMAIN
    if ([string]::IsNullOrWhiteSpace($suffix)) {
        try {
            $system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            if ([bool]$system.PartOfDomain) { $suffix = [string]$system.Domain }
        }
        catch {
            try {
                $system = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
                if ([bool]$system.PartOfDomain) { $suffix = [string]$system.Domain }
            }
            catch { }
        }
    }
    $suffix = $suffix.Trim().Trim('.')
    if ([string]::IsNullOrWhiteSpace($suffix) -or -not $suffix.Contains('.')) {
        throw 'A short hostname cannot be resolved safely because the current administrator session has no usable DNS domain suffix. Supply the authorized FQDN.'
    }

    $candidate = ('{0}.{1}' -f $Target, $suffix).ToLowerInvariant()
    if (-not (Test-SasFqdn -ComputerName $candidate)) {
        throw 'The short hostname plus the current DNS domain suffix did not form a valid FQDN.'
    }
    return $candidate
}

function Get-SasTargetFingerprint {
    param([Parameter(Mandatory = $true)][string]$TargetFqdn)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($TargetFqdn.ToLowerInvariant())
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha.Dispose()
    }
}

$targetFqdn = Resolve-SasAuthorizedTargetFqdn -Target $targetInput
$contextParameters = @{
    WorkflowId = 'cybernet-deployment-readiness'
    RepoRoot = $repoRoot
    Survey = $true
    RequestSummary = if ($FixtureMode) {
        'Offline sanitized Cybernet software deployment readiness fixture.'
    }
    else {
        'One-target low-noise Cybernet software deployment readiness probe.'
    }
    CreatedBy = 'Invoke-SasCybernetDeploymentReadiness'
}
if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) { $contextParameters.OutputRoot = $OutputRoot }
$context = New-SasRunContext @contextParameters
$resultPath = Join-Path $context.directories.artifacts 'cybernet_deployment_readiness_result.json'
$summaryPath = Join-Path $context.directories.reports 'english_summary.txt'

$result = [ordered]@{
    schema_version = 'sas-cybernet-deployment-readiness-result/v1'
    run_id = $context.run_id
    target_scope = [ordered]@{
        target_count = 1
        target_fingerprint = Get-SasTargetFingerprint -TargetFqdn $targetFqdn
        identifier_emitted = $false
        input_was_fqdn = $targetInput.Contains('.')
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

$artifactRegistered = $false
function Save-SasReadinessResult {
    $result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}
function Register-SasReadinessArtifact {
    if ($script:artifactRegistered) { return }
    Register-SasArtifact -RegistryPath $context.artifact_registry_path -Role 'cybernet_deployment_readiness' -Path $resultPath -Tracked $false -LiveData (-not $FixtureMode) -Generated $true -Description 'One-target low-noise Cybernet deployment readiness classification without target identifiers.' -NetworkActivity (if ($FixtureMode) { 'No network activity performed.' } else { 'Bounded Kerberos SMB plus Task Scheduler readiness observations for one authorized target.' }) -CreatedBy 'Invoke-SasCybernetDeploymentReadiness' | Out-Null
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
    }

    $transportParameters = @{
        ComputerName = $targetFqdn
        TransportIntent = 'kerberos_smb_task'
        TimeoutSeconds = $TimeoutSeconds
        OutputRoot = (Join-Path $context.run_root 'transport')
        PassThru = $true
    }
    if ($FixtureMode) {
        $transportParameters.FixtureMode = $true
        $transportParameters.FixturePath = $FixturePath
    }
    else {
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
    Register-SasArtifact -RegistryPath $context.artifact_registry_path -Role 'english_summary' -Path $summaryPath -Tracked $false -LiveData (-not $FixtureMode) -Generated $true -Description 'Technician-readable readiness status, tested port subset, and proof ceiling.' -NetworkActivity (if ($FixtureMode) { 'No network activity performed.' } else { 'Bounded readiness observations only.' }) -CreatedBy 'Invoke-SasCybernetDeploymentReadiness' | Out-Null

    Write-Host "`nCYBERNET DEPLOYMENT READINESS: $($result.status)" -ForegroundColor $(if ($result.status -like '*READY') { 'Green' } else { 'Yellow' })
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
    throw
}

exit 0
