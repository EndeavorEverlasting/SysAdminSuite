#Requires -Version 5.1
<#
.SYNOPSIS
    Offline, read-only printer incident intake for a technician's next AI agent.
.DESCRIPTION
    Emits an allowlisted, privacy-safe handoff and a local private finding input.
    No target/network access, elevation, remediation, ticket creation, upload,
    PowerShell execution-policy bypass, or raw log publication.
    Existing machine and user receipts are *hints*, never live runtime proof.
#>
[CmdletBinding()]
param(
    [ValidateSet('mapping-failed','standard-user-missing','fallback-staging','task-logon',
        'startup-cleanup','launcher-download','unknown')][string]$Symptom = 'unknown',
    [string]$EvidenceRoot,
    [string]$OutputRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace([string]$env:LOCALAPPDATA)) {
    throw 'PRIVATE_OUTPUT_UNAVAILABLE: LOCALAPPDATA is required; no report created.'
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\Evidence\PrinterSupport'
}
$outputFull = [IO.Path]::GetFullPath($OutputRoot)
$repoFull = ([IO.Path]::GetFullPath($repoRoot)).TrimEnd('\')
if ($outputFull.TrimEnd('\').Equals($repoFull,[StringComparison]::OrdinalIgnoreCase) -or
    $outputFull.StartsWith($repoFull + '\',[StringComparison]::OrdinalIgnoreCase)) {
    throw 'PRIVATE_OUTPUT_REQUIRED: incident files cannot be written inside the source repository.'
}
if ($outputFull -notmatch '^[A-Za-z]:\\' -or $outputFull -match '^\\\\') {
    throw 'PRIVATE_OUTPUT_REQUIRED: choose a local Windows drive, not a network share.'
}
$incidentId = 'sas-printer-' + [guid]::NewGuid().ToString('N')
$incidentRoot = Join-Path $outputFull $incidentId

function Get-SasEvidenceState {
    param([AllowNull()][string]$Root)
    if ([string]::IsNullOrWhiteSpace($Root)) { return 'NO_LOCAL_MAPPING_EVIDENCE' }
    # Intentionally do not fetch UNC/admin shares or contact a workstation.
    if ($Root -notmatch '^[A-Za-z]:\\' -or $Root -match '^\\\\') {
        return 'EVIDENCE_NOT_LOCAL'
    }
    try {
        $full = [IO.Path]::GetFullPath($Root)
        $candidate = Join-Path $full 'Summary.json'
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return 'NO_LOCAL_MAPPING_EVIDENCE'
        }
        $item = Get-Item -LiteralPath $candidate -ErrorAction Stop
        if ($item.Length -gt 262144) { return 'EVIDENCE_OVERSIZE_NOT_PARSED' }
        $summary = Get-Content -LiteralPath $candidate -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $allowed = @('MachineWidePerComputer','NorthwellPrinterBatch')
        if ($allowed -notcontains [string]$summary.Mode) { return 'UNRECOGNIZED_MAPPING_EVIDENCE' }
        if ([bool]$summary.Success) { return 'LOCAL_SUMMARY_REPORTS_MACHINE_SUCCESS_UNVERIFIED' }
        return 'LOCAL_SUMMARY_REPORTS_FAILURE'
    }
    catch { return 'LOCAL_EVIDENCE_UNREADABLE' }
}

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $pointer = Join-Path $repoRoot 'mapping\Logs\LATEST-PATH.txt'
    if (Test-Path -LiteralPath $pointer -PathType Leaf) {
        try {
            if ((Get-Item -LiteralPath $pointer -ErrorAction Stop).Length -lt 4096) {
                $EvidenceRoot = ([string](Get-Content -LiteralPath $pointer -Raw -ErrorAction Stop)).Trim()
            }
        }
        catch { $EvidenceRoot = $null }
    }
}
$machineState = Get-SasEvidenceState -Root $EvidenceRoot

$userReceiptState = 'NO_CURRENT_USER_RECEIPT_OBSERVED'
$userReceipt = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\Printer\latest-printer-session.json'
try {
    if (Test-Path -LiteralPath $userReceipt -PathType Leaf) {
        if ((Get-Item -LiteralPath $userReceipt -ErrorAction Stop).Length -gt 262144) {
            $userReceiptState = 'USER_RECEIPT_OVERSIZE_NOT_PARSED'
        }
        else {
            $receipt = Get-Content -LiteralPath $userReceipt -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ([string]$receipt.SchemaVersion -ceq 'sas-northwell-printer-user-proof/v1' -and
                [string]$receipt.Result -ceq 'USER_SESSION_VERIFIED') {
                $userReceiptState = 'LOCAL_PRIOR_USER_RECEIPT_EXISTS_NOT_CURRENT_PROOF'
            }
            else { $userReceiptState = 'UNRECOGNIZED_USER_RECEIPT' }
        }
    }
}
catch { $userReceiptState = 'USER_RECEIPT_UNREADABLE' }

$descriptions = @{
    'mapping-failed' = 'Technician reports machine-wide mapping failed.'
    'standard-user-missing' = 'Technician reports approved printer missing after standard-user login.'
    'fallback-staging' = 'Technician reports deferred recovery could not be staged.'
    'task-logon' = 'Technician reports per-user logon task did not materialize the printer.'
    'startup-cleanup' = 'Technician reports Common Startup fallback or cleanup problem.'
    'launcher-download' = 'Technician reports launcher, distribution, or integrity problem.'
    'unknown' = 'Technician reports an unclassified printer workflow problem.'
}
$packet = [ordered]@{
    schema_version = 'sas-printer-technician-incident/v1'
    incident_id = $incidentId
    source = 'TECHNICIAN_LOCAL_OFFLINE'
    category = 'northwell-shared-printer'
    symptom = $Symptom
    machine_evidence = $machineState
    user_receipt = $userReceiptState
    live_proof = 'NOT_OBSERVED_BY_INTAKE'
    field_authority = 'NOT_GRANTED'
    privacy = 'private_operational'
    publication = 'NO_EXTERNAL_PUSH'
    cleanup_state = 'NOT_INSPECTED_ON_TARGET'
    created_utc = [datetime]::UtcNow.ToString('o')
}

$handoff = @(
    'SAS PRINTER INCIDENT — INVESTIGATE AND REPAIR'
    'Repository: EndeavorEverlasting/SysAdminSuite'
    'Incident ID: ' + $incidentId
    'Symptom class: ' + $Symptom
    'Mapping evidence: ' + $machineState
    'User receipt: ' + $userReceiptState
    'Runtime proof: NOT OBSERVED BY THIS REPORT'
    ''
    'Agent: load AGENTS.md -> field-workflow skill -> docs/field/PRINTER-INCIDENT-AGENT-RUNBOOK.md.'
    'Recover current default-branch, matching PR/issues, source, tests, and CI.'
    'Resolve TokenCorridor P04 + trifecta P08/P82/P07 from the current registry.'
    'Classify the failure against M0-M6; inspect the correct existing launcher,'
    'canonical Status.json / Summary.json / HKLM vs HKU/HKCU, and owned cleanup.'
    'Do not infer field approval or expose private hostnames, queues, users, paths,'
    'tokens, raw logs, screenshots or customer material in public Git/agent tools.'
    'Do not remap, install drivers, edit policy or execute rollback without'
    'scope-specific authority. Repair generic code and regression tests first.'
    'Preserve the known-good mapping path; prove a failing and protected control.'
    'Report CHANGED | PROVED | NEXT, with exact merge/deploy/live ceiling.'
    ''
    'Technician: describe what you observed in plain words. Attach raw evidence'
    'only to an explicitly approved private support channel, never public Issues.'
)
try {
    New-Item -ItemType Directory -Path $incidentRoot -Force -ErrorAction Stop | Out-Null
    $jsonPath = Join-Path $incidentRoot 'incident.v1.json'
    $handoffPath = Join-Path $incidentRoot 'agent-handoff.txt'
    $findingPath = Join-Path $incidentRoot 'finding-input.v1.json'
    $packet | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding UTF8 -ErrorAction Stop
    $handoff -join [Environment]::NewLine | Set-Content -LiteralPath $handoffPath -Encoding UTF8 -ErrorAction Stop
    # Stage, but never automatically submit, the matching canonical finding event.
    $finding = [ordered]@{
        schema_version = 'sas-finding-event/v1'
        event_id = $incidentId
        logical_subject_key = 'printer-support-incident'
        event_type = 'FINDING_RECORDED'
        occurred_at = [datetime]::UtcNow.ToString('o')
        evidence_ref = $jsonPath
        category = 'workflow'
        proof_level = 'operator_reported'
        privacy = 'private_operational'
        finding = [ordered]@{ summary = $descriptions[$Symptom] }
    }
    $finding | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $findingPath -Encoding UTF8 -ErrorAction Stop
    # Save a local pointer for the CMD launcher; nothing uploads or mutates a target.
    $handoffPath | Set-Content -LiteralPath (Join-Path $outputFull 'latest-handoff.txt') -Encoding UTF8 -ErrorAction Stop
}
catch {
    throw 'LOCAL_INTAKE_WRITE_FAILED: no remote action was attempted.'
}
Write-Host ('PRINTER_INCIDENT_CAPTURED: {0}' -f $incidentId)
Write-Host ('Private report folder: {0}' -f $incidentRoot)
Write-Host 'Safe handoff prepared. Field problem remains unverified and unresolved.'
