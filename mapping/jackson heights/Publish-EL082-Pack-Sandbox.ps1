<#
Publish-EL082-Pack-Sandbox.ps1
- Sandbox-enabled version of Publish-EL082-Pack.ps1
- Can deploy to remote computers OR create local sandbox directories
- When -SandboxRoot is specified, creates local directory structure instead of remote deployment
- Copies CSVs to local sandbox directories (no remote deployment)
- Optional: installs per-user default script into local sandbox All Users Startup
- Optional: creates local task files for simulation
- Shows progress locally; can pause for a keypress before closing

Requires on your admin box (same folder as this script):
  - el082_printers.csv
  - el082_defaults.csv
If using -MapNow:
  - Map-EL082-MachineWide.ps1
If using -InstallDefaultAtLogon:
  - Set-EL082-Default-FromCSV.vbs
#>

[CmdletBinding()]
param(
  # Targets: edit or pass your own list at runtime
  [string[]] $ComputerName = @(
    'WEL082MST051','WEL082MST052','WEL082MST053','WEL082MST054',
    'WEL082MST055','WEL082MST056','WEL082MST057','WEL082MST058',
    'WEL082MST060','WEL082MST061','WEL082MST062','WEL082MST063',
    'WEL082MST066','WEL082MST067'
  ),

  # Local file locations (next to this script by default)
  [string] $PrintersCsv = "$PSScriptRoot\el082_printers.csv",
  [string] $DefaultsCsv = "$PSScriptRoot\el082_defaults.csv",
  [string] $MapScript   = "$PSScriptRoot\Map-EL082-MachineWide.ps1",
  [string] $UserVbs     = "$PSScriptRoot\Set-EL082-Default-FromCSV.vbs",

  # Sandbox mode: if specified, creates local directory structure instead of remote deployment
  [string] $SandboxRoot = $null,

  # Actions
  [switch] $MapNow,                  # run machine-wide /ga now (via one-shot SYSTEM task) or create task file in sandbox
  [switch] $InstallDefaultAtLogon,   # drop the per-user default VBS into All Users Startup
  [switch] $PauseAtEnd               # ask for keypress before closing
)

$ErrorActionPreference = 'Stop'

# --- Verify local inputs ---
foreach ($p in @($PrintersCsv,$DefaultsCsv)) {
  if (!(Test-Path -LiteralPath $p)) { throw "Missing required file: $p" }
}
if ($MapNow -and !(Test-Path -LiteralPath $MapScript)) {
  throw "Missing Map script (required with -MapNow): $MapScript"
}
if ($InstallDefaultAtLogon -and !(Test-Path -LiteralPath $UserVbs)) {
  throw "Missing per-user default script (required with -InstallDefaultAtLogon): $UserVbs"
}

# --- Helpers ---
function _ProgDataEL082([string]$c){ 
  if ($SandboxRoot) {
    return Join-Path (Join-Path $SandboxRoot $c) "C$\ProgramData\EL082"
  } else {
    return "\\$c\C$\ProgramData\EL082"
  }
}

function _StartupPath([string]$c){ 
  if ($SandboxRoot) {
    return Join-Path (Join-Path $SandboxRoot $c) "C$\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
  } else {
    return "\\$c\C$\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
  }
}

function _CopyIfChanged($src, $dst) {
  if (!(Test-Path $dst)) { Copy-Item -LiteralPath $src -Destination $dst -Force; return $true }
  try {
    $h1 = (Get-FileHash -Algorithm SHA256 -LiteralPath $src).Hash
    $h2 = (Get-FileHash -Algorithm SHA256 -LiteralPath $dst).Hash
    if ($h1 -ne $h2) { Copy-Item -LiteralPath $src -Destination $dst -Force; return $true }
    return $false
  } catch {
    # Some hosts may lack Get-FileHash over UNC; just force copy
    Copy-Item -LiteralPath $src -Destination $dst -Force; return $true
  }
}

