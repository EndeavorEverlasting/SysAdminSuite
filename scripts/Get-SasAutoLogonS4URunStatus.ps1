#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OuterRunId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$S4URunId,

    [string]$OutputRoot
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'runs'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)

$outerRoot = Join-Path $OutputRoot $OuterRunId
$s4uRoot = Join-Path (Join-Path $outerRoot 's4u') $S4URunId

if (-not (Test-Path -LiteralPath $outerRoot -PathType Container)) {
    throw "Outer AutoLogon run not found: $outerRoot"
}
if (-not (Test-Path -LiteralPath $s4uRoot -PathType Container)) {
    throw "S4U run not found: $s4uRoot"
}

function Test-SasLocalArtifact {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    Test-Path -LiteralPath (Join-Path $s4uRoot $RelativePath) -PathType Leaf
}

function Test-SasStatusPathUnderRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    return $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)
}

$allFiles = @(Get-ChildItem -LiteralPath $s4uRoot -File -Recurse -ErrorAction SilentlyContinue)
$latest = $allFiles | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
$latestAgeSeconds = if ($latest) {
    [Math]::Max(0, [int]((Get-Date).ToUniversalTime() - $latest.LastWriteTimeUtc).TotalSeconds)
}
else {
    $null
}

$preflightResult = $allFiles | Where-Object { $_.Name -eq 'software_deployment_transport_result.json' } | Select-Object -First 1
$preflightLinkFile = $allFiles | Where-Object { $_.Name -eq 'transport_preflight_link.json' } | Select-Object -First 1
$preflightLinkValid = $false
$preflightResultPath = $(if ($preflightResult) { $preflightResult.FullName } else { $null })
if ($null -eq $preflightResult -and $null -ne $preflightLinkFile) {
    try {
        $link = Get-Content -LiteralPath $preflightLinkFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $linkedPath = [string]$link.result_path
        $approvedTransportRoot = Join-Path $repoRoot 'runs'
        if ([string]$link.schema_version -eq 'sas-software-deployment-transport-link/v1' -and
            -not [string]::IsNullOrWhiteSpace($linkedPath) -and
            [IO.Path]::GetFileName($linkedPath) -eq 'software_deployment_transport_result.json' -and
            (Test-SasStatusPathUnderRoot -Path $linkedPath -Root $approvedTransportRoot) -and
            (Test-Path -LiteralPath $linkedPath -PathType Leaf)) {
            $preflightLinkValid = $true
            $preflightResultPath = [IO.Path]::GetFullPath($linkedPath)
            $preflightResult = Get-Item -LiteralPath $preflightResultPath
        }
    }
    catch { }
}

$sourceIdentity = Test-SasLocalArtifact 'evidence\software_source_identity.json'
$sourceTicket = Test-SasLocalArtifact 'evidence\software_source_kerberos_ticket.json'
$baselineLifecycle = Test-SasLocalArtifact 'evidence\baseline_lifecycle.json'
$baselineSnapshot = Test-SasLocalArtifact 'evidence\baseline_snapshot.json'
$beforeManifest = Test-SasLocalArtifact 'actions\s4u_before_manifest.json'
$probeWorker = Test-SasLocalArtifact 'actions\s4u-probe-worker.ps1'
$probeLifecycle = Test-SasLocalArtifact 'evidence\s4u_probe_lifecycle.json'
$probeResult = Test-SasLocalArtifact 'evidence\s4u_probe_result.json'
$installWorker = Test-SasLocalArtifact 'actions\s4u-install-worker.ps1'
$installLifecycle = Test-SasLocalArtifact 'evidence\s4u_install_lifecycle.json'
$installResult = Test-SasLocalArtifact 'evidence\s4u_install_result.json'
$afterLifecycle = Test-SasLocalArtifact 'evidence\after_lifecycle.json'
$afterSnapshot = Test-SasLocalArtifact 'evidence\after_snapshot.json'
$pilotResult = Test-SasLocalArtifact 'autologon_kerberos_s4u_pilot_result.json'

$finalGate = $allFiles | Where-Object { $_.Name -eq 'autologon_final_step_gate.json' } | Select-Object -First 1

$stage = if ($pilotResult) {
    'terminal_result_written'
}
elseif ($afterSnapshot -or $afterLifecycle) {
    'after_state_capture'
}
elseif ($installLifecycle -or $installResult) {
    'install_task_result_or_cleanup'
}
elseif ($installWorker) {
    'install_task_preparation_or_execution'
}
elseif ($probeLifecycle -or $probeResult) {
    'probe_task_result_or_cleanup'
}
elseif ($probeWorker) {
    'probe_task_preparation_or_execution'
}
elseif ($finalGate) {
    'source_validation_hash_or_staging'
}
elseif ($beforeManifest) {
    'final_step_gate'
}
elseif ($baselineSnapshot -or $baselineLifecycle) {
    'baseline_validation'
}
elseif ($sourceTicket -or $sourceIdentity) {
    'baseline_capture'
}
elseif ($preflightResult) {
    'software_source_kerberos'
}
else {
    'transport_preflight'
}

$terminalClassification = $null
$terminalReason = $null
if ($pilotResult) {
    try {
        $terminal = Get-Content -LiteralPath (Join-Path $s4uRoot 'autologon_kerberos_s4u_pilot_result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $terminalClassification = [string]$terminal.classification
        $terminalReason = [string]$terminal.reason
    }
    catch { }
}

[pscustomobject][ordered]@{
    schema_version = 'sas-autologon-s4u-local-run-status/v1'
    outer_run_id = $OuterRunId
    s4u_run_id = $S4URunId
    stage = $stage
    terminal_classification = $terminalClassification
    terminal_reason = $terminalReason
    latest_local_artifact = $(if ($latest) { $latest.FullName } else { $null })
    latest_local_artifact_age_seconds = $latestAgeSeconds
    preflight_result_present = ($null -ne $preflightResult)
    preflight_result_path = $preflightResultPath
    preflight_link_present = ($null -ne $preflightLinkFile)
    preflight_link_valid = $preflightLinkValid
    preflight_link_path = $(if ($preflightLinkFile) { $preflightLinkFile.FullName } else { $null })
    software_source_identity_present = $sourceIdentity
    software_source_ticket_present = $sourceTicket
    baseline_snapshot_present = $baselineSnapshot
    final_gate_result_present = ($null -ne $finalGate)
    probe_worker_present = $probeWorker
    probe_result_present = $probeResult
    install_worker_present = $installWorker
    install_result_present = $installResult
    after_snapshot_present = $afterSnapshot
    terminal_result_present = $pilotResult
    network_activity_performed_by_observer = $false
    target_contact_performed_by_observer = $false
    target_mutation_performed_by_observer = $false
}
