<#
.SYNOPSIS
  Fast read-only Active Directory existence check for large Cybernet hostname manifests.

.DESCRIPTION
  This is optimized for the Cybernet survey manifest shape:
  Identifier, HostName, SerialNumber, MACAddress, DeviceType, Site, Room, SourceFile, SourceSheet, SourceRow, Notes

  It checks whether each unique HostName exists in AD. It does not prove location,
  reachability, subnet, ping, serial identity, or physical presence.

  Speed model:
  - Prefer HostName over Identifier.
  - Deduplicate manifest rows before querying AD.
  - Query AD in exact-match batches instead of one row at a time.
  - Do not resolve DNS unless a separate workflow needs that later.

  Output is one row per unique hostname.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Manifest,

    [Parameter(Mandatory = $true)]
    [string]$Output,

    [string]$HostNameColumn = 'HostName',

    [int]$BatchSize = 75,

    [int]$StaleDays = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-LdapEscapedValue {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return ($Value -replace '\\','\5c' -replace '\*','\2a' -replace '\(','\28' -replace '\)','\29' -replace "`0",'\00')
}

function ConvertTo-ShortHostName {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return (($Value.Trim() -split '\.')[0] -replace '\$$','').ToUpperInvariant()
}

function Get-PropertyValue {
    param(
        [object]$Row,
        [string[]]$Names
    )
    foreach ($name in $Names) {
        foreach ($prop in $Row.PSObject.Properties) {
            if ($prop.Name -and $prop.Name.Trim().ToLowerInvariant() -eq $name.Trim().ToLowerInvariant()) {
                $value = [string]$prop.Value
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    return $value.Trim()
                }
            }
        }
    }
    return ''
}

function Add-UniqueText {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Value
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    if (-not $List.Contains($Value.Trim())) {
        $List.Add($Value.Trim()) | Out-Null
    }
}

function New-HostBucket {
    param([string]$HostName)
    [pscustomobject]@{
        HostName = $HostName
        ManifestRowCount = 0
        SerialNumbers = [System.Collections.Generic.List[string]]::new()
        MACAddresses = [System.Collections.Generic.List[string]]::new()
        Sites = [System.Collections.Generic.List[string]]::new()
        Rooms = [System.Collections.Generic.List[string]]::new()
        SourceFiles = [System.Collections.Generic.List[string]]::new()
        SourceRows = [System.Collections.Generic.List[string]]::new()
        Notes = [System.Collections.Generic.List[string]]::new()
    }
}

function Add-CandidateMatch {
    param(
        [hashtable]$CandidateMap,
        [string]$Key,
        [object]$Computer
    )
    $hostKey = ConvertTo-ShortHostName $Key
    if (-not $hostKey) { return }

    if (-not $CandidateMap.ContainsKey($hostKey)) {
        $CandidateMap[$hostKey] = [System.Collections.Generic.List[object]]::new()
    }

    $dn = [string]$Computer.DistinguishedName
    foreach ($existing in $CandidateMap[$hostKey]) {
        if ([string]$existing.DistinguishedName -eq $dn) {
            return
        }
    }

    $CandidateMap[$hostKey].Add($Computer) | Out-Null
}

function Get-ADDomainDnsRootSafe {
    try {
        if (Get-Command Get-ADDomain -ErrorAction SilentlyContinue) {
            return [string](Get-ADDomain -ErrorAction Stop).DNSRoot
        }
    } catch {
        return ''
    }
    return ''
}