# --- Work loop ---
$results = [System.Collections.Generic.List[object]]::new()
$total   = [math]::Max($ComputerName.Count,1)
$idx     = 0

foreach ($c in $ComputerName) {
  $idx++
  Write-Progress -Activity "Publishing EL082 pack" -Status "$c ($idx/$total)" -PercentComplete ((($idx-1)/$total)*100)

  $row = [pscustomobject]@{
    Host      = $c
    Reachable = $false
    CsvsPushed= $false
    DefaultVbs= $false
    MapTask   = $false
    Notes     = ''
  }

  try {
    # In sandbox mode, skip connectivity test
    if ($SandboxRoot) {
      $row.Reachable = $true
    } else {
      if (!(Test-Connection -ComputerName $c -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
        $row.Notes = 'offline/unreachable'; $results.Add($row); continue
      }
      $row.Reachable = $true
    }

    # Ensure C:\ProgramData\EL082\ exists
    $pd = _ProgDataEL082 $c
    if (!(Test-Path $pd)) { New-Item -ItemType Directory -Path $pd -Force | Out-Null }

    # Push CSVs (only if changed)
    $pushed1 = _CopyIfChanged $PrintersCsv (Join-Path $pd 'el082_printers.csv')
    $pushed2 = _CopyIfChanged $DefaultsCsv (Join-Path $pd 'el082_defaults.csv')
    $row.CsvsPushed = ($pushed1 -or $pushed2)

    # Install per-user default script to All Users Startup
    if ($InstallDefaultAtLogon) {
      $startup = _StartupPath $c
      if (!(Test-Path $startup)) { New-Item -ItemType Directory -Path $startup -Force | Out-Null }
      _CopyIfChanged $UserVbs (Join-Path $startup 'Set-EL082-Default-FromCSV.vbs') | Out-Null
      $row.DefaultVbs = $true
    }

    # Handle machine-wide mapping
    if ($MapNow) {
      $remoteMap = 'C:\ProgramData\EL082\Map-EL082-MachineWide.ps1'
      _CopyIfChanged $MapScript (Join-Path $pd 'Map-EL082-MachineWide.ps1') | Out-Null
      
      if ($SandboxRoot) {
        # In sandbox mode, create a task file instead of running actual task
        $taskFile = Join-Path (Join-Path $SandboxRoot $c) "EL082_MapAll_Task.txt"
        $taskContent = @"
# Simulated task for sandbox mode
# Original command would be:
# schtasks /Create /S $c /RU SYSTEM /SC ONCE /ST 00:00 /RL HIGHEST /TN EL082_MapAll /TR "powershell -NoProfile -ExecutionPolicy Bypass -File `"$remoteMap`"" /F /Z
# schtasks /Run /S $c /TN EL082_MapAll

# Task would execute: powershell -NoProfile -ExecutionPolicy Bypass -File "$remoteMap"
"@
        Set-Content -Path $taskFile -Value $taskContent -Force
        $row.MapTask = $true
        $row.Notes = 'sandbox mode - task file created'
      } else {
        # Real deployment mode
        $tr = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$remoteMap`""
        cmd /c "schtasks /Create /S $c /RU SYSTEM /SC ONCE /ST 00:00 /RL HIGHEST /TN EL082_MapAll /TR `"$tr`" /F /Z" | Out-Null
        cmd /c "schtasks /Run /S $c /TN EL082_MapAll" | Out-Null
        $row.MapTask = $true
      }
    }

    $results.Add($row)

  } catch {
    $row.Notes = $_.Exception.Message
    $results.Add($row)
  }
}

Write-Progress -Activity "Publishing EL082 pack" -Completed

# --- Results ---
Write-Host "`nEL082 Pack Deployment Results:" -ForegroundColor Cyan
$results | Format-Table -AutoSize

if ($SandboxRoot) {
  Write-Host "`nSandbox mode enabled. Files deployed to: $SandboxRoot" -ForegroundColor Yellow
}

if ($PauseAtEnd) {
  Write-Host "`nPress any key to continue..." -ForegroundColor Gray
  $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
} 