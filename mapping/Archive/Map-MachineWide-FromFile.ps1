<#  Map-MachineWide-FromFile.ps1
    - Reads a CSV or TXT of printer shares
    - Adds machine-wide connections with PrintUI /ga (idempotent)
    - Logs BEFORE and AFTER snapshots (+ installed queues)
    - Only maps when not already present machine-wide
    - No default-printer logic here (defaults are per-user)

    Accepted input formats:
      CSV with header "UNC"                 e.g. \\server\share
      CSV with headers "Server,Share"       e.g. SWBPNSHPS01V,LS111-WCC10
      TXT lines of \\server\share
      TXT lines of "server,share" or "server share"
#>

param(
  [string]$InputPath = 'C:\ProgramData\SysAdminSuite\Mapping\wcc_printers.csv',
  [string]$LogDir    = 'C:\ProgramData\SysAdminSuite\Mapping\logs',
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# ----- helpers -----
function Write-Log {
  param([string]$Message)
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line = "[$ts] $Message"
  Write-Host $line
  Add-Content -LiteralPath $script:LogPath -Value $line
}

function Get-GlobalPrinterUNCs {
  $base = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections'
  $out  = New-Object System.Collections.Generic.List[string]
  if (Test-Path $base) {
    foreach ($k in Get-ChildItem $base -ErrorAction SilentlyContinue) {
      try {
        $p = Get-ItemProperty -LiteralPath $k.PSPath
        if ($p.Server -and $p.Printer) {
          [void]$out.Add("\\$($p.Server)\$($p.Printer)")
        }
      } catch {}
    }
  }
  return $out | Sort-Object -Unique
}

function Parse-Targets([string]$Path) {
  if (!(Test-Path -LiteralPath $Path)) { throw "Input file not found: $Path" }
  $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
  $list = New-Object System.Collections.Generic.List[string]

  if ($ext -eq '.csv') {
    $rows = Import-Csv -LiteralPath $Path
    foreach ($r in $rows) {
      $props = $r.PSObject.Properties.Name
      $u = $null
      if ($props -contains 'UNC')            { $u = $r.UNC }
      elseif ($props -contains 'Path')       { $u = $r.Path }
      elseif ($props -contains 'Printer')    { $u = $r.Printer }
      elseif ($props -contains 'Server' -and $props -contains 'Share') { $u = "\\$($r.Server)\$($r.Share)" }
      else { $u = ($r.PSObject.Properties | Select-Object -First 1).Value }
      if ($u) { $u = $u.Trim() }
      if ($u -and $u -match '^[\\/]{2}.+\\.+$') { [void]$list.Add($u) }
    }
  }
  else {
    foreach ($line in Get-Content -LiteralPath $Path) {
      $t = ($line -replace '^\s*#.*$','').Trim()
      if (-not $t) { continue }
      if ($t -match '^[\\/]{2}.+\\.+$') { [void]$list.Add($t) ; continue }
      $parts = $t -split '[,\s]+' | Where-Object { $_ -ne '' }
      if ($parts.Count -ge 2) { [void]$list.Add("\\$($parts[0])\$($parts[1])") }
    }
  }

  return $list |
    ForEach-Object { $_.ToLowerInvariant() } |
    Sort-Object -Unique
}

# ----- prep & logging -----
if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$script:LogPath = Join-Path $LogDir ("MapPrinters_{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Write-Log "---- Map-MachineWide-FromFile.ps1 starting on $env:COMPUTERNAME ----"
Write-Log "Input: $InputPath"

$targets      = Parse-Targets -Path $InputPath
$beforeGlobal = Get-GlobalPrinterUNCs
Write-Log "BEFORE (machine-wide registered):"
$beforeGlobal | ForEach-Object { Write-Log "  $_" }
if (-not $beforeGlobal) { Write-Log "  (none)" }

# ----- plan -----
$toAdd = @()
foreach ($u in $targets) {
  if ($beforeGlobal -contains $u) { Write-Log "Already machine-wide: $u" }
  else { $toAdd += $u; Write-Log "Will add: $u" }
}

if ($WhatIf) {
  Write-Log "WHATIF mode: no changes will be made."
  Write-Log "---- Completed (WHATIF) ----"
  return
}

# ----- apply -----
foreach ($u in $toAdd) {
  Write-Log "Adding with PrintUI /ga : $u"
  $cmd = "rundll32 printui.dll,PrintUIEntry /ga /q /n `"$u`""
  $p   = Start-Process -FilePath cmd.exe -ArgumentList "/c $cmd" -Wait -PassThru -WindowStyle Hidden
  if ($p.ExitCode -ne 0) { Write-Log "WARN exit $($p.ExitCode) for $u" }
}

if ($toAdd.Count -gt 0) {
  Write-Log "Restarting Print Spooler to realize machine-wide connections..."
  Start-Process cmd.exe -ArgumentList '/c net stop spooler & net start spooler' -Wait -WindowStyle Hidden | Out-Null
} else {
  Write-Log "Nothing new to add; skipping spooler bounce."
}

# ----- after -----
$afterGlobal = Get-GlobalPrinterUNCs
$addedNow    = $afterGlobal | Where-Object { $beforeGlobal -notcontains $_ }

Write-Log "AFTER (machine-wide registered):"
$afterGlobal | ForEach-Object { Write-Log "  $_" }
if (-not $afterGlobal) { Write-Log "  (none)" }

Write-Log "ADDED in this run:"
$addedNow | ForEach-Object { Write-Log "  $_" }
if (-not $addedNow) { Write-Log "  (none)" }

try {
  $queues = Get-Printer | Select-Object Name,ShareName,DriverName,PortName
  Write-Log "Installed queues (Get-Printer):"
  foreach ($q in $queues) { Write-Log ("  {0}  [Share:{1}] [Driver:{2}] [Port:{3}]" -f $q.Name,$q.ShareName,$q.DriverName,$q.PortName) }
} catch {
  Write-Log "Get-Printer unavailable in this environment: $($_.Exception.Message)"
}

Write-Log "---- Completed successfully ----"
