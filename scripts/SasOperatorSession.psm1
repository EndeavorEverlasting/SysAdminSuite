Set-StrictMode -Version 2.0

function Get-SasOperatorStateRoot {
    $root = Join-Path $env:LOCALAPPDATA 'SysAdminSuite'
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    return $root
}

function Get-SasOperatorSessionPath { return (Join-Path (Get-SasOperatorStateRoot) 'operator-session.json') }

function New-SasOperatorSession {
    [pscustomobject][ordered]@{
        schema_version='sas-operator-session/v1'
        updated_at_utc=(Get-Date).ToUniversalTime().ToString('o')
        repo_root=$null
        repo_head=$null
        launcher_head=$null
        current_network_classification='UNKNOWN'
        current_network_label=$null
        last_network_classification='UNKNOWN'
        last_network_label=$null
        current_terminal=$null
        target_input=$null
        target_fqdn=$null
        target_locked=$false
        equipment_profile=$null
        profile_eligibility_proven=$false
        profile_eligibility_source=$null
        deployment_lane=$null
        package_set=$null
        expected_autologon_state=$null
        expected_autologon_enabled=$null
        imprivata_disposition='observational/external'
        latest_run_id=$null
        latest_status=$null
        latest_phase=$null
        latest_checkpoint=$null
        cleanup_status='UNKNOWN'
        cleanup_outstanding=$false
        target_contact_performed=$false
        target_mutation_performed=$false
        package_execution_started=$false
        completed_package_ids=@()
        next_required_network=$null
        next_command=$null
        evidence_path=$null
    }
}

function Get-SasObjectPropertyValue {
    param($Object,[string]$Name,$Default=$null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Read-SasOperatorSession {
    $path=Get-SasOperatorSessionPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-SasOperatorSession) }
    try {
        $value=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string](Get-SasObjectPropertyValue $value 'schema_version') -ne 'sas-operator-session/v1') { return (New-SasOperatorSession) }
        return $value
    } catch { return (New-SasOperatorSession) }
}

function Write-SasOperatorSession {
    param([Parameter(Mandatory=$true)]$Session)
    $path=Get-SasOperatorSessionPath
    $Session.updated_at_utc=(Get-Date).ToUniversalTime().ToString('o')
    $temp="$path.tmp"
    $Session | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $path -Force
    return $path
}

function Set-SasOperatorSessionValues {
    param([Parameter(Mandatory=$true)][hashtable]$Values)
    $session=Read-SasOperatorSession
    if ($Values.ContainsKey('current_network_classification')) {
        $previousClassification=[string](Get-SasObjectPropertyValue $session 'current_network_classification' 'UNKNOWN')
        $previousLabel=Get-SasObjectPropertyValue $session 'current_network_label'
        if (-not $Values.ContainsKey('last_network_classification')) { $Values['last_network_classification']=$previousClassification }
        if (-not $Values.ContainsKey('last_network_label')) { $Values['last_network_label']=$previousLabel }
    }
    foreach ($name in $Values.Keys) {
        $property=$session.PSObject.Properties[$name]
        if ($property) { $property.Value=$Values[$name] }
        else { $session | Add-Member -NotePropertyName $name -NotePropertyValue $Values[$name] }
    }
    [void](Write-SasOperatorSession -Session $session)
    return $session
}

function Get-SasRepoHead {
    param([Parameter(Mandatory=$true)][string]$RepoRoot)
    try {
        $value=(& git -C $RepoRoot rev-parse HEAD 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and $value) { return ([string]$value).Trim() }
    } catch {}
    return $null
}

function Get-SasTerminalLabel {
    try {
        $self=Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop
        $parent=Get-CimInstance Win32_Process -Filter "ProcessId=$($self.ParentProcessId)" -ErrorAction Stop
        if ($parent.Name) { return [string]$parent.Name }
    } catch {}
    return [string]$Host.Name
}

function Get-SasOperatorNetworkClassification {
    param([Parameter(Mandatory=$true)][string]$RepoRoot)
    $module=Join-Path $RepoRoot 'scripts\SasNetworkGuard.psm1'
    if (-not (Test-Path -LiteralPath $module -PathType Leaf)) { return [pscustomobject]@{ classification='INCONCLUSIVE'; label='unknown'; protected=$false } }
    Import-Module $module -Force
    $label=Get-SasCurrentWifiSsid
    $protected=Test-SasNorthwellWifiSsid -Ssid $label
    if (-not $protected) { try { $protected=Test-SasNorthwellWiredEvidence -NetworkText (Get-SasLocalNetworkText) } catch { $protected=$false } }
    $classification=if ($protected) { 'PROTECTED_NORTHWELL' } elseif ($label -and $label -ne 'unknown') { 'GUEST_INTERNET' } else { 'INCONCLUSIVE' }
    [pscustomobject][ordered]@{ classification=$classification; label=$label; protected=[bool]$protected }
}

