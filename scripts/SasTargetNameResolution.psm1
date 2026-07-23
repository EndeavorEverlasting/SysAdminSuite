#Requires -Version 5.1
Set-StrictMode -Version 2.0

function Test-SasDnsHostLabel {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Value)

    return ($Value.Length -ge 1 -and
        $Value.Length -le 63 -and
        $Value -match '^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$')
}

function Test-SasCanonicalFqdn {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Value)

    $normalized = $Value.Trim().TrimEnd('.')
    return ($normalized.Length -le 253 -and
        $normalized.Contains('.') -and
        $normalized -match '^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$')
}

function Get-SasLocalDnsSuffixCandidates {
    [CmdletBinding()]
    param([string[]]$AdditionalSuffixes = @())

    $values = New-Object System.Collections.Generic.List[string]
    foreach ($value in @($AdditionalSuffixes)) {
        if (-not [string]::IsNullOrWhiteSpace($value)) { [void]$values.Add($value) }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:SAS_TARGET_DNS_SUFFIXES)) {
        foreach ($value in ($env:SAS_TARGET_DNS_SUFFIXES -split ',')) {
            if (-not [string]::IsNullOrWhiteSpace($value)) { [void]$values.Add($value) }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERDNSDOMAIN)) {
        [void]$values.Add($env:USERDNSDOMAIN)
    }

    try {
        $global = Get-DnsClientGlobalSetting -ErrorAction Stop
        foreach ($value in @($global.SuffixSearchList)) {
            if (-not [string]::IsNullOrWhiteSpace($value)) { [void]$values.Add($value) }
        }
    }
    catch { }

    try {
        foreach ($client in @(Get-DnsClient -ErrorAction Stop)) {
            if (-not [string]::IsNullOrWhiteSpace($client.ConnectionSpecificSuffix)) {
                [void]$values.Add($client.ConnectionSpecificSuffix)
            }
        }
    }
    catch { }

    try {
        $domainName = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().DomainName
        if (-not [string]::IsNullOrWhiteSpace($domainName)) { [void]$values.Add($domainName) }
    }
    catch { }

    $normalized = @($values |
        ForEach-Object { $_.Trim().TrimStart('.').TrimEnd('.').ToLowerInvariant() } |
        Where-Object { $_ -and (Test-SasCanonicalFqdn -Value ("probe.{0}" -f $_)) } |
        Sort-Object -Unique)
    return ,$normalized
}

function Invoke-SasTargetDnsLookup {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Name)

    try {
        $entry = [System.Net.Dns]::GetHostEntry($Name)
        $addresses = @($entry.AddressList |
            ForEach-Object { $_.IPAddressToString } |
            Where-Object { $_ } |
            Sort-Object -Unique)
        if ([string]::IsNullOrWhiteSpace($entry.HostName) -or $addresses.Count -eq 0) { return $null }
        return [pscustomobject]@{
            canonical_name = $entry.HostName
            addresses = $addresses
        }
    }
    catch {
        return $null
    }
}

function Resolve-SasCanonicalTargetFqdn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$TargetName,
        [string[]]$SuffixCandidates = @(),
        [scriptblock]$DnsResolver
    )

    $normalizedInput = $TargetName.Trim().TrimEnd('.')
    $inputIsFqdn = $normalizedInput.Contains('.')
    if ($inputIsFqdn) {
        if (-not (Test-SasCanonicalFqdn -Value $normalizedInput)) {
            throw 'Target name is not a valid fully qualified DNS name.'
        }
        $shortName = $normalizedInput.Split('.')[0]
    }
    else {
        if (-not (Test-SasDnsHostLabel -Value $normalizedInput)) {
            throw 'Target name must be one valid short hostname or fully qualified DNS name.'
        }
        $shortName = $normalizedInput
    }

    if ($null -eq $DnsResolver) {
        $DnsResolver = { param($Name) Invoke-SasTargetDnsLookup -Name $Name }
    }

    $suffixes = if ($inputIsFqdn) { @() } else { @(Get-SasLocalDnsSuffixCandidates -AdditionalSuffixes $SuffixCandidates) }
    $lookupNames = New-Object System.Collections.Generic.List[string]
    [void]$lookupNames.Add($normalizedInput)
    if (-not $inputIsFqdn) {
        foreach ($suffix in $suffixes) {
            [void]$lookupNames.Add(("{0}.{1}" -f $shortName, $suffix))
        }
    }

    $resolved = New-Object System.Collections.Generic.List[object]
    $identityMismatches = New-Object System.Collections.Generic.List[string]
    foreach ($lookupName in @($lookupNames | Sort-Object -Unique)) {
        $answer = & $DnsResolver $lookupName
        if ($null -eq $answer) { continue }

        $canonical = [string]$answer.canonical_name
        if ([string]::IsNullOrWhiteSpace($canonical)) { continue }
        $canonical = $canonical.Trim().TrimEnd('.').ToLowerInvariant()
        if (-not (Test-SasCanonicalFqdn -Value $canonical)) { continue }

        $canonicalShort = $canonical.Split('.')[0]
        if (-not $canonicalShort.Equals($shortName, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$identityMismatches.Add($canonical)
            continue
        }
        if ($inputIsFqdn -and -not $canonical.Equals($normalizedInput, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$identityMismatches.Add($canonical)
            continue
        }

        $addresses = @($answer.addresses |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique)
        if ($addresses.Count -eq 0) { continue }

        [void]$resolved.Add([pscustomobject]@{
            lookup_name = $lookupName.ToLowerInvariant()
            canonical_name = $canonical
            addresses = $addresses
        })
    }

    $canonicalNames = @($resolved | ForEach-Object { $_.canonical_name } | Sort-Object -Unique)
    if ($canonicalNames.Count -eq 0) {
        if ($identityMismatches.Count -gt 0) {
            throw 'DNS resolved the supplied name to a different canonical host identity. Stop and reconcile the assignment before live certification.'
        }
        throw 'Unable to resolve one canonical FQDN from the supplied hostname and the controller DNS context. Stop; do not guess or append a domain manually.'
    }
    if ($canonicalNames.Count -ne 1) {
        throw 'The supplied hostname resolved to multiple canonical FQDNs. Stop and reconcile DNS or inventory before live certification.'
    }

    $fqdn = $canonicalNames[0]
    $matching = @($resolved | Where-Object { $_.canonical_name -eq $fqdn })
    $addresses = @($matching | ForEach-Object { $_.addresses } | Sort-Object -Unique)
    if ($addresses.Count -eq 0) {
        throw 'Canonical FQDN resolution returned no usable addresses.'
    }

    return [pscustomobject][ordered]@{
        schema_version = 'sas-target-name-resolution/v1'
        input_name = $normalizedInput
        short_name = $shortName.ToUpperInvariant()
        fqdn = $fqdn
        addresses = $addresses
        resolution_sources = @($matching | ForEach-Object { $_.lookup_name } | Sort-Object -Unique)
        suffix_candidate_count = $suffixes.Count
        disposition = 'UNIQUE_CANONICAL_FQDN'
    }
}

Export-ModuleMember -Function Test-SasDnsHostLabel, Test-SasCanonicalFqdn, Get-SasLocalDnsSuffixCandidates, Invoke-SasTargetDnsLookup, Resolve-SasCanonicalTargetFqdn
