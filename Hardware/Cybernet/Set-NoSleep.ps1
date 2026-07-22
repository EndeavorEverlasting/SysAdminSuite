#Requires -Version 5.1
<#
.SYNOPSIS
Set standby and hibernate idle timeouts to Never on explicit Cybernet targets.

.DESCRIPTION
Sets only the AC/DC standby-idle and hibernate-idle timeout indexes to zero for every parsed Windows
power scheme, reactivates the originally active scheme, verifies every changed index, and writes local
evidence. It does not alter display timeout, physical power-button behavior, lid behavior, disk timeout,
DDC/CI controls, hibernate availability, or any application setting.

-WhatIf performs request-only planning with no remote contact. -FixtureMode emits synthetic contract
evidence. Live mutation requires -AllowTargetMutation and ShouldProcess confirmation.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string[]]$ComputerName = @(),
    [string]$TargetsCsv,
    [string]$OutputRoot,
    [ValidateRange(1, 25)][int]$MaxTargets = 25,
    [switch]$AllowTargetMutation,
    [switch]$FixtureMode
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($FixtureMode -and $AllowTargetMutation) {
    throw 'FixtureMode is offline and cannot be combined with -AllowTargetMutation.'
}
if (-not $FixtureMode -and -not $WhatIfPreference -and -not $AllowTargetMutation) {
    throw 'Refusing no-sleep mutation without -AllowTargetMutation. Use -WhatIf or -FixtureMode first.'
}

$common = Join-Path $PSScriptRoot 'CybernetHardware.Common.psm1'
if (-not (Test-Path -LiteralPath $common -PathType Leaf)) { throw "Missing shared Cybernet hardware module: $common" }
Import-Module $common -Force
$repoRoot = Get-SasCybernetRepositoryRoot
$targets = @(Resolve-SasCybernetTargets -ComputerName $ComputerName -TargetsCsv $TargetsCsv -MaxTargets $MaxTargets -RepoRoot $repoRoot -Role 'Cybernet no-sleep target CSV')
$run = New-SasCybernetRunRoot -OutputRoot $OutputRoot -RepoRoot $repoRoot -Prefix 'no-sleep' -Role 'Cybernet no-sleep output root'
$resultsPath = Join-Path $run.run_root 'no_sleep_results.json'
$summaryPath = Join-Path $run.run_root 'no_sleep_summary.json'
$handoffPath = Join-Path $run.run_root 'operator_handoff.txt'

if ($WhatIfPreference) {
    $summary = [ordered]@{
        schema_version = 'sas-cybernet-no-sleep-summary/v1'
        run_id = $run.run_id
        status = 'PLANNED_WHATIF'
        target_count = $targets.Count
        targets = @($targets)
        standby_ac_minutes = 0
        standby_dc_minutes = 0
        hibernate_ac_minutes = 0
        hibernate_dc_minutes = 0
        network_activity_performed = $false
        target_mutation_performed = $false
        results_path = $resultsPath
    }
    Write-SasCybernetHardwareJson -Path $summaryPath -Value $summary
    @(
        "Cybernet no-sleep plan: $($run.run_id)",
        "Targets: $($targets.Count)",
        'Planned: set standby and hibernate idle timeouts to Never for AC and DC on every parsed scheme.',
        'No target contact or mutation occurred.',
        'Next: run one authorized pilot with -AllowTargetMutation and confirmation enabled.'
    ) | Set-Content -LiteralPath $handoffPath -Encoding UTF8 -WhatIf:$false
    Write-Output ([pscustomobject]$summary)
    return
}

$results = @()
if ($FixtureMode) {
    foreach ($target in $targets) {
        $results += [pscustomobject][ordered]@{
            computer_name = $target
            status = 'FIXTURE_PASS'
            scheme_count = 2
            verified_scheme_count = 2
            standby_ac = 0
            standby_dc = 0
            hibernate_ac = 0
            hibernate_dc = 0
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

        function Invoke-CheckedPowerCfg {
            param([string[]]$Arguments)
            $text = & $powerCfg @Arguments 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                throw "powercfg $($Arguments -join ' ') exited $LASTEXITCODE :: $text"
            }
            return $text
        }

        function Get-PowerIndexes {
            param([string]$SchemeGuid, [string]$SettingGuid)
            $text = Invoke-CheckedPowerCfg -Arguments @('/query', $SchemeGuid, $subSleep, $SettingGuid)
            $ac = $null
            $dc = $null
            if ($text -match 'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)') { $ac = [Convert]::ToInt32($Matches[1], 16) }
            if ($text -match 'Current DC Power Setting Index:\s*0x([0-9a-fA-F]+)') { $dc = [Convert]::ToInt32($Matches[1], 16) }
            return [pscustomobject]@{ ac = $ac; dc = $dc }
        }

        $list = Invoke-CheckedPowerCfg -Arguments @('/list')
        $schemes = @()
        foreach ($line in ($list -split "`r?`n")) {
            if ($line -match 'Power Scheme GUID:\s*([a-fA-F0-9-]{36})\s+\(([^)]*)\)\s*(\*)?') {
                $schemes += [pscustomobject]@{
                    guid = $Matches[1]
                    name = $Matches[2]
                    active = ($Matches[3] -eq '*')
                }
            }
        }
        if ($schemes.Count -eq 0) { throw 'No power schemes parsed from powercfg /list.' }

        $activeGuid = [string](@($schemes | Where-Object { $_.active } | Select-Object -First 1).guid)
        $settings = @()
        $errors = @()
        foreach ($scheme in $schemes) {
            try {
                $beforeStandby = Get-PowerIndexes -SchemeGuid $scheme.guid -SettingGuid $standbyIdle
                $beforeHibernate = Get-PowerIndexes -SchemeGuid $scheme.guid -SettingGuid $hibernateIdle
                Invoke-CheckedPowerCfg -Arguments @('/setacvalueindex', $scheme.guid, $subSleep, $standbyIdle, '0') | Out-Null
                Invoke-CheckedPowerCfg -Arguments @('/setdcvalueindex', $scheme.guid, $subSleep, $standbyIdle, '0') | Out-Null
                Invoke-CheckedPowerCfg -Arguments @('/setacvalueindex', $scheme.guid, $subSleep, $hibernateIdle, '0') | Out-Null
                Invoke-CheckedPowerCfg -Arguments @('/setdcvalueindex', $scheme.guid, $subSleep, $hibernateIdle, '0') | Out-Null
                $afterStandby = Get-PowerIndexes -SchemeGuid $scheme.guid -SettingGuid $standbyIdle
                $afterHibernate = Get-PowerIndexes -SchemeGuid $scheme.guid -SettingGuid $hibernateIdle
                $verified = ($afterStandby.ac -eq 0 -and $afterStandby.dc -eq 0 -and $afterHibernate.ac -eq 0 -and $afterHibernate.dc -eq 0)
                if (-not $verified) { $errors += "No-sleep verification failed for scheme $($scheme.guid)." }
                $settings += [pscustomobject][ordered]@{
                    scheme_guid = $scheme.guid
                    scheme_name = $scheme.name
                    before_standby_ac = $beforeStandby.ac
                    before_standby_dc = $beforeStandby.dc
                    before_hibernate_ac = $beforeHibernate.ac
                    before_hibernate_dc = $beforeHibernate.dc
                    after_standby_ac = $afterStandby.ac
                    after_standby_dc = $afterStandby.dc
                    after_hibernate_ac = $afterHibernate.ac
                    after_hibernate_dc = $afterHibernate.dc
                    verified = [bool]$verified
                }
            }
            catch {
                $errors += "$($scheme.guid) :: $($_.Exception.Message)"
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($activeGuid)) {
            try { Invoke-CheckedPowerCfg -Arguments @('/setactive', $activeGuid) | Out-Null }
            catch { $errors += "setactive $activeGuid :: $($_.Exception.Message)" }
        }

        $verifiedCount = @($settings | Where-Object { $_.verified }).Count
        $status = if ($errors.Count -eq 0 -and $verifiedCount -eq $schemes.Count) { 'APPLIED_VERIFIED' }
            elseif ($verifiedCount -gt 0) { 'PARTIAL' }
            else { 'FAILED' }
        return [pscustomobject][ordered]@{
            computer_name = $env:COMPUTERNAME
            status = $status
            scheme_count = $schemes.Count
            verified_scheme_count = $verifiedCount
            settings = @($settings)
            network_activity_performed = $true
            target_mutation_performed = $true
            errors = @($errors)
        }
    }

    foreach ($target in $targets) {
        if (-not $PSCmdlet.ShouldProcess($target, 'Set and verify standby/hibernate idle timeouts = Never for AC and DC')) {
            $results += [pscustomobject][ordered]@{
                computer_name = $target
                status = 'SKIPPED_OPERATOR_DECLINED'
                scheme_count = 0
                verified_scheme_count = 0
                network_activity_performed = $false
                target_mutation_performed = $false
                error = 'Operator declined ShouldProcess confirmation.'
            }
            continue
        }
        try {
            $remote = Invoke-Command -ComputerName $target -ScriptBlock $remoteScript -ErrorAction Stop
            $results += [pscustomobject][ordered]@{
                computer_name = $target
                status = [string]$remote.status
                scheme_count = [int]$remote.scheme_count
                verified_scheme_count = [int]$remote.verified_scheme_count
                settings = @($remote.settings)
                network_activity_performed = [bool]$remote.network_activity_performed
                target_mutation_performed = [bool]$remote.target_mutation_performed
                error = (@($remote.errors) -join '; ')
            }
        }
        catch {
            $results += [pscustomobject][ordered]@{
                computer_name = $target
                status = 'FAILED_REMOTE_EXECUTION'
                scheme_count = 0
                verified_scheme_count = 0
                network_activity_performed = $true
                target_mutation_performed = $false
                error = $_.Exception.Message
            }
        }
    }
}

Write-SasCybernetHardwareJson -Path $resultsPath -Value @($results)
$successCount = @($results | Where-Object { $_.status -in @('APPLIED_VERIFIED', 'FIXTURE_PASS') }).Count
$partialCount = @($results | Where-Object { $_.status -eq 'PARTIAL' }).Count
$failedCount = @($results | Where-Object { $_.status -like 'FAILED*' }).Count
$skippedCount = @($results | Where-Object { $_.status -like 'SKIPPED*' }).Count
$status = if ($successCount -eq $targets.Count -and $partialCount -eq 0 -and $failedCount -eq 0 -and $skippedCount -eq 0) { 'PASS' }
    elseif ($successCount -gt 0) { 'PARTIAL' }
    else { 'FAIL' }
$summary = [ordered]@{
    schema_version = 'sas-cybernet-no-sleep-summary/v1'
    run_id = $run.run_id
    status = $status
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    target_count = $targets.Count
    success_count = $successCount
    partial_count = $partialCount
    failed_count = $failedCount
    skipped_count = $skippedCount
    fixture_mode = [bool]$FixtureMode
    standby_ac_minutes = 0
    standby_dc_minutes = 0
    hibernate_ac_minutes = 0
    hibernate_dc_minutes = 0
    network_activity_performed = (@($results | Where-Object { $_.network_activity_performed }).Count -gt 0)
    target_mutation_performed = (@($results | Where-Object { $_.target_mutation_performed }).Count -gt 0)
    results_path = $resultsPath
}
Write-SasCybernetHardwareJson -Path $summaryPath -Value $summary
@(
    "Cybernet no-sleep result: $($run.run_id)",
    "Status: $status",
    "Targets: $($targets.Count)",
    "Successful: $successCount",
    "Partial: $partialCount",
    "Failed: $failedCount",
    "Skipped: $skippedCount",
    'Only standby and hibernate idle timeouts were changed. Display, buttons, disk, lid, and hibernate availability were not changed.',
    "Summary: $summaryPath",
    "Results: $resultsPath"
) | Set-Content -LiteralPath $handoffPath -Encoding UTF8 -WhatIf:$false
Write-Output ([pscustomobject]$summary)
if ($status -eq 'FAIL') { exit 1 }
if ($status -eq 'PARTIAL') { exit 2 }
exit 0
