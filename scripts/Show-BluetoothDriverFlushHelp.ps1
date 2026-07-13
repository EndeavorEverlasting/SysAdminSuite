#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-RunningAsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-RunningAsAdministrator)) {
  throw 'Run this from an elevated Command Prompt or through Run-BluetoothDriverFlushHelp.cmd.'
}

# Import the utility function
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$btFlushScript = Join-Path $repoRoot 'Utilities\Invoke-BluetoothDriverFlush.ps1'

if (-not (Test-Path -LiteralPath $btFlushScript -PathType Leaf)) {
  throw "Bluetooth flush script not found at: $btFlushScript"
}

# dot-source the utility
. $btFlushScript

function Show-Menu {
  Clear-Host
  Write-Host "==========================================================" -ForegroundColor Cyan
  Write-Host "         SysAdminSuite - Bluetooth Driver Flush Menu     " -ForegroundColor Cyan
  Write-Host "==========================================================" -ForegroundColor Cyan
  Write-Host "  1. Status / Help (Check services and PnP devices)"
  Write-Host "  2. WhatIf Preview (Preview what the flush will do)"
  Write-Host "  3. Backup Only (Backup Bluetooth state without flush)"
  Write-Host "  4. Open Latest Backup Folder"
  Write-Host "  5. Run Full Repair (Backup + Flush + Reset)" -ForegroundColor Yellow
  Write-Host "  6. Restore and Re-Pair Guidance"
  Write-Host "  7. Exit"
  Write-Host "==========================================================" -ForegroundColor Cyan
}

function Get-BluetoothStatus {
  Write-Host "`n--- Bluetooth Service Status ---" -ForegroundColor Cyan
  $services = @('bthserv', 'BthAudioHF', 'btwavext', 'RFCOMM', 'BthLEEnum')
  foreach ($svc in $services) {
    $status = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($status) {
      $color = if ($status.Status -eq 'Running') { 'Green' } else { 'Yellow' }
      Write-Host "  $svc : $($status.Status)" -ForegroundColor $color
    } else {
      Write-Host "  $svc : Not Installed" -ForegroundColor Red
    }
  }

  Write-Host "`n--- Bluetooth PnP Devices ---" -ForegroundColor Cyan
  try {
    $devices = Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue
    if ($devices) {
      foreach ($dev in $devices) {
        $color = if ($dev.Status -eq 'OK') { 'Green' } else { 'Yellow' }
        Write-Host "  $($dev.FriendlyName) [Status: $($dev.Status)]" -ForegroundColor $color
      }
    } else {
      Write-Host "  No Bluetooth PnP devices found." -ForegroundColor Yellow
    }
  } catch {
    Write-Host "  Could not query PnP devices: $($_.Exception.Message)" -ForegroundColor Red
  }
  Write-Host ""
}

function Open-LatestBackup {
  $backupRoot = Join-Path $env:APPDATA 'BT_Flush_Backups'
  if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
    Write-Host "`nNo backups folder found at $backupRoot" -ForegroundColor Yellow
    return
  }

  $latest = Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

  if ($latest) {
    Write-Host "`nOpening latest backup: $($latest.FullName)" -ForegroundColor Green
    explorer.exe "`"$($latest.FullName)`""
  } else {
    Write-Host "`nNo backup folders found under $backupRoot" -ForegroundColor Yellow
  }
}

function Show-Guidance {
  Write-Host "`n==========================================================" -ForegroundColor Cyan
  Write-Host "             RESTORE AND RE-PAIR GUIDANCE                 " -ForegroundColor Cyan
  Write-Host "==========================================================" -ForegroundColor Cyan
  Write-Host "  This utility backs up your Bluetooth state before making"
  Write-Host "  any changes. Backups are saved in:"
  Write-Host "    %APPDATA%\BT_Flush_Backups\<timestamp>"
  Write-Host ""
  Write-Host "  To restore a specific registry key from the backup:"
  Write-Host "    reg import <backup-folder>\<key-name>.reg"
  Write-Host "    Example: reg import %APPDATA%\BT_Flush_Backups\<timestamp>\bthport.reg"
  Write-Host ""
  Write-Host "  Re-Pairing Instructions:"
  Write-Host "    1. Open Settings > Bluetooth & devices"
  Write-Host "    2. Click 'Add device' > 'Bluetooth'"
  Write-Host "    3. Put your Bluetooth device (e.g. speaker) in pairing mode"
  Write-Host "    4. Select it when it appears in the list"
  Write-Host "==========================================================" -ForegroundColor Cyan
  Write-Host ""
}

# Main interactive loop
do {
  Show-Menu
  $choice = Read-Host "Select an option (1-7)"
  switch ($choice) {
    '1' {
      Get-BluetoothStatus
      Read-Host "Press Enter to return to menu..."
    }
    '2' {
      Write-Host "`n--- Running WhatIf Preview ---" -ForegroundColor Yellow
      Invoke-BluetoothDriverFlush -WhatIf
      Read-Host "`nPress Enter to return to menu..."
    }
    '3' {
      Write-Host "`n--- Running Backup Only ---" -ForegroundColor Cyan
      Invoke-BluetoothDriverFlush -BackupOnly
      Read-Host "`nPress Enter to return to menu..."
    }
    '4' {
      Open-LatestBackup
      Read-Host "`nPress Enter to return to menu..."
    }
    '5' {
      Write-Host "`n!!! WARNING !!!" -ForegroundColor Red
      Write-Host "This will reset the Bluetooth stack, remove paired devices," -ForegroundColor Red
      Write-Host "and delete cached Bluetooth driver packages." -ForegroundColor Red
      Write-Host "You will need to manually re-pair all Bluetooth devices afterwards." -ForegroundColor Red
      Write-Host "This operation must be confirmed by typing YES when prompted." -ForegroundColor Red
      Write-Host ""
      Invoke-BluetoothDriverFlush
      Read-Host "`nPress Enter to return to menu..."
    }
    '6' {
      Show-Guidance
      Read-Host "Press Enter to return to menu..."
    }
    '7' {
      Write-Host "Exiting..."
      break
    }
    default {
      Write-Host "Invalid option. Please try again." -ForegroundColor Red
      Start-Sleep -Seconds 1
    }
  }
} while ($choice -ne '7')
