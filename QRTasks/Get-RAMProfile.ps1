<#
.SYNOPSIS
    Quick local RAM profile: per-DIMM capacity, speed, type, part number.

.DESCRIPTION
    QR-optimized task script. Runs locally, no parameters needed.
    Pulls Win32_PhysicalMemory via CIM. Outputs a table to console
    and saves a text file to GetInfo\Output\QRTasks.

.NOTES
    Part of SysAdminSuite -- QRTasks extension module.
    Designed for PowerShell 5.1+.
    For multi-machine parallel RAM inventory, use GetInfo\Get-RamInfo.ps1 instead.
#>

$timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$_outDir   = Join-Path (Split-Path -Parent $PSScriptRoot) 'GetInfo\Output\QRTasks'
if (-not (Test-Path $_outDir)) { New-Item -ItemType Directory -Path $_outDir -Force | Out-Null }
$outFile   = Join-Path $_outDir "RAMProfile_$($env:COMPUTERNAME).txt"

function Resolve-MemoryType {
    param([int]$Code)
    switch ($Code) {
        20 { 'DDR' }   21 { 'DDR2' }  24 { 'DDR3' }
        26 { 'DDR4' }  34 { 'DDR5' }
        default { "Type$Code" }
    }
}

try {
    $sticks = Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop
} catch {
    Write-Warning "Failed to query RAM info: $_"
    return
}

if (-not $sticks) {
    Write-Warning 'No physical memory sticks reported.'
    return
}

$result = $sticks | ForEach-Object {
    [PSCustomObject]@{
        BankLabel            = $_.BankLabel
        DeviceLocator        = $_.DeviceLocator
        Manufacturer         = $_.Manufacturer
        PartNumber           = ($_.PartNumber -replace '\s+$', '')
        SerialNumber         = $_.SerialNumber
        CapacityGB           = [math]::Round($_.Capacity / 1GB, 2)
        Speed                = $_.Speed
        ConfiguredClockSpeed = $_.ConfiguredClockSpeed
        MemoryType           = Resolve-MemoryType $_.SMBIOSMemoryType
    }
}

# ── Console output ───────────────────────────────────────────────────
$totalGB = ($result | Measure-Object -Property CapacityGB -Sum).Sum

Write-Host "`n  === RAM Profile -- $env:COMPUTERNAME ===" -ForegroundColor Cyan
Write-Host "  Total: ${totalGB} GB across $($result.Count) stick(s)`n" -ForegroundColor White
$result | Format-Table -AutoSize | Out-Host

# ── Output file ──────────────────────────────────────────────────────
$header = "RAM Profile -- $env:COMPUTERNAME -- $timestamp"
$divider = '-' * $header.Length
@($header, $divider, "Total: ${totalGB} GB across $($result.Count) stick(s)", '') |
    Out-File -FilePath $outFile -Encoding UTF8
$result | Format-Table -AutoSize | Out-File -FilePath $outFile -Append -Encoding UTF8

Write-Host "  Saved to: $outFile" -ForegroundColor Green

