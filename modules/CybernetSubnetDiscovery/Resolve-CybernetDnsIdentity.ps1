#Requires -Version 5.1
Set-StrictMode -Version Latest

function ConvertFrom-DnsResolutionResult {
    param(
        [string]$QueryName,
        [object[]]$DnsResults,
        [string]$Source = 'DNS'
    )

    $records = New-Object System.Collections.Generic.List[object]
    foreach ($result in @($DnsResults)) {
        if ($null -eq $result) { continue }

        $recordType = ''
        if ($result.PSObject.Properties['Type']) {
            $recordType = [string]$result.Type
        }

        $ip = ''
        if ($result.PSObject.Properties['IPAddress']) {
            $ip = [string]$result.IPAddress
        }

        if ([string]::IsNullOrWhiteSpace($ip) -and $recordType -eq 'A' -and $result.PSObject.Properties['NameHost']) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($ip)) {
            $records.Add([pscustomobject]@{
                Hostname   = $QueryName
                IP         = $ip
                RecordType = if ($recordType) { $recordType } else { 'A' }
                Source     = $Source
            }) | Out-Null
        }
    }

    return $records.ToArray()
}

function Resolve-CybernetDnsForward {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hostname,

        [string]$DnsSuffix,
        [scriptblock]$DnsResolver
    )

    if ([string]::IsNullOrWhiteSpace($Hostname)) {
        return @()
    }

    if (-not $DnsResolver) {
        $DnsResolver = {
            param($Name)
            Resolve-DnsName -Name $Name -Type A -ErrorAction Stop
        }
    }

    $namesToTry = New-Object System.Collections.Generic.List[string]
    $namesToTry.Add($Hostname) | Out-Null
    if ($DnsSuffix -and $Hostname -notmatch '\.') {
        $namesToTry.Add("$Hostname.$DnsSuffix") | Out-Null
    }

    $allRecords = New-Object System.Collections.Generic.List[object]
    foreach ($name in $namesToTry) {
        try {
            $results = & $DnsResolver $name
            $parsed = @(ConvertFrom-DnsResolutionResult -QueryName $name -DnsResults @($results) -Source 'DNS-Forward')
            foreach ($record in $parsed) {
                $allRecords.Add($record) | Out-Null
            }
            if (@($parsed).Count -gt 0) { break }
        } catch {
            continue
        }
    }

    return $allRecords.ToArray()
}

function Resolve-CybernetDnsReverse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$IPv4,

        [scriptblock]$DnsResolver
    )

    if ([string]::IsNullOrWhiteSpace($IPv4)) {
        return @()
    }

    if (-not $DnsResolver) {
        $DnsResolver = {
            param($Name)
            Resolve-DnsName -Name $Name -Type PTR -ErrorAction Stop
        }
    }

    try {
        $results = & $DnsResolver $IPv4
        $hostname = ''
        foreach ($result in @($results)) {
            if ($result.PSObject.Properties['NameHost'] -and $result.NameHost) {
                $hostname = [string]$result.NameHost
                break
            }
        }

        if ([string]::IsNullOrWhiteSpace($hostname)) {
            return @()
        }

        return @([pscustomobject]@{
            Hostname   = $hostname.TrimEnd('.')
            IP         = $IPv4
            RecordType = 'PTR'
            Source     = 'DNS-Reverse'
        })
    } catch {
        return @()
    }
}

function Apply-CybernetDnsToInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$InventoryRows,

        [string]$DnsSuffix,
        [scriptblock]$DnsResolver
    )

    $updated = foreach ($row in $InventoryRows) {
        $copy = [pscustomobject]@{
            Site             = $row.Site
            Serial           = $row.Serial
            ExpectedHostname = $row.ExpectedHostname
            ExpectedMAC      = $row.ExpectedMAC
            ExpectedRoom     = $row.ExpectedRoom
            ExpectedStatus   = $row.ExpectedStatus
            Notes            = $row.Notes
            IP               = $row.IP
            SubnetCandidate  = $row.SubnetCandidate
            SubnetSource     = $row.SubnetSource
            Confidence       = $row.Confidence
            Evidence         = $row.Evidence
        }

        if (-not [string]::IsNullOrWhiteSpace($copy.ExpectedHostname) -and [string]::IsNullOrWhiteSpace($copy.IP)) {
            $records = Resolve-CybernetDnsForward -Hostname $copy.ExpectedHostname -DnsSuffix $DnsSuffix -DnsResolver $DnsResolver
            if (@($records).Count -gt 0) {
                $copy.IP = $records[0].IP
                $copy.Evidence = "DNS forward resolved $($copy.ExpectedHostname) to $($copy.IP)"
            }
        }

        $copy
    }

    return @($updated)
}
