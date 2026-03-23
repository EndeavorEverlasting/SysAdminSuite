<#
.SYNOPSIS
    Tests network connectivity to one or more target hosts.

.DESCRIPTION
    Sends ICMP echo requests to each target. Returns $true per host that
    responds, $false otherwise. Safe to call offline — never throws.

.PARAMETER ComputerName
    One or more hostnames or IP addresses to ping. Default: 8.8.8.8.

.PARAMETER Count
    Number of echo requests to send per host. Default: 2.

.EXAMPLE
    Test-Network
    # Pings 8.8.8.8 twice.

.EXAMPLE
    Test-Network -ComputerName 'SWBPNHPHPS01V','SWBPNSXPS01V' -Count 4
    # Pings both print servers four times each.
#>
function Test-Network {
    [CmdletBinding()]
    param(
        # BUG-FIX: was [string]$Host — $Host is a PowerShell built-in automatic
        # variable (case-insensitive). Renamed to $ComputerName to avoid collision.
        [string[]]$ComputerName = '8.8.8.8',
        [int]$Count = 2
    )

    foreach ($target in $ComputerName) {
        $result = Test-Connection -ComputerName $target -Count $Count -ErrorAction SilentlyContinue -Quiet
        [pscustomobject]@{ ComputerName = $target; Reachable = [bool]$result }
    }
}