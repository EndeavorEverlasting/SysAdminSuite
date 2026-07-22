#Requires -Version 5.1
<#
.SYNOPSIS
Validate the Cybernet hardware configuration after software installation and hardware-policy application.

.DESCRIPTION
Performs read-only verification of standby/hibernate idle indexes, the Windows physical power-button
action, COM-port readiness, and the integrated display's MCCS VCP 0xCA state. The DDC/CI probe is
delegated to the canonical display-button controller. This script never changes a target.
#>
[CmdletBinding()]
param(
    [string[]]$ComputerName = @(),
    [string]$TargetsCsv,
    [ValidateRange(-1, 64)][int]$MonitorIndex = -1,
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
$targets = @(Resolve-SasCybernetTargets -ComputerName $ComputerName -TargetsCsv $TargetsCsv -MaxTargets $MaxTargets -RepoRoot $repoRoot -Role 'Cybernet post-install validation target CSV')
$run = New-SasCybernetRunRoot -OutputRoot $OutputRoot -RepoRoot $repoRoot -Prefix 'postinstall-validation' -Role 'Cybernet post-install validation output root'
$resultsPath = Join-Path $run.run_root 'postinstall_validation_results.json'
$summaryPath = Join-Path $run.run_root 'postinstall_validation_summary.json'
$handoffPath = Join-Path $run.run_root 'operator_handoff.txt'

if ($PlanOnly) {
    $summary = [ordered]@{
        schema_version = 'sas-cybernet-postinstall-validation-summary/v1'
        run_id = $run.run_id
        status = 'PLANNED_NO_CONTACT'
        target_count = $targets.Count
        targets = @($targets)
        checks = @('no_sleep', 'physical_power_button_do_nothing', 'display_privacy_buttons_disabled', 'com1_com4')
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
        $results += [pscustomobject][ordered]@{
            computer_name = $target
            status = 'POSTINSTALL_VALIDATED'
            no_sleep_status = 'VERIFIED'
            power_button_status = 'DO_NOTHING_VERIFIED'
            display_button_status = 'VCP_CA_0X0303_VERIFIED'
            com_port_status = 'COM_PORTS_READY'
            ports = @('COM1', 'COM2', 'COM3', 'COM4')
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
        $powerCfg = Join-Path $env:WINDIR 'System32\powercfg.exe'
        $subSleep = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
        $standbyIdle = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'
        $hibernateIdle = '9d7815a6-7ee4-497e-8888-515a05f02364'
        $subButtons = '4f971e89-eebd-4455-a8de-9e59040e7347'
        $powerButtonAction = '7648efa3-dd9c-4e3e-b566-50f929386280'

        function Invoke-ReadPowerCfg {
            param([string[]]$Arguments)
            $text = & $powerCfg @Arguments 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) { throw "powercfg $($Arguments -join ' ') exited $LASTEXITCODE :: $text" }
            return $text
        }
        function Get-Indexes {
            param([string]$SchemeGuid, [string]$SubgroupGuid, [string]$SettingGuid)
            $text = Invoke-ReadPowerCfg -Arguments @('/query', $SchemeGuid, $SubgroupGuid, $SettingGuid)
            $ac = $null
            $dc = $null
            if ($text -match 'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)') { $ac = [Convert]::ToInt32($Matches[1], 16) }
            if ($text -match 'Current DC Power Setting Index:\s*0x([0-9a-fA-F]+)') { $dc = [Convert]::ToInt32($Matches[1], 16) }
            return [pscustomobject]@{ ac = $ac; dc = $dc }
        }

        $list = Invoke-ReadPowerCfg -Arguments @('/list')
        $schemes = @()
        foreach ($line in ($list -split "`r?`n")) {
            if ($line -match 'Power Scheme GUID:\s*([a-fA-F0-9-]{36})\s+\(([^)]*)\)\s*(\*)?') {
                $schemes += [pscustomobject]@{ guid = $Matches[1]; name = $Matches[2]; active = ($Matches[3] -eq '*') }
            }
        }
        if ($schemes.Count -eq 0) { throw 'No power schemes parsed from powercfg /list.' }

        $powerRows = @()
        foreach ($scheme in $schemes) {
            $standby = Get-Indexes -SchemeGuid $scheme.guid -SubgroupGuid $subSleep -SettingGuid $standbyIdle
            $hibernate = Get-Indexes -SchemeGuid $scheme.guid -SubgroupGuid $subSleep -SettingGuid $hibernateIdle
            $button = Get-Indexes -SchemeGuid $scheme.guid -SubgroupGuid $subButtons -SettingGuid $powerButtonAction
            $powerRows += [pscustomobject][ordered]@{
                scheme_guid = $scheme.guid
                scheme_name = $scheme.name
                standby_ac = $standby.ac
                standby_dc = $standby.dc
                hibernate_ac = $hibernate.ac
                hibernate_dc = $hibernate.dc
                power_button_ac = $button.ac
                power_button_dc = $button.dc
            }
        }

        $ports = @()
        try {
            foreach ($serial in @(Get-CimInstance -ClassName Win32_SerialPort -ErrorAction Stop)) {
                if ([string]$serial.DeviceID -match '^COM\d+$') { $ports += ([string]$serial.DeviceID).ToUpperInvariant() }
            }
        }
        catch { }
        try {
            $registryPath = 'HKLM:\HARDWARE\DEVICEMAP\SERIALCOMM'
            if (Test-Path -LiteralPath $registryPath) {
                $item = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
                foreach ($property in $item.PSObject.Properties) {
                    if ([string]$property.Value -match '^COM\d+$') { $ports += ([string]$property.Value).ToUpperInvariant() }
                }
            }
        }
        catch { }

        return [pscustomobject][ordered]@{
            computer_name = $env:COMPUTERNAME
            schemes = @($powerRows)
            ports = @($ports | Sort-Object -Unique)
        }
    }

    $powerByTarget = @{}
    foreach ($target in $targets) {
        try { $powerByTarget[$target.ToUpperInvariant()] = Invoke-Command -ComputerName $target -ScriptBlock $remoteScript -ErrorAction Stop }
        catch { $powerByTarget[$target.ToUpperInvariant()] = [pscustomobject]@{ error = $_.Exception.Message; schemes = @(); ports = @() } }
    }

    $displayCore = Join-Path $repoRoot 'scripts\Invoke-SasCybernetDisplayButtonControl.ps1'
    $displayOutput = Join-Path $run.run_root 'display_probe'
    $displaySummary = $null
    try {
        $displaySummary = & $displayCore -ComputerName $targets -Operation Probe -MonitorIndex $MonitorIndex -MaxTargets $MaxTargets -OutputRoot $displayOutput
    }
    catch { $displaySummary = [pscustomobject]@{ status = 'FAIL'; details_path = ''; error = $_.Exception.Message } }

    $displayByTarget = @{}
    if ($displaySummary -and -not [string]::IsNullOrWhiteSpace([string]$displaySummary.details_path) -and (Test-Path -LiteralPath $displaySummary.details_path)) {
        foreach ($entry in @(Get-Content -LiteralPath $displaySummary.details_path -Raw -Encoding UTF8 | ConvertFrom-Json)) {
            $locked = @($entry.result | Where-Object { [string]$_.VcpCaCurrentHex -eq '0x0303' }).Count -gt 0
            $displayByTarget[([string]$entry.computer_name).ToUpperInvariant()] = if ($locked) { 'VCP_CA_0X0303_VERIFIED' } else { 'VCP_CA_NOT_LOCKED' }
        }
    }

    foreach ($target in $targets) {
        $key = $target.ToUpperInvariant()
        $remote = $powerByTarget[$key]
        if ($remote.PSObject.Properties.Name -contains 'error') {
            $results += [pscustomobject][ordered]@{
                computer_name = $target
                status = 'POSTINSTALL_CHECK_FAILED'
                no_sleep_status = 'UNKNOWN'
                power_button_status = 'UNKNOWN'
                display_button_status = if ($displayByTarget.ContainsKey($key)) { $displayByTarget[$key] } else { 'UNKNOWN' }
                com_port_status = 'UNKNOWN'
                ports = @()
                network_activity_performed = $true
                target_mutation_performed = $false
                error = [string]$remote.error
            }
            continue
        }

        $schemes = @($remote.schemes)
        $noSleep = ($schemes.Count -gt 0 -and @($schemes | Where-Object { $_.standby_ac -ne 0 -or $_.standby_dc -ne 0 -or $_.hibernate_ac -ne 0 -or $_.hibernate_dc -ne 0 }).Count -eq 0)
        $buttonReady = ($schemes.Count -gt 0 -and @($schemes | Where-Object { $_.power_button_ac -ne 0 -or $_.power_button_dc -ne 0 }).Count -eq 0)
        $comStatus = Get-SasCybernetComClassification -Ports @($remote.ports)
        $displayStatus = if ($displayByTarget.ContainsKey($key)) { $displayByTarget[$key] } else { 'DISPLAY_PROBE_FAILED' }
        $ready = ($noSleep -and $buttonReady -and $comStatus -eq 'COM_PORTS_READY' -and $displayStatus -eq 'VCP_CA_0X0303_VERIFIED')
        $results += [pscustomobject][ordered]@{
            computer_name = $target
            status = if ($ready) { 'POSTINSTALL_VALIDATED' } else { 'POSTINSTALL_ACTION_REQUIRED' }
            no_sleep_status = if ($noSleep) { 'VERIFIED' } else { 'NOT_VERIFIED' }
            power_button_status = if ($buttonReady) { 'DO_NOTHING_VERIFIED' } else { 'NOT_VERIFIED' }
            display_button_status = $displayStatus
            com_port_status = $comStatus
            ports = @($remote.ports)
            network_activity_performed = $true
            target_mutation_performed = $false
            error = ''
        }
    }
}

Write-SasCybernetHardwareJson -Path $resultsPath -Value @($results)
$validCount = @($results | Where-Object { $_.status -eq 'POSTINSTALL_VALIDATED' }).Count
$actionCount = @($results | Where-Object { $_.status -eq 'POSTINSTALL_ACTION_REQUIRED' }).Count
$failedCount = @($results | Where-Object { $_.status -eq 'POSTINSTALL_CHECK_FAILED' }).Count
$status = if ($validCount -eq $targets.Count) { 'PASS' }
    elseif ($validCount -gt 0) { 'PARTIAL' }
    else { 'FAIL' }
$summary = [ordered]@{
    schema_version = 'sas-cybernet-postinstall-validation-summary/v1'
    run_id = $run.run_id
    status = $status
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    target_count = $targets.Count
    validated_count = $validCount
    action_required_count = $actionCount
    failed_count = $failedCount
    fixture_mode = [bool]$FixtureMode
    network_activity_performed = (@($results | Where-Object { $_.network_activity_performed }).Count -gt 0)
    target_mutation_performed = $false
    results_path = $resultsPath
}
Write-SasCybernetHardwareJson -Path $summaryPath -Value $summary
@(
    "Cybernet post-install validation: $($run.run_id)",
    "Status: $status",
    "Validated: $validCount/$($targets.Count)",
    "Action required: $actionCount",
    "Failed checks: $failedCount",
    'Validation is read-only. COM3-COM6 must be repaired locally through the existing AutoFix before this gate can pass.',
    "Summary: $summaryPath",
    "Results: $resultsPath"
) | Set-Content -LiteralPath $handoffPath -Encoding UTF8 -WhatIf:$false
Write-Output ([pscustomobject]$summary)
if ($status -eq 'FAIL') { exit 1 }
if ($status -eq 'PARTIAL') { exit 2 }
exit 0
