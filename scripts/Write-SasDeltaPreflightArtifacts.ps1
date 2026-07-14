# Internal artifact writer for survey/sas-delta-preflight-plan.ps1. Dot-source only.

function Export-SasDeltaCsv {
    param(
        [Parameter(Mandatory = $true)][object[]]$Rows,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Template
    )
    if ($Rows.Count -gt 0) {
        $Rows | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
        return
    }
    $header = @($Template | ConvertTo-Csv -NoTypeInformation)[0]
    Set-Content -LiteralPath $Path -Value $header -Encoding UTF8
}

$planRows | Export-Csv -LiteralPath $planPath -NoTypeInformation -Encoding UTF8
Export-SasDeltaCsv -Rows @($planRows | Where-Object { $_.Decision -like 'SKIP_*' }) -Path $skipPath -Template $planRows[0]
Export-SasDeltaCsv -Rows @($planRows | Where-Object { $_.ReviewRequired }) -Path $reviewPath -Template $planRows[0]
$observationRows | Export-Csv -LiteralPath $observationPath -NoTypeInformation -Encoding UTF8
Set-Content -LiteralPath $targetPath -Value @($targetSet | Sort-Object) -Encoding UTF8

$probeCount = @($planRows | Where-Object { $_.Decision -like 'PROBE_REQUIRED_*' }).Count
$summary = [ordered]@{
    workflow_id = 'delta-preflight'
    run_id = $RunId
    generated_at = $ReferenceTime.ToString('o')
    local_time_of_day_bucket = Get-SasDeltaTimeBucket -Timestamp $ReferenceTime
    input_source = $resolvedInput
    input_rows = $requestedRows.Count
    total_serials = @($requestedRows | Where-Object { $_.Serial } | Select-Object -ExpandProperty NormalizedSerial -Unique).Count
    probe_required_count = $probeCount
    skipped_recent_reachable_count = @($planRows | Where-Object { $_.Decision -eq 'SKIP_RECENT_REACHABLE' }).Count
    skipped_identity_confirmed_count = @($planRows | Where-Object { $_.Decision -eq 'SKIP_RECENT_IDENTITY_CONFIRMED' }).Count
    skipped_recently_silent_count = @($planRows | Where-Object { $_.Decision -eq 'SKIP_RECENTLY_SILENT_WITHIN_COOLDOWN' }).Count
    review_required_count = @($planRows | Where-Object { $_.ReviewRequired }).Count
    blocked_count = @($planRows | Where-Object { $_.Decision -eq 'BLOCKED_NO_PROBE_READY_HOST' }).Count
    stale_evidence_count = @($planRows | Where-Object { $_.Decision -eq 'PROBE_REQUIRED_STALE_EVIDENCE' }).Count
    conflicting_evidence_count = @($planRows | Where-Object { $_.Decision -eq 'PROBE_REQUIRED_CONFLICTING_EVIDENCE' }).Count
    became_reachable_count = @($observationRows | Where-Object { $_.ObservationDelta -eq 'BECAME_REACHABLE' }).Count
    became_silent_count = @($observationRows | Where-Object { $_.ObservationDelta -eq 'BECAME_SILENT' }).Count
    unchanged_reachable_count = @($observationRows | Where-Object { $_.ObservationDelta -eq 'UNCHANGED_REACHABLE' }).Count
    unchanged_silent_count = @($observationRows | Where-Object { $_.ObservationDelta -eq 'UNCHANGED_SILENT' }).Count
    to_probe_targets_path = $targetPath
    summary_path = $summaryPath
    plan_path = $planPath
    review_required_path = $reviewPath
    skipped_recent_evidence_path = $skipPath
    observation_delta_path = $observationPath
    operator_handoff_path = $handoffPath
    evidence_files_loaded = @($resolvedEvidence)
    reachability_ttl_hours = $ReachabilityTtlHours
    identity_ttl_days = $IdentityTtlDays
    force_reprobe = [bool]$ForceReprobe
    force_reason = if ($ForceReprobe) { $ForceReason } else { '' }
    network_activity_performed = $false
    target_mutation_performed = $false
    next_command = if ($targetSet.Count -gt 0) { ".\survey\sas-network-preflight.ps1 -TargetFile `"$targetPath`" -Ports 135,445,3389,9100" } else { '' }
}
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

@(
    'SysAdminSuite delta preflight evidence cache',
    "RunId: $RunId",
    "Requested rows: $($requestedRows.Count)",
    "Evidence files loaded: $($resolvedEvidence.Count)",
    "Probe-required targets: $($targetSet.Count)",
    "Review-required rows: $($summary.review_required_count)",
    "Became reachable: $($summary.became_reachable_count)",
    "Became silent: $($summary.became_silent_count)",
    '',
    "Plan: $planPath",
    "Observation delta: $observationPath",
    "Review queue: $reviewPath",
    "Staged targets: $targetPath",
    '',
    'The planner performed no network activity and no target mutation.',
    'Run the double-click launcher for the next survey action; technicians should not compose PowerShell commands from these paths.',
    'Dynamic path rewriting or continuation-state path rehydration after copying/moving an in-progress run is unsupported. Reselect the approved source if saved state no longer resolves.'
) | Set-Content -LiteralPath $handoffPath -Encoding UTF8

@(
    'This directory contains local delta-planning evidence.',
    'delta_preflight_plan.csv: one decision per requested row.',
    'survey_observation_delta.csv: latest-versus-previous network observation changes.',
    'skipped_recent_evidence.csv: rows skipped because useful evidence is fresh.',
    'review_required.csv: ambiguity, serial-only, or unknown-freshness rows.',
    'delta_summary.json: machine-readable counts and paths.',
    'operator_handoff.txt: technician-facing interpretation.',
    '',
    'The runnable target handoff is staged separately under survey/input/delta_preflight/<run_id>/to_probe_targets.txt.',
    'No packets are sent by this planner.'
) | Set-Content -LiteralPath $readmePath -Encoding UTF8

Write-Host "Delta run: $RunId"
Write-Host "Plan: $planPath"
Write-Host "Observation delta: $observationPath"
Write-Host "Probe-required targets: $($targetSet.Count)"
Write-Host "Review-required rows: $($summary.review_required_count)"
Write-Host "Staged target file: $targetPath"
Write-Output ([pscustomobject]$summary)
