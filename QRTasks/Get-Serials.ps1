<#
.SYNOPSIS
    Quick local serial number collector: BIOS, system product, monitors.

.DESCRIPTION
    QR-optimized task script. Runs locally, no parameters needed.
    Pulls BIOS serial, system product identifying number, and monitor
    serials (via WmiMonitorID). Outputs to console and saves to GetInfo\Output\QRTasks.

.NOTES
    Part of SysAdminSuite -- QRTasks extension module.
    Designed for PowerShell 5.1+.
    For multi-machine parallel serial collection, use GetInfo\Get-MachineInfo.ps1 instead.
#>

$timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$_outDir   = Join-Path (Split-Path -Parent $PSScriptRoot) 'GetInfo\Output\QRTasks'
if (-not (Test-Path $_outDir)) { New-Item -ItemType Directory -Path $_outDir -Force | Out-Null }
$outFile   = Join-Path $_outDir "Serials_$($env:COMPUTERNAME).txt"

# ── BIOS serial ──────────────────────────────────────────────────────
try {
    $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
    $biosSerial = $bios.SerialNumber
} catch {
    $biosSerial = "Error: $_"
}

# ── System product ───────────────────────────────────────────────────
try {
    $product = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop
    $productID = $product.IdentifyingNumber
    $productName = $product.Name
} catch {
    $productID = "Error: $_"
    $productName = ''
}

# ── Monitor serials ──────────────────────────────────────────────────
$monitorSerials = @()
try {
    $monitors = Get-WmiObject -Namespace root\wmi -Class WmiMonitorID -ErrorAction Stop
    if ($monitors) {
        $monitorSerials = $monitors | ForEach-Object {
            $sn = ($_.SerialNumberID | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ''
            $mfg = ($_.ManufacturerName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ''
            $model = ($_.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ''
            [PSCustomObject]@{
                Manufacturer = $mfg
                Model        = $model
                Serial       = $sn
            }
        } | Where-Object { $_.Serial -and $_.Serial.Trim() -ne '' }
    }
} catch { }

# ── Output ───────────────────────────────────────────────────────────
Write-Host "`n  === Serials -- $env:COMPUTERNAME ===" -ForegroundColor Cyan
Write-Host "  BIOS Serial    : $biosSerial" -ForegroundColor White
Write-Host "  Product ID     : $productID" -ForegroundColor White
Write-Host "  Product Name   : $productName" -ForegroundColor White

if ($monitorSerials.Count -gt 0) {
    Write-Host "`n  Monitors:" -ForegroundColor Cyan
    $monitorSerials | Format-Table -AutoSize | Out-Host
} else {
    Write-Host "  Monitors       : none detected or no serials" -ForegroundColor DarkGray
}

# ── Output file ──────────────────────────────────────────────────────
$lines = @(
    "Serials -- $env:COMPUTERNAME -- $timestamp"
    ('-' * 50)
    "BIOS Serial    : $biosSerial"
    "Product ID     : $productID"
    "Product Name   : $productName"
    ''
)

if ($monitorSerials.Count -gt 0) {
    $lines += 'Monitors:'
}

$lines | Out-File -FilePath $outFile -Encoding UTF8
if ($monitorSerials.Count -gt 0) {
    $monitorSerials | Format-Table -AutoSize | Out-File -FilePath $outFile -Append -Encoding UTF8
}

Write-Host "`n  Saved to: $outFile" -ForegroundColor Green

