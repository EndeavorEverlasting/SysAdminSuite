#Requires -Version 5.1
Set-StrictMode -Version 2.0

$sessionModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasOperatorSession.psm1'
if (-not (Test-Path -LiteralPath $sessionModule -PathType Leaf)) {
    throw "Missing AutoLogon operator-state dependency: $sessionModule"
}
# Nested state consumers must not force-reload SasOperatorSession. Refresh and field
# transactions import the session module first and rely on its exported helpers remaining
# visible in caller scope after this module loads.
Import-Module $sessionModule -ErrorAction Stop

function Get-SasAutoLogonPreparedRuntimeIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $statePath = Join-Path (Get-SasOperatorStateRoot) 'autologon-short-runtime.json'
    $preparedCommit = $null
    $schemaVersion = $null
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        try {
            $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $preparedCommit = ([string](Get-SasObjectPropertyValue $state 'prepared_commit' '')).Trim()
            $schemaVersion = [string](Get-SasObjectPropertyValue $state 'schema_version' '')
        }
        catch { }
    }

    return [pscustomobject][ordered]@{
        repo_root = $RepoRoot
        commit = $(if ([string]::IsNullOrWhiteSpace($preparedCommit)) { $null } else { $preparedCommit })
        branch = 'sealed-runtime'
        manifest_schema = $schemaVersion
        manifest_path = $statePath
        git_invoked = $false
    }
}

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
    return [string](Get-SasAutoLogonPreparedRuntimeIdentity -RepoRoot $RepoRoot).branch
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
    $runtimeIdentity = Get-SasAutoLogonPreparedRuntimeIdentity -RepoRoot $RepoRoot
    return (Set-SasAutoLogonOperatorStateValues -Values @{
        repo_root=$RepoRoot
        repo_head=$runtimeIdentity.commit
        repo_branch=$runtimeIdentity.branch
        launcher_head=$runtimeIdentity.commit
        current_terminal=(Get-SasTerminalLabel)
        target_input=$RequestedTarget
        target_fqdn=$ResolvedTargetFqdn
        requested_target=$RequestedTarget
        requested_target_short_name=$RequestedTarget.Split('.')[0].ToUpperInvariant()
        resolved_target_fqdn=$ResolvedTargetFqdn
        resolved_target_addresses=@($ResolutionAddresses)
        resolution_sources=@($ResolutionSources)
        target_locked=$true
        equipment_profile='unknown'
        profile_eligibility_proven=$false
        profile_eligibility_source='unproven_pending_exact_local_host_policy'
        profile_eligibility_evidence_path=$null
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
        [AllowNull()][string]$Target,
        [AllowNull()][string]$ExcludePath
    )
    $items = @()
    $normalizedExclude = $null
    if (-not [string]::IsNullOrWhiteSpace($ExcludePath)) {
        try { $normalizedExclude = [IO.Path]::GetFullPath($ExcludePath).TrimEnd('\') }
        catch { $normalizedExclude = $ExcludePath.TrimEnd('\') }
    }
    $targetIsFqdn = (-not [string]::IsNullOrWhiteSpace($Target) -and $Target.Contains('.'))

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
                if ($normalizedExclude) {
                    try { $candidatePath = [IO.Path]::GetFullPath($file.FullName).TrimEnd('\') }
                    catch { $candidatePath = $file.FullName.TrimEnd('\') }
                    if ($candidatePath.Equals($normalizedExclude, [StringComparison]::OrdinalIgnoreCase)) {
                        continue
                    }
                }
                try {
                    $value = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    $requested = [string](Get-SasObjectPropertyValue $value 'requested_target')
                    $resolved = [string](Get-SasObjectPropertyValue $value 'resolved_target_fqdn')
                    if ($Target) {
                        if (-not [string]::IsNullOrWhiteSpace($resolved)) {
                            if (-not (Test-SasAutoLogonSameTarget -Left $resolved -Right $Target)) { continue }
                        }
                        elseif ($targetIsFqdn) {
                            continue
                        }
                        elseif (-not (Test-SasAutoLogonSameTarget -Left $requested -Right $Target)) {
                            continue
                        }
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

    $terminal = @(
        $items | Where-Object {
            [string](Get-SasObjectPropertyValue $_.value 'status') -eq 'COMPLETED' -and
            [string](Get-SasObjectPropertyValue $_.value 'classification') -eq 'AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED'
        } | Sort-Object last_write_utc -Descending | Select-Object -First 1
    )
    if ($terminal.Count -gt 0) { return $terminal }
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
                    if ($Target) {
                        if ($Target.Contains('.') -and -not $recordedTarget.Contains('.')) { continue }
                        if (-not (Test-SasAutoLogonSameTarget -Left $recordedTarget -Right $Target)) { continue }
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
    $runtimeIdentity = Get-SasAutoLogonPreparedRuntimeIdentity -RepoRoot $RepoRoot

    $updates = @{
        repo_root=$RepoRoot
        repo_head=$runtimeIdentity.commit
        repo_branch=$runtimeIdentity.branch
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
        $eligibilityProven = [bool](Get-SasObjectPropertyValue $value 'host_eligibility_proven' $false)
        $eligibilityEvidence = [string](Get-SasObjectPropertyValue $value 'host_eligibility_evidence_path' '')

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
        $updates['equipment_profile'] = $(if ($eligibilityProven) { 'Cybernet' } else { 'unknown' })
        $updates['profile_eligibility_proven'] = $eligibilityProven
        $updates['profile_eligibility_source'] = $(if ($eligibilityProven) {
            'Test-SasHostEligibility.ps1 canonical FQDN remote policy gate'
        } else {
            'unproven_pending_exact_local_host_policy'
        })
        $updates['profile_eligibility_evidence_path'] = $eligibilityEvidence
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
        elseif ($classification -eq 'AUTOLOGON_FIELD_TARGET_LOCKED') {
            $updates['next_required_network'] = 'NONE'
            $updates['next_command'] = 'STOP - another AutoLogon transaction owns this target; inspect sas context after it finishes.'
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

Export-ModuleMember -Function Get-SasAutoLogonPreparedRuntimeIdentity,Test-SasAutoLogonSameTarget,Get-SasAutoLogonRepoBranch,Set-SasAutoLogonOperatorStateValues,Initialize-SasAutoLogonOperatorState,Find-SasLatestAutoLogonFieldResult,Find-SasLatestCompletedAutoLogonRecovery,Sync-SasAutoLogonOperatorState