function Invoke-BatchedADComputerLookup {
    param(
        [string[]]$HostNames,
        [int]$Size,
        [string]$DomainDnsRoot
    )

    $candidateMap = @{}
    $blockedMap = @{}

    $props = @('Name', 'SamAccountName', 'DNSHostName', 'Enabled', 'DistinguishedName', 'whenChanged')
    for ($i = 0; $i -lt $HostNames.Count; $i += $Size) {
        $last = [Math]::Min($i + $Size - 1, $HostNames.Count - 1)
        $chunk = @($HostNames[$i..$last])

        $clauses = [System.Collections.Generic.List[string]]::new()
        foreach ($host in $chunk) {
            $safe = ConvertTo-LdapEscapedValue $host
            if (-not $safe) { continue }

            # Exact AD computer identity clauses only. No broad wildcard matching.
            $clauses.Add("(name=$safe)") | Out-Null
            $clauses.Add("(sAMAccountName=$safe`$)") | Out-Null

            if (-not [string]::IsNullOrWhiteSpace($DomainDnsRoot)) {
                $safeDns = ConvertTo-LdapEscapedValue ("{0}.{1}" -f $host.ToLowerInvariant(), $DomainDnsRoot.ToLowerInvariant())
                $clauses.Add("(dNSHostName=$safeDns)") | Out-Null
            }
        }

        if ($clauses.Count -eq 0) { continue }
        $filter = if ($clauses.Count -eq 1) { $clauses[0] } else { "(|$($clauses -join ''))" }

        try {
            $matches = @(Get-ADComputer -LDAPFilter $filter -Properties $props -ErrorAction Stop)
            foreach ($match in $matches) {
                Add-CandidateMatch -CandidateMap $candidateMap -Key ([string]$match.Name) -Computer $match
                Add-CandidateMatch -CandidateMap $candidateMap -Key ([string]$match.SamAccountName) -Computer $match
                Add-CandidateMatch -CandidateMap $candidateMap -Key ([string]$match.DNSHostName) -Computer $match
            }
        } catch {
            $message = $_.Exception.Message
            foreach ($host in $chunk) {
                $blockedMap[$host] = $message
            }
        }
    }

    return @{
        CandidateMap = $candidateMap
        BlockedMap = $blockedMap
    }
}

function Invoke-DsqueryLookup {
    param([string[]]$HostNames)

    $candidateMap = @{}
    $blockedMap = @{}

    foreach ($host in $HostNames) {
        try {
            $raw = & dsquery.exe computer -name $host 2>&1
            if ($LASTEXITCODE -eq 0 -and $raw) {
                $lines = @($raw | Where-Object { $_ -and $_.ToString().Trim() })
                foreach ($line in $lines) {
                    $resolvedHost = ''
                    if ($line -match '^"?CN=([^,"]+)') { $resolvedHost = $matches[1] }
                    $obj = [pscustomobject]@{
                        Name = $resolvedHost
                        SamAccountName = if ($resolvedHost) { "$resolvedHost`$" } else { '' }
                        DNSHostName = ''
                        Enabled = ''
                        DistinguishedName = [string]$line
                        whenChanged = ''
                    }
                    Add-CandidateMatch -CandidateMap $candidateMap -Key $host -Computer $obj
                }
            }
        } catch {
            $blockedMap[$host] = $_.Exception.Message
        }
    }

    return @{
        CandidateMap = $candidateMap
        BlockedMap = $blockedMap
    }
}

if (-not (Test-Path -LiteralPath $Manifest)) {
    throw "Manifest not found: $Manifest"
}

if ($BatchSize -lt 1) {
    throw "BatchSize must be at least 1."
}

$outDir = Split-Path -Parent $Output
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$manifestRows = @(Import-Csv -LiteralPath $Manifest)
$buckets = [ordered]@{}
$skipped = [System.Collections.Generic.List[object]]::new()
$rowNumber = 1

