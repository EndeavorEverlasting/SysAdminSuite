param(
  [string] $PrintersCsv = 'C:\ProgramData\EL082\el082_printers.csv',
  [string] $PrunePrefix = 'EL082-',
  [switch] $Simulate,                          # <-- NEW: no real changes; write manifest instead
  [string] $RemoteRoot = 'C:'                  # <-- NEW: when Simulate, points at sandbox host root, e.g. .\sandbox\WEL082MST055\C$
)
$ErrorActionPreference = 'Stop'

function _Join($root, $rel) { Join-Path $root $rel }

# Resolve CSV path (supports sandbox when -RemoteRoot is used)
$CsvPath = if ($Simulate) { _Join $RemoteRoot 'ProgramData\EL082\el082_printers.csv' } else { $PrintersCsv }
if (!(Test-Path -LiteralPath $CsvPath)) { if ($Simulate) { exit 0 } else { throw "Missing $CsvPath" } }

$rows = Import-Csv -LiteralPath $CsvPath
if (!$rows) { if ($Simulate) { exit 0 } else { throw "No rows in $CsvPath" } }

# Build target UNC set
$targets = [System.Collections.Generic.HashSet[string]]::new()
foreach ($r in $rows) {
  $server = $r.Server.Trim(); $share = $r.Share.Trim()
  if ($server -and $share) { $null = $targets.Add("\\$server\$share") }
}

if ($Simulate) {
  # --- Sandbox manifest: what WOULD happen ---
  $simDir = _Join $RemoteRoot 'ProgramData\EL082\sim'
  New-Item -ItemType Directory -Path $simDir -Force | Out-Null
  $manifest = [ordered]@{
    printers     = @($targets)
    actions      = @()
    prunePrefix  = $PrunePrefix
    spoolerBounce= $true
    timestamp    = (Get-Date).ToString('s')
  }
  foreach ($unc in $targets) { $manifest.actions += "ADD /ga $unc" }

  # Optional prune (compute only)
  $manifest.pruned = @()
  if ($PrunePrefix) {
    # In simulate, pretend current installed = none
    # (or store some mock state if you want to test prune logic deeper)
    $manifest.pruned = @()   # nothing
  }

  $json = $manifest | ConvertTo-Json -Depth 5
  Set-Content -Path (_Join $simDir 'manifest.json') -Value $json -Encoding UTF8
  # Also write a human-readable preview
  $preview = @()
  $preview += "== Simulated Map (no changes) =="
  $preview += "CSV: $CsvPath"
  $preview += "Would ADD (/ga):"
  $preview += $targets
  $preview += ""
  $preview += "Would RESTART Spooler: Yes"
  $preview += "Would PRUNE prefix '$PrunePrefix': none"
  Set-Content -Path (_Join $simDir 'preview.txt') -Value ($preview -join [Environment]::NewLine) -Encoding UTF8
  exit 0
}

# --- REAL mode below ---
foreach ($unc in $targets) {
  Start-Process cmd.exe "/c rundll32 printui.dll,PrintUIEntry /ga /q /n `"$unc`"" -WindowStyle Hidden -Wait
}

# Optional prune (real)
try {
  if ($PrunePrefix) {
    $installed = Get-Printer | Where-Object { $_.Name -like "$PrunePrefix*" } | Select-Object -ExpandProperty Name
    foreach ($name in $installed) {
      $match = $false
      foreach ($unc in $targets) {
        if ($unc.Split('\')[-1] -eq $name) { $match = $true; break }
      }
      if (-not $match) {
        $server = $rows[0].Server
        Start-Process cmd.exe "/c rundll32 printui.dll,PrintUIEntry /gd /q /n `"`\\$server\$name`"" -WindowStyle Hidden -Wait
      }
    }
  }
} catch {}

Start-Process cmd.exe "/c net stop spooler & net start spooler" -WindowStyle Hidden -Wait

# Ensure future profiles keep their default (no auto-switch)
$base = 'Registry::HKEY_USERS\.DEFAULT\Software\Microsoft\Windows NT\CurrentVersion\Windows'
New-Item -Path $base -Force | Out-Null
New-ItemProperty -Path $base -Name LegacyDefaultPrinterMode -PropertyType DWord -Value 1 -Force | Out-Null
