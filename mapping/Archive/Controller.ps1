<#
Controller.ps1
-------------
Purpose:
- Dispatches Map-MachineWide-FromFile.ps1 + CSV to a list of target hosts
- Creates a scheduled task on each host to run the mapper as SYSTEM
- Fixes the Task Scheduler XML bug by using a valid StartBoundary (now + 1 minute)
- Collects per-host logs back to your local dev machine for centralized review
- Supports a -WhatIf switch for safe dry-run testing

Usage:
- Dry-run only (show actions, no changes):
    .\Controller.ps1 -WhatIf
- Actual run (deploy mapper + CSV, execute tasks, collect logs):
    .\Controller.ps1
#>

param(
  [switch]$WhatIf
)

# -------------------------
# 1. Build host list
# -------------------------
$targets = @()
$targets += 121..123 | ForEach-Object { "WLS111WCC$_" }
$targets += 126..132 | ForEach-Object { "WLS111WCC$_" }
$targets = $targets | Sort-Object -Unique

# -------------------------
# 2. Define local paths
# -------------------------
# Where your scripts/CSVs live — resolved relative to this script's directory
$localRoot   = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$localScript = Join-Path $localRoot "Map-MachineWide-FromFile.ps1"
$localCsv    = Join-Path $localRoot "wcc_printers.csv"

# -------------------------
# 3. Define remote paths
# -------------------------
# Remote drop point (non-intrusive, under ProgramData)
$remoteRoot  = "C$\ProgramData\SysAdminSuite\Mapping"

# -------------------------
# 4. Create central log archive for this controller run
# -------------------------
$sessionLogRoot = Join-Path $localRoot ("logs\controller-run-{0:yyyyMMdd-HHmmss}" -f (Get-Date))
New-Item -ItemType Directory -Path $sessionLogRoot -Force | Out-Null

# -------------------------
# 5. Loop through each target host
# -------------------------
foreach ($c in $targets) {
  $dst = "\\$c\$remoteRoot"

  try {
    # ---- connectivity check ----
    if (!(Test-Connection -ComputerName $c -Count 1 -Quiet)) {
      Write-Host "Skip $c (offline)"
      continue
    }

    # ---- dry-run mode ----
    if ($WhatIf) {
      Write-Host "[WhatIf] Would copy $localScript and $localCsv to $dst, run mapper, and collect logs"
      continue
    }

    # ---- ensure remote directory exists ----
    New-Item -ItemType Directory -Path $dst -Force | Out-Null

    # ---- copy mapper + CSV ----
    Copy-Item -LiteralPath $localScript,$localCsv -Destination $dst -Force

    # ---- schedule mapper via Task Scheduler ----
    # HOTFIX: Task Scheduler needs a valid StartBoundary.
    # Set StartBoundary = 1 minute in the future, in HH:mm format.
    $start = (Get-Date).AddMinutes(1).ToString("HH:mm")
    $tr = 'powershell -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\SysAdminSuite\Mapping\Map-MachineWide-FromFile.ps1"'

    # Create the scheduled task
    $createOut = cmd /c "schtasks /Create /S $c /RU SYSTEM /SC ONCE /ST $start /RL HIGHEST /TN SysAdminSuite_MapFromFile /TR `"$tr`" /F /Z" 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Error "schtasks /Create failed on $c (exit $LASTEXITCODE): $createOut"
      continue
    }

    # Run it immediately (don’t wait for the trigger time)
    $runOut = cmd /c "schtasks /Run /S $c /TN SysAdminSuite_MapFromFile" 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Error "schtasks /Run failed on $c (exit $LASTEXITCODE): $runOut"
      continue
    }
    Write-Host "Triggered $c"

    # ---- wait briefly for task to execute ----
    Start-Sleep -Seconds 10

    # ---- collect logs back from remote ----
    $remoteLogDir = "\\$c\C$\ProgramData\SysAdminSuite\Mapping\logs"
    if (Test-Path $remoteLogDir) {
      $hostLogDir = Join-Path $sessionLogRoot $c
      New-Item -ItemType Directory -Path $hostLogDir -Force | Out-Null
      Copy-Item -Path (Join-Path $remoteLogDir "*.log") -Destination $hostLogDir -Force -ErrorAction SilentlyContinue
      Write-Host "Collected logs from $c → $hostLogDir"
    } else {
      Write-Host "No logs found yet on $c"
    }

  } catch {
    Write-Host "Error $c : $($_.Exception.Message)"
  }
}

Write-Host "`nAll logs gathered under: $sessionLogRoot"
