#Requires -Version 5.1
Set-StrictMode -Version 2.0

$sessionModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasOperatorSession.psm1'
if (-not (Test-Path -LiteralPath $sessionModule -PathType Leaf)) {
    throw "Missing AutoLogon operator-state dependency: $sessionModule"
}
Import-Module $sessionModule -Force

function Test-SasAutoLogonSameTarget {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Left,
        [AllowNull()][string]$Right
    )
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }
    $a = $Left.Trim().TrimEnd('.').ToLowerInvariant()
    $b = $Right.Trim().TrimEnd('.').ToLowerInvariant()
    if ($a -eq $b) { return $true }
    $aIsFqdn = $a.Contains('.')
    $bIsFqdn = $b.Contains('.')
    if ($aIsFqdn -and $bIsFqdn) { return $false }
    return ($a.Split('.')[0] -eq $b.Split('.')[0])
}

function Get-SasAutoLogonRepoBranch {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RepoRoot)
    try {
        $value = (& git -C $RepoRoot branch --show-current 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            return ([string]$value).Trim()
        }
        $value = (& git -C $RepoRoot rev-parse --short HEAD 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and $value) { return "detached@$(([string]$value).Trim())" }
    }
    catch { }
    return 'unknown'
}

function Set-SasAutoLogonOperatorStateValues {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Values)
    return (Set-SasOperatorSessionValues -Values $Values)
}

function Initialize-SasAutoLogonOperatorState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$RequestedTarget,
        [Parameter(Mandatory = $true)][string]$ResolvedTargetFqdn,
        [string[]]$ResolutionAddresses = @(),
        [string[]]$ResolutionSources = @()
    )
    $command = "sas autologon Remote $RequestedTarget"
    return (Set-SasAutoLogonOperatorStateValues -Values @{
        repo_root=$RepoRoot
        repo_head=(Get-SasRepoHead -RepoRoot $RepoRoot)
        repo_branch=(Get-SasAutoLogonRepoBranch -RepoRoot $RepoRoot)
        launcher_head=(Get-SasRepoHead -RepoRoot $RepoRoot)
        current_terminal=(Get-SasTerminalLabel)
        target_input=$RequestedTarget
        target_fqdn=$ResolvedTargetFqdn
        requested_target=$RequestedTarget
        requested_target_short_name=$RequestedTarget.Split('.')[0].ToUpperInvariant()
        resolved_target_fqdn=$ResolvedTargetFqdn
        resolved_target_addresses=@($ResolutionAddresses)
        resolution_sources=@($ResolutionSources)
        target_locked=$true
        equipment_profile='Cybernet'
        profile_eligibility_proven=$true
        profile_eligibility_source='canonical_fqdn_then_exact_local_host_policy'
        deployment_lane='autologon_only'
        package_set='cybernet-autologon-only'
        expected_autologon_state='enabled_after_restart'
        expected_autologon_enabled=$true
        imprivata_disposition='observational/external'
        historical_recovery_status='UNKNOWN'
        historical_recovery_classification=$null
        historical_recovery_result_path=$null
        autologon_deployment_started=$false
        autologon_deployment_completed=$false
        next_required_network='PROTECTED NORTHWELL'
        next_command=$command
    })
}

function Find-SasLatestAutoLogonFieldResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [AllowNull()][string]$Target
    )
    $items = @()
    foreach ($root in @(Get-SasEvidenceRoots -RepoRoot $RepoRoot)) {
        foreach ($relative in @(
            'survey\output\runs\autologon-field-deployment',
            'runs'
        )) {
            $searchRoot = Join-Path -Path $root -ChildPath $relative
            if (-not (Test-Path -LiteralPath $searchRoot -PathType Container)) { continue }
            foreach ($file in @(
                Get-ChildItem -LiteralPath $searchRoot -Filter 'autologon_field_deployment_result.json' `
                    -File -Recurse -ErrorAction SilentlyContinue
            )) {
                try {
                    $value = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    $requested = [string](Get-SasObjectPropertyValue $value 'requested_target')
                    $resolved = [string](Get-SasObjectPropertyValue $value 'resolved_target_fqdn')
                    if ($Target -and
                        -not (Test-SasAutoLogonSameTarget -Left $requested -Right $Target) -and
                        -not (Test-SasAutoLogonSameTarget -Left $resolved -Right $Target)) {
                        continue
                    }
                    $items += [pscustomobject]@{
                        path=$file.FullName
                        last_write_utc=$file.LastWriteTimeUtc
                        value=$value
                    }
                }
                catch { }
            }
        }
    }
    return @($items | Sort-Object last_write_utc -Descending | Select-Object -First 1)
}

function Find-SasLatestCompletedAutoLogonRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [AllowNull()][string]$Target
    )
    $items = @()
    foreach ($root in @(Get-SasEvidenceRoots -RepoRoot $RepoRoot)) {
        foreach ($relative in @('runs','survey\output\runs')) {
            $searchRoot = Join-Path -Path $root -ChildPath $relative
            if (-not (Test-Path -LiteralPath $searchRoot -PathType Container)) { continue }
            foreach ($file in @(
                Get-ChildItem -LiteralPath $searchRoot -Filter 's4u_probe_hang_recovery_result.json' `
                    -File -Recurse -ErrorAction SilentlyContinue
            )) {
                try {
                    $value = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    $status = [string](Get-SasObjectPropertyValue $value 'status')
                    $classification = [string](Get-SasObjectPropertyValue $value 'classification')
                    $recordedTarget = [string](Get-SasObjectPropertyValue $value 'target')
                    if ($status -ne 'COMPLETED' -or $classification -ne 'S4U_PROBE_CREATE_HANG_RECOVERED') {
                        continue
                    }
                    if ($Target -and -not (Test-SasAutoLogonSameTarget -Left $recordedTarget -Right $Target)) {
                        continue
                    }
                    $items += [pscustomobject]@{
                        path=$file.FullName
                        last_write_utc=$file.LastWriteTimeUtc
                        value=$value
                    }
                }
                catch { }
            }
        }
    }
    return @($items | Sort-Object last_write_utc -Descending | Select-Object -First 1)
}

