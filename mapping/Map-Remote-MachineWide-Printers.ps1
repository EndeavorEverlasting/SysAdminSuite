<# 
  Map-Remote-MachineWide-Printers.ps1
  Machine-wide printer mapping with AD-style artifacts.
  Supports BOTH:
    • UNC queues (\\server\share) via /ga (machine-wide)
    • Direct IP printers (Standard TCP/IP Port + local printer)

  Modes:
    -ListOnly : snapshot current machine-wide/installed printers; write artifacts; NO input required; NO changes
    -PlanOnly : read desired list; write artifacts; plan adds/removes; NO changes
    -WhatIf   : pure simulation; NO file I/O; NO changes
    -Preflight: spooler/elevation/input checks
    -PruneNotInList : remove machine-wide UNC connections NOT in CSV + remove IP-mode printers whose PrinterName NOT in CSV
    -RestartSpoolerIfNeeded : restart Spooler if we changed connections

  Driver strategy for IP printers:
    1) Use DriverName from CSV if present and installed.
    2) If not, try to find a correlating installed driver (brand/model/tech fuzzy match).
    3) If not, use FallbackDriver (default: "Microsoft PCL6 Class Driver").
    4) Only fail if none of the above is installed.

  Input CSV (mixed rows allowed):
    # UNC schema (either UNC or Server+Share). Optional FriendlyName (display only).
    UNC, FriendlyName
    or
    Server, Share, FriendlyName

    # IP schema
    # DriverName optional (auto-pick + fallback will kick in)
    IP, DriverName, PrinterName, PortName, Protocol, Port, LprQueueName, SNMP
      IP            : e.g. 10.55.21.202
      DriverName    : optional exact installed name (e.g. "HP Universal Printing PCL 6")
      PrinterName   : required (e.g. "HP-Path-10.55.21.202")
      PortName      : optional (default "IP_<IP>")
      Protocol      : RAW or LPR (default RAW)
      Port          : integer (default 9100)
      LprQueueName  : required only when Protocol=LPR
      SNMP          : true/false (default false)

  Artifacts (when IO enabled: ListOnly, PlanOnly, or real run):
    C:\ProgramData\SysAdminSuite\Mapping\logs\<yyyyMMdd-HHmmss>\{Run.log,Preflight.csv,Results.csv,Results.html}
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
param(
  [Parameter(Mandatory=$false)]
  [string]$InputPath,

  [string]$OutputRoot = 'C:\ProgramData\SysAdminSuite\Mapping',

  [switch]$ListOnly,
  [switch]$PlanOnly,
  [switch]$Preflight,
  [switch]$PruneNotInList,
  [switch]$RestartSpoolerIfNeeded,

  # You can override this if your image uses a different name:
  [string]$FallbackDriver = 'Microsoft PCL6 Class Driver'
)

$ErrorActionPreference = 'Stop'