function Set-SasOperatorNextAction {
    param([Parameter(Mandatory=$true)][string]$Network,[Parameter(Mandatory=$true)][string]$Command)
    return (Set-SasOperatorSessionValues -Values @{ next_required_network=$Network; next_command=$Command })
}

function Initialize-SasCybernetCoreSession {
    param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$TargetInput,[Parameter(Mandatory=$true)][string]$TargetFqdn)
    $head=Get-SasRepoHead -RepoRoot $RepoRoot
    return (Set-SasOperatorSessionValues -Values @{
        repo_root=$RepoRoot
        repo_head=$head
        launcher_head=$head
        current_terminal=(Get-SasTerminalLabel)
        target_input=$TargetInput
        target_fqdn=$TargetFqdn
        target_locked=$true
        equipment_profile='Cybernet'
        profile_eligibility_proven=$true
        profile_eligibility_source='explicit_tracked_sas_cybernet_core_command'
        deployment_lane='profiled_clinical_core'
        package_set='cybernet-clinical-core'
        expected_autologon_state='disabled_preserve_only'
        expected_autologon_enabled=$false
        imprivata_disposition='observational/external'
        next_required_network='PROTECTED NORTHWELL'
        next_command="sas cybernet Core $TargetInput"
    })
}

function Get-SasEvidenceRoots {
    param([Parameter(Mandatory=$true)][string]$RepoRoot)
    $roots=New-Object 'System.Collections.Generic.List[string]'
    foreach ($candidate in @($RepoRoot,$env:SAS_REPO_ROOT)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Container) -and -not $roots.Contains($candidate)) { [void]$roots.Add($candidate) }
    }
    $stateRoot=Get-SasOperatorStateRoot
    $cache=Join-Path $stateRoot 'repo-root.txt'
    if (Test-Path -LiteralPath $cache -PathType Leaf) {
        try { $candidate=(Get-Content -LiteralPath $cache -Raw).Trim(); if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Container) -and -not $roots.Contains($candidate)) { [void]$roots.Add($candidate) } } catch {}
    }
    foreach ($candidate in @(Get-ChildItem -LiteralPath $stateRoot -Directory -Filter 'field-ready*' -ErrorAction SilentlyContinue)) { if (-not $roots.Contains($candidate.FullName)) { [void]$roots.Add($candidate.FullName) } }
    return @($roots)
}

function Find-SasLatestCybernetCoreEvidence {
    param([Parameter(Mandatory=$true)][string]$RepoRoot,[AllowNull()][string]$TargetFqdn,[AllowNull()][string]$ExcludeRunId)
    $items=New-Object System.Collections.Generic.List[object]
    foreach ($root in @(Get-SasEvidenceRoots -RepoRoot $RepoRoot)) {
        $runRoot=Join-Path $root 'survey\output\runs\cybernet-profiled-clinical-core'
        if (-not (Test-Path -LiteralPath $runRoot -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $runRoot -Filter 'cybernet_profiled_clinical_core_result.json' -File -Recurse -ErrorAction SilentlyContinue)) {
            try {
                $value=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $valueRun=[string](Get-SasObjectPropertyValue $value 'run_id')
                $valueTarget=[string](Get-SasObjectPropertyValue $value 'target_fqdn')
                if ($ExcludeRunId -and $valueRun -eq $ExcludeRunId) { continue }
                if ($TargetFqdn -and $valueTarget -and -not $valueTarget.Equals($TargetFqdn,[StringComparison]::OrdinalIgnoreCase)) { continue }
                $items.Add([pscustomobject]@{ path=$file.FullName; last_write_utc=$file.LastWriteTimeUtc; value=$value })
            } catch {}
        }
    }
    return @($items | Sort-Object last_write_utc -Descending | Select-Object -First 1)
}

