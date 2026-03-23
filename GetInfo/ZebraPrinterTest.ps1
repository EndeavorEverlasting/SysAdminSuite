# Importing your previous SNMP/WMI/Live Check logic
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
        $macRaw = snmpget -v 1 -c public $IPAddress $macOID 2>&1
        $serialRaw = snmpget -v 1 -c public $IPAddress $serialOID 2>&1

        $mac = if ($macRaw -match "Hex-STRING: ([\dA-Fx ]+)") {
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

# === Test the two Zebra printers ===
$zebraIPs = @(
    "10.202.46.169",
    "10.202.46.168",
    "10.202.46.170",
    "10.202.47.142",
    "10.202.47.144",
    "10.202.47.111",
    "10.202.47.45",
    "10.202.47.134",
    "10.202.46.172"
)

$results = $zebraIPs | ForEach-Object { Get-PrinterInfoFromIP -IPAddress $_ }

# Show in console
$results | Format-Table -AutoSize

# Optional: Export to CSV
$results | Export-Csv ".\ZebraPrinterTestResults.csv" -NoTypeInformation