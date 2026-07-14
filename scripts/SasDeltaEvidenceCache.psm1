#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-SasDeltaRowValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Row,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    foreach ($name in $Names) {
        $property = $Row.PSObject.Properties | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return ([string]$property.Value).Trim()
        }
    }
    return ''
}

function ConvertTo-SasDeltaBoolean {
    [CmdletBinding()]
    param($Value)

    if ($Value -is [bool]) { return $Value }
    if ($null -eq $Value) { return $false }
    return ([string]$Value).Trim() -match '^(1|true|yes|y|confirmed)$'
}

function ConvertTo-SasDeltaTimestamp {
    [CmdletBinding()]
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $parsed = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse($Value, [ref]$parsed)) { return $parsed }
    return $null
}

function ConvertTo-SasNormalizedSerial {
    [CmdletBinding()]
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return (($Value.Trim().ToUpperInvariant()) -replace '[^A-Z0-9]', '')
}

function ConvertTo-SasNormalizedTarget {
    [CmdletBinding()]
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return $Value.Trim().TrimEnd('.').ToLowerInvariant()
}

function Test-SasDeltaProbeReadyTarget {
    [CmdletBinding()]
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $candidate = $Value.Trim()
    $parsedIp = $null
    if ([System.Net.IPAddress]::TryParse($candidate, [ref]$parsedIp)) { return $true }
    if ($candidate -match '^[A-Za-z0-9][A-Za-z0-9._-]{1,252}$') { return $true }
    return $false
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

function Get-SasDeltaEvidenceTier {
    [CmdletBinding()]
    param($Row)

    $explicit = (Get-SasDeltaRowValue -Row $Row -Names @('EvidenceStrengthTier', 'EvidenceTier', 'Tier')).ToUpperInvariant()
    if ($explicit) { return $explicit }

    $evidenceType = (Get-SasDeltaRowValue -Row $Row -Names @('EvidenceType', 'EvidenceKind', 'SourceType', 'Classification')).ToLowerInvariant()
    $identity = ConvertTo-SasDeltaBoolean (Get-SasDeltaRowValue -Row $Row -Names @('SerialIdentityConfirmed', 'IdentityConfirmed', 'IdentityMatch'))
    $serial = Get-SasDeltaRowValue -Row $Row -Names @('Serial', 'SerialNumber', 'ExpectedSerial', 'DeviceSerial', 'TargetSerial', 'ComputerSerial', 'AssetSerial', 'SN')
    $mac = Get-SasDeltaRowValue -Row $Row -Names @('MacAddress', 'MAC', 'PhysicalAddress')
    $ip = Get-SasDeltaRowValue -Row $Row -Names @('IPAddress', 'IP', 'IPv4', 'ResolvedAddress')
    $ping = (Get-SasDeltaRowValue -Row $Row -Names @('PingStatus', 'ReachabilityStatus', 'Reachability', 'Status', 'Outcome')).ToLowerInvariant()
    $port = (Get-SasDeltaRowValue -Row $Row -Names @('PortStatus', 'ServiceStatus')).ToLowerInvariant()
    $adStatus = (Get-SasDeltaRowValue -Row $Row -Names @('ADCandidateStatus', 'ADStatus', 'DirectoryStatus')).ToLowerInvariant()

    if ($identity -or $evidenceType -match 'identity|wmi|cim|sccm|mdm|vendor') { return 'IDENTITY_CONFIRMED' }
    if ($serial -and $mac -and $ip) { return 'PROBABLE_DEVICE_LOCATION' }
    if ($evidenceType -match 'tracker|workbook|population|manifest') { return 'POPULATION_ONLY' }
    if ($adStatus -match 'exact|registered' -or $evidenceType -match 'ad_exact|registered_ad') { return 'REGISTERED_AD_TARGET' }
    if ($adStatus -match 'candidate|variant' -or $evidenceType -match 'ad_variant|candidate') { return 'AD_VARIANT_REVIEW' }
    if ($evidenceType -match 'dns|subnet' -or $ip) { return 'DNS_OR_SUBNET_ONLY' }
    if ($ping -match 'reachable|success|online|up') { return 'REACHABILITY_ONLY' }
    if ($port -match 'open') { return 'PACKET_SERVICE_ONLY' }
    if ($ping -match 'noping|silent|unreachable|offline|failed|timeout|down') { return 'NEGATIVE_OR_SILENT' }
    if ($evidenceType -match 'fixture|test') { return 'TEST_ONLY' }
    return 'NONE'
}

function ConvertTo-SasRequestedRows {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $rawRows = @()
    if ($extension -eq '.csv') {
        $rawRows = @(Import-Csv -LiteralPath $Path)
    } elseif ($extension -eq '.txt') {
        $rawRows = @(Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
            $value = ([string]$_).Trim()
            if ($value -and -not $value.StartsWith('#')) { [pscustomobject]@{ Target = $value } }
        })
    } else {
        throw "Unsupported requested input extension '$extension'. Use .csv or .txt."
    }

    $results = New-Object System.Collections.Generic.List[object]
    $rowId = 0
    foreach ($row in $rawRows) {
        if ($null -eq $row) { continue }
        $rowId++
        $serial = Get-SasDeltaRowValue -Row $row -Names @('Serial', 'ExpectedSerial', 'Cybernet Serial', 'Cybernet S/N', 'Neuron Serial', 'Neuron S/N', 'SerialNumber', 'DeviceSerial', 'TargetSerial', 'ComputerSerial', 'AssetSerial', 'SN')
        $host = Get-SasDeltaRowValue -Row $row -Names @('HostName', 'Hostname', 'ComputerName', 'ExpectedHostname', 'DeviceName', 'DnsName', 'DNSName', 'FQDN', 'IPAddress', 'IP', 'IPv4')
        if (-not $host) {
            $target = Get-SasDeltaRowValue -Row $row -Names @('Target')
            if ($target -and (Test-SasDeltaProbeReadyTarget -Value $target)) { $host = $target }
        }
        if (-not $host) {
            $identifier = Get-SasDeltaRowValue -Row $row -Names @('Identifier')
            $identifierType = Get-SasDeltaRowValue -Row $row -Names @('IdentifierType', 'TargetType', 'Type', 'ValueType')
            if ($identifier -and $identifierType -match '^(HostName|Hostname|Host|ComputerName|DnsName|DNSName|FQDN|IPv4|IPv6|IPAddress|IP)$') { $host = $identifier }
        }
        $candidateText = Get-SasDeltaRowValue -Row $row -Names @('CandidateHostnames', 'CandidateHosts', 'HostCandidates')
        $candidates = @()
        if ($candidateText) { $candidates = @($candidateText -split '[,;|]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        if ($host) { $candidates = @($host) + $candidates }
        $candidates = @($candidates | Sort-Object -Unique)

        $results.Add([pscustomobject]@{
            InputRowId = $rowId
            Serial = $serial
            NormalizedSerial = ConvertTo-SasNormalizedSerial $serial
            RequestedHostname = $host
            NormalizedRequestedTarget = ConvertTo-SasNormalizedTarget $host
            CandidateHostnames = $candidates
            DeviceType = Get-SasDeltaRowValue -Row $row -Names @('DeviceType', 'Type')
            Site = Get-SasDeltaRowValue -Row $row -Names @('Site', 'Location')
            ExpectedPrefix = Get-SasDeltaRowValue -Row $row -Names @('ExpectedPrefix', 'SitePrefix', 'HostnamePrefix')
            Source = Get-SasDeltaRowValue -Row $row -Names @('Source', 'InputSource')
        })
    }
    return @($results)
}

function ConvertTo-SasEvidenceSnapshots {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$Paths)

    $snapshots = New-Object System.Collections.Generic.List[object]
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $extension = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
        if ($extension -ne '.csv') { continue }
        $rows = @(Import-Csv -LiteralPath $path)
        if ($rows.Count -eq 0) { continue }

        $groups = @{}
        foreach ($row in $rows) {
            $target = Get-SasDeltaRowValue -Row $row -Names @('HostName', 'Hostname', 'ComputerName', 'ExpectedHostname', 'DeviceName', 'DnsName', 'DNSName', 'FQDN', 'Target', 'IPAddress', 'IP', 'IPv4', 'ResolvedAddress')
            $serial = Get-SasDeltaRowValue -Row $row -Names @('Serial', 'SerialNumber', 'ExpectedSerial', 'DeviceSerial', 'TargetSerial', 'ComputerSerial', 'AssetSerial', 'SN')
            $normalizedTarget = ConvertTo-SasNormalizedTarget $target
            $normalizedSerial = ConvertTo-SasNormalizedSerial $serial
            $key = "$normalizedTarget|$normalizedSerial"
            if (-not $groups.ContainsKey($key)) { $groups[$key] = New-Object System.Collections.Generic.List[object] }
            $groups[$key].Add($row)
        }

        foreach ($key in $groups.Keys) {
            $groupRows = @($groups[$key])
            $first = $groupRows[0]
            $target = Get-SasDeltaRowValue -Row $first -Names @('HostName', 'Hostname', 'ComputerName', 'ExpectedHostname', 'DeviceName', 'DnsName', 'DNSName', 'FQDN', 'Target', 'IPAddress', 'IP', 'IPv4', 'ResolvedAddress')
            $serial = Get-SasDeltaRowValue -Row $first -Names @('Serial', 'SerialNumber', 'ExpectedSerial', 'DeviceSerial', 'TargetSerial', 'ComputerSerial', 'AssetSerial', 'SN')
            $timestamps = @($groupRows | ForEach-Object {
                ConvertTo-SasDeltaTimestamp (Get-SasDeltaRowValue -Row $_ -Names @('Timestamp', 'GeneratedAt', 'generated_at', 'probed_at', 'ProbedAt', 'ObservedAt', 'AttemptFinishedAt'))
            } | Where-Object { $null -ne $_ } | Sort-Object -Descending)
            $timestamp = if ($timestamps.Count -gt 0) { $timestamps[0] } else { $null }
            $tiers = @($groupRows | ForEach-Object { Get-SasDeltaEvidenceTier $_ })
            $tier = @($tiers | Sort-Object { Get-SasDeltaTierRank $_ })[0]
            $identityConfirmed = $false
            foreach ($row in $groupRows) {
                if ((Get-SasDeltaEvidenceTier $row) -eq 'IDENTITY_CONFIRMED' -and (ConvertTo-SasNormalizedSerial $serial)) { $identityConfirmed = $true }
                if (ConvertTo-SasDeltaBoolean (Get-SasDeltaRowValue -Row $row -Names @('SerialIdentityConfirmed', 'IdentityConfirmed', 'IdentityMatch'))) { $identityConfirmed = $true }
            }
            $pingValues = @($groupRows | ForEach-Object { (Get-SasDeltaRowValue -Row $_ -Names @('PingStatus', 'ReachabilityStatus', 'Reachability', 'Status', 'Outcome')).ToLowerInvariant() })
            $portRows = @($groupRows | Where-Object { (Get-SasDeltaRowValue -Row $_ -Names @('PortStatus', 'ServiceStatus')).ToLowerInvariant() -eq 'open' })
            $openPorts = @($portRows | ForEach-Object { Get-SasDeltaRowValue -Row $_ -Names @('Port') } | Where-Object { $_ } | Sort-Object {[int]$_} -Unique)
            $reachability = 'unknown'
            if ($pingValues -match 'reachable|success|online|up') { $reachability = 'reachable' }
            elseif ($pingValues -match 'noping|silent|unreachable|offline|failed|timeout|down') { $reachability = 'silent' }
            elseif ($openPorts.Count -gt 0) { $reachability = 'reachable' }
            $resolvedAddress = Get-SasDeltaRowValue -Row $first -Names @('ResolvedAddress', 'IPAddress', 'IP', 'IPv4')
            $adStatus = Get-SasDeltaRowValue -Row $first -Names @('ADCandidateStatus', 'ADStatus', 'DirectoryStatus')
            $trackerStatus = Get-SasDeltaRowValue -Row $first -Names @('TrackerStatus', 'DeploymentStatus', 'BuildStatus')

            $snapshots.Add([pscustomobject]@{
                SourceFile = [System.IO.Path]::GetFullPath($path)
                Target = $target
                NormalizedTarget = ConvertTo-SasNormalizedTarget $target
                Serial = $serial
                NormalizedSerial = ConvertTo-SasNormalizedSerial $serial
                Timestamp = $timestamp
                EvidenceStrengthTier = $tier
                SerialIdentityConfirmed = $identityConfirmed
                ReachabilityStatus = $reachability
                OpenPorts = $openPorts
                ResolvedAddress = $resolvedAddress
                ADCandidateStatus = $adStatus
                TrackerStatus = $trackerStatus
            })
        }
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

Export-ModuleMember -Function Get-SasDeltaRowValue, ConvertTo-SasDeltaBoolean, ConvertTo-SasDeltaTimestamp, ConvertTo-SasNormalizedSerial, ConvertTo-SasNormalizedTarget, Test-SasDeltaProbeReadyTarget, Get-SasDeltaTimeBucket, Get-SasDeltaTierRank, Get-SasDeltaEvidenceTier, ConvertTo-SasRequestedRows, ConvertTo-SasEvidenceSnapshots, Get-SasObservationDelta
