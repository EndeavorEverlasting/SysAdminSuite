#Requires -Version 5.1
<#
.SYNOPSIS
Recover locally recorded interrupted probe-only AutoLogon S4U runs for one target.

.DESCRIPTION
Searches only machine-local SysAdminSuite evidence roots for exact durable probe lifecycle records.
It deduplicates physical paths and subst aliases, accepts only the exact terminal probe-create-timeout
shape that remains safe for bounded cleanup, skips other terminal or already-completed recovery
records, fails closed on any install/after-state evidence, and invokes only the exact recorded
recovery helper against the canonical requested target. It never discovers remote tasks broadly
and never launches AutoLogon.
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

$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
$sessionModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasOperatorSession.psm1'
$targetModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasTargetNameResolution.psm1'
$recoveryScript = Join-Path -Path $PSScriptRoot -ChildPath 'Complete-SasInterruptedAutoLogonS4URecovery.ps1'
foreach ($required in @($sessionModule,$targetModule,$recoveryScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing AutoLogon interrupted-recovery dependency: $required"
    }
}
Import-Module $sessionModule -Force
Import-Module $targetModule -Force

if (-not $ConfirmRecovery) {
    throw 'Interrupted AutoLogon recovery requires -ConfirmRecovery.'
}

if (-not ('SasPathIdentity.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace SasPathIdentity {
    public static class NativeMethods {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern uint QueryDosDevice(
            string lpDeviceName,
            StringBuilder lpTargetPath,
            int ucchMax
        );
    }
}
'@
}

function Test-SasSameTarget {
    param(
        [AllowNull()][string]$Recorded,
        [Parameter(Mandatory = $true)][string]$Requested
    )
    if ([string]::IsNullOrWhiteSpace($Recorded)) { return $false }
    $left = $Recorded.Trim().TrimEnd('.').ToLowerInvariant()
    $right = $Requested.Trim().TrimEnd('.').ToLowerInvariant()
    if ($left -eq $right) { return $true }

    $leftIsFqdn = $left.Contains('.')
    $rightIsFqdn = $right.Contains('.')
    if ($rightIsFqdn) {
        if ($leftIsFqdn) { return $false }
        try {
            $legacyResolution = Resolve-SasCanonicalTargetFqdn -TargetName $Recorded
            return ([string]$legacyResolution.fqdn).Trim().TrimEnd('.').Equals(
                $right,
                [StringComparison]::OrdinalIgnoreCase
            )
        }
        catch { return $false }
    }
    if ($leftIsFqdn) { return $false }
    return ($left -eq $right)
}

function Get-SasOptionalJsonString {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($null -eq $Object) { return '' }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return [string]$property.Value
}

function Test-SasTerminalProbeCreateTimeoutRecoverable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$RequestedTarget,
        [Parameter(Mandatory = $true)][ref]$Classification
    )

    $Classification.Value = ''
    try {
        $terminal = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $schema = Get-SasOptionalJsonString -Object $terminal -Name 'schema_version'
        $classification = Get-SasOptionalJsonString -Object $terminal -Name 'classification'
        $terminalRunId = Get-SasOptionalJsonString -Object $terminal -Name 'run_id'
        $terminalTarget = Get-SasOptionalJsonString -Object $terminal -Name 'target'
        $probeProperty = $terminal.PSObject.Properties['probe']
        $installProperty = $terminal.PSObject.Properties['install']
        $installerExitProperty = $terminal.PSObject.Properties['installer_exit_code']
        $afterPathProperty = $terminal.PSObject.Properties['after_snapshot_path']
        $preRebootProperty = $terminal.PSObject.Properties['pre_reboot_autologon_ready']
        $cleanupProperty = $terminal.PSObject.Properties['staging_cleanup_verified']
        $rebootProperty = $terminal.PSObject.Properties['automatic_reboot_performed']
        $signInProperty = $terminal.PSObject.Properties['automatic_sign_in_observed']

        if ($schema -ne 'sas-autologon-kerberos-s4u-pilot-result/v2' -or
            $classification -ne 'S4U_PROBE_CREATE_TIMEOUT' -or
            $terminalRunId -ne $RunId -or
            -not (Test-SasSameTarget -Recorded $terminalTarget -Requested $RequestedTarget) -or
            $null -eq $probeProperty -or $null -eq $probeProperty.Value -or
            $null -eq $installProperty -or $null -ne $installProperty.Value -or
            $null -eq $installerExitProperty -or $null -ne $installerExitProperty.Value -or
            $null -eq $afterPathProperty -or -not [string]::IsNullOrWhiteSpace([string]$afterPathProperty.Value) -or
            $null -eq $preRebootProperty -or [bool]$preRebootProperty.Value -or
            $null -eq $cleanupProperty -or -not [bool]$cleanupProperty.Value -or
            $null -eq $rebootProperty -or [bool]$rebootProperty.Value -or
            $null -eq $signInProperty -or [bool]$signInProperty.Value) {
            return $false
        }

        $probe = $probeProperty.Value
        if ((Get-SasOptionalJsonString -Object $probe -Name 'classification') -ne 'S4U_PROBE_CREATE_TIMEOUT' -or
            (Get-SasOptionalJsonString -Object $probe -Name 'run_id') -ne $RunId -or
            (Get-SasOptionalJsonString -Object $probe -Name 'task_name') -ne $TaskName) {
            return $false
        }

        $Classification.Value = $classification
        return $true
    }
    catch {
        return $false
    }
}