function Sync-SasAutoLogonOperatorState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [AllowNull()][string]$Target
    )
    $session = Read-SasOperatorSession
    $filter = $Target
    if ([string]::IsNullOrWhiteSpace($filter)) {
        $filter = [string](Get-SasObjectPropertyValue $session 'resolved_target_fqdn' (
            Get-SasObjectPropertyValue $session 'target_fqdn' $null
        ))
    }

    $field = @(Find-SasLatestAutoLogonFieldResult -RepoRoot $RepoRoot -Target $filter)
    $recovery = @(Find-SasLatestCompletedAutoLogonRecovery -RepoRoot $RepoRoot -Target $filter)

    $updates = @{
        repo_root=$RepoRoot
        repo_head=(Get-SasRepoHead -RepoRoot $RepoRoot)
        repo_branch=(Get-SasAutoLogonRepoBranch -RepoRoot $RepoRoot)
        current_terminal=(Get-SasTerminalLabel)
    }

    if ($recovery.Count -gt 0) {
        $recoveryValue = $recovery[0].value
        $updates['historical_recovery_status'] = 'COMPLETED'
        $updates['historical_recovery_classification'] = [string](
            Get-SasObjectPropertyValue $recoveryValue 'classification'
        )
        $updates['historical_recovery_result_path'] = $recovery[0].path
    }

    if ($field.Count -gt 0) {
        $value = $field[0].value
        $requested = [string](Get-SasObjectPropertyValue $value 'requested_target')
        $resolved = [string](Get-SasObjectPropertyValue $value 'resolved_target_fqdn')
        $status = [string](Get-SasObjectPropertyValue $value 'status')
        $classification = [string](Get-SasObjectPropertyValue $value 'classification')
        $started = [bool](Get-SasObjectPropertyValue $value 'autologon_deployment_started' $false)
        $completed = ($status -eq 'COMPLETED' -and
            $classification -eq 'AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED')
        $mutated = [bool](Get-SasObjectPropertyValue $value 'target_mutation_performed' $false)

        if ($requested) {
            $updates['target_input'] = $requested
            $updates['requested_target'] = $requested
            $updates['requested_target_short_name'] = $requested.Split('.')[0].ToUpperInvariant()
        }
        if ($resolved) {
            $updates['target_fqdn'] = $resolved
            $updates['resolved_target_fqdn'] = $resolved
            $updates['target_locked'] = $true
        }
        $updates['resolved_target_addresses'] = @(
            Get-SasObjectPropertyValue $value 'resolved_addresses' @()
        )
        $updates['resolution_sources'] = @(
            Get-SasObjectPropertyValue $value 'resolution_sources' @()
        )
        $updates['equipment_profile'] = 'Cybernet'
        $updates['profile_eligibility_proven'] = (-not [string]::IsNullOrWhiteSpace($resolved))
        $updates['profile_eligibility_source'] = 'canonical_fqdn_then_exact_local_host_policy'
        $updates['deployment_lane'] = 'autologon_only'
        $updates['package_set'] = 'cybernet-autologon-only'
        $updates['expected_autologon_state'] = 'enabled_after_restart'
        $updates['expected_autologon_enabled'] = $true
        $updates['historical_recovery_status'] = [string](
            Get-SasObjectPropertyValue $value 'historical_recovery_status' (
                Get-SasObjectPropertyValue $session 'historical_recovery_status' 'UNKNOWN'
            )
        )
        $updates['historical_recovery_classification'] = [string](
            Get-SasObjectPropertyValue $value 'historical_recovery_classification' (
                Get-SasObjectPropertyValue $session 'historical_recovery_classification' $null
            )
        )
        $updates['autologon_deployment_started'] = $started
        $updates['autologon_deployment_completed'] = $completed
        $updates['latest_run_id'] = [string](Get-SasObjectPropertyValue $value 'run_id')
        $updates['latest_status'] = $status
        $updates['latest_phase'] = $(if ($completed) {
            'terminal'
        } elseif ($started) {
            'apply_or_restart'
        } else {
            'pre_apply'
        })
        $updates['latest_checkpoint'] = $classification
        $updates['target_mutation_performed'] = $mutated
        $updates['evidence_path'] = $field[0].path

        if ($completed) {
            $updates['next_required_network'] = 'NONE'
            $updates['next_command'] = 'STOP - AutoLogon deployment completed; do not rerun.'
        }
        elseif ($started -or $mutated) {
            $updates['next_required_network'] = 'NONE'
            $updates['next_command'] = 'STOP - inspect persisted AutoLogon evidence; do not rerun.'
        }
        elseif ($requested) {
            $updates['next_required_network'] = 'PROTECTED NORTHWELL'
            $updates['next_command'] = "sas autologon Remote $requested"
        }
    }
    elseif ($recovery.Count -gt 0) {
        $requested = [string](Get-SasObjectPropertyValue $session 'requested_target' (
            Get-SasObjectPropertyValue $session 'target_input' $Target
        ))
        if ($requested) {
            $updates['next_required_network'] = 'PROTECTED NORTHWELL'
            $updates['next_command'] = "sas autologon Remote $requested"
        }
    }

    [void](Set-SasAutoLogonOperatorStateValues -Values $updates)
    return (Read-SasOperatorSession)
}

Export-ModuleMember -Function Test-SasAutoLogonSameTarget,Get-SasAutoLogonRepoBranch,Set-SasAutoLogonOperatorStateValues,Initialize-SasAutoLogonOperatorState,Find-SasLatestAutoLogonFieldResult,Find-SasLatestCompletedAutoLogonRecovery,Sync-SasAutoLogonOperatorState