# ----------------- Utils -----------------
function New-StampedDir([string]$root){
  if (!(Test-Path $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $dir   = Join-Path $root $stamp
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  return $dir
}
function W([string]$m){
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line = "[{0}] {1}" -f $ts,$m
  Write-Host $line
  if ($script:doIO -and $script:logPath) { Add-Content -LiteralPath $script:logPath -Value $line }
}
function Get-GlobalUNCs {
  $key = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections'
  if (!(Test-Path $key)) { return @() }
  Get-ChildItem $key | ForEach-Object {
    try {
      $p = Get-ItemProperty $_.PSPath
      if ($p.Server -and $p.Printer) { "\\$($p.Server)\$($p.Printer)".ToLower() }
    } catch {}
  } | Sort-Object -Unique
}
function Get-LocalPrinters { try { Get-Printer -ErrorAction Stop } catch { @() } }
function Get-Ports        { try { Get-PrinterPort -ErrorAction Stop } catch { @() } }
function Get-Drivers      { try { Get-PrinterDriver -ErrorAction Stop } catch { @() } }

function Parse-CSVRow($r){
  if ($r.PSObject.Properties.Name -contains 'UNC' -and $r.UNC) {
    return [pscustomobject]@{
      Type         = 'UNC'
      UNC          = ($r.UNC.ToString().Trim().ToLower())
      FriendlyName = ($r.FriendlyName ?? '').Trim()
    }
  }
  if (($r.PSObject.Properties.Name -contains 'Server') -and ($r.PSObject.Properties.Name -contains 'Share') -and $r.Server -and $r.Share) {
    return [pscustomobject]@{
      Type         = 'UNC'
      UNC          = ("\\{0}\{1}" -f $r.Server.ToString().Trim(),$r.Share.ToString().Trim()).ToLower()
      FriendlyName = ($r.FriendlyName ?? '').Trim()
    }
  }
  if ($r.PSObject.Properties.Name -contains 'IP' -and $r.IP) {
    $ip = $r.IP.ToString().Trim()
    $drv = ($r.DriverName ?? '').ToString().Trim()    # optional
    $pname = $r.PrinterName.ToString().Trim()
    if (-not $pname){ throw "IP row requires PrinterName for $ip" }
    $portName = if ($r.PortName){ $r.PortName.ToString().Trim() } else { "IP_$ip" }
    $protoRaw = ($r.Protocol ?? 'RAW').ToString().Trim().ToUpper()
    $proto = if ($protoRaw -in @('RAW','LPR')) { $protoRaw } else { 'RAW' }
    $port = if ($r.Port){ [int]$r.Port } else { 9100 }
    $snmp = if ($r.SNMP){ [bool]::Parse($r.SNMP.ToString()) } else { $false }
    $lprq = ($r.LprQueueName ?? '').ToString().Trim()
    if ($proto -eq 'LPR' -and -not $lprq) { throw "Protocol=LPR requires LprQueueName for IP $ip" }
    return [pscustomobject]@{
      Type         = 'IP'
      IP           = $ip
      DriverName   = $drv     # may be empty; we’ll choose
      PrinterName  = $pname
      PortName     = $portName
      Protocol     = $proto
      Port         = $port
      LprQueueName = $lprq
      SNMP         = $snmp
    }
  }
  throw "Row is neither UNC nor IP schema."
}
function Parse-Targets([string]$path){
  if (!(Test-Path -LiteralPath $path)) { throw "Input not found: $path" }
  if ([IO.Path]::GetExtension($path).ToLower() -ne '.csv') { throw "For mixed UNC/IP, please use CSV." }
  $rows = Import-Csv -LiteralPath $path
  $list = New-Object System.Collections.Generic.List[Object]
  foreach($r in $rows){ $list.Add( (Parse-CSVRow $r) ) }
  return $list
}

# --- Driver helpers (correlate → fallback PCL6) ---
function Find-CorrelatingDriver([string]$hint){
  $hint = ($hint ?? '').Trim()
  $drivers = Get-Drivers
  if (-not $drivers) { return $null }
  if ($hint) {
    # 1) exact
    $exact = $drivers | Where-Object { $_.Name -eq $hint }
    if ($exact) { return $exact.Name }
    # 2) brand/model-ish contains (HP|Canon|Brother|Ricoh|Kyocera|Xerox) + (PCL|PostScript|PS|XPS|KX|UFR)
    $tokens = ($hint -split '[\s\-_/]+' | Where-Object { $_ }) + @()
    $prefBrands = 'HP','Hewlett','Canon','Brother','Ricoh','Kyocera','Xerox','Sharp','Tosh','Lexmark'
    $prefTech   = 'PCL','PCL6','PS','PostScript','XPS','UFR','KX'
    $cands = $drivers | Where-Object {
      $n = $_.Name
      ($prefBrands | ForEach-Object { $n -match $_ }) -or
      ($prefTech   | ForEach-Object { $n -match $_ }) -or
      ($tokens     | ForEach-Object { if($_){ $n -match [regex]::Escape($_) } })
    }
    if ($cands) {
      # Prefer PCL6 over PS over others
      ($cands | Sort-Object {
        if ($_.Name -match 'PCL\s*6') { 0 }
        elseif ($_.Name -match '\bPCL\b') { 1 }
        elseif ($_.Name -match 'PostScript|\bPS\b') { 2 }
        else { 3 }
      })[0].Name
    } else { $null }
  } else {
    # No hint → grab a sane default from installed drivers (prefer PCL6)
    ($drivers | Sort-Object {
      if ($_.Name -match 'PCL\s*6') { 0 }
      elseif ($_.Name -match '\bPCL\b') { 1 }
      else { 2 }
    })[0].Name
  }
}

function Resolve-DriverName($spec){
  # Returns a usable driver name or $null if unresolved
  $drivers = Get-Drivers
  if (-not $drivers) { return $null }

  if ($spec.DriverName) {
    if ($drivers.Name -contains $spec.DriverName) { return $spec.DriverName }
    $corr = Find-CorrelatingDriver $spec.DriverName
    if ($corr) { W "Driver correlate for '$($spec.DriverName)': using '$corr'"; return $corr }
  } else {
    $corr = Find-CorrelatingDriver ''
    if ($corr) { W "No driver specified; using correlating driver '$corr'"; return $corr }
  }

  if ($drivers.Name -contains $FallbackDriver) {
    W "Falling back to '$FallbackDriver'"
    return $FallbackDriver
  }

  return $null
}

function Ensure-Port($spec){
  $existing = Get-Ports | Where-Object { $_.Name -eq $spec.PortName }
  if ($existing) { return @{ Action='KeepPort'; Ok=$true; PortName=$spec.PortName } }
  $args = @{
    Name               = $spec.PortName
    PrinterHostAddress = $spec.IP
    SnmpEnabled        = [bool]$spec.SNMP
  }
  if ($spec.Protocol -eq 'RAW') {
    $args['PortNumber'] = $spec.Port
    $args['Protocol']   = 'Raw'
  } else {
    $args['Protocol']    = 'Lpr'
    $args['LprQueueName']= $spec.LprQueueName
  }
  if ($PSCmdlet.ShouldProcess($spec.PortName,"Add-PrinterPort")) {
    try { Add-PrinterPort @args -ErrorAction Stop } catch { return @{ Action='AddPort'; Ok=$false; Error=$_.Exception.Message } }
  }
  return @{ Action='AddPort'; Ok=$true; PortName=$spec.PortName }
}

function Ensure-Printer($spec,[string]$driverToUse){
  $p = Get-LocalPrinters | Where-Object { $_.Name -eq $spec.PrinterName }
  if ($p) {
    # compare
    $portOk = ($p.PortName -eq $spec.PortName)
    $drvOk  = ($p.DriverName -eq $driverToUse)
    if (-not $portOk) { W "Printer '$($spec.PrinterName)' exists but on port '$($p.PortName)'; desired '$($spec.PortName)'" }
    if (-not $drvOk)  { W "Printer '$($spec.PrinterName)' exists with driver '$($p.DriverName)'; desired '$driverToUse'" }
    return @{ Action='KeepPrinter'; Ok=($portOk -and $drvOk) }
  }
  if ($PSCmdlet.ShouldProcess($spec.PrinterName,"Add-Printer (local, IP)")) {
    try { Add-Printer -Name $spec.PrinterName -DriverName $driverToUse -PortName $spec.PortName -ErrorAction Stop }
    catch { return @{ Action='AddPrinter'; Ok=$false; Error=$_.Exception.Message } }
  }
  return @{ Action='AddPrinter'; Ok=$true }
}

function Remove-UNC([string]$unc){
  $args = @('printui.dll,PrintUIEntry','/gd','/n',"$unc")
  if ($PSCmdlet.ShouldProcess($unc,"Remove machine-wide (/gd)")) {
    Start-Process rundll32.exe -ArgumentList $args -NoNewWindow -Wait
  }
}
function Add-UNC([string]$unc){
  $args = @('printui.dll,PrintUIEntry','/ga','/n',"$unc")
  if ($PSCmdlet.ShouldProcess($unc,"Add machine-wide (/ga)")) {
    Start-Process rundll32.exe -ArgumentList $args -NoNewWindow -Wait
  }
}
function Remove-LocalPrinterByName([string]$name){
  if ($PSCmdlet.ShouldProcess($name,"Remove-Printer")) {
    try { Remove-Printer -Name $name -ErrorAction Stop } catch {}
  }
}

# ----------------- Artifacts wiring -----------------
$doIO = $ListOnly -or $PlanOnly -or -not $PSBoundParameters.ContainsKey('WhatIf')  # WhatIf => no IO
$outDir = $null; $logPath=$null; $preflightCsv=$null; $resultsCsv=$null; $htmlPath=$null
$TranscriptStarted = $false
if ($doIO) {
  $outDir      = New-StampedDir (Join-Path $OutputRoot 'logs')
  $logPath      = Join-Path $outDir 'Run.log'
  $preflightCsv = Join-Path $outDir 'Preflight.csv'
  $resultsCsv   = Join-Path $outDir 'Results.csv'
  $htmlPath     = Join-Path $outDir 'Results.html'
  try { Start-Transcript -Path $logPath -Force | Out-Null; $TranscriptStarted=$true } catch {}
}

W "=== Printer Map start @ $env:COMPUTERNAME as $([Security.Principal.WindowsIdentity]::GetCurrent().Name) ==="
if ($doIO) { W "Artifacts in: $outDir" } else { W "Output suppressed by -WhatIf" }

# ----------------- Preflight -----------------
if ($Preflight) {
  $svc = Get-Service -Name Spooler -ErrorAction SilentlyContinue
  if (-not $svc) { if($TranscriptStarted){Stop-Transcript|Out-Null}; throw "Spooler service not found." }
  W "Spooler: $($svc.Status)"
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { W "WARN: Not elevated; machine-wide actions may fail." }
  if (-not $ListOnly -and -not $InputPath) { if($TranscriptStarted){Stop-Transcript|Out-Null}; throw "InputPath is required unless -ListOnly." }
  if (-not $ListOnly -and $InputPath -and -not (Test-Path -LiteralPath $InputPath)) { if($TranscriptStarted){Stop-Transcript|Out-Null}; throw "Input file not found: $InputPath" }
}

# ----------------- Parse desired + BEFORE -----------------
$desired = @()
if (-not $ListOnly -and $InputPath) { $desired = Parse-Targets -path $InputPath }

$beforeUNC = Get-GlobalUNCs
$printers  = Get-LocalPrinters
$ports     = Get-Ports
$drivers   = Get-Drivers

$currentLocalByName = @{}
foreach($lp in $printers){ $currentLocalByName[$lp.Name] = $lp }

# Preflight.csv
if ($doIO) {
  $pfRows = New-Object System.Collections.Generic.List[Object]

  foreach($u in $beforeUNC){
    $pfRows.Add([pscustomobject]@{
      SnapshotTime = (Get-Date).ToString('s')
      ComputerName = $env:COMPUTERNAME
      Type         = 'UNC'
      Target       = $u
      PresentNow   = $true
      Reachable    = (try { Test-Path -LiteralPath $u } catch { $false })
      InDesired    = ($desired | Where-Object { $_.Type -eq 'UNC' -and $_.UNC -eq $u }).Count -gt 0
      Notes        = ''
    })
  }
  foreach($p in $printers){
    $pfRows.Add([pscustomobject]@{
      SnapshotTime = (Get-Date).ToString('s'); ComputerName=$env:COMPUTERNAME
      Type='LOCAL'; Target=$p.Name; PresentNow=$true; Reachable=$null
      InDesired=($desired | Where-Object { $_.Type -eq 'IP' -and $_.PrinterName -eq $p.Name }).Count -gt 0
      Notes="Driver=$($p.DriverName); Port=$($p.PortName)"
    })
  }
  foreach($d in $desired){
    if ($d.Type -eq 'UNC'){
      if ($beforeUNC -notcontains $d.UNC){
        $pfRows.Add([pscustomobject]@{
          SnapshotTime=(Get-Date).ToString('s');ComputerName=$env:COMPUTERNAME;Type='UNC';Target=$d.UNC;
          PresentNow=$false;Reachable=(try{Test-Path -LiteralPath $d.UNC}catch{$false});InDesired=$true;Notes='(missing)'
        })
      }
    } else {
      if (-not $currentLocalByName.ContainsKey($d.PrinterName)){
        $pfRows.Add([pscustomobject]@{
          SnapshotTime=(Get-Date).ToString('s');ComputerName=$env:COMPUTERNAME;Type='IP';Target=$d.PrinterName;
          PresentNow=$false;Reachable=$null;InDesired=$true;Notes="IP=$($d.IP); DriverHint=$($d.DriverName); Port=$($d.PortName)"
        })
      }
    }
  }
  $pfRows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $preflightCsv
}

# Short-circuit: ListOnly
if ($ListOnly) {
  $rows = New-Object System.Collections.Generic.List[Object]
  $now = (Get-Date).ToString('s')
  foreach($u in $beforeUNC){
    $rows.Add([pscustomobject]@{ Timestamp=$now; ComputerName=$env:COMPUTERNAME; Type='UNC'; Target=$u; Driver=''; Port=''; Status='PresentNow' })
  }
  foreach($p in $printers){
    $rows.Add([pscustomobject]@{ Timestamp=$now; ComputerName=$env:COMPUTERNAME; Type='LOCAL'; Target=$p.Name; Driver=$p.DriverName; Port=$p.PortName; Status='PresentNow' })
  }
  if ($doIO) {
    $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $resultsCsv
    $table = $rows | Select-Object Timestamp,Type,Target,Driver,Port,Status |
      ConvertTo-Html -Fragment -PreContent '<h3>Current Printers (UNC + Local)</h3>'
    $logFrag = if (Test-Path $logPath) { "<h3>Run Log</h3><pre>" + [System.Web.HttpUtility]::HtmlEncode((Get-Content -Raw -LiteralPath $logPath)) + "</pre>" } else { '' }
    $doc = @"
<!DOCTYPE html><html><head><meta charset="utf-8"/><title>Printer Mappings — $env:COMPUTERNAME (ListOnly)</title>
<style>body{font-family:Segoe UI,Arial;background:#101014;color:#ececf1;padding:20px}
table{border-collapse:collapse;width:100%}th,td{border:1px solid #2a2a33;padding:6px 8px;font-size:12px}
th{background:#171720}tr:nth-child(even){background:#0f0f16}</style></head><body>
<h2>Printer Mappings — $env:COMPUTERNAME (ListOnly)</h2>$table$logFrag</body></html>
"@
    Set-Content -LiteralPath $htmlPath -Value $doc -Encoding UTF8
    W "Artifacts:`n  $preflightCsv`n  $resultsCsv`n  $htmlPath`n  $logPath"
  }
  if ($TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
  W "=== Completed (ListOnly) ==="
  return
}

# ----------------- Plan (not ListOnly) -----------------
$desiredUNC = $desired | Where-Object { $_.Type -eq 'UNC' }
$desiredIP  = $desired | Where-Object { $_.Type -eq 'IP'  }

$uncToAdd    = @($desiredUNC | ForEach-Object { $_.UNC } | Where-Object { $beforeUNC -notcontains $_ })
$uncToRemove = if ($PruneNotInList){ $beforeUNC | Where-Object { ($desiredUNC | ForEach-Object {$_.UNC}) -notcontains $_ } } else { @() }

$ipToAdd    = @($desiredIP | Where-Object { -not $currentLocalByName.ContainsKey($_.PrinterName) })
$ipToRemove = if ($PruneNotInList){ $printers | Where-Object { -not ($desiredIP.PrinterName -contains $_.Name) } } else { @() }

# If executing (not PlanOnly), resolve driver for each IP add (with fallback)
$driverErrors = @()
if (-not $PlanOnly) {
  foreach($d in $ipToAdd){
    $resolved = Resolve-DriverName $d
    if (-not $resolved) { $driverErrors += "$($d.PrinterName): no suitable driver found (hint='$($d.DriverName)'; fallback='$FallbackDriver' not installed)" }
    else { $d | Add-Member -NotePropertyName ResolvedDriver -NotePropertyValue $resolved -Force }
  }
  if ($driverErrors.Count -gt 0) {
    if ($TranscriptStarted){ try { Stop-Transcript | Out-Null } catch {} }
    throw "Cannot proceed due to driver resolution: `n  $($driverErrors -join "`n  ")"
  }
}

# ----------------- Execute -----------------
$changed = $false

# UNC adds/removes
if (-not $PlanOnly) {
  foreach($u in $uncToAdd){ Add-UNC $u; $changed=$true }
  foreach($u in $uncToRemove){ Remove-UNC $u; $changed=$true }
} else {
  W "PLAN-ONLY: UNC Adds => $($uncToAdd.Count), Removes => $($uncToRemove.Count)"
}

# IP adds/removes
if (-not $PlanOnly) {
  foreach($d in $ipToAdd){
    $portRes = Ensure-Port $d
    if (-not $portRes.Ok){ W "Port error for $($d.PrinterName): $($portRes.Error)"; continue }
    $drvUse  = if ($d.PSObject.Properties.Name -contains 'ResolvedDriver') { $d.ResolvedDriver } else { Resolve-DriverName $d }
    if (-not $drvUse) { W "No usable driver for $($d.PrinterName)"; continue }
    $prtRes  = Ensure-Printer $d $drvUse
    if (-not $prtRes.Ok){ W "Add-Printer error for $($d.PrinterName): $($prtRes.Error)" } else { $changed=$true }
  }
  foreach($p in $ipToRemove){ Remove-LocalPrinterByName $p.Name; $changed=$true }
} else {
  # Enrich plan with resolved/fallback info for visibility
  foreach($d in $ipToAdd){
    $drvPlan = Resolve-DriverName $d
    if ($drvPlan) { W "PLAN-ONLY: $($d.PrinterName) would use driver '$drvPlan'" }
    else { W "PLAN-ONLY: $($d.PrinterName) has NO driver available (fallback '$FallbackDriver' not installed)" }
  }
  W "PLAN-ONLY: IP Adds (by name) => $($ipToAdd.Count), Removes => $($ipToRemove.Count)"
}

if ($changed -and $RestartSpoolerIfNeeded) {
  try { Restart-Service Spooler -Force -ErrorAction Stop; W "Spooler restarted." } catch { W "Spooler restart failed: $($_.Exception.Message)" }
}

# ----------------- AFTER + Results -----------------
$afterUNC  = Get-GlobalUNCs
$afterPrin = Get-LocalPrinters

$rows = New-Object System.Collections.Generic.List[Object]
$now  = (Get-Date).ToString('s')

$universeUNC = ($beforeUNC + $afterUNC + ($desiredUNC | ForEach-Object {$_.UNC})) | Sort-Object -Unique
foreach($u in $universeUNC){
  $status = if ($PlanOnly) {
    if ($uncToAdd -contains $u) {'PlannedAdd'}
    elseif ($uncToRemove -contains $u) {'PlannedRemove'}
    elseif ($afterUNC -contains $u) {'PresentAfter'}
    elseif ($beforeUNC -contains $u) {'GoneAfter'}
    else {'NotPresent'}
  } else {
    if (($afterUNC -contains $u) -and ($beforeUNC -notcontains $u)) {'AddedNow'}
    elseif (($afterUNC -notcontains $u) -and ($beforeUNC -contains $u)) {'RemovedNow'}
    elseif ($afterUNC -contains $u) {'PresentAfter'} else {'NotPresent'}
  }
  $rows.Add([pscustomobject]@{
    Timestamp=$now; ComputerName=$env:COMPUTERNAME; Type='UNC'; Target=$u;
    Driver=''; Port=''; Status=$status
  })
}

$universeNames = @($printers.Name + $afterPrin.Name + $desiredIP.PrinterName) | Sort-Object -Unique
foreach($n in $universeNames){
  $beforeP = $printers | Where-Object { $_.Name -eq $n }
  $afterP  = $afterPrin | Where-Object { $_.Name -eq $n }
  $status = if ($PlanOnly) {
    if ($ipToAdd.PrinterName -contains $n) {'PlannedAdd'}
    elseif ($ipToRemove.Name -contains $n) {'PlannedRemove'}
    elseif ($afterP) {'PresentAfter'}
    elseif ($beforeP) {'GoneAfter'}
    else {'NotPresent'}
  } else {
    if ($afterP -and -not $beforeP) {'AddedNow'}
    elseif (-not $afterP -and $beforeP) {'RemovedNow'}
    elseif ($afterP) {'PresentAfter'}
    else {'NotPresent'}
  }
  $drv = if ($afterP){ $afterP.DriverName } elseif ($beforeP){ $beforeP.DriverName } else { '' }
  $prt = if ($afterP){ $afterP.PortName } elseif ($beforeP){ $beforeP.PortName } else { '' }
  $rows.Add([pscustomobject]@{
    Timestamp=$now; ComputerName=$env:COMPUTERNAME; Type='LOCAL'; Target=$n;
    Driver=$drv; Port=$prt; Status=$status
  })
}

if ($doIO) {
  $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $resultsCsv
  $table = $rows | Select-Object Timestamp,Type,Target,Driver,Port,Status |
    ConvertTo-Html -Fragment -PreContent '<h3>Per-Target Detail</h3>'

  $doc = @"
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <title>Printer Mapping — $env:COMPUTERNAME</title>
  <style>
    body{font-family:Segoe UI,Arial;background:#101014;color:#ececf1;padding:20px}
    table{border-collapse:collapse;width:100%}
    th,td{border:1px solid #2a2a33;padding:6px 8px;font-size:12px}
    th{background:#171720}
    tr:nth-child(even){background:#0f0f16}
  </style>
</head>
<body>
  <h2>Printer Mapping Results — $env:COMPUTERNAME</h2>
  $table
</body>
</html>
"@
  Set-Content -LiteralPath $htmlPath -Value $doc -Encoding UTF8
  W "Artifacts:`n  $preflightCsv`n  $resultsCsv`n  $htmlPath`n  $logPath"
}

if ($TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
W "=== Completed ==="
