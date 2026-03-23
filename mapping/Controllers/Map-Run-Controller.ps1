<# =========================
 SysAdminSuite - Printer Map Controller
 Robust remote scheduler + artifact collector
 - Fixes schtasks EndBoundary error (/SC ONCE + /Z) by removing /Z and adding /SD
 - Uses -File in /TR to avoid 261-char command limit
 - Uses absolute path to powershell.exe (PS5.1) by default
 - Polls remote logs and collects immediately when ready
 - Best-effort cleanup of task and remote crumbs
 - Graceful Ctrl+C: partial results kept, summary printed

 Usage examples:
   .\controller.ps1 -Computers WKS001,WKS002
   .\controller.ps1 -ComputerFile .\hosts.txt
   .\controller.ps1 -LocalScriptPath .\Map-Remote-MachineWide-Printers.ps1

 Requirements:
   - Admin rights to targets (admin shares C$ accessible)
   - Task Scheduler service running on targets
 ========================= #>

 [CmdletBinding()]
 param(
   [string[]]$Computers,
 
   [string]$ComputerFile,
 
   # Local path to the remote payload script you want to run on each host:
   [string]$LocalScriptPath = ".\Map-Remote-MachineWide-Printers.ps1",
 
   # Where to store this runΓÇÖs outputs on the controller:
   [string]$SessionRoot = (Join-Path -Path (Get-Location) -ChildPath ("SysAdminSuite-Session-{0:yyyyMMdd-HHmmss}" -f (Get-Date))),
 
   # PowerShell path on endpoints (PS5.1 is broadly available on enterprise images)
   [string]$RemotePwshPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
 
   # Remote base folder for payload + logs
   [string]$RemoteBase = "C:\ProgramData\SysAdminSuite\Mapping",
 
   # Task name (per host)
   [string]$TaskName = "SysAdminSuite_PrinterMap",
 
   # Max seconds to wait for artifacts before moving on
   [int]$MaxWaitSeconds = 45
 )
 
 Set-StrictMode -Version Latest
 $ErrorActionPreference = 'Stop'
 
 # ---------------------------
 # Setup output directories
 # ---------------------------
 New-Item -ItemType Directory -Force -Path $SessionRoot | Out-Null
 $ControllerLog = Join-Path $SessionRoot 'controller-log.txt'
 "[$(Get-Date -Format s)] Session start ΓåÆ $SessionRoot" | Out-File -FilePath $ControllerLog -Encoding utf8
 
 function Write-Log {
   param([string]$Message)
   $stamp = "[{0}] {1}" -f (Get-Date -Format s), $Message
   Write-Host $stamp
   $stamp | Out-File -FilePath $ControllerLog -Encoding utf8 -Append
 }
 
 # ---------------------------
 # Resolve computer list
 # ---------------------------
 if (-not $Computers -and $ComputerFile) {
   if (-not (Test-Path $ComputerFile)) {
     throw "ComputerFile not found: $ComputerFile"
   }
   $Computers = Get-Content -Path $ComputerFile | Where-Object { $_ -and $_.Trim() -notmatch '^\s*#' } | ForEach-Object { $_.Trim() }
 }
 if (-not $Computers -or $Computers.Count -eq 0) {
   $defaultFile = ".\computers.txt"
   if (Test-Path $defaultFile) {
     $Computers = Get-Content $defaultFile | Where-Object { $_ -and $_.Trim() -notmatch '^\s*#' } | ForEach-Object { $_.Trim() }
   } else {
     throw "No computers provided. Pass -Computers or -ComputerFile (or provide .\computers.txt)."
   }
 }
 
 # ---------------------------
 # Validate payload
 # ---------------------------
 if (-not (Test-Path $LocalScriptPath)) {
   throw "LocalScriptPath not found: $LocalScriptPath"
 }
 
 # ---------------------------
 # Ctrl+C graceful handling
 # ---------------------------
 $script:StopRequested = $false
 $null = Register-EngineEvent -SourceIdentifier Console_CancelKeyPress -Action {
   $script:StopRequested = $true
   'CTRL+C detected. Will stop after current host.' | Out-File -FilePath $ControllerLog -Append -Encoding utf8
   Write-Host "`nCTRL+C detected ΓÇö finishing current host, then exitingΓÇª`n"
 }
 
 # Utility: join admin share path
 function Join-AdminShare {
   param([string]$Computer, [string]$SubPath)
   "\\{0}\C$\{1}" -f $Computer, ($SubPath -replace '^[cC]:\\', '') -replace '^[\\]+',''
 }
 
 # ---------------------------
 # Core per-host routine
 # ---------------------------
 function Invoke-Host {
   param([string]$Computer)
 
   Write-Log "==== [$Computer] Begin ===="
 
   $remoteBase    = $RemoteBase
   $remoteLogsDir = Join-Path $remoteBase 'logs'
   $remoteScript  = Join-Path $remoteBase (Split-Path -Leaf $LocalScriptPath)
 
   $adminBase     = Join-AdminShare -Computer $Computer -SubPath $remoteBase
   $adminLogs     = Join-AdminShare -Computer $Computer -SubPath $remoteLogsDir
   $adminScript   = Join-AdminShare -Computer $Computer -SubPath $remoteScript
 
   # Ensure remote folders exist via admin share
   try {
     if (-not (Test-Path $adminBase)) {
       New-Item -ItemType Directory -Force -Path $adminBase | Out-Null
       Write-Log "[$Computer] Created remote base: $adminBase"
     }
     if (-not (Test-Path $adminLogs)) {
       New-Item -ItemType Directory -Force -Path $adminLogs | Out-Null
       Write-Log "[$Computer] Created remote logs: $adminLogs"
     }
   } catch {
     Write-Log "[$Computer] ERROR creating remote folders: $($_.Exception.Message)"
     return
   }
 
   # Copy payload script
   try {
     Copy-Item -Path $LocalScriptPath -Destination $adminScript -Force
     Write-Log "[$Computer] Copied script ΓåÆ $adminScript"
   } catch {
     Write-Log "[$Computer] ERROR copying script: $($_.Exception.Message)"
     return
   }
 
   # ----- Robust schedule + run + poll + collect + cleanup -----
   $when   = (Get-Date).AddMinutes(1)
   $stTime = $when.ToString('HH:mm')        # 24h
   $stDate = $when.ToString('MM/dd/yyyy')   # schtasks likes US dates
 
   # Build schtasks /Create (drop /Z; add /SD; -File keeps /TR short)
   $createCmd = @(
     'schtasks',
     '/Create',
     '/S', $Computer,
     '/RU', 'SYSTEM',
     '/SC', 'ONCE',
     '/SD', $stDate,
     '/ST', $stTime,
     '/TN', $TaskName,
     '/TR', ('"{0} -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File {1}"' -f $RemotePwshPath, $remoteScript),
     '/RL', 'HIGHEST',
     '/F'
   ) -join ' '
 
   $createOut = cmd /c $createCmd 2>&1
   Write-Log "[$Computer] schtasks /Create output:`n$createOut"
 
   # Start it
   $runOut = cmd /c ("schtasks /Run /S {0} /TN {1}" -f $Computer, $TaskName) 2>&1
   Write-Log "[$Computer] schtasks /Run output:`n$runOut"
 
   # Poll for newest log bundle
   $maxWait = [Math]::Max(5, $MaxWaitSeconds)
   $waited  = 0
   $latest  = $null
   while ($waited -lt $maxWait) {
     try {
       if (Test-Path $adminLogs) {
         $latest = Get-ChildItem -Path $adminLogs -Directory -ErrorAction SilentlyContinue |
                   Sort-Object Name -Descending | Select-Object -First 1
         if ($latest) { break }
       }
     } catch { }
     Start-Sleep -Seconds 3
     $waited += 3
   }
 
   if ($latest) {
     $hostOut = Join-Path $SessionRoot $Computer
     New-Item -ItemType Directory -Path $hostOut -Force | Out-Null
 
     # Copy artifacts down
     try {
       Copy-Item -Path (Join-Path $latest.FullName '*') -Destination $hostOut -Force -ErrorAction SilentlyContinue
       Write-Log "[$Computer] Collected artifacts ΓåÆ $hostOut"
     } catch {
       Write-Log "[$Computer] WARNING copying artifacts: $($_.Exception.Message)"
     }
 
     # Wipe remote artifacts
     try {
       Get-ChildItem -Path $latest.FullName -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
       Remove-Item -LiteralPath $latest.FullName -Force -ErrorAction SilentlyContinue
       Write-Log "[$Computer] Wiped remote bundle: $($latest.Name)"
     } catch {
       Write-Log "[$Computer] WARNING wiping remote bundle: $($_.Exception.Message)"
     }
   } else {
     Write-Log "[$Computer] No artifacts detected after $maxWait seconds."
   }
 
   # Cleanup the scheduled task
   try {
     cmd /c ("schtasks /Delete /S {0} /TN {1} /F" -f $Computer, $TaskName) | Out-Null
     Write-Log "[$Computer] Deleted task $TaskName."
   } catch {
     Write-Log "[$Computer] Cleanup warning: $($_.Exception.Message)"
   }
 
   Write-Log "==== [$Computer] End ===="
 }
 
 # ---------------------------
 # Main loop
 # ---------------------------
 $success = 0
 $fail    = 0
 
 foreach ($c in $Computers) {
   if ($script:StopRequested) { break }
   try {
     Invoke-Host -Computer $c
     $success++
   } catch {
     $fail++
     Write-Log "[$c] FATAL: $($_.Exception.Message)"
   }
 }
 
 Write-Log "Session complete. Success: $success  Failed: $fail  Hosts total: $($Computers.Count)"
 
 # Final reminder for PS7 targets (optional)
 Write-Log "Note: If some targets only have PowerShell 7, set -RemotePwshPath 'C:\Program Files\PowerShell\7\pwsh.exe'."
 