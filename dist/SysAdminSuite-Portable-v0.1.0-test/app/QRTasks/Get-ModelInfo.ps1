<#
.SYNOPSIS
    Quick local machine identity: manufacturer, model, name, serial, motherboard.

.DESCRIPTION
    QR-optimized task script. Runs locally, no parameters needed.
    Pulls system identity from Win32_ComputerSystem, Win32_ComputerSystemProduct,
    and Win32_BaseBoard via CIM. Outputs to console and saves to GetInfo\Output\QRTasks.

.NOTES
    Part of SysAdminSuite -- QRTasks extension module.
    Designed for PowerShell 5.1+.
#>

$timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$_outDir   = Join-Path (Split-Path -Parent $PSScriptRoot) 'GetInfo\Output\QRTasks'
if (-not (Test-Path $_outDir)) { New-Item -ItemType Directory -Path $_outDir -Force | Out-Null }
$outFile   = Join-Path $_outDir "ModelInfo_$($env:COMPUTERNAME).txt"

try {
    $cs   = Get-CimInstance Win32_ComputerSystem       | Select-Object Manufacturer, Model, Name
    $csp  = Get-CimInstance Win32_ComputerSystemProduct | Select-Object Vendor, Name, IdentifyingNumber
    $bb   = Get-CimInstance Win32_BaseBoard             | Select-Object Manufacturer, Product, SerialNumber
    $bios = Get-CimInstance Win32_BIOS                  | Select-Object SerialNumber, SMBIOSBIOSVersion

    $result = [PSCustomObject]@{
        Timestamp           = $timestamp
        ComputerName        = $cs.Name
        Manufacturer        = $cs.Manufacturer
        Model               = $cs.Model
        ProductVendor       = $csp.Vendor
        ProductName         = $csp.Name
        ProductID           = $csp.IdentifyingNumber
        BIOSSerial          = $bios.SerialNumber
        BIOSVersion         = $bios.SMBIOSBIOSVersion
        BoardManufacturer   = $bb.Manufacturer
        BoardProduct        = $bb.Product
        BoardSerial         = $bb.SerialNumber
    }
} catch {
    Write-Warning "Failed to query system info: $_"
    return
}

# ── Output ───────────────────────────────────────────────────────────
Write-Host "`n  === Model / Identity Info ===" -ForegroundColor Cyan
$result | Format-List | Out-Host

$lines = @(
    "Model / Identity Info -- $timestamp"
    "Computer Name       : $($result.ComputerName)"
    "Manufacturer        : $($result.Manufacturer)"
    "Model               : $($result.Model)"
    "Product Vendor      : $($result.ProductVendor)"
    "Product Name        : $($result.ProductName)"
    "Product ID          : $($result.ProductID)"
    "BIOS Serial         : $($result.BIOSSerial)"
    "BIOS Version        : $($result.BIOSVersion)"
    "Board Manufacturer  : $($result.BoardManufacturer)"
    "Board Product       : $($result.BoardProduct)"
    "Board Serial        : $($result.BoardSerial)"
)

$lines | Out-File -FilePath $outFile -Encoding UTF8
Write-Host "  Saved to: $outFile" -ForegroundColor Green

# ── HTML output ─────────────────────────────────────────────────────
$suiteHtmlHelper = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\ConvertTo-SuiteHtml.ps1'
if (Test-Path -LiteralPath $suiteHtmlHelper) {
    . $suiteHtmlHelper
    $htmlPath = [IO.Path]::ChangeExtension($outFile, '.html')
    $result | ConvertTo-Html -Fragment -PreContent '<h2>System Identity</h2>' |
        ConvertTo-SuiteHtml -Title "Model Info - $($result.ComputerName)" -Subtitle $result.ComputerName -OutputPath $htmlPath
}

