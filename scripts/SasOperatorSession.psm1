Set-StrictMode -Version 2.0

function Get-SasOperatorStateRoot {
    $root = Join-Path $env:LOCALAPPDATA 'SysAdminSuite'
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    return $root
}

function Get-SasOperatorSessionPath {
    return (Join-Path (Get-SasOperatorStateRoot) 'operator-session.json')
}

function New-SasOperatorSession {
    [pscustomobject][ordered]@{
        schema_version = 'sas-operator-session/v1'
        updated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        repo_root = $null
        repo_head = $null
        launcher_head = $null
        current_network_classification = 'UNKNOWN'
        current_network_label = $null
        current_terminal = $null
        target_input = $null
        target_fqdn = $null
        equipment_profile = $null
        deployment_lane = $null
        package_set = $null
        expected_autologon_state = $null
        expected_autologon_enabled = $null
        imprivata_disposition = 'observational/external'
        latest_run_id = $null
        latest_status = $null
        latest_phase = $null
        latest_checkpoint = $null
        cleanup_status = 'UNKNOWN'
        cleanup_outstanding = $false
        target_contact_performed = $false
        target_mutation_performed = $false
        package_execution_started = $false
        completed_package_ids = @()
        next_required_network = $null
        next_command = $null
        evidence_path = $null
    }
}

function Read-SasOperatorSession {
    $path = Get-SasOperatorSessionPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-SasOperatorSession) }
    try {
        $value = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$value.schema_version -ne 'sas-operator-session/v1') { return (New-SasOperatorSession) }
        return $value
    }
    catch { return (New-SasOperatorSession) }
}

function Write-SasOperatorSession {
    param([Parameter(Mandatory = $true)]$Session)
    $path = Get-SasOperatorSessionPath
    $Session.updated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    $temp = "$path.tmp"
    $Session | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $path -Force
    return $path
}

function Set-SasOperatorSessionValues {
    param([Parameter(Mandatory = $true)][hashtable]$Values)
    $session = Read-SasOperatorSession
    foreach ($name in $Values.Keys) {
        $property = $session.PSObject.Properties[$name]
        if ($property) { $property.Value = $Values[$name] }
        else { $session | Add-Member -NotePropertyName $name -NotePropertyValue $Values[$name] }
    }
    [void](Write-SasOperatorSession -Session $session)
    return $session
}

function Get-SasRepoHead {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)
    try {
        $value = (& git -C $RepoRoot rev-parse HEAD 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and $value) { return ([string]$value).Trim() }
    } catch {}
    return $null
}

function Get-SasTerminalLabel {
    if ($env:PSModulePath -and $Host.Name) { return "PowerShell:$($Host.Name)" }
    return 'unknown-shell'
}

function Get-SasOperatorNetworkClassification {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)
    $module = Join-Path $RepoRoot 'scripts\SasNetworkGuard.psm1'
    if (-not (Test-Path -LiteralPath $module -PathType Leaf)) {
        return [pscustomobject]@{ classification='INCONCLUSIVE'; label='unknown'; protected=$false }
    }
    Import-Module $module -Force
    $label = Get-SasCurrentWifiSsid
    $protected = Test-SasNorthwellWifiSsid -Ssid $label
    if (-not $protected) {
        try { $protected = Test-SasNorthwellWiredEvidence -NetworkText (Get-SasLocalNetworkText) } catch { $protected = $false }
    }
    $classification = if ($protected) { 'PROTECTED_NORTHWELL' } elseif ($label -and $label -ne 'unknown') { 'GUEST_INTERNET' } else { 'INCONCLUSIVE' }
    return [pscustomobject][ordered]@{ classification=$classification; label=$label; protected=[bool]$protected }
}

function Set-SasOperatorNextAction {
    param(
        [Parameter(Mandatory = $true)][string]$Network,
        [Parameter(Mandatory = $true)][string]$Command
    )
    return (Set-SasOperatorSessionValues -Values @{ next_required_network=$Network; next_command=$Command })
}

