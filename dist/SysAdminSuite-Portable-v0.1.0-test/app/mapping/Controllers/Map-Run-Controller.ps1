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
 
  # Where to store this run's outputs on the controller:
   [string]$SessionRoot = (Join-Path -Path (Get-Location) -ChildPath ("SysAdminSuite-Session-{0:yyyyMMdd-HHmmss}" -f (Get-Date))),
 
   # PowerShell path on endpoints (PS5.1 is broadly available on enterprise images)
   [string]$RemotePwshPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
 
   # Remote base folder for payload + logs
   [string]$RemoteBase = "C:\ProgramData\SysAdminSuite\Mapping",
 
   # Task name (per host)
   [string]$TaskName = "SysAdminSuite_PrinterMap",
 
   # Max seconds to wait for artifacts before moving on
   [int]$MaxWaitSeconds = 45,

   # Opt-in reversible action capture for controller + worker operations
   [switch]$EnableUndoRedo,
   [string]$UndoRedoLogPath,

   # Raw worker argument fragment appended when invoking the payload.
   # Example: -Queues '\\PRINTSRV\Q01','\\PRINTSRV\Q02' -ListOnly -Preflight
   [string]$WorkerArgumentLine,

   # GUI-friendly stop + live status contract
   [string]$StopSignalPath,
   [string]$StatusPath
 )
 
 Set-StrictMode -Version Latest
 $ErrorActionPreference = 'Stop'
 $script:undoRedoEnabled = $false
 $script:undoRedoSession = $null
 $script:undoRedoUtilityPath = $null
 $script:undoRedoLogPath = $null
 $script:runControlUtilityPath = $null
 $script:stopSignalPath = $null
 $script:statusPath = $null
 $script:payloadSupportsStopSignal = $false
 $script:currentHost = $null
 $script:currentRemoteStopAdminPath = $null
 $script:currentRemoteStatusAdminPath = $null
 $script:remoteStopForwarded = $false
 $script:success = 0
 $script:fail = 0
 
 # ---------------------------
 # Setup output directories
 # ---------------------------
 New-Item -ItemType Directory -Force -Path $SessionRoot | Out-Null
 $ControllerLog = Join-Path $SessionRoot 'controller-log.txt'
