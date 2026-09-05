#Requires -Version 5.1
<#
.SYNOPSIS
Runs the supported AutoLogon Remote lane in a child PowerShell while preserving crash-safe local diagnostics.

.DESCRIPTION
The interactive operator shell must survive deployment failure. This runner therefore launches the existing
Invoke-SasAutoLogonOnsite.ps1 Remote lane in a child powershell.exe process, streams and persists its output,
normalizes any forward numbered-stage gap into an explicit SKIP record, then performs offline evidence recovery.
Stable result and latest-run pointers are written below %LOCALAPPDATA%\SysAdminSuite even when the child exits
nonzero or the deployment throws.

Repository identity is supplied by the already-sealed runtime manifest/bootstrap. This runner does not invoke
Git, so protected-network execution remains valid when Git commands are unavailable.

This script does not weaken network, host-eligibility, recovery, baseline, final-step, cleanup, or restart gates.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [string]$RepositoryRoot,

    [string]$RepositoryHead,

    [switch]$ConfirmDeployment
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not $ConfirmDeployment) {
    throw 'Explicit -ConfirmDeployment is required for the crash-safe AutoLogon field runner.'
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}
else {
    $RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
}

$autoLogonScript = Join-Path $RepositoryRoot 'scripts\Invoke-SasAutoLogonOnsite.ps1'
$evidenceScript = Join-Path $RepositoryRoot 'scripts\Show-SasOperatorEvidence.ps1'
$progressModule = Join-Path $RepositoryRoot 'scripts\SasAutoLogonProgress.psm1'
foreach ($required in @($autoLogonScript, $evidenceScript, $progressModule)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required crash-safe field dependency is missing: $required"
    }
}
Import-Module $progressModule -Force

$stateRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite'
$fieldRoot = Join-Path $stateRoot 'field-runs\autologon'
$runId = 'autologon-field-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runRoot = Join-Path $fieldRoot $runId
$transcriptPath = Join-Path $runRoot 'operator-transcript.txt'
$childOutputPath = Join-Path $runRoot 'autologon-child-output.txt'
$evidenceOutputPath = Join-Path $runRoot 'offline-evidence-recovery.txt'
$resultPath = Join-Path $runRoot 'field-run-result.json'
$latestPointerPath = Join-Path $stateRoot 'last-autologon-field-run.json'
$stableEvidenceIndex = Join-Path $stateRoot 'last-evidence.json'
$copiedEvidenceIndex = Join-Path $runRoot 'last-evidence.json'
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

$repoHead = if ([string]::IsNullOrWhiteSpace($RepositoryHead)) { $null } else { $RepositoryHead.Trim() }

$result = [ordered]@{
    schema_version = 'sas-autologon-crash-safe-field-run/v1'
    run_id = $runId
    target = $ComputerName.Trim().TrimEnd('.').ToLowerInvariant()
    repository_root = $RepositoryRoot
    repository_head = $repoHead
    started_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    completed_at_utc = $null
    status = 'RUNNING'
    child_exit_code = $null
    evidence_recovery_exit_code = $null
    failure_message = $null
    transcript_path = $transcriptPath
    child_output_path = $childOutputPath
    evidence_output_path = $evidenceOutputPath
    evidence_index_path = $null
    target_contact_performed_by_runner = $false
    target_mutation_performed_by_runner = $false
}
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8

