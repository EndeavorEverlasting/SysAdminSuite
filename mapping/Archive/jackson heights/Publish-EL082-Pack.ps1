<#
Publish-EL082-Pack.ps1
- Copies CSVs to C:\ProgramData\EL082 on each host (no manual Explorer)
- Optional: installs per-user default script into All Users Startup
- Optional: triggers a one-shot SYSTEM task to run the machine-wide /ga mapper NOW
- Shows progress locally; can pause for a keypress before closing
- Leaves no logs/markers/usernames on the remotes

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

  # Actions
  [switch] $MapNow,                  # run machine-wide /ga now (via one-shot SYSTEM task)
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
function _ProgDataEL082([string]$c){ "\\$c\C$\ProgramData\EL082" }
function _StartupPath([string]$c){ "\\$c\C$\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup" }

function _CopyIfChanged($src, $dst) {
  # BUG-FIX: Use -LiteralPath for Test-Path to match Copy-Item/Get-FileHash behavior
  if (!(Test-Path -LiteralPath $dst)) { Copy-Item -LiteralPath $src -Destination $dst -Force; return $true }
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
    if (!(Test-Connection -ComputerName $c -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
      $row.Notes = 'offline/unreachable'; $results.Add($row); continue
    }
    $row.Reachable = $true

    # Ensure C:\ProgramData\EL082\ exists
    # BUG-FIX: Use -LiteralPath for Test-Path and New-Item to handle UNC paths correctly
    $pd = _ProgDataEL082 $c
    if (!(Test-Path -LiteralPath $pd)) { New-Item -ItemType Directory -LiteralPath $pd -Force | Out-Null }

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

    # Trigger machine-wide /ga now (one-shot SYSTEM task; auto-deletes with /Z)
    if ($MapNow) {
      # BUG-FIX: Validate $c against a strict hostname pattern to prevent command injection
      if ($c -notmatch '^[A-Za-z0-9\-\.]+$') {
        throw "Invalid hostname '$c' — skipping to prevent command injection."
      }
      $remoteMap = 'C:\ProgramData\EL082\Map-EL082-MachineWide.ps1'
      _CopyIfChanged $MapScript (Join-Path $pd 'Map-EL082-MachineWide.ps1') | Out-Null
      # BUG-FIX: Use single quotes for -File path to avoid nested double-quote parsing errors
      $tr = "powershell -NoProfile -ExecutionPolicy Bypass -File '$remoteMap'"
      # BUG-FIX: Call schtasks.exe directly (not via cmd /c) and check exit codes
      $createOut = & schtasks.exe /Create /S $c /RU SYSTEM /SC ONCE /ST 00:00 /RL HIGHEST /TN EL082_MapAll /TR $tr /F /Z 2>&1
      if ($LASTEXITCODE -ne 0) {
        throw "schtasks /Create failed (exit $LASTEXITCODE): $createOut"
      }
      # BUG-FIX: Only set MapTask = $true when both Create and Run succeed
      $runOut = & schtasks.exe /Run /S $c /TN EL082_MapAll 2>&1
      if ($LASTEXITCODE -ne 0) {
        throw "schtasks /Run failed (exit $LASTEXITCODE): $runOut"
      }
      $row.MapTask = $true
    }

  } catch {
    $row.Notes = $_.Exception.Message
  }

  $results.Add($row)
}

Write-Progress -Activity "Publishing EL082 pack" -Completed
$results | Sort-Object Host | Format-Table -Auto Host,Reachable,CsvsPushed,DefaultVbs,MapTask,Notes

if ($PauseAtEnd) {
  Write-Host "`nPress any key to continue..."
  $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
