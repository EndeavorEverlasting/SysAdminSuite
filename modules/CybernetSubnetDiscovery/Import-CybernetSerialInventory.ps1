#Requires -Version 5.1
Set-StrictMode -Version Latest

function Normalize-CybernetSerial {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $clean = ($Value.Trim().ToUpperInvariant() -replace '\s+', '')
    return $clean
}

function Normalize-CybernetMac {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $clean = ($Value.ToUpperInvariant().ToCharArray() | Where-Object { $_ -match '[0-9A-F]' }) -join ''
    if ($clean.Length -ne 12) { return $clean }
    $pairs = for ($i = 0; $i -lt 12; $i += 2) { $clean.Substring($i, 2) }
    return ($pairs -join ':')
}

function Normalize-CybernetHostname {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $trimmed = $Value.Trim()
    if ($trimmed -match '\.') { return $trimmed }
    return $trimmed.ToUpperInvariant()
}

function ConvertTo-BooleanLike {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    switch -Regex ($Value.Trim()) {
        '^(?i)(true|yes|y|1)$' { return $true }
        default { return $false }
    }
}

function Get-CsvPropertyValue {
    param(
        [object]$Row,
        [string[]]$Names
    )
    foreach ($name in $Names) {
        $prop = $Row.PSObject.Properties[$name]
        if ($prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
            return ([string]$prop.Value).Trim()
        }
    }
    return ''
}

function Import-CybernetSerialInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Site
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Serial inventory file not found: $Path"
    }

    $rawRows = @(Import-Csv -LiteralPath $Path)
    $normalized = New-Object System.Collections.Generic.List[object]
    $duplicateSerials = New-Object System.Collections.Generic.List[string]

    foreach ($row in $rawRows) {
        $rowSite = Get-CsvPropertyValue -Row $row -Names @('Site')
        if ($rowSite -and $rowSite -ne $Site) { continue }

        $serial = Normalize-CybernetSerial -Value (Get-CsvPropertyValue -Row $row -Names @('Serial'))
        if ([string]::IsNullOrWhiteSpace($serial)) { continue }

        $normalized.Add([pscustomobject]@{
            Site             = $Site
            Serial           = $serial
            ExpectedHostname = Normalize-CybernetHostname -Value (Get-CsvPropertyValue -Row $row -Names @('ExpectedHostname', 'Hostname'))
            ExpectedMAC      = Normalize-CybernetMac -Value (Get-CsvPropertyValue -Row $row -Names @('ExpectedMAC', 'MAC'))
            ExpectedRoom     = Get-CsvPropertyValue -Row $row -Names @('ExpectedRoom', 'Room')
            ExpectedStatus   = Get-CsvPropertyValue -Row $row -Names @('ExpectedStatus', 'Status')
            Notes            = Get-CsvPropertyValue -Row $row -Names @('Notes')
            IP               = ''
            SubnetCandidate  = ''
            SubnetSource     = ''
            Confidence       = 'Missing'
            Evidence         = ''
        }) | Out-Null
    }

    $groups = $normalized | Group-Object -Property Serial
    foreach ($group in $groups) {
        if ($group.Count -gt 1) {
            $duplicateSerials.Add($group.Name) | Out-Null
        }
    }

    return [pscustomobject]@{
        Rows             = $normalized.ToArray()
        DuplicateSerials = $duplicateSerials.ToArray()
    }
}

function Import-CybernetSiteSubnets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Site
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Site subnet file not found: $Path"
    }

    $rows = @(Import-Csv -LiteralPath $Path)
    $subnets = New-Object System.Collections.Generic.List[object]

    foreach ($row in $rows) {
        $rowSite = Get-CsvPropertyValue -Row $row -Names @('Site', 'site_code', 'site')
        if ($rowSite -and $rowSite -ne $Site) { continue }

        $cidr = Get-CsvPropertyValue -Row $row -Names @('Subnet', 'subnet_cidr', 'cidr')
        if ([string]::IsNullOrWhiteSpace($cidr)) { continue }

        $subnets.Add([pscustomobject]@{
            Site             = $Site
            Subnet           = $cidr.Trim()
            Description      = Get-CsvPropertyValue -Row $row -Names @('Description', 'notes', 'Notes')
            ApprovedForScan  = ConvertTo-BooleanLike -Value (Get-CsvPropertyValue -Row $row -Names @('ApprovedForScan', 'enabled', 'Enabled'))
            Source           = 'SiteSubnets'
        }) | Out-Null
    }

    return $subnets.ToArray()
}

function Import-CybernetApprovedSubnetsJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Site
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Approved subnets JSON file not found: $Path"
    }

    $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $subnets = New-Object System.Collections.Generic.List[object]

    foreach ($entry in @($json.subnets)) {
        $entrySite = [string]$entry.site
        if ($entrySite -and $entrySite -ne $Site) { continue }

        $cidr = [string]$entry.cidr
        if ([string]::IsNullOrWhiteSpace($cidr)) { continue }

        $subnets.Add([pscustomobject]@{
            Site             = $Site
            Subnet           = $cidr.Trim()
            Description      = [string]$entry.description
            ApprovedForScan  = [bool]$entry.approvedForScan
            Source           = 'ApprovedSubnets'
        }) | Out-Null
    }

    return $subnets.ToArray()
}

function Merge-CybernetKnownData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$InventoryRows,

        [string]$KnownHostsPath,
        [string]$KnownMacsPath
    )

    $hostMap = @{}
    $macMap = @{}

    if ($KnownHostsPath -and (Test-Path -LiteralPath $KnownHostsPath)) {
        foreach ($row in @(Import-Csv -LiteralPath $KnownHostsPath)) {
            $serial = Normalize-CybernetSerial -Value (Get-CsvPropertyValue -Row $row -Names @('Serial'))
            $hostname = Normalize-CybernetHostname -Value (Get-CsvPropertyValue -Row $row -Names @('ExpectedHostname', 'Hostname'))
            $ip = Get-CsvPropertyValue -Row $row -Names @('IP', 'IPAddress')
            if ($serial) { $hostMap[$serial] = @{ Hostname = $hostname; IP = $ip } }
        }
    }

    if ($KnownMacsPath -and (Test-Path -LiteralPath $KnownMacsPath)) {
        foreach ($row in @(Import-Csv -LiteralPath $KnownMacsPath)) {
            $serial = Normalize-CybernetSerial -Value (Get-CsvPropertyValue -Row $row -Names @('Serial'))
            $mac = Normalize-CybernetMac -Value (Get-CsvPropertyValue -Row $row -Names @('ExpectedMAC', 'MAC'))
            if ($serial) { $macMap[$serial] = $mac }
        }
    }

    $merged = foreach ($row in $InventoryRows) {
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

        if ($hostMap.ContainsKey($row.Serial)) {
            if ([string]::IsNullOrWhiteSpace($copy.ExpectedHostname)) {
                $copy.ExpectedHostname = $hostMap[$row.Serial].Hostname
            }
            if ([string]::IsNullOrWhiteSpace($copy.IP)) {
                $copy.IP = $hostMap[$row.Serial].IP
            }
        }

        if ($macMap.ContainsKey($row.Serial) -and [string]::IsNullOrWhiteSpace($copy.ExpectedMAC)) {
            $copy.ExpectedMAC = $macMap[$row.Serial]
        }

        $copy
    }

    return @($merged)
}
