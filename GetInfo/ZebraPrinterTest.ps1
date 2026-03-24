# Runs SNMP/live checks for Zebra printers.
param(
    [string[]]$PrinterIPs,
    [ValidateNotNullOrEmpty()]
    [string]$Community = $env:SNMP_COMMUNITY,
    [ValidateSet('1','2c','3')]
    [string]$SnmpVersion = '1'
)

if ([string]::IsNullOrWhiteSpace($Community)) {
    throw "SNMP community is required. Pass -Community or set SNMP_COMMUNITY."
}
function Get-PrinterInfoFromIP {
    param (
        [Parameter(Mandatory = $true)]
        [string]$IPAddress
    )

    $pingResult = Test-Connection -ComputerName $IPAddress -Count 2 -Quiet
    if (-not $pingResult) {
        return [PSCustomObject]@{
            IPAddress    = $IPAddress
            Status       = "Offline"
            MACAddress   = "N/A"
            SerialNumber = "N/A"
            Source       = "None"
        }
    }

    $macOID    = "1.3.6.1.2.1.2.2.1.6.1"
    $serialOID = "1.3.6.1.2.1.43.5.1.1.17.1"

    $snmpAvailable = Get-Command snmpget -ErrorAction SilentlyContinue
    if ($snmpAvailable) {
        $macRaw = snmpget -v $SnmpVersion -c $Community $IPAddress $macOID 2>&1
        $serialRaw = snmpget -v $SnmpVersion -c $Community $IPAddress $serialOID 2>&1

        $mac = if ($macRaw -match "(?i)Hex-STRING:\s*([0-9A-Fa-fxX ]+)") {
            ($matches[1] -split ' ') -join ':'
        } else { "Not Found (SNMP)" }

        $serial = if ($serialRaw -match "STRING: (.+)") {
            $matches[1].Trim()
        } else { "Not Found (SNMP)" }

        return [PSCustomObject]@{
            IPAddress    = $IPAddress
            Status       = "Online"
            MACAddress   = $mac
            SerialNumber = $serial
            Source       = "SNMP"
        }
    }

    # Fallback if SNMP fails
    return [PSCustomObject]@{
        IPAddress    = $IPAddress
        Status       = "Online"
        MACAddress   = "Unavailable"
        SerialNumber = "Unavailable"
        Source       = "Unknown"
    }
}

if (-not $PrinterIPs -or $PrinterIPs.Count -eq 0) {
    $ipsPath = Join-Path $PSScriptRoot 'ZebraPrinterIPs.txt'
    if (Test-Path -Path $ipsPath) {
        $PrinterIPs = Get-Content -Path $ipsPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() }
    } else {
        throw "No printer IPs provided. Pass -PrinterIPs or create $ipsPath."
    }
}
$invalidIps = $PrinterIPs | Where-Object { $_ -notmatch '^(?:\d{1,3}\.){3}\d{1,3}$' }
if ($invalidIps) {
    throw "Invalid printer IP(s): $($invalidIps -join ', ')"
}

$results = $PrinterIPs | ForEach-Object { Get-PrinterInfoFromIP -IPAddress $_ }

# Show in console
$results | Format-Table -AutoSize

# Optional: Export to CSV
$results | Export-Csv ".\ZebraPrinterTestResults.csv" -NoTypeInformation