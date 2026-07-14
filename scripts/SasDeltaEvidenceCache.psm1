#Requires -Version 5.1
Set-StrictMode -Version Latest

function Test-SasDeltaProbeReadyTarget {
    [CmdletBinding()]
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $candidate = $Value.Trim()
    $parsedIp = $null
    if ([System.Net.IPAddress]::TryParse($candidate, [ref]$parsedIp)) { return $true }
    return $candidate -match '^[A-Za-z0-9][A-Za-z0-9._-]{1,252}$'
}

function Get-SasDeltaTimeBucket {
    [CmdletBinding()]
    param([datetimeoffset]$Timestamp = [datetimeoffset]::Now)

    if ($Timestamp.DayOfWeek -in @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday)) { return 'weekend' }
    $hour = $Timestamp.Hour
    if ($hour -ge 5 -and $hour -lt 11) { return 'morning' }
    if ($hour -ge 11 -and $hour -lt 14) { return 'midday' }
    if ($hour -ge 14 -and $hour -lt 18) { return 'afternoon' }
    if ($hour -ge 18 -and $hour -lt 23) { return 'evening' }
    return 'overnight'
}

function Get-SasDeltaTierRank {
    [CmdletBinding()]
    param([string]$Tier)

    $rank = @{
        IDENTITY_CONFIRMED        = 1
        PROBABLE_DEVICE_LOCATION  = 2
        POPULATION_ONLY           = 3
        REGISTERED_AD_TARGET      = 4
        AD_VARIANT_REVIEW         = 5
        DNS_OR_SUBNET_ONLY        = 6
        REACHABILITY_ONLY         = 7
        PACKET_SERVICE_ONLY       = 8
        NEGATIVE_OR_SILENT        = 9
        TEST_ONLY                 = 10
        NONE                      = 99
    }
    if ($rank.ContainsKey($Tier)) { return [int]$rank[$Tier] }
    return 99
}

function ConvertFrom-SasRequestedArtifactPackage {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Package)

    if ($Package.artifact_role -ne 'requested_population') {
        throw "Expected requested_population package; found '$($Package.artifact_role)'."
    }
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($row in @($Package.rows)) {
        $candidates = New-Object System.Collections.Generic.List[string]
        foreach ($candidate in @($row.candidate_targets)) {
            $clean = ([string]$candidate).Trim()
            if ($clean -and -not $candidates.Contains($clean)) { $candidates.Add($clean) }
        }
        if ($row.target -and -not $candidates.Contains([string]$row.target)) { $candidates.Insert(0, [string]$row.target) }
        $results.Add([pscustomobject]@{
            InputRowId = [string]$row.row_id
            Serial = [string]$row.serial
            NormalizedSerial = [string]$row.normalized_serial
            RequestedHostname = [string]$row.target
            NormalizedRequestedTarget = [string]$row.normalized_target
            CandidateHostnames = @($candidates)
            DeviceType = [string]$row.device_type
            Site = [string]$row.site
            ExpectedPrefix = [string]$row.expected_prefix
            Source = [string]$Package.source_path
            SourceAdapter = [string]$Package.adapter_id
        })
    }
    return @($results)
}

function ConvertFrom-SasEvidenceArtifactPackages {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object[]]$Packages)

    $groups = @{}
    foreach ($package in @($Packages)) {
        if ($package.artifact_role -ne 'evidence_snapshot') {
            throw "Expected evidence_snapshot package; found '$($package.artifact_role)'."
        }
        foreach ($row in @($package.rows)) {
            $observedKey = if ($row.observed_at) { [string]$row.observed_at } else { 'undated' }
            $key = '{0}|{1}|{2}|{3}' -f $row.source_file, $row.normalized_target, $row.normalized_serial, $observedKey
            if (-not $groups.ContainsKey($key)) { $groups[$key] = New-Object System.Collections.Generic.List[object] }
            $groups[$key].Add($row)
        }
    }

    $snapshots = New-Object System.Collections.Generic.List[object]
    foreach ($key in $groups.Keys) {
        $rows = @($groups[$key])
        $first = $rows[0]
        $tiers = @($rows | ForEach-Object { [string]$_.evidence_strength_tier } | Sort-Object { Get-SasDeltaTierRank $_ })
        $identityConfirmed = @($rows | Where-Object { $_.serial_identity_confirmed }).Count -gt 0
        $reachabilityValues = @($rows | ForEach-Object { [string]$_.reachability_status })
        $reachability = 'unknown'
        if ($reachabilityValues -contains 'reachable') { $reachability = 'reachable' }
        elseif ($reachabilityValues -contains 'silent') { $reachability = 'silent' }
        $openPorts = @($rows | ForEach-Object { @($_.open_ports) } | ForEach-Object { [int]$_ } | Sort-Object -Unique)
        $timestamp = ConvertTo-SasSurveyTimestamp -Value $first.observed_at
        $snapshots.Add([pscustomobject]@{
            SourceFile = [string]$first.source_file
            SourceAdapter = [string]$first.source_adapter
            Target = [string]$first.target
            NormalizedTarget = [string]$first.normalized_target
            Serial = [string]$first.serial
            NormalizedSerial = [string]$first.normalized_serial
            Timestamp = $timestamp
            EvidenceStrengthTier = if ($tiers.Count -gt 0) { $tiers[0] } else { 'NONE' }
            SerialIdentityConfirmed = $identityConfirmed
            ReachabilityStatus = $reachability
            OpenPorts = $openPorts
            ResolvedAddress = [string]$first.resolved_address
            MacAddress = [string]$first.mac_address
            ADCandidateStatus = [string]$first.ad_candidate_status
            TrackerStatus = [string]$first.tracker_status
            EvidenceType = [string]$first.evidence_type
        })
    }
    return @($snapshots)
}

function Get-SasObservationDelta {
    [CmdletBinding()]
    param([object[]]$Snapshots)

    $ordered = @($Snapshots | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending)
    if ($ordered.Count -eq 0) {
        return [pscustomobject]@{ Previous = $null; Latest = $null; Delta = 'NO_TIMESTAMPED_OBSERVATION' }
    }
    $latest = $ordered[0]
    if ($ordered.Count -eq 1) {
        return [pscustomobject]@{ Previous = $null; Latest = $latest; Delta = 'FIRST_OBSERVATION' }
    }
    $previous = $ordered[1]
    $delta = 'UNCHANGED_UNKNOWN'
    if ($previous.ReachabilityStatus -ne $latest.ReachabilityStatus) {
        if ($latest.ReachabilityStatus -eq 'reachable') { $delta = 'BECAME_REACHABLE' }
        elseif ($latest.ReachabilityStatus -eq 'silent') { $delta = 'BECAME_SILENT' }
        else { $delta = 'REACHABILITY_CHANGED' }
    } elseif (($previous.OpenPorts -join ',') -ne ($latest.OpenPorts -join ',')) {
        $delta = 'SERVICE_PORTS_CHANGED'
    } elseif ($latest.ReachabilityStatus -eq 'reachable') {
        $delta = 'UNCHANGED_REACHABLE'
    } elseif ($latest.ReachabilityStatus -eq 'silent') {
        $delta = 'UNCHANGED_SILENT'
    }
    return [pscustomobject]@{ Previous = $previous; Latest = $latest; Delta = $delta }
}

Export-ModuleMember -Function Test-SasDeltaProbeReadyTarget, Get-SasDeltaTimeBucket, Get-SasDeltaTierRank, ConvertFrom-SasRequestedArtifactPackage, ConvertFrom-SasEvidenceArtifactPackages, Get-SasObservationDelta
