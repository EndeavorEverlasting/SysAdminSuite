#Requires -Version 5.1
<#
.SYNOPSIS
Recover locally recorded interrupted probe-only AutoLogon S4U runs for one target.

.DESCRIPTION
Searches only machine-local SysAdminSuite evidence roots for durable S4U probe lifecycle records.
It never discovers remote tasks broadly. For the requested target it fails closed if any unfinished
run contains install/after-state evidence, and otherwise invokes the exact recovery helper for each
recorded probe-only interrupted run. Each recovery re-proves the protected network, operates only on
the recorded exact task and run root, and never launches AutoLogon.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ComputerName,
    [switch]$ConfirmRecovery,
    [ValidateRange(5,60)][int]$TimeoutSeconds = 20,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot=(Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
$sessionModule=Join-Path -Path $PSScriptRoot -ChildPath 'SasOperatorSession.psm1'
$recoveryScript=Join-Path -Path $PSScriptRoot -ChildPath 'Complete-SasInterruptedAutoLogonS4URecovery.ps1'
foreach ($required in @($sessionModule,$recoveryScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing AutoLogon interrupted-recovery dependency: $required" }
}
Import-Module $sessionModule -Force

if (-not $ConfirmRecovery) { throw 'Interrupted AutoLogon recovery requires -ConfirmRecovery.' }

function Test-SasSameTarget {
    param([AllowNull()][string]$Recorded,[Parameter(Mandatory = $true)][string]$Requested)
    if ([string]::IsNullOrWhiteSpace($Recorded)) { return $false }
    $left=$Recorded.Trim().TrimEnd('.').ToLowerInvariant()
    $right=$Requested.Trim().TrimEnd('.').ToLowerInvariant()
    if ($left -eq $right) { return $true }
    return ($left.Split('.')[0] -eq $right.Split('.')[0])
}

function Get-SasInterruptedS4UCandidates {
    $files=New-Object 'System.Collections.Generic.List[object]'
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($root in @(Get-SasEvidenceRoots -RepoRoot $repoRoot)) {
        foreach ($relative in @('runs','survey\output\runs\autologon-s4u-deployment','survey\output\runs\autologon-kerberos-s4u')) {
            $searchRoot=Join-Path -Path $root -ChildPath $relative
            if (-not (Test-Path -LiteralPath $searchRoot -PathType Container)) { continue }
            foreach ($file in @(Get-ChildItem -LiteralPath $searchRoot -Filter 's4u_probe_lifecycle.json' -File -Recurse -ErrorAction SilentlyContinue)) {
                if ($seen.Add($file.FullName)) { [void]$files.Add($file) }
            }
        }
    }

    $items=New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in $files) {
        try { $lifecycle=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { continue }
        if ([string]$lifecycle.mode -ne 'Probe') { continue }
        if (-not (Test-SasSameTarget -Recorded ([string]$lifecycle.target) -Requested $ComputerName)) { continue }
        $runId=[string]$lifecycle.run_id
        $taskName=[string]$lifecycle.task_name
        if ($runId -notmatch '^autologon-kerberos-s4u-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$') { continue }
        if ($taskName -notmatch '^SysAdminSuite-AutoLogonS4UProbe-[0-9a-f]{32}$') { continue }

        $evidenceRoot=Split-Path -Parent $file.FullName
        $s4uRoot=Split-Path -Parent $evidenceRoot
        if ((Split-Path -Leaf $s4uRoot) -ne $runId) { continue }
        $actionsRoot=Join-Path -Path $s4uRoot -ChildPath 'actions'
        $terminal=Join-Path -Path $s4uRoot -ChildPath 'autologon_kerberos_s4u_pilot_result.json'
        $recovered=Join-Path -Path $s4uRoot -ChildPath 's4u_probe_hang_recovery_result.json'
        if (Test-Path -LiteralPath $terminal -PathType Leaf) { continue }
        if (Test-Path -LiteralPath $recovered -PathType Leaf) {
            try {
                $previous=Get-Content -LiteralPath $recovered -Raw -Encoding UTF8 | ConvertFrom-Json
                if ([string]$previous.status -eq 'COMPLETED') { continue }
            }
            catch { }
        }

        $installEvidence=@(
            (Join-Path -Path $actionsRoot -ChildPath 's4u-install-worker.ps1'),
            (Join-Path -Path $evidenceRoot -ChildPath 's4u_install_lifecycle.json'),
            (Join-Path -Path $evidenceRoot -ChildPath 's4u_install_result.json'),
            (Join-Path -Path $evidenceRoot -ChildPath 'after_lifecycle.json'),
            (Join-Path -Path $evidenceRoot -ChildPath 'after_snapshot.json')
        )
        $installPresent=@($installEvidence | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0
        [void]$items.Add([pscustomobject][ordered]@{
            run_id=$runId
            task_name=$taskName
            target=[string]$lifecycle.target
            lifecycle_path=$file.FullName
            local_s4u_root=$s4uRoot
            install_or_after_evidence_present=$installPresent
            last_write_utc=$file.LastWriteTimeUtc
            lifecycle_classification=[string]$lifecycle.classification
            lifecycle_stage=[string]$lifecycle.current_stage
        })
    }
    return @($items | Sort-Object last_write_utc)
}

$candidates=@(Get-SasInterruptedS4UCandidates)
$unsafe=@($candidates | Where-Object { $_.install_or_after_evidence_present })
if ($unsafe.Count -gt 0) {
    $paths=@($unsafe | ForEach-Object { $_.local_s4u_root }) -join '; '
    throw "Interrupted AutoLogon evidence includes install/after-state activity. Refusing automatic recovery or redeployment. Review: $paths"
}

$safe=@($candidates | Where-Object { -not $_.install_or_after_evidence_present })
if ($safe.Count -eq 0) {
    $result=[pscustomobject][ordered]@{
        schema_version='sas-autologon-s4u-recovery-discovery/v1'
        status='COMPLETED'
        classification='NO_INTERRUPTED_PROBE_RUN_FOUND'
        target=$ComputerName
        recovered_count=0
        recovered_runs=@()
        target_contact_performed=$false
        target_mutation_performed=$false
        next_action='Proceed through the supported AutoLogon deployment command.'
    }
    Write-Host 'NO_INTERRUPTED_PROBE_RUN_FOUND' -ForegroundColor Green
    if ($PassThru) { return $result }
    exit 0
}

Write-Host "`n=== RECOVER RECORDED INTERRUPTED AUTOLOGON RUNS ===" -ForegroundColor Cyan
Write-Host "Target: $ComputerName"
Write-Host "Probe-only runs to recover: $($safe.Count)"
$recovered=New-Object 'System.Collections.Generic.List[object]'
foreach ($item in $safe) {
    Write-Host "Recovering exact run $($item.run_id) / task $($item.task_name)" -ForegroundColor Cyan
    $one=& $recoveryScript -ComputerName ([string]$item.target) -RunId ([string]$item.run_id) -TaskName ([string]$item.task_name) -LocalS4URoot ([string]$item.local_s4u_root) -ConfirmRecovery -TimeoutSeconds $TimeoutSeconds
    if ([string]$one.classification -ne 'S4U_PROBE_CREATE_HANG_RECOVERED' -or [string]$one.status -ne 'COMPLETED') {
        throw "Exact recovery did not complete for $($item.run_id)."
    }
    [void]$recovered.Add($one)
}

$result=[pscustomobject][ordered]@{
    schema_version='sas-autologon-s4u-recovery-discovery/v1'
    status='COMPLETED'
    classification='INTERRUPTED_PROBE_RUNS_RECOVERED'
    target=$ComputerName
    recovered_count=$recovered.Count
    recovered_runs=@($recovered | ForEach-Object { [string]$_.run_id })
    target_contact_performed=$true
    target_mutation_performed=$false
    exact_cleanup_only=$true
    autologon_installer_launched=$false
    next_action='Proceed through the supported AutoLogon deployment command once.'
}
Write-Host "INTERRUPTED_PROBE_RUNS_RECOVERED: $($recovered.Count)" -ForegroundColor Green
if ($PassThru) { return $result }
exit 0
