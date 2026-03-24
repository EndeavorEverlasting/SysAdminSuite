<#
.SYNOPSIS
  Proof-of-concept: Take printer queues, resolve to IPs, grab SNMP info, export.

.NOTES
  Requires: PowerShell 5+, permission to query print server, SNMP utilities if enabled.
#>

param(
    [string]$PrintServer = "SWBPNSHPS01V",
    [string[]]$Queues = @("PV522-PED01","PV522-PED02","PV522-PED03","PV522-PED04"),
    [string]$OutputPath = "C:\Temp\QueueInventory.csv",
    [ValidateNotNullOrEmpty()]
    [string]$Community = "public",
    [ValidateSet('1','2c','3')]
    [string]$SnmpVersion = '1'
)

function Get-PrinterIPFromQueue {
    param([string]$Server, [string]$Queue)

    try {
        $printer = Get-Printer -ComputerName $Server -Name $Queue -ErrorAction Stop
        $port    = Get-PrinterPort -ComputerName $Server -Name $printer.PortName -ErrorAction Stop
        return $port.PrinterHostAddress
    } catch {
        Write-Warning "Queue $Queue not found on $Server"
        return $null
    }
}

function Get-PrinterInfoFromIP {
    param([string]$IPAddress)

    # Liveness check
    $pingResult = Test-Connection -ComputerName $IPAddress -Count 1 -Quiet
    if (-not $pingResult) {
        return [PSCustomObject]@{
            IPAddress     = $IPAddress
            Status        = "Offline"
            MACAddress    = "N/A"
            SerialNumber  = "N/A"
            Source        = "Ping"
        }
    }

    # Attempt SNMP (requires snmpget in path)
    $macOID    = "1.3.6.1.2.1.2.2.1.6.1"
    $serialOID = "1.3.6.1.2.1.43.5.1.1.17.1"

    $snmpAvailable = Get-Command snmpget -ErrorAction SilentlyContinue
    if ($snmpAvailable) {
        $macRaw    = snmpget -v $SnmpVersion -c $Community $IPAddress $macOID 2>&1
        $serialRaw = snmpget -v $SnmpVersion -c $Community $IPAddress $serialOID 2>&1

        $mac = if ($macRaw -match "Hex-STRING: ([\dA-Fx ]+)") {
            ($matches[1] -split ' ') -join ':'
        } else { "Unavailable" }

        $serial = if ($serialRaw -match "STRING: (.+)") {
            $matches[1].Trim()
        } else { "Unavailable" }

        return [PSCustomObject]@{
            IPAddress     = $IPAddress
            Status        = "Online"
            MACAddress    = $mac
            SerialNumber  = $serial
            Source        = "SNMP"
        }
    }

    return [PSCustomObject]@{
        IPAddress     = $IPAddress
        Status        = "Online"
        MACAddress    = "Unavailable"
        SerialNumber  = "Unavailable"
        Source        = "No SNMP"
    }
}

# === Main Pipeline ===
$results = foreach ($q in $Queues) {
    $ip = Get-PrinterIPFromQueue -Server $PrintServer -Queue $q
    if ($ip) {
        $info = Get-PrinterInfoFromIP -IPAddress $ip
        [PSCustomObject]@{
            QueueName     = $q
            PrinterIP     = $info.IPAddress
            Status        = $info.Status
            MACAddress    = $info.MACAddress
            SerialNumber  = $info.SerialNumber
            Source        = $info.Source
        }
    } else {
        [PSCustomObject]@{
            QueueName     = $q
            PrinterIP     = "N/A"
            Status        = "Not Found"
            MACAddress    = "N/A"
            SerialNumber  = "N/A"
            Source        = "None"
        }
    }
}

# Export results
$outDir = Split-Path -Path $OutputPath -Parent
if ([string]::IsNullOrWhiteSpace($outDir)) { $outDir = (Get-Location).Path }
if (-not (Test-Path -Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$results | Tee-Object -Variable r | Format-Table -AutoSize
$results | Export-Csv -Path $OutputPath -NoTypeInformation
Write-Host "`nDone. Results saved to $OutputPath" -ForegroundColor Green