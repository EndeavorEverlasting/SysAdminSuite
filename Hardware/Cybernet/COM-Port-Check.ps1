#Requires -Version 5.1
<#
.SYNOPSIS
Read and classify Cybernet COM-port assignments across explicit targets.

.DESCRIPTION
This lane is read-only. COM1-COM4 is ready. The exact COM3-COM6 condition is routed to the existing
local-only Cybernet COM AutoFix; it is never repaired remotely because that workflow requires local
administration, registry backups, PnP state, and a controlled reboot. Every other shape requires review.
#>
[CmdletBinding()]
param(
    [string[]]$ComputerName = @(),
    [string]$TargetsCsv,
    [string]$OutputRoot,
    [ValidateRange(1, 25)][int]$MaxTargets = 25,
    [switch]$FixtureMode,
    [switch]$PlanOnly
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$common = Join-Path $PSScriptRoot 'CybernetHardware.Common.psm1'
if (-not (Test-Path -LiteralPath $common -PathType Leaf)) { throw "Missing shared Cybernet hardware module: $common" }
Import-Module $common -Force
$repoRoot = Get-SasCybernetRepositoryRoot
$targets = @(Resolve-SasCybernetTargets -ComputerName $ComputerName -TargetsCsv $TargetsCsv -MaxTargets $MaxTargets -RepoRoot $repoRoot -Role 'Cybernet COM check target CSV')
$run = New-SasCybernetRunRoot -OutputRoot $OutputRoot -RepoRoot $repoRoot -Prefix 'com-check' -Role 'Cybernet COM check output root'
$resultsPath = Join-Path $run.run_root 'com_port_check_results.json'
$summaryPath = Join-Path $run.run_root 'com_port_check_summary.json'
$handoffPath = Join-Path $run.run_root 'operator_handoff.txt'

if ($PlanOnly) {
    $summary = [ordered]@{
        schema_version = 'sas-cybernet-com-port-check-summary/v1'
        run_id = $run.run_id
        status = 'PLANNED_NO_CONTACT'
        target_count = $targets.Count
        targets = @($targets)
        network_activity_performed = $false
        target_mutation_performed = $false
        results_path = $resultsPath
    }
    Write-SasCybernetHardwareJson -Path $summaryPath -Value $summary
    Write-Output ([pscustomobject]$summary)
    return
}

$results = @()
if ($FixtureMode) {
    foreach ($target in $targets) {
        $ports = @('COM1', 'COM2', 'COM3', 'COM4')
        $results += [pscustomobject][ordered]@{
            computer_name = $target
            status = 'COM_PORTS_READY'
            ports = $ports
            source = 'sanitized_fixture'
            network_activity_performed = $false
            target_mutation_performed = $false
            error = ''
        }
    }
}
else {
    $remoteScript = {
        Set-StrictMode -Version 2.0
        $ErrorActionPreference = 'Stop'
        $ports = @()
        $errors = @()
        try {
            foreach ($serial in @(Get-CimInstance -ClassName Win32_SerialPort -ErrorAction Stop)) {
                if ([string]$serial.DeviceID -match '^COM\d+$') { $ports += ([string]$serial.DeviceID).ToUpperInvariant() }
            }
        }
        catch { $errors += "Win32_SerialPort :: $($_.Exception.Message)" }

        try {
            $registryPath = 'HKLM:\HARDWARE\DEVICEMAP\SERIALCOMM'
            if (Test-Path -LiteralPath $registryPath) {
                $item = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
                foreach ($property in $item.PSObject.Properties) {
                    if ([string]$property.Value -match '^COM\d+$') { $ports += ([string]$property.Value).ToUpperInvariant() }
                }
            }
        }
        catch { $errors += "SERIALCOMM :: $($_.Exception.Message)" }

        return [pscustomobject]@{
            computer_name = $env:COMPUTERNAME
            ports = @($ports | Sort-Object -Unique)
            errors = @($errors)
        }
    }

    foreach ($target in $targets) {
        try {
            $remote = Invoke-Command -ComputerName $target -ScriptBlock $remoteScript -ErrorAction Stop
            $ports = @($remote.ports)
            $classification = Get-SasCybernetComClassification -Ports $ports
            $results += [pscustomobject][ordered]@{
                computer_name = $target
                status = $classification
                ports = $ports
                source = 'remote_read_only'
                network_activity_performed = $true
                target_mutation_performed = $false
                error = (@($remote.errors) -join '; ')
            }
        }
        catch {
            $results += [pscustomobject][ordered]@{
                computer_name = $target
                status = 'COM_PORT_CHECK_FAILED'
                ports = @()
                source = 'remote_read_only'
                network_activity_performed = $true
                target_mutation_performed = $false
                error = $_.Exception.Message
            }
        }
    }
}

Write-SasCybernetHardwareJson -Path $resultsPath -Value @($results)
$readyCount = @($results | Where-Object { $_.status -eq 'COM_PORTS_READY' }).Count
$localRepairCount = @($results | Where-Object { $_.status -eq 'COM_AUTOFIX_ELIGIBLE_LOCAL_ONLY' }).Count
$reviewCount = @($results | Where-Object { $_.status -eq 'COM_PORT_REVIEW_REQUIRED' }).Count
$failedCount = @($results | Where-Object { $_.status -eq 'COM_PORT_CHECK_FAILED' }).Count
$status = if ($readyCount -eq $targets.Count) { 'PASS' }
    elseif ($readyCount -gt 0) { 'PARTIAL' }
    else { 'ACTION_REQUIRED' }
$summary = [ordered]@{
    schema_version = 'sas-cybernet-com-port-check-summary/v1'
    run_id = $run.run_id
    status = $status
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    target_count = $targets.Count
    ready_count = $readyCount
    local_autofix_required_count = $localRepairCount
    review_required_count = $reviewCount
    failed_count = $failedCount
    fixture_mode = [bool]$FixtureMode
    network_activity_performed = (@($results | Where-Object { $_.network_activity_performed }).Count -gt 0)
    target_mutation_performed = $false
    local_autofix_entrypoint = 'Run-CybernetComPortAutoFix-DryRun.cmd'
    results_path = $resultsPath
}
Write-SasCybernetHardwareJson -Path $summaryPath -Value $summary
@(
    "Cybernet COM-port check: $($run.run_id)",
    "Status: $status",
    "Ready COM1-COM4: $readyCount",
    "Exact COM3-COM6 requiring local AutoFix: $localRepairCount",
    "Other shapes requiring review: $reviewCount",
    "Failed checks: $failedCount",
    'No COM mapping was changed. The AutoFix lane remains local-only and reboot-gated.',
    'For COM3-COM6, run Run-CybernetComPortAutoFix-DryRun.cmd locally on that Cybernet before any apply.',
    "Summary: $summaryPath",
    "Results: $resultsPath"
) | Set-Content -LiteralPath $handoffPath -Encoding UTF8 -WhatIf:$false
Write-Output ([pscustomobject]$summary)
if ($failedCount -gt 0) { exit 2 }
if ($localRepairCount -gt 0 -or $reviewCount -gt 0) { exit 3 }
exit 0
