#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Field-proven primitive: Get-Service cbdhsvc* | Restart-Service -Force
# Keep the implementation scoped to the per-user Windows Clipboard User Service.
if ($env:OS -ne 'Windows_NT') {
    Write-Error 'Clipboard reset is supported on Windows only.'
    exit 2
}

$services = @(Get-Service -Name 'cbdhsvc*' -ErrorAction SilentlyContinue)
if ($services.Count -eq 0) {
    Write-Error 'No Windows Clipboard User Service instance (cbdhsvc_*) was found for this session.'
    exit 3
}

$serviceNames = @($services | ForEach-Object { $_.Name })
Write-Host ("Restarting Clipboard User Service: {0}" -f ($serviceNames -join ', ')) -ForegroundColor Cyan

try {
    $services | Restart-Service -Force -ErrorAction Stop
    $verified = @(Get-Service -Name $serviceNames -ErrorAction Stop)
    $notRunning = @($verified | Where-Object { $_.Status -ne 'Running' })
    if ($notRunning.Count -gt 0) {
        $states = @($notRunning | ForEach-Object { '{0}={1}' -f $_.Name, $_.Status }) -join ', '
        Write-Error "Clipboard User Service restart did not return all instances to Running: $states"
        exit 4
    }
} catch {
    Write-Error ("Clipboard User Service restart failed: {0}" -f $_.Exception.Message)
    exit 1
}

Write-Host ("CLIPBOARD_RESET_OK: {0}" -f ($serviceNames -join ', ')) -ForegroundColor Green
exit 0