foreach ($row in $manifestRows) {
    $rowNumber++
    $host = ConvertTo-ShortHostName (Get-PropertyValue -Row $row -Names @($HostNameColumn, 'HostName', 'Hostname', 'ComputerName', 'ADHostname'))

    if (-not $host) {
        $skipped.Add([pscustomobject]@{
            InputRow = $rowNumber
            Identifier = Get-PropertyValue -Row $row -Names @('Identifier', 'Target')
            SerialNumber = Get-PropertyValue -Row $row -Names @('SerialNumber', 'Serial', 'Cybernet Serial', 'Cybernet S/N')
            MACAddress = Get-PropertyValue -Row $row -Names @('MACAddress', 'MAC')
            ADStatus = 'NEEDS_OPERATOR_REVIEW'
            Notes = 'No HostName value. This fast AD existence checker is hostname-based.'
        }) | Out-Null
        continue
    }

    if (-not $buckets.Contains($host)) {
        $buckets[$host] = New-HostBucket -HostName $host
    }

    $bucket = $buckets[$host]
    $bucket.ManifestRowCount++

    Add-UniqueText -List $bucket.SerialNumbers -Value (Get-PropertyValue -Row $row -Names @('SerialNumber', 'Serial', 'Cybernet Serial', 'Cybernet S/N'))
    Add-UniqueText -List $bucket.MACAddresses -Value (Get-PropertyValue -Row $row -Names @('MACAddress', 'MAC'))
    Add-UniqueText -List $bucket.Sites -Value (Get-PropertyValue -Row $row -Names @('Site'))
    Add-UniqueText -List $bucket.Rooms -Value (Get-PropertyValue -Row $row -Names @('Room'))
    Add-UniqueText -List $bucket.SourceFiles -Value (Get-PropertyValue -Row $row -Names @('SourceFile'))
    Add-UniqueText -List $bucket.SourceRows -Value (Get-PropertyValue -Row $row -Names @('SourceRow'))
    Add-UniqueText -List $bucket.Notes -Value (Get-PropertyValue -Row $row -Names @('Notes'))
}

$hostNames = @($buckets.Keys)
$hasADModule = $null -ne (Get-Module -ListAvailable -Name ActiveDirectory | Select-Object -First 1)
$hasDsquery = $null -ne (Get-Command dsquery.exe -ErrorAction SilentlyContinue)
$queryMode = 'none'
$lookup = @{
    CandidateMap = @{}
    BlockedMap = @{}
}
$domainDnsRoot = ''

if ($hasADModule) {
    Import-Module ActiveDirectory -ErrorAction Stop
    $domainDnsRoot = Get-ADDomainDnsRootSafe
    $queryMode = 'active_directory_module_batched_exact_hostname'
    $lookup = Invoke-BatchedADComputerLookup -HostNames $hostNames -Size $BatchSize -DomainDnsRoot $domainDnsRoot
} elseif ($hasDsquery) {
    $queryMode = 'dsquery_deduped_hostname'
    $lookup = Invoke-DsqueryLookup -HostNames $hostNames
} else {
    $queryMode = 'no_ad_tooling_available'
}