function Sync-SasOperatorSessionFromEvidence {
    param([Parameter(Mandatory=$true)][string]$RepoRoot,[AllowNull()][string]$TargetFqdn)
    $found=@(Find-SasLatestCybernetCoreEvidence -RepoRoot $RepoRoot -TargetFqdn $TargetFqdn)
    if ($found.Count -eq 0) { return (Read-SasOperatorSession) }
    $item=$found[0]; $value=$item.value
    $completed=@()
    foreach ($row in @((Get-SasObjectPropertyValue $value 'package_results' @()))) {
        if ($row -and [bool](Get-SasObjectPropertyValue $row 'success' $false) -and (Get-SasObjectPropertyValue $row 'id')) { $completed += [string](Get-SasObjectPropertyValue $row 'id') }
    }
    foreach ($id in @((Get-SasObjectPropertyValue $value 'completed_package_ids' @()))) { if ($id) { $completed += [string]$id } }
    $completed=@($completed | Sort-Object -Unique)
    $cleanupSucceeded=[bool](Get-SasObjectPropertyValue $value 'cleanup_succeeded' $false)
    $status=[string](Get-SasObjectPropertyValue $value 'status')
    $targetInput=[string](Get-SasObjectPropertyValue $value 'target_input' (Get-SasObjectPropertyValue (Read-SasOperatorSession) 'target_input'))
    $valueTarget=[string](Get-SasObjectPropertyValue $value 'target_fqdn' $TargetFqdn)
    $nextNetwork=if ($status -eq 'CYBERNET_PROFILED_CLINICAL_CORE_COMPLETED') { 'NONE' } else { 'PROTECTED NORTHWELL' }
    $nextCommand=if ($status -eq 'CYBERNET_PROFILED_CLINICAL_CORE_COMPLETED') { 'sas evidence Cybernet' } elseif (-not $cleanupSucceeded) { "sas cybernet Recover $targetInput" } else { "sas cybernet Core $targetInput" }
    $profileProven=[bool](Get-SasObjectPropertyValue $value 'profile_eligibility_proven' $false)
    $profileSource=[string](Get-SasObjectPropertyValue $value 'profile_eligibility_source' 'legacy_profiled_core_evidence')
    return (Set-SasOperatorSessionValues -Values @{
        repo_root=$RepoRoot
        repo_head=(Get-SasRepoHead -RepoRoot $RepoRoot)
        target_input=$targetInput
        target_fqdn=$valueTarget
        target_locked=(-not [string]::IsNullOrWhiteSpace($valueTarget))
        equipment_profile='Cybernet'
        profile_eligibility_proven=$profileProven
        profile_eligibility_source=$profileSource
        deployment_lane='profiled_clinical_core'
        package_set='cybernet-clinical-core'
        expected_autologon_state='disabled_preserve_only'
        expected_autologon_enabled=$false
        imprivata_disposition='observational/external'
        latest_run_id=[string](Get-SasObjectPropertyValue $value 'run_id')
        latest_status=$status
        latest_phase=[string](Get-SasObjectPropertyValue $value 'phase')
        latest_checkpoint=[string](Get-SasObjectPropertyValue $value 'checkpoint')
        cleanup_status=$(if ($cleanupSucceeded) { 'VERIFIED' } else { 'OUTSTANDING_OR_UNPROVEN' })
        cleanup_outstanding=(-not $cleanupSucceeded -and $status -ne 'CYBERNET_PROFILED_CLINICAL_CORE_COMPLETED')
        target_contact_performed=[bool](Get-SasObjectPropertyValue $value 'target_contact_performed' $false)
        target_mutation_performed=[bool](Get-SasObjectPropertyValue $value 'target_mutation_performed' (Get-SasObjectPropertyValue $value 'staging_started' $false))
        package_execution_started=[bool](Get-SasObjectPropertyValue $value 'package_execution_started' (Get-SasObjectPropertyValue $value 'scheduled_task_started' $false))
        completed_package_ids=$completed
        evidence_path=$item.path
        next_required_network=$nextNetwork
        next_command=$nextCommand
    })
}

Export-ModuleMember -Function Get-SasOperatorStateRoot,Get-SasOperatorSessionPath,New-SasOperatorSession,Get-SasObjectPropertyValue,Read-SasOperatorSession,Write-SasOperatorSession,Set-SasOperatorSessionValues,Get-SasRepoHead,Get-SasTerminalLabel,Get-SasOperatorNetworkClassification,Set-SasOperatorNextAction,Initialize-SasCybernetCoreSession,Get-SasEvidenceRoots,Find-SasLatestCybernetCoreEvidence,Sync-SasOperatorSessionFromEvidence