#Requires -Version 5.1
Set-StrictMode -Version Latest

function ConvertTo-IPv4Int {
    param([string]$IPv4)
    try {
        $bytes = [System.Net.IPAddress]::Parse($IPv4).GetAddressBytes()
        [array]::Reverse($bytes)
        return [BitConverter]::ToUInt32($bytes, 0)
    } catch {
        return $null
    }
}

function Split-Cidr {
    param([string]$Cidr)
    if ($Cidr -notmatch '^(\d{1,3}(?:\.\d{1,3}){3})/(\d{1,2})$') {
        throw "Invalid CIDR format: $Cidr"
    }
    return @{
        Network      = $Matches[1]
        PrefixLength = [int]$Matches[2]
    }
}

function Test-IpInSubnet {
    param(
        [string]$IPv4,
        [string]$Cidr
    )
    $parts = Split-Cidr -Cidr $Cidr
    $prefixLength = $parts.PrefixLength
    if ($prefixLength -lt 0 -or $prefixLength -gt 32) { return $false }
    if ($prefixLength -eq 0) { return $true }

    $ipBytes = [System.Net.IPAddress]::Parse($IPv4).GetAddressBytes()
    $netBytes = [System.Net.IPAddress]::Parse($parts.Network).GetAddressBytes()

    $fullBytes = [math]::Floor($prefixLength / 8)
    $remainder = $prefixLength % 8

    for ($i = 0; $i -lt $fullBytes; $i++) {
        if ($ipBytes[$i] -ne $netBytes[$i]) { return $false }
    }

    if ($remainder -gt 0) {
        $mask = [byte](255 -band (255 -shl (8 - $remainder)))
        if (($ipBytes[$fullBytes] -band $mask) -ne ($netBytes[$fullBytes] -band $mask)) { return $false }
    }

    return $true
}

function Test-IsPublicIPv4 {
    param([string]$IPv4)
    if ([string]::IsNullOrWhiteSpace($IPv4)) { return $false }
    try {
        $ip = [System.Net.IPAddress]::Parse($IPv4)
    } catch {
        return $true
    }

    if ($ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        return $true
    }

    $privateRanges = @(
        '10.0.0.0/8',
        '172.16.0.0/12',
        '192.168.0.0/16',
        '100.64.0.0/10',
        '169.254.0.0/16',
        '127.0.0.0/8'
    )

    foreach ($range in $privateRanges) {
        if (Test-IpInSubnet -IPv4 $IPv4 -Cidr $range) {
            return $false
        }
    }

    $documentationRanges = @(
        '192.0.2.0/24',
        '198.51.100.0/24',
        '203.0.113.0/24'
    )

    foreach ($range in $documentationRanges) {
        if (Test-IpInSubnet -IPv4 $IPv4 -Cidr $range) {
            return $true
        }
    }

    $firstOctet = [int]($IPv4.Split('.')[0])
    if ($firstOctet -ge 224) { return $true }

    return $true
}

function Test-SubnetApprovedForScan {
    param(
        [object]$SubnetRow,
        [bool]$RequireApprovedSubnet = $true
    )
    if (-not $RequireApprovedSubnet) { return $true }
    return [bool]$SubnetRow.ApprovedForScan
}

function Convert-IpToSubnetCandidate {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$IPv4,

        [Parameter(Mandatory = $true)]
        [object[]]$ApprovedSubnets,

        [bool]$RequireApprovedSubnet = $true
    )

    if ([string]::IsNullOrWhiteSpace($IPv4)) {
        return [pscustomobject]@{
            IP              = ''
            SubnetCandidate = ''
            SubnetSource    = ''
            ApprovedForScan = $false
            IsPublic        = $false
            Matched         = $false
        }
    }

    $isPublic = Test-IsPublicIPv4 -IPv4 $IPv4
    if ($isPublic) {
        return [pscustomobject]@{
            IP              = $IPv4
            SubnetCandidate = ''
            SubnetSource    = ''
            ApprovedForScan = $false
            IsPublic        = $true
            Matched         = $false
        }
    }

    $matches = @()
    foreach ($subnet in $ApprovedSubnets) {
        if (Test-IpInSubnet -IPv4 $IPv4 -Cidr $subnet.Subnet) {
            $matches += $subnet
        }
    }

    if (@($matches).Count -eq 0) {
        return [pscustomobject]@{
            IP              = $IPv4
            SubnetCandidate = ''
            SubnetSource    = ''
            ApprovedForScan = $false
            IsPublic        = $false
            Matched         = $false
        }
    }

    $best = $matches | Sort-Object -Property Subnet | Select-Object -First 1
    $approved = Test-SubnetApprovedForScan -SubnetRow $best -RequireApprovedSubnet $RequireApprovedSubnet

    return [pscustomobject]@{
        IP              = $IPv4
        SubnetCandidate = $best.Subnet
        SubnetSource    = [string]$best.Source
        ApprovedForScan = $approved
        IsPublic        = $false
        Matched         = $true
    }
}