$results = [System.Collections.Generic.List[object]]::new()
foreach ($host in $hostNames) {
    $bucket = $buckets[$host]
    $candidates = @()
    if ($lookup.CandidateMap.ContainsKey($host)) {
        $candidates = @($lookup.CandidateMap[$host])
    }

    $status = 'AD_NOT_FOUND'
    $exists = 'NO'
    $adHost = ''
    $dnsHost = ''
    $enabled = ''
    $dn = ''
    $whenChanged = ''
    $notes = ''

    if ($queryMode -eq 'no_ad_tooling_available') {
        $status = 'AD_QUERY_BLOCKED'
        $exists = 'UNKNOWN'
        $notes = 'Neither ActiveDirectory PowerShell module nor dsquery.exe is available.'
    } elseif ($lookup.BlockedMap.ContainsKey($host)) {
        $status = 'AD_QUERY_BLOCKED'
        $exists = 'UNKNOWN'
        $notes = [string]$lookup.BlockedMap[$host]
    } elseif ($candidates.Count -eq 1) {
        $match = $candidates[0]
        $exists = 'YES'
        $adHost = [string]$match.Name
        $dnsHost = [string]$match.DNSHostName
        $enabled = [string]$match.Enabled
        $dn = [string]$match.DistinguishedName
        $whenChanged = [string]$match.whenChanged

        if ($enabled -eq 'False') {
            $status = 'AD_OBJECT_FOUND_DISABLED'
        } elseif ($whenChanged) {
            try {
                if (((Get-Date) - [datetime]$whenChanged).Days -gt $StaleDays) {
                    $status = 'AD_OBJECT_FOUND_STALE'
                } else {
                    $status = 'AD_CONFIRMED'
                }
            } catch {
                $status = 'AD_CONFIRMED'
            }
        } else {
            $status = 'AD_CONFIRMED'
        }
    } elseif ($candidates.Count -gt 1) {
        $status = 'AD_DUPLICATE_CANDIDATES'
        $exists = 'REVIEW'
        $adHost = ($candidates | Select-Object -ExpandProperty Name) -join ';'
        $dn = ($candidates | Select-Object -ExpandProperty DistinguishedName) -join ';'
        $notes = 'Multiple AD computer candidates matched this hostname.'
    }

    $results.Add([pscustomobject]@{
        QueryHostName = $host
        ADExists = $exists
        ADStatus = $status
        ADHostname = $adHost
        DNSHostName = $dnsHost
        ADEnabled = $enabled
        DistinguishedName = $dn
        WhenChanged = $whenChanged
        ManifestRowCount = $bucket.ManifestRowCount
        SerialNumbers = ($bucket.SerialNumbers -join ';')
        MACAddresses = ($bucket.MACAddresses -join ';')
        Sites = ($bucket.Sites -join ';')
        Rooms = ($bucket.Rooms -join ';')
        SourceFiles = ($bucket.SourceFiles -join ';')
        SourceRows = ($bucket.SourceRows -join ';')
        Notes = $notes
    }) | Out-Null
}

$results | Sort-Object QueryHostName | Export-Csv -LiteralPath $Output -NoTypeInformation -Encoding UTF8

$skippedPath = [System.IO.Path]::ChangeExtension($Output, '.skipped_no_hostname.csv')
$skipped | Export-Csv -LiteralPath $skippedPath -NoTypeInformation -Encoding UTF8

$summaryPath = [System.IO.Path]::ChangeExtension($Output, '.summary.json')
$summary = [ordered]@{
    query_mode_used = $queryMode
    domain_dns_root = $domainDnsRoot
    input_rows = $manifestRows.Count
    unique_hostnames_checked = $hostNames.Count
    skipped_no_hostname = $skipped.Count
    ad_exists_yes = @($results | Where-Object { $_.ADExists -eq 'YES' }).Count
    ad_exists_no = @($results | Where-Object { $_.ADExists -eq 'NO' }).Count
    ad_exists_review = @($results | Where-Object { $_.ADExists -eq 'REVIEW' }).Count
    ad_exists_unknown = @($results | Where-Object { $_.ADExists -eq 'UNKNOWN' }).Count
    batch_size = $BatchSize
    output = $Output
    skipped_output = $skippedPath
}
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host 'AD EXISTENCE SUMMARY:'
Write-Host ("- Query mode used: {0}" -f $summary.query_mode_used)
Write-Host ("- Input rows: {0}" -f $summary.input_rows)
Write-Host ("- Unique hostnames checked: {0}" -f $summary.unique_hostnames_checked)
Write-Host ("- Skipped no hostname: {0}" -f $summary.skipped_no_hostname)
Write-Host ("- AD exists YES: {0}" -f $summary.ad_exists_yes)
Write-Host ("- AD exists NO: {0}" -f $summary.ad_exists_no)
Write-Host ("- AD review/duplicate: {0}" -f $summary.ad_exists_review)
Write-Host ("- AD unknown/blocked: {0}" -f $summary.ad_exists_unknown)
Write-Host ("- Output: {0}" -f $Output)
Write-Host ("- Skipped output: {0}" -f $skippedPath)
Write-Host ("- Summary: {0}" -f $summaryPath)
