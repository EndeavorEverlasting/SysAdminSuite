# Internal core for survey/sas-delta-preflight-plan.ps1. Dot-source only.
$planRows = New-Object System.Collections.Generic.List[object]
$observationRows = New-Object System.Collections.Generic.List[object]
$targetSet = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

foreach ($requested in $requestedRows) {
    $matches = @($evidenceSnapshots | Where-Object {
        ($requested.NormalizedSerial -and $_.NormalizedSerial -eq $requested.NormalizedSerial) -or
        ($requested.NormalizedRequestedTarget -and $_.NormalizedTarget -eq $requested.NormalizedRequestedTarget) -or
        ($_.NormalizedTarget -and $requested.CandidateHostnames -contains $_.Target)
    })

    $candidateHostnames = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @($requested.CandidateHostnames)) {
        if ($candidate -and -not $candidateHostnames.Contains($candidate)) { $candidateHostnames.Add($candidate) }
    }
    foreach ($match in $matches) {
        if ($match.Target -and -not $candidateHostnames.Contains($match.Target)) { $candidateHostnames.Add($match.Target) }
    }

    $identityMatches = @($matches | Where-Object {
        $_.SerialIdentityConfirmed -and $requested.NormalizedSerial -and $_.NormalizedSerial -eq $requested.NormalizedSerial
    } | Sort-Object Timestamp -Descending)
    $identityConfirmed = $identityMatches.Count -gt 0

    $resolvedHostname = $requested.RequestedHostname
    if (-not $resolvedHostname -and $identityMatches.Count -gt 0) { $resolvedHostname = $identityMatches[0].Target }
    if (-not $resolvedHostname -and $candidateHostnames.Count -eq 1) { $resolvedHostname = $candidateHostnames[0] }
    $probeTarget = if (Test-SasDeltaProbeReadyTarget -Value $resolvedHostname) { $resolvedHostname } else { '' }

    $rankedMatches = @($matches | Sort-Object @{ Expression = { Get-SasDeltaTierRank $_.EvidenceStrengthTier }; Ascending = $true }, @{ Expression = { $_.Timestamp }; Descending = $true })
    $strongest = if ($rankedMatches.Count -gt 0) { $rankedMatches[0] } else { $null }
    $tier = if ($strongest) { $strongest.EvidenceStrengthTier } elseif ($requested.Serial) { 'POPULATION_ONLY' } else { 'NONE' }
    $strongestPath = if ($strongest) { $strongest.SourceFile } else { $resolvedInput }

    $targetMatches = @($matches | Where-Object { $probeTarget -and $_.NormalizedTarget -eq (ConvertTo-SasSurveyNormalizedTarget -Value $probeTarget) })
    $observation = Get-SasObservationDelta -Snapshots $targetMatches
    $latest = $observation.Latest
    $previous = $observation.Previous

    $recentIdentity = $false
    if ($identityMatches.Count -gt 0 -and $identityMatches[0].Timestamp) {
        $recentIdentity = (($ReferenceTime - $identityMatches[0].Timestamp).TotalDays -le $IdentityTtlDays)
    }
    $recentReachable = $false
    $recentSilent = $false
    if ($latest -and $latest.Timestamp) {
        $latestAgeHours = ($ReferenceTime - $latest.Timestamp).TotalHours
        if ($latestAgeHours -ge 0 -and $latestAgeHours -le $ReachabilityTtlHours) {
            if ($latest.ReachabilityStatus -eq 'reachable') { $recentReachable = $true }
            if ($latest.ReachabilityStatus -eq 'silent') { $recentSilent = $true }
        }
    }

    $distinctIdentityTargets = @($identityMatches | ForEach-Object { $_.NormalizedTarget } | Where-Object { $_ } | Sort-Object -Unique)
    $conflictingIdentity = $distinctIdentityTargets.Count -gt 1
    $mismatchedSerialForTarget = @($targetMatches | Where-Object {
        $_.NormalizedSerial -and $requested.NormalizedSerial -and $_.NormalizedSerial -ne $requested.NormalizedSerial
    }).Count -gt 0
    $multipleHostnames = $candidateHostnames.Count -gt 1 -and -not $identityConfirmed
    $adVariantOnly = $rankedMatches.Count -gt 0 -and $rankedMatches[0].EvidenceStrengthTier -eq 'AD_VARIANT_REVIEW'
    $prefixMismatch = $false
    if ($requested.ExpectedPrefix -and $resolvedHostname) {
        $prefixMismatch = -not $resolvedHostname.StartsWith($requested.ExpectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)
    }
    $hasUnknownTimestampEvidence = $matches.Count -gt 0 -and @($matches | Where-Object { $null -eq $_.Timestamp }).Count -gt 0 -and @($matches | Where-Object { $null -ne $_.Timestamp }).Count -eq 0

    $decision = ''
    $reason = ''
    $probeWorthiness = ''
    $nextHandoff = ''
    $reviewRequired = $false

    if (-not $probeTarget) {
        if ($requested.Serial) {
            $decision = 'REVIEW_REQUIRED_SERIAL_ONLY'
            $reason = 'The row is anchored by serial but has no single probe-ready hostname or IP bridge.'
            $probeWorthiness = 'review_required'
            $nextHandoff = 'spreadsheet_gap_review'
            $reviewRequired = $true
        } else {
            $decision = 'BLOCKED_NO_PROBE_READY_HOST'
            $reason = 'The row has no probe-ready hostname, IP, or serial-to-target bridge.'
            $probeWorthiness = 'blocked_no_probe_ready_target'
            $nextHandoff = 'spreadsheet_gap_review'
            $reviewRequired = $true
        }
    } elseif ($multipleHostnames -or $conflictingIdentity) {
        $decision = 'REVIEW_REQUIRED_MULTIPLE_HOSTNAMES'
        $reason = 'Multiple target candidates remain and no single approved identity observation resolves the ambiguity.'
        $probeWorthiness = 'review_required'
        $nextHandoff = 'identity_reconciliation'
        $reviewRequired = $true
    } elseif ($prefixMismatch) {
        $decision = 'REVIEW_REQUIRED_PREFIX_SITE_MISMATCH'
        $reason = "Resolved target '$resolvedHostname' does not match expected prefix '$($requested.ExpectedPrefix)'."
        $probeWorthiness = 'review_required'
        $nextHandoff = 'subnet_location_review'
        $reviewRequired = $true
    } elseif ($adVariantOnly) {
        $decision = 'REVIEW_REQUIRED_AD_VARIANT_ONLY'
        $reason = 'The strongest evidence is an AD naming candidate, which is review evidence rather than identity proof.'
        $probeWorthiness = 'review_required'
        $nextHandoff = 'ad_candidate_review'
        $reviewRequired = $true
    } elseif ($mismatchedSerialForTarget) {
        $decision = 'PROBE_REQUIRED_CONFLICTING_EVIDENCE'
        $reason = 'The selected target is associated with a different serial in prior evidence; a bounded recheck and reconciliation are required.'
        $probeWorthiness = 'probe_stale_or_missing'
        $nextHandoff = 'identity_reconciliation'
    } elseif ($ForceReprobe) {
        $decision = 'PROBE_REQUIRED_OPERATOR_FORCED'
        $reason = "Operator requested a time-diverse repeat: $ForceReason"
        $probeWorthiness = 'operator_forced'
        $nextHandoff = 'delta_network_preflight'
    } elseif ($recentIdentity) {
        $decision = 'SKIP_RECENT_IDENTITY_CONFIRMED'
        $reason = 'Approved identity evidence matching the requested serial is still within the identity freshness window.'
        $probeWorthiness = 'skip_identity_confirmed'
        $nextHandoff = 'identity_reconciliation'
    } elseif ($recentReachable) {
        $decision = 'SKIP_RECENT_REACHABLE'
        $reason = 'Recent reachability evidence is still within the configured TTL; another immediate probe would add little information.'
        $probeWorthiness = 'skip_recent_reachability'
        $nextHandoff = 'delta_network_preflight'
    } elseif ($recentSilent) {
        $decision = 'SKIP_RECENTLY_SILENT_WITHIN_COOLDOWN'
        $reason = 'The target was recently silent; wait for a different time bucket before retrying unless an operator explicitly forces a repeat.'
        $probeWorthiness = 'skip_recent_reachability'
        $nextHandoff = 'delta_network_preflight'
    } elseif ($hasUnknownTimestampEvidence) {
        $decision = 'REVIEW_REQUIRED_EVIDENCE_TIMESTAMP_UNKNOWN'
        $reason = 'Evidence exists but has no usable timestamp, so freshness cannot be established safely.'
        $probeWorthiness = 'review_required'
        $nextHandoff = 'identity_reconciliation'
        $reviewRequired = $true
    } elseif ($matches.Count -eq 0) {
        $decision = 'PROBE_REQUIRED_NO_EVIDENCE'
        $reason = 'No prior local evidence matches this serial or target.'
        $probeWorthiness = 'probe_stale_or_missing'
        $nextHandoff = 'delta_network_preflight'
    } else {
        $decision = 'PROBE_REQUIRED_STALE_EVIDENCE'
        $reason = 'Prior evidence exists but is outside the applicable freshness window.'
        $probeWorthiness = 'probe_stale_or_missing'
        $nextHandoff = 'delta_network_preflight'
    }

    if ($decision -like 'PROBE_REQUIRED_*' -and $probeTarget) { [void]$targetSet.Add($probeTarget) }

    $lastReachabilityStatus = if ($latest) { $latest.ReachabilityStatus } else { '' }
    $lastReachabilityTimestamp = if ($latest -and $latest.Timestamp) { $latest.Timestamp.ToString('o') } else { '' }
    $lastReachabilitySource = if ($latest) { $latest.SourceFile } else { '' }
    $lastIdentityStatus = if ($identityConfirmed) { 'confirmed' } else { 'not_confirmed' }
    $lastIdentityTimestamp = if ($identityMatches.Count -gt 0 -and $identityMatches[0].Timestamp) { $identityMatches[0].Timestamp.ToString('o') } else { '' }
    $lastIdentitySource = if ($identityMatches.Count -gt 0) { $identityMatches[0].SourceFile } else { '' }
    $adStatus = if ($rankedMatches.Count -gt 0) { $rankedMatches[0].ADCandidateStatus } else { '' }
    $trackerStatus = if ($rankedMatches.Count -gt 0) { $rankedMatches[0].TrackerStatus } else { '' }
    $sourceFiles = @($matches | ForEach-Object { $_.SourceFile } | Sort-Object -Unique)
    $sourceAdapters = @($matches | ForEach-Object { $_.SourceAdapter } | Where-Object { $_ } | Sort-Object -Unique)

    $planRows.Add([pscustomobject][ordered]@{
        InputRowId = $requested.InputRowId
        InputSource = $resolvedInput
        InputAdapter = $requested.SourceAdapter
        Serial = $requested.Serial
        RequestedHostname = $requested.RequestedHostname
        ResolvedHostname = $resolvedHostname
        CandidateHostnames = ($candidateHostnames -join ';')
        ProbeTarget = $probeTarget
        EvidenceStrengthTier = $tier
        StrongestEvidencePath = $strongestPath
        SerialIdentityConfirmed = $identityConfirmed
        ProbeWorthiness = $probeWorthiness
        PreferredNextHandoff = $nextHandoff
        LastReachabilityStatus = $lastReachabilityStatus
        LastReachabilityTimestamp = $lastReachabilityTimestamp
        LastReachabilitySource = $lastReachabilitySource
        LastIdentityStatus = $lastIdentityStatus
        LastIdentityTimestamp = $lastIdentityTimestamp
        LastIdentitySource = $lastIdentitySource
        ADCandidateStatus = $adStatus
        ADCandidateSource = if ($adStatus -and $strongest) { $strongest.SourceFile } else { '' }
        TrackerStatus = $trackerStatus
        EvidenceAdapters = ($sourceAdapters -join ';')
        PreviousReachabilityStatus = if ($previous) { $previous.ReachabilityStatus } else { '' }
        PreviousReachabilityTimestamp = if ($previous -and $previous.Timestamp) { $previous.Timestamp.ToString('o') } else { '' }
        ObservationDelta = $observation.Delta
        Decision = $decision
        DecisionReason = $reason
        ReviewRequired = $reviewRequired
        EvidenceSourceFiles = ($sourceFiles -join ';')
    })

    $observationRows.Add([pscustomobject][ordered]@{
        InputRowId = $requested.InputRowId
        Serial = $requested.Serial
        Target = $probeTarget
        PreviousStatus = if ($previous) { $previous.ReachabilityStatus } else { '' }
        PreviousTimestamp = if ($previous -and $previous.Timestamp) { $previous.Timestamp.ToString('o') } else { '' }
        PreviousOpenPorts = if ($previous) { $previous.OpenPorts -join ',' } else { '' }
        LatestStatus = if ($latest) { $latest.ReachabilityStatus } else { '' }
        LatestTimestamp = if ($latest -and $latest.Timestamp) { $latest.Timestamp.ToString('o') } else { '' }
        LatestOpenPorts = if ($latest) { $latest.OpenPorts -join ',' } else { '' }
        ObservationDelta = $observation.Delta
        PreviousSource = if ($previous) { $previous.SourceFile } else { '' }
        LatestSource = if ($latest) { $latest.SourceFile } else { '' }
    })
}
