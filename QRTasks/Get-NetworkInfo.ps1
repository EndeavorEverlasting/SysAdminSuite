<#
.SYNOPSIS
    Quick local network snapshot: active adapters, IPs, MACs, gateway, DNS.

.DESCRIPTION
    QR-optimized task script. Runs locally, no parameters needed.
    Queries Win32_NetworkAdapterConfiguration for IP-enabled adapters.
    Outputs to console and saves to GetInfo\Output\QRTasks.

.NOTES
    Part of SysAdminSuite -- QRTasks extension module.
    Designed for PowerShell 5.1+.
#>

$timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$_outDir   = Join-Path (Split-Path -Parent $PSScriptRoot) 'GetInfo\Output\QRTasks'
if (-not (Test-Path $_outDir)) { New-Item -ItemType Directory -Path $_outDir -Force | Out-Null }
$outFile   = Join-Path $_outDir "NetworkInfo_$($env:COMPUTERNAME).txt"

try {
    $nics = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=TRUE" -ErrorAction Stop
} catch {
    Write-Warning "Failed to query network info: $_"
    return
}

if (-not $nics) {
    Write-Warning 'No IP-enabled adapters found.'
    return
}

$result = $nics | ForEach-Object {
    $ipv4 = ($_.IPAddress | Where-Object { $_ -match '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' }) -join '; '
    $ipv6 = ($_.IPAddress | Where-Object { $_ -match ':' }) -join '; '

    [PSCustomObject]@{
        Description    = $_.Description
        MACAddress     = $_.MACAddress
        IPv4           = $ipv4
        IPv6           = $ipv6
        Gateway        = ($_.DefaultIPGateway -join '; ')
        DNSServers     = ($_.DNSServerSearchOrder -join '; ')
        DHCPEnabled    = $_.DHCPEnabled
        DHCPServer     = $_.DHCPServer
        DNSDomain      = $_.DNSDomain
    }
}

# ── Console output ───────────────────────────────────────────────────
Write-Host "`n  === Network Info -- $env:COMPUTERNAME ===" -ForegroundColor Cyan
Write-Host "  Active adapters: $($result.Count)`n" -ForegroundColor White
$result | Format-List | Out-Host

# ── Output file ──────────────────────────────────────────────────────
$header = "Network Info -- $env:COMPUTERNAME -- $timestamp"
$divider = '-' * $header.Length
@($header, $divider, '') | Out-File -FilePath $outFile -Encoding UTF8
$result | Format-List | Out-File -FilePath $outFile -Append -Encoding UTF8

Write-Host "  Saved to: $outFile" -ForegroundColor Green