function Get-SasPhysicalPathIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    $isDriveRoot = (-not [string]::IsNullOrWhiteSpace($root) -and
        $root.Length -eq 3 -and $root[1] -eq ':' -and $root[2] -eq [char]92)
    if (-not $isDriveRoot) {
        return $full.TrimEnd('\').ToLowerInvariant()
    }

    $drive = $root.TrimEnd('\')
    $buffer = New-Object Text.StringBuilder 4096
    $count = [SasPathIdentity.NativeMethods]::QueryDosDevice($drive, $buffer, $buffer.Capacity)
    if ($count -gt 0) {
        $mapping = $buffer.ToString()
        if ($mapping.StartsWith('\??\', [StringComparison]::OrdinalIgnoreCase)) {
            $mappedRoot = $mapping.Substring(4).TrimEnd('\')
            if ($mappedRoot -match '^[A-Za-z]:\') {
                $relative = $full.Substring($root.Length)
                $full = if ([string]::IsNullOrWhiteSpace($relative)) {
                    [IO.Path]::GetFullPath($mappedRoot)
                } else {
                    [IO.Path]::GetFullPath((Join-Path -Path $mappedRoot -ChildPath $relative))
                }
            }
        }
    }

    return $full.TrimEnd('\').ToLowerInvariant()
}

function Get-SasInterruptedS4UCandidates {
    $files = @()
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    foreach ($root in @(Get-SasEvidenceRoots -RepoRoot $repoRoot)) {
        foreach ($relative in @(
            'runs',
            'survey\output\runs\autologon-s4u-deployment',
            'survey\output\runs\autologon-kerberos-s4u'
        )) {
            $searchRoot = Join-Path -Path $root -ChildPath $relative
            if (-not (Test-Path -LiteralPath $searchRoot -PathType Container)) { continue }

            foreach ($file in @(
                Get-ChildItem -LiteralPath $searchRoot -Filter 's4u_probe_lifecycle.json' `
                    -File -Recurse -ErrorAction SilentlyContinue
            )) {
                $identity = Get-SasPhysicalPathIdentity -Path $file.FullName
                if ($seen.Add($identity)) {
                    $files += [pscustomobject]@{
                        file=$file
                        physical_identity=$identity
                    }
                }
            }
        }
    }

    $items = @()
    foreach ($entry in @($files)) {
        $file = $entry.file
        try {
            $lifecycle = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch { continue }

        $mode = Get-SasOptionalJsonString -Object $lifecycle -Name 'mode'
        if (-not [string]::IsNullOrWhiteSpace($mode) -and $mode -ne 'Probe') { continue }

        $recordedTarget = Get-SasOptionalJsonString -Object $lifecycle -Name 'target'
        if (-not (Test-SasSameTarget -Recorded $recordedTarget -Requested $ComputerName)) { continue }

        $runId = Get-SasOptionalJsonString -Object $lifecycle -Name 'run_id'
        $taskName = Get-SasOptionalJsonString -Object $lifecycle -Name 'task_name'
        if ($runId -notmatch '^autologon-kerberos-s4u-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$') { continue }
        if ($taskName -notmatch '^SysAdminSuite-AutoLogonS4UProbe-[0-9a-f]{32}$') { continue }

        $evidenceRoot = Split-Path -Parent $file.FullName
        $s4uRoot = Split-Path -Parent $evidenceRoot
        if ((Split-Path -Leaf $s4uRoot) -ne $runId) { continue }

        $actionsRoot = Join-Path -Path $s4uRoot -ChildPath 'actions'
        $terminal = Join-Path -Path $s4uRoot -ChildPath 'autologon_kerberos_s4u_pilot_result.json'
        $recovered = Join-Path -Path $s4uRoot -ChildPath 's4u_probe_hang_recovery_result.json'

        $terminalPresent = (Test-Path -LiteralPath $terminal -PathType Leaf)
        $terminalClassification = ''
        $terminalProbeTimeoutAccepted = $false
        if ($terminalPresent) {
            $terminalProbeTimeoutAccepted = Test-SasTerminalProbeCreateTimeoutRecoverable -Path $terminal `
                -RunId $runId -TaskName $taskName -RequestedTarget $ComputerName `
                -Classification ([ref]$terminalClassification)
            if (-not $terminalProbeTimeoutAccepted) { continue }
        }

        if (Test-Path -LiteralPath $recovered -PathType Leaf) {
            try {
                $previous = Get-Content -LiteralPath $recovered -Raw -Encoding UTF8 | ConvertFrom-Json
                $previousStatus = Get-SasOptionalJsonString -Object $previous -Name 'status'
                $previousClassification = Get-SasOptionalJsonString -Object $previous -Name 'classification'
                if ($previousStatus -eq 'COMPLETED' -and
                    $previousClassification -eq 'S4U_PROBE_CREATE_HANG_RECOVERED') {
                    continue
                }
            }
            catch { }
        }

        $installEvidence = @(
            (Join-Path -Path $actionsRoot -ChildPath 's4u-install-worker.ps1'),
            (Join-Path -Path $evidenceRoot -ChildPath 's4u_install_lifecycle.json'),
            (Join-Path -Path $evidenceRoot -ChildPath 's4u_install_result.json'),
            (Join-Path -Path $evidenceRoot -ChildPath 'after_lifecycle.json'),
            (Join-Path -Path $evidenceRoot -ChildPath 'after_snapshot.json')
        )
        $installPresent = @(
            $installEvidence | Where-Object { Test-Path -LiteralPath $_ }
        ).Count -gt 0

        $items += [pscustomobject][ordered]@{
            run_id=$runId
            task_name=$taskName
            target=$recordedTarget
            canonical_recovery_target=$ComputerName
            lifecycle_path=$file.FullName
            lifecycle_physical_identity=$entry.physical_identity
            local_s4u_root=$s4uRoot
            install_or_after_evidence_present=$installPresent
            terminal_pilot_result_present=$terminalPresent
            terminal_pilot_classification=$terminalClassification
            terminal_probe_timeout_accepted=$terminalProbeTimeoutAccepted
            last_write_utc=$file.LastWriteTimeUtc
            lifecycle_classification=(Get-SasOptionalJsonString -Object $lifecycle -Name 'classification')
            lifecycle_stage=(Get-SasOptionalJsonString -Object $lifecycle -Name 'current_stage')
        }
    }

    return @($items | Sort-Object last_write_utc)
}

$candidates = @(Get-SasInterruptedS4UCandidates)
$unsafe = @($candidates | Where-Object { $_.install_or_after_evidence_present })
if ($unsafe.Count -gt 0) {
    $paths = @($unsafe | ForEach-Object { $_.local_s4u_root }) -join '; '
    throw "Interrupted AutoLogon evidence includes install/after-state activity. Refusing automatic recovery or redeployment. Review: $paths"
}

$safe = @($candidates | Where-Object { -not $_.install_or_after_evidence_present })
if ($safe.Count -eq 0) {
    $result = [pscustomobject][ordered]@{
        schema_version='sas-autologon-s4u-recovery-discovery/v3'
        status='COMPLETED'
        classification='NO_INTERRUPTED_PROBE_RUN_FOUND'
        target=$ComputerName
        recovered_count=0
        recovered_runs=@()
        candidate_count=0
        path_aliases_deduplicated=$true
        target_contact_performed=$false
        target_mutation_performed=$false
        exact_cleanup_only=$true
        autologon_installer_launched=$false
        next_action='Proceed through the supported AutoLogon deployment command.'
    }
    Write-Host 'NO_INTERRUPTED_PROBE_RUN_FOUND' -ForegroundColor Green
    if ($PassThru) { return $result }
    exit 0
}

Write-Host "`n=== RECOVER RECORDED INTERRUPTED AUTOLOGON RUNS ===" -ForegroundColor Cyan
Write-Host "Target: $ComputerName"
Write-Host "Probe-only runs to recover: $($safe.Count)"

$recovered = @()
foreach ($item in $safe) {
    Write-Host "Recovering exact run $($item.run_id) / task $($item.task_name)" -ForegroundColor Cyan
    $one = & $recoveryScript -ComputerName $ComputerName `
        -RunId ([string]$item.run_id) -TaskName ([string]$item.task_name) `
        -LocalS4URoot ([string]$item.local_s4u_root) -ConfirmRecovery `
        -TimeoutSeconds $TimeoutSeconds

    if ($null -eq $one -or
        [string](Get-SasOptionalJsonString -Object $one -Name 'classification') -ne 'S4U_PROBE_CREATE_HANG_RECOVERED' -or
        [string](Get-SasOptionalJsonString -Object $one -Name 'status') -ne 'COMPLETED') {
        throw "Exact recovery did not complete for $($item.run_id)."
    }
    $recovered += $one
}

$result = [pscustomobject][ordered]@{
    schema_version='sas-autologon-s4u-recovery-discovery/v3'
    status='COMPLETED'
    classification='INTERRUPTED_PROBE_RUNS_RECOVERED'
    target=$ComputerName
    recovered_count=@($recovered).Count
    recovered_runs=@($recovered | ForEach-Object { [string]$_.run_id })
    candidate_count=$safe.Count
    path_aliases_deduplicated=$true
    target_contact_performed=$true
    target_mutation_performed=$false
    exact_cleanup_only=$true
    autologon_installer_launched=$false
    next_action='Proceed through the supported AutoLogon deployment command once.'
}
Write-Host "INTERRUPTED_PROBE_RUNS_RECOVERED: $(@($recovered).Count)" -ForegroundColor Green
if ($PassThru) { return $result }
exit 0