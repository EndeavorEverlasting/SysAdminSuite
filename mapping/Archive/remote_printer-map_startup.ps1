# Open an elevated PowerShell and run:
# BUG-FIX: Changed Bypass to RemoteSigned — Bypass is unnecessarily permissive
# Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
# .\remote_printer-map_startup.ps1

$Hosts = "WEL082MST051","WEL082MST052","WEL082MST053","WEL082MST054","WEL082MST063"
$File  = Join-Path $PSScriptRoot "Map-EL082-All.vbs"

# BUG-FIX: Validate that the source file exists before attempting any copies
if (-not (Test-Path -LiteralPath $File)) {
  Write-Error "Source file not found: $File"
  exit 1
}

# BUG-FIX: Added reachability check, confirmation prompt, and per-host error handling
$reachable = $Hosts | Where-Object { Test-Connection -ComputerName $_ -Count 1 -Quiet -ErrorAction SilentlyContinue }
if (-not $reachable) {
  Write-Error "No hosts are reachable. Aborting."
  exit 1
}

Write-Host "Will copy '$File' to Startup on: $($reachable -join ', ')"
$confirm = Read-Host "Proceed? (y/N)"
if ($confirm -notmatch '^[Yy]') {
  Write-Host "Aborted by user."
  exit 0
}

foreach ($h in $reachable) {
  $startup = "\\$h\C$\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
  try {
    Copy-Item -LiteralPath $File -Destination $startup -Force -ErrorAction Stop
    Write-Host "OK -> $h"
  } catch {
    Write-Error "FAILED -> $h ($startup): $($_.Exception.Message)"
  }
}