"[$(Get-Date -Format s)] Session start -> $SessionRoot" | Out-File -FilePath $ControllerLog -Encoding utf8
 
 function Write-Log {
   param([string]$Message)
   $stamp = "[{0}] {1}" -f (Get-Date -Format s), $Message
   Write-Host $stamp
   $stamp | Out-File -FilePath $ControllerLog -Encoding utf8 -Append
 }

 function Initialize-ControllerRunControl {
   $candidatePaths = @(
     (Join-Path $PSScriptRoot 'Invoke-RunControl.ps1'),
     (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Utilities\Invoke-RunControl.ps1')
   ) | Select-Object -Unique

   $script:runControlUtilityPath = $candidatePaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
   if (-not $script:runControlUtilityPath) {
     throw 'Invoke-RunControl.ps1 could not be located.'
   }

   . $script:runControlUtilityPath
   $script:stopSignalPath = if ($StopSignalPath) { $StopSignalPath } else { Join-Path $SessionRoot 'Stop.json' }
   $script:statusPath = if ($StatusPath) { $StatusPath } else { Join-Path $SessionRoot 'Controller.Status.json' }
 }

 function Get-RemoteStatusSummary {
   if (-not $script:currentRemoteStatusAdminPath -or -not (Test-Path -LiteralPath $script:currentRemoteStatusAdminPath)) {
     return $null
   }

   try {
     $remote = Import-RunStatusSnapshot -Path $script:currentRemoteStatusAdminPath
     return [pscustomobject]@{
       State   = $remote.State
       Stage   = $remote.Stage
       Message = $remote.Message
     }
   } catch {
     return $null
   }
 }

 function Export-ControllerStatus {
   param(
     [string]$State = 'Running',
     [string]$Stage = 'Controller',
     [string]$Message = ''
   )

   if (-not $script:statusPath) { return }

   try {
     Export-RunStatusSnapshot -Path $script:statusPath -State $State -Stage $Stage -Message $Message -Data @{
       SessionRoot         = $SessionRoot
       ControllerLog       = $ControllerLog
       StopSignalPath      = $script:stopSignalPath
       StopRequested       = [bool]($script:StopRequested)
       CurrentHost         = $script:currentHost
       SuccessCount        = $script:success
       FailCount           = $script:fail
       HostsTotal          = $Computers.Count
       EnableUndoRedo      = [bool]$script:undoRedoEnabled
       UndoRedoLogPath     = $script:undoRedoLogPath
       RemoteStatusSummary = Get-RemoteStatusSummary
     } | Out-Null
   } catch {
     Write-Log "WARN: Failed to export controller status: $($_.Exception.Message)"
   }
 }

 function Request-RemoteWorkerStop {
   param([string]$Reason = 'Controller stop requested.')

   if ($script:remoteStopForwarded -or -not $script:currentRemoteStopAdminPath) { return }

   try {
     Request-RunStop -Path $script:currentRemoteStopAdminPath -Reason $Reason -RequestedBy 'Map-Run-Controller' | Out-Null
     $script:remoteStopForwarded = $true
     Write-Log "[$($script:currentHost)] Forwarded stop signal -> $($script:currentRemoteStopAdminPath)"
   } catch {
     Write-Log "[$($script:currentHost)] WARN forwarding stop signal: $($_.Exception.Message)"
   }
 }

 function Test-ControllerStopRequested {
   param([string]$Context = 'controller loop')

   $signal = $null
   if ($script:StopRequested) {
     $signal = [pscustomobject]@{
       RequestedAt = Get-Date
       RequestedBy = 'Console'
       Reason      = 'CTRL+C detected.'
     }
   } elseif ($script:stopSignalPath) {
     $signal = Test-RunStopRequested -Path $script:stopSignalPath
   }

   if (-not $signal) { return $false }

   if (-not $script:StopRequested) {
     $script:StopRequested = $true
     Write-Log "Stop requested during $Context. Will stop after current host."
   }

   if ($script:currentRemoteStopAdminPath) {
     Request-RemoteWorkerStop -Reason "Stop requested during $Context."
   }

   Export-ControllerStatus -State 'Stopping' -Stage 'StopRequested' -Message "Stop requested during $Context."
   return $true
 }

 function Initialize-ControllerUndoRedo {
   if (-not $EnableUndoRedo) { return }

   $candidatePaths = @(
     (Join-Path $PSScriptRoot 'Invoke-UndoRedo.ps1'),
     (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Utilities\Invoke-UndoRedo.ps1')
   ) | Select-Object -Unique

   $script:undoRedoUtilityPath = $candidatePaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
   if (-not $script:undoRedoUtilityPath) {
     throw 'EnableUndoRedo was requested, but Invoke-UndoRedo.ps1 could not be located.'
   }

   . $script:undoRedoUtilityPath
   $script:undoRedoSession = New-UndoRedoSession
   $script:undoRedoEnabled = $true
   $script:undoRedoLogPath = if ($UndoRedoLogPath) { $UndoRedoLogPath } else { Join-Path $SessionRoot 'UndoRedo.Controller.json' }
   Write-Log "Undo/redo capture enabled -> $script:undoRedoLogPath"
 }

 function Export-ControllerUndoRedoSummary {
   if (-not $script:undoRedoEnabled -or -not $script:undoRedoSession -or -not $script:undoRedoLogPath) { return }

   try {
     Export-UndoRedoSessionSummary -Session $script:undoRedoSession -Path $script:undoRedoLogPath | Out-Null
     Write-Log "Undo/redo controller summary exported -> $script:undoRedoLogPath"
   } catch {
     Write-Log "WARN: Failed to export controller undo/redo summary: $($_.Exception.Message)"
   }
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

 $payloadCommand = Get-Command $LocalScriptPath -ErrorAction Stop
 $script:payloadSupportsStopSignal = ($payloadCommand.Parameters.Keys -contains 'StopSignalPath' -and $payloadCommand.Parameters.Keys -contains 'StatusPath')

 if ($EnableUndoRedo) {
   if ($payloadCommand.Parameters.Keys -notcontains 'EnableUndoRedo') {
     throw "LocalScriptPath does not expose -EnableUndoRedo: $LocalScriptPath"
   }
 }

 Initialize-ControllerRunControl
 Initialize-ControllerUndoRedo
 Export-ControllerStatus -State 'Running' -Stage 'Startup' -Message 'Controller initialized.'
 
 # ---------------------------
 # Ctrl+C graceful handling
 # ---------------------------
 $script:StopRequested = $false
$null = Register-ObjectEvent -InputObject ([Console]) -EventName CancelKeyPress -SourceIdentifier 'Console.CancelKeyPress' -Action {
  $Event.SourceEventArgs.Cancel = $true
   $script:StopRequested = $true
   'CTRL+C detected. Will stop after current host.' | Out-File -FilePath $ControllerLog -Append -Encoding utf8
  Write-Host "`nCTRL+C detected - finishing current host, then exiting...`n"
 }
 
 # Utility: join admin share path
 function Join-AdminShare {
   param([string]$Computer, [string]$SubPath)
  "\\{0}\C$\{1}" -f $Computer, ((($SubPath -replace '^[cC]:\\', '') -replace '^[\\]+',''))
 }

 function ConvertTo-SingleQuotedPowerShellLiteral {
   param([AllowNull()][string]$Value)

   if ($null -eq $Value) { return "''" }
   return "'{0}'" -f ($Value -replace "'", "''")
 }

 function Write-WorkerLauncherScript {
   param(
     [Parameter(Mandatory)][string]$Path,
     [Parameter(Mandatory)][string]$RemoteScriptPath,
     [string]$RemoteStopSignalPath,
     [string]$RemoteStatusPath
   )

   $invocation = '& {0}' -f (ConvertTo-SingleQuotedPowerShellLiteral -Value $RemoteScriptPath)
   if ($script:payloadSupportsStopSignal) {
     $invocation += (' -StopSignalPath {0} -StatusPath {1}' -f 
       (ConvertTo-SingleQuotedPowerShellLiteral -Value $RemoteStopSignalPath),
       (ConvertTo-SingleQuotedPowerShellLiteral -Value $RemoteStatusPath))
   }
   if ($script:undoRedoEnabled) {
     $invocation += ' -EnableUndoRedo'
   }
   if ($WorkerArgumentLine -and $WorkerArgumentLine.Trim()) {
     $invocation += ' ' + $WorkerArgumentLine.Trim()
   }

   $launcherContent = @(
     '$ErrorActionPreference = ''Stop''',
     $invocation
   ) -join [Environment]::NewLine

   Set-Content -LiteralPath $Path -Value $launcherContent -Encoding UTF8
 }

 function New-ControllerTaskAction {
   param(
     [Parameter(Mandatory)][string]$Computer,
     [Parameter(Mandatory)][string]$TaskName,
     [Parameter(Mandatory)][string]$TaskCommand,
     [Parameter(Mandatory)][datetime]$StartTime,
     [Parameter(Mandatory)][ValidateSet('Create','Delete')][string]$Operation
   )

   $stTime = $StartTime.ToString('HH:mm')
   $stDate = $StartTime.ToString([System.Globalization.CultureInfo]::CurrentCulture.DateTimeFormat.ShortDatePattern)
   $actionTarget = ('{0}::{1}' -f $Computer, $TaskName)
   $createCmd = @(
     'schtasks',
     '/Create',
     '/S', $Computer,
     '/RU', 'SYSTEM',
     '/SC', 'ONCE',
     '/SD', $stDate,
     '/ST', $stTime,
     '/TN', $TaskName,
     '/TR', $TaskCommand,
     '/RL', 'HIGHEST',
     '/F'
   ) -join ' '
   $deleteCmd = ('schtasks /Delete /S {0} /TN {1} /F' -f $Computer, $TaskName)

   $probe = {
     param($ctx)
     $m = $ctx.Metadata
     $out = cmd /c ("schtasks /Query /S {0} /TN {1} /FO LIST" -f $m.ComputerName, $m.TaskName) 2>$null
     [pscustomobject]@{
       ComputerName = $m.ComputerName
       TaskName     = $m.TaskName
       Exists       = ($LASTEXITCODE -eq 0)
       QueryOutput  = if ($LASTEXITCODE -eq 0) { $out -join [Environment]::NewLine } else { $null }
     }
   }
   $createDo = {
     param($ctx)
     $m = $ctx.Metadata
     $out = cmd /c $m.CreateCommand 2>&1
     $exitCode = $LASTEXITCODE
     Write-Log "[$($m.ComputerName)] schtasks /Create output:`n$out"
     if ($exitCode -ne 0) {
       throw "schtasks /Create failed for $($m.TaskName) on $($m.ComputerName). ExitCode=$exitCode"
     }
   }
   $deleteDo = {
     param($ctx)
     $m = $ctx.Metadata
     $out = cmd /c $m.DeleteCommand 2>&1
     $exitCode = $LASTEXITCODE
     Write-Log "[$($m.ComputerName)] schtasks /Delete output:`n$out"
     if ($exitCode -ne 0) {
       throw "schtasks /Delete failed for $($m.TaskName) on $($m.ComputerName). ExitCode=$exitCode"
     }
   }

   $metadata = @{
     Kind          = 'ScheduledTask'
     ComputerName  = $Computer
     TaskName      = $TaskName
     TaskCommand   = $TaskCommand
     CreateCommand = $createCmd
     DeleteCommand = $deleteCmd
     StartDate     = $stDate
     StartTime     = $stTime
   }

   if ($Operation -eq 'Create') {
     New-UndoRedoActionRecord -Name 'Create scheduled task' -Target $actionTarget -Do $createDo -Undo $deleteDo -Probe $probe -Metadata $metadata
   } else {
     New-UndoRedoActionRecord -Name 'Delete scheduled task' -Target $actionTarget -Do $deleteDo -Undo $createDo -Probe $probe -Metadata $metadata
   }
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
   $remoteUndoRedo = Join-Path $remoteBase 'Invoke-UndoRedo.ps1'
   $remoteRunControl = Join-Path $remoteBase 'Invoke-RunControl.ps1'
   $remoteLauncher = Join-Path $remoteBase 'Start-Worker.ps1'
   $remoteStopSignal = Join-Path $remoteBase 'Stop.json'
   $remoteStatusPath = Join-Path $remoteBase 'status.json'
 
   $adminBase     = Join-AdminShare -Computer $Computer -SubPath $remoteBase
   $adminLogs     = Join-AdminShare -Computer $Computer -SubPath $remoteLogsDir
   $adminScript   = Join-AdminShare -Computer $Computer -SubPath $remoteScript
   $adminUndoRedo = Join-AdminShare -Computer $Computer -SubPath $remoteUndoRedo
   $adminRunControl = Join-AdminShare -Computer $Computer -SubPath $remoteRunControl
   $adminLauncher = Join-AdminShare -Computer $Computer -SubPath $remoteLauncher
   $adminStopSignal = Join-AdminShare -Computer $Computer -SubPath $remoteStopSignal
   $adminStatusPath = Join-AdminShare -Computer $Computer -SubPath $remoteStatusPath

   $script:currentHost = $Computer
   $script:currentRemoteStopAdminPath = $adminStopSignal
   $script:currentRemoteStatusAdminPath = $adminStatusPath
   $script:remoteStopForwarded = $false
   Export-ControllerStatus -State 'Running' -Stage 'HostStart' -Message "Starting host $Computer."
 
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
    return $false
   }
 
   # Copy payload script
   try {
     Remove-Item -LiteralPath $adminStopSignal,$adminStatusPath,$adminLauncher -Force -ErrorAction SilentlyContinue
     Copy-Item -Path $LocalScriptPath -Destination $adminScript -Force
    Write-Log "[$Computer] Copied script -> $adminScript"
     if ($script:undoRedoEnabled) {
       Copy-Item -Path $script:undoRedoUtilityPath -Destination $adminUndoRedo -Force
       Write-Log "[$Computer] Copied undo/redo utility -> $adminUndoRedo"
     }
     if ($script:payloadSupportsStopSignal) {
       Copy-Item -Path $script:runControlUtilityPath -Destination $adminRunControl -Force
       Write-Log "[$Computer] Copied run-control utility -> $adminRunControl"
     }
     Write-WorkerLauncherScript -Path $adminLauncher -RemoteScriptPath $remoteScript -RemoteStopSignalPath $remoteStopSignal -RemoteStatusPath $remoteStatusPath
     Write-Log "[$Computer] Wrote launcher -> $adminLauncher"
   } catch {
     Write-Log "[$Computer] ERROR copying script: $($_.Exception.Message)"
    return $false
   }
 
   # ----- Robust schedule + run + poll + collect + cleanup -----
   $when   = (Get-Date).AddMinutes(1)
   $stTime = $when.ToString('HH:mm')        # 24h
  $dateFmt = [System.Globalization.CultureInfo]::CurrentCulture.DateTimeFormat.ShortDatePattern
  $stDate = $when.ToString($dateFmt)
   $taskCommand = ('"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}"' -f $RemotePwshPath, $remoteLauncher)
 
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
     '/TR', $taskCommand,
     '/RL', 'HIGHEST',
     '/F'
   ) -join ' '

   if ($script:undoRedoEnabled) {
     $createAction = New-ControllerTaskAction -Computer $Computer -TaskName $TaskName -TaskCommand $taskCommand -StartTime $when -Operation Create
     try {
       Invoke-UndoRedo -Session $script:undoRedoSession -Action $createAction | Out-Null
     } catch {
       Write-Log "[$Computer] ERROR creating task via undo/redo action: $($_.Exception.Message)"
       return $false
     }
   } else {
     $createOut = cmd /c $createCmd 2>&1
    $createExit = $LASTEXITCODE
     Write-Log "[$Computer] schtasks /Create output:`n$createOut"
    if ($createExit -ne 0) {
      Write-Log "[$Computer] ERROR creating task. ExitCode=$createExit"
      return $false
    }
   }
 
   # Start it
   $runOut = cmd /c ("schtasks /Run /S {0} /TN {1}" -f $Computer, $TaskName) 2>&1
  $runExit = $LASTEXITCODE
   Write-Log "[$Computer] schtasks /Run output:`n$runOut"
  if ($runExit -ne 0) {
    Write-Log "[$Computer] ERROR running task. ExitCode=$runExit"
    return $false
  }
 
   # Poll for newest log bundle
   $maxWait = [Math]::Max(5, $MaxWaitSeconds)
   $waited  = 0
   $latest  = $null
   while ($waited -lt $maxWait) {
     if (Test-ControllerStopRequested -Context "polling $Computer") {
       Export-ControllerStatus -State 'Stopping' -Stage 'Polling' -Message "Waiting for $Computer to flush artifacts after stop request."
     } else {
       Export-ControllerStatus -State 'Running' -Stage 'Polling' -Message "Waiting for $Computer artifacts."
     }

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
       if (Test-Path -LiteralPath $adminStatusPath) {
         Copy-Item -LiteralPath $adminStatusPath -Destination (Join-Path $hostOut 'Worker.Status.json') -Force -ErrorAction SilentlyContinue
       }
      Write-Log "[$Computer] Collected artifacts -> $hostOut"
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
     if ($script:undoRedoEnabled) {
       $deleteAction = New-ControllerTaskAction -Computer $Computer -TaskName $TaskName -TaskCommand $taskCommand -StartTime $when -Operation Delete
       Invoke-UndoRedo -Session $script:undoRedoSession -Action $deleteAction | Out-Null
     } else {
       cmd /c ("schtasks /Delete /S {0} /TN {1} /F" -f $Computer, $TaskName) | Out-Null
       Write-Log "[$Computer] Deleted task $TaskName."
     }
     Remove-Item -LiteralPath $adminStopSignal,$adminStatusPath,$adminLauncher -Force -ErrorAction SilentlyContinue
   } catch {
     Write-Log "[$Computer] Cleanup warning: $($_.Exception.Message)"
   }
 
   Write-Log "==== [$Computer] End ===="
  return $true
 }
 
 # ---------------------------
 # Main loop
 # ---------------------------
 foreach ($c in $Computers) {
   if (Test-ControllerStopRequested -Context 'main loop') { break }
   try {
    $ok = Invoke-Host -Computer $c
    if ($ok) { $script:success++ } else { $script:fail++ }
   } catch {
     $script:fail++
     Write-Log "[$c] FATAL: $($_.Exception.Message)"
   }
   $script:currentHost = $null
   $script:currentRemoteStopAdminPath = $null
   $script:currentRemoteStatusAdminPath = $null
   $script:remoteStopForwarded = $false
   Export-ControllerStatus -State ($(if ($script:StopRequested) { 'Stopping' } else { 'Running' })) -Stage 'HostComplete' -Message "Finished host $c."
 }
 
 Write-Log "Session complete. Success: $($script:success)  Failed: $($script:fail)  Hosts total: $($Computers.Count)"
 Export-ControllerUndoRedoSummary
 Export-ControllerStatus -State ($(if ($script:StopRequested) { 'Stopped' } else { 'Completed' })) -Stage 'Complete' -Message 'Controller session finalized.'
 
 # Final reminder for PS7 targets (optional)
 Write-Log "Note: If some targets only have PowerShell 7, set -RemotePwshPath 'C:\Program Files\PowerShell\7\pwsh.exe'."
 