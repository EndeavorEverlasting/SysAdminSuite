#Requires -Version 5.1
Set-StrictMode -Version 2.0

function Resolve-SasCanonicalSoftwareSourceIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ApprovedServer
    )

    $alias = $ApprovedServer.Trim().TrimEnd('.')
    if ($alias -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$') {
        throw "Approved software-source server name is invalid: $alias"
    }

    try {
        $aliasEntry = [System.Net.Dns]::GetHostEntry($alias)
    }
    catch {
        throw "Approved software-source server did not resolve canonically: $alias"
    }

    $canonical = ([string]$aliasEntry.HostName).Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($canonical) -or $canonical -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9.-]+$') {
        throw "Approved software-source server did not resolve to a usable canonical FQDN: $alias"
    }

    $aliasAddresses = @(
        $aliasEntry.AddressList |
            ForEach-Object { $_.ToString() } |
            Where-Object { $_ } |
            Select-Object -Unique
    )
    if ($aliasAddresses.Count -eq 0) {
        throw "Approved software-source alias resolved without an address: $alias"
    }

    try {
        $canonicalAddresses = @(
            [System.Net.Dns]::GetHostAddresses($canonical) |
                ForEach-Object { $_.ToString() } |
                Where-Object { $_ } |
                Select-Object -Unique
        )
    }
    catch {
        throw "Canonical software-source FQDN did not resolve: $canonical"
    }
    if ($canonicalAddresses.Count -eq 0) {
        throw "Canonical software-source FQDN resolved without an address: $canonical"
    }

    $sharedAddresses = @($aliasAddresses | Where-Object { $_ -in $canonicalAddresses })
    if ($sharedAddresses.Count -eq 0) {
        throw "Canonical software-source FQDN does not resolve to the approved alias address set: $alias -> $canonical"
    }

    [pscustomobject][ordered]@{
        schema_version = 'sas-software-source-identity/v1'
        approved_server_alias = $alias
        canonical_fqdn = $canonical
        cifs_spn = ('CIFS/{0}' -f $canonical)
        canonical_unc_root = ('\\{0}\' -f $canonical)
        address_overlap_verified = $true
        alias_address_count = $aliasAddresses.Count
        canonical_address_count = $canonicalAddresses.Count
        shared_address_count = $sharedAddresses.Count
        credential_collected = $false
        ticket_bytes_emitted = $false
        target_contact_performed = $false
        target_mutation_performed = $false
    }
}

Export-ModuleMember -Function Resolve-SasCanonicalSoftwareSourceIdentity