$transcriptStarted = $false
$pendingFailure = $null
try {
    Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null
    $transcriptStarted = $true

    Write-Host 'SYSADMINSUITE AUTOLOGON CRASH-SAFE FIELD RUN' -ForegroundColor Cyan
    Write-Host "Run ID: $runId"
    Write-Host "Target: $($result.target)"
    Write-Host "Repo: $RepositoryRoot"
    Write-Host "HEAD: $repoHead"
    Write-Host "Stable run root: $runRoot"
    Write-Host 'The AutoLogon transaction runs in a child PowerShell. Child exit cannot close this operator shell.' -ForegroundColor Green
    Write-Host 'Operator progress continuity: ENABLED; a bypassed numbered stage is rendered as SKIP before any later stage.' -ForegroundColor Green

    $childArguments = @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $autoLogonScript,
        '-Action', 'Remote',
        '-ComputerName', [string]$result.target
    )

    # Windows PowerShell 5.1 can surface merged native stderr as ErrorRecord objects. Keep that
    # diagnostic stream visible/non-terminating while the canonical child runs, then restore the
    # caller preference and preserve the child's real exit code. A native executable inside a
    # PowerShell pipeline updates the global LASTEXITCODE state, so capture that exact scope.
    # Durable output writes stay terminating so success cannot be reported without child evidence.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        & powershell.exe @childArguments 2>&1 |
            ConvertTo-SasAutoLogonContiguousProgress |
            Tee-Object -FilePath $childOutputPath -ErrorAction Stop |
            Out-Host
        $result.child_exit_code = [int]$global:LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    Write-Host ''
    Write-Host '=== OFFLINE EVIDENCE RECOVERY ===' -ForegroundColor Cyan
    $evidenceArguments = @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $evidenceScript,
        'AutoLogon', '20'
    )
    $global:LASTEXITCODE = 0
    & powershell.exe @evidenceArguments 2>&1 |
        Tee-Object -FilePath $evidenceOutputPath -ErrorAction Stop |
        Out-Host
    $result.evidence_recovery_exit_code = [int]$global:LASTEXITCODE

    if (Test-Path -LiteralPath $stableEvidenceIndex -PathType Leaf) {
        Copy-Item -LiteralPath $stableEvidenceIndex -Destination $copiedEvidenceIndex -Force
        $result.evidence_index_path = $copiedEvidenceIndex
    }

    if ([int]$result.child_exit_code -ne 0) {
        $result.status = 'FAILED'
        $result.failure_message = "AutoLogon child process returned exit code $($result.child_exit_code)."
        $pendingFailure = $result.failure_message
    }
    elseif ([int]$result.evidence_recovery_exit_code -ne 0) {
        $result.status = 'FAILED'
        $result.failure_message = "Offline evidence recovery returned exit code $($result.evidence_recovery_exit_code)."
        $pendingFailure = $result.failure_message
    }
    else {
        $result.status = 'COMPLETED'
    }
}
catch {
    $result.status = 'FAILED'
    $result.failure_message = $_.Exception.Message
    $pendingFailure = $_.Exception.Message
}
finally {
    $result.completed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8

    $pointer = [ordered]@{
        schema_version = 'sas-autologon-last-field-run/v1'
        updated_at_utc = $result.completed_at_utc
        run_id = $runId
        status = $result.status
        target = $result.target
        repository_root = $RepositoryRoot
        repository_head = $repoHead
        run_root = $runRoot
        result_path = $resultPath
        transcript_path = $transcriptPath
        child_output_path = $childOutputPath
        evidence_output_path = $evidenceOutputPath
        evidence_index_path = $result.evidence_index_path
        child_exit_code = $result.child_exit_code
        evidence_recovery_exit_code = $result.evidence_recovery_exit_code
    }
    $pointer | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $latestPointerPath -Encoding UTF8

    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
    }
}

Write-Host ''
Write-Host "FIELD RUN STATUS: $($result.status)" -ForegroundColor $(if ($result.status -eq 'COMPLETED') { 'Green' } else { 'Yellow' })
Write-Host "Result: $resultPath"
Write-Host "Transcript: $transcriptPath"
Write-Host "Child output: $childOutputPath"
Write-Host "Evidence recovery: $evidenceOutputPath"
Write-Host "Latest pointer: $latestPointerPath"

if ($pendingFailure) {
    throw "$pendingFailure Diagnostics were preserved under: $runRoot"
}

[pscustomobject]$result