function Initialize-SasCybernetCoreSession {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$TargetInput,
        [Parameter(Mandatory = $true)][string]$TargetFqdn
    )
    $head = Get-SasRepoHead -RepoRoot $RepoRoot
    return (Set-SasOperatorSessionValues -Values @{
        repo_root=$RepoRoot
        repo_head=$head
        launcher_head=$head
        current_terminal=(Get-SasTerminalLabel)
        target_input=$TargetInput
        target_fqdn=$TargetFqdn
        equipment_profile='Cybernet'
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
    param([Parameter(Mandatory = $true)][string]$RepoRoot)
    $roots = New-Object 'System.Collections.Generic.List[string]'
    foreach ($candidate in @($RepoRoot,$env:SAS_REPO_ROOT)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Container) -and -not $roots.Contains($candidate)) { [void]$roots.Add($candidate) }
    }
    $stateRoot = Get-SasOperatorStateRoot
    $cache = Join-Path $stateRoot 'repo-root.txt'
    if (Test-Path -LiteralPath $cache -PathType Leaf) {
        try {
            $candidate = (Get-Content -LiteralPath $cache -Raw).Trim()
            if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Container) -and -not $roots.Contains($candidate)) { [void]$roots.Add($candidate) }
        } catch {}
    }
    foreach ($candidate in @(Get-ChildItem -LiteralPath $stateRoot -Directory -Filter 'field-ready*' -ErrorAction SilentlyContinue)) {
        if (-not $roots.Contains($candidate.FullName)) { [void]$roots.Add($candidate.FullName) }
    }
    return @($roots)
}

function Find-SasLatestCybernetCoreEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [AllowNull()][string]$TargetFqdn,
        [AllowNull()][string]$ExcludeRunId
    )
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($root in @(Get-SasEvidenceRoots -RepoRoot $RepoRoot)) {
        $runRoot = Join-Path $root 'survey\output\runs\cybernet-profiled-clinical-core'
        if (-not (Test-Path -LiteralPath $runRoot -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $runRoot -Filter 'cybernet_profiled_clinical_core_result.json' -File -Recurse -ErrorAction SilentlyContinue)) {
            try {
                $value = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($ExcludeRunId -and [string]$value.run_id -eq $ExcludeRunId) { continue }
                if ($TargetFqdn -and $value.target_fqdn -and -not ([string]$value.target_fqdn).Equals($TargetFqdn,[StringComparison]::OrdinalIgnoreCase)) { continue }
                $items.Add([pscustomobject]@{ path=$file.FullName; last_write_utc=$file.LastWriteTimeUtc; value=$value })
            } catch {}
        }
    }
    return @($items | Sort-Object last_write_utc -Descending | Select-Object -First 1)
}

function Sync-SasOperatorSessionFromEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [AllowNull()][string]$TargetFqdn
    )
    $found = @(Find-SasLatestCybernetCoreEvidence -RepoRoot $RepoRoot -TargetFqdn $TargetFqdn)
    if ($found.Count -eq 0) { return (Read-SasOperatorSession) }
    $item = $found[0]
    $value = $item.value
    $completed = @()
    foreach ($row in @($value.package_results)) {
        if ($row -and [bool]$row.success -and $row.id) { $completed += [string]$row.id }
    }
    if ($value.completed_package_ids) { $completed += @($value.completed_package_ids | ForEach-Object { [string]$_ }) }
    $completed = @($completed | Sort-Object -Unique)
    $cleanupSucceeded = ($value.PSObject.Properties['cleanup_succeeded'] -and [bool]$value.cleanup_succeeded)
    $status = [string]$value.status
    $nextNetwork = 'PROTECTED NORTHWELL'
    $targetInput = if ($value.target_input) { [string]$value.target_input } else { [string](Read-SasOperatorSession).target_input }
    $nextCommand = if ($status -eq 'CYBERNET_PROFILED_CLINICAL_CORE_COMPLETED') { 'sas evidence Cybernet' } elseif (-not $cleanupSucceeded) { "sas cybernet Recover $targetInput" } else { "sas cybernet Core $targetInput" }
    return (Set-SasOperatorSessionValues -Values @{
        latest_run_id=[string]$value.run_id
        latest_status=$status
        latest_phase=[string]$value.phase
        latest_checkpoint=[string]$value.checkpoint
        cleanup_status=$(if ($cleanupSucceeded) { 'VERIFIED' } else { 'OUTSTANDING_OR_UNPROVEN' })
        cleanup_outstanding=(-not $cleanupSucceeded -and $status -ne 'CYBERNET_PROFILED_CLINICAL_CORE_COMPLETED')
        target_contact_performed=[bool]$value.target_contact_performed
        target_mutation_performed=[bool]$value.target_mutation_performed
        package_execution_started=[bool]$value.package_execution_started
        completed_package_ids=$completed
        evidence_path=$item.path
        next_required_network=$nextNetwork
        next_command=$nextCommand
    })
}

Export-ModuleMember -Function Get-SasOperatorStateRoot,Get-SasOperatorSessionPath,Read-SasOperatorSession,Write-SasOperatorSession,Set-SasOperatorSessionValues,Get-SasRepoHead,Get-SasOperatorNetworkClassification,Set-SasOperatorNextAction,Initialize-SasCybernetCoreSession,Get-SasEvidenceRoots,Find-SasLatestCybernetCoreEvidence,Sync-SasOperatorSessionFromEvidence