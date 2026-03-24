<#
Add-Computers-To-Group.ps1  — standalone AD tool

New behavior:
- -PlanOnly writes artifacts and plans actions without touching AD
- -WhatIf remains a pure simulation (no file I/O, no AD changes)
- Artifacts saved locally on the machine running the script
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$HostListPath,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$GroupName,

  [string]$Server,  # domain or DC FQDN
  [string]$OutputRoot = "$($env:USERPROFILE)\Documents\ADGroupEnroll",
  [ValidateRange(1, [int]::MaxValue)]
  [int]$ChunkSize = 50,
  [ValidateRange(1, [int]::MaxValue)]
  [int]$RetryCount = 2,
  [ValidateRange(1, [int]::MaxValue)]
  [int]$RetryDelaySeconds = 2,

  [switch]$PlanOnly      # <-- new: create reports, no AD changes
)

$ErrorActionPreference = 'Stop'
try { Import-Module ActiveDirectory -ErrorAction Stop } catch {
  throw "ActiveDirectory module is required (install RSAT). $_"
}

if (-not (Test-Path -LiteralPath $HostListPath)) {
  throw "Host list not found: $HostListPath"
}

$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$outDir = Join-Path $OutputRoot $stamp

# We always create artifacts when PlanOnly or real run.
# Under -WhatIf we DO NOT create anything.
$doIO = $PlanOnly -or -not $PSBoundParameters.ContainsKey('WhatIf')

if ($doIO) {
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

$logPath      = Join-Path $outDir 'Run.log'
$preflightCsv = Join-Path $outDir 'Preflight.csv'
$resultsCsv   = Join-Path $outDir 'Results.csv'
$htmlPath     = Join-Path $outDir 'Results.html'
$undoPs1      = Join-Path $outDir 'Undo-GroupMembership.ps1'

# Only start transcript when we are doing IO (PlanOnly or real)
$TranscriptStarted = $false
if ($doIO) {
  try { Start-Transcript -Path $logPath -Force | Out-Null; $TranscriptStarted = $true } catch {}
}

Write-Host "Artifacts location (local): $env:COMPUTERNAME"
if ($doIO) { Write-Host "Output: $outDir" } else { Write-Host "Output suppressed by -WhatIf" }

# Resolve target group
$gParams = @{ Identity = $GroupName }
if ($Server) { $gParams.Server = $Server }
try {
  $Group = Get-ADGroup @gParams -Properties Member
} catch {
  if ($TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
  throw "AD group '$GroupName' not found or inaccessible. $_"
}

# Read hosts
$Hosts = Get-Content -LiteralPath $HostListPath | ForEach-Object { $_.Trim() } | Where-Object { $_ }
if (-not $Hosts) {
  if ($TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
  throw "No hostnames found in $HostListPath"
}

# Helpers
function Get-Comp {
  param([string]$Name)
  $p = @{
    Identity   = $Name
    Properties = @('DistinguishedName','Enabled','DNSHostName','whenCreated','whenChanged',
                   'ObjectGUID','CanonicalName','OperatingSystem','LastLogonDate','sAMAccountName')
  }
  if ($Server) { $p.Server = $Server }
  return Get-ADComputer @p
}
function In-Group { param([string]$ComputerDN) return ($Group.Member -contains $ComputerDN) }
function Add-WithRetry {
  param([string]$ComputerDN)
  for ($i=0; $i -le $RetryCount; $i++) {
    try {
      $params = @{ Identity = $Group; Members = $ComputerDN; ErrorAction = 'Stop' }
      if ($Server) { $params.Server = $Server }
      if ($PSCmdlet.ShouldProcess("Add '$ComputerDN' to '$($Group.Name)'")) {
        Add-ADGroupMember @params
      }
      return @{ Outcome='Added'; Error=$null }
    } catch {
      if ($i -lt $RetryCount) { Start-Sleep -Seconds $RetryDelaySeconds } else {
        return @{ Outcome='Failed'; Error = ($_.Exception.Message -split "`r?`n")[0] }
      }
    }
  }
}

# Preflight + results collectors
$preflight = New-Object System.Collections.Generic.List[Object]
$results   = New-Object System.Collections.Generic.List[Object]
$restore   = New-Object System.Collections.Generic.List[string]

# Snapshot + plan
foreach ($h in $Hosts) {
  $row = [ordered]@{
    Timestamp          = (Get-Date).ToString('s')
    Hostname           = $h
    Found              = $false
    Enabled            = $null
    DistinguishedName  = $null
    OUPath             = $null
    DNSHostName        = $null
    AlreadyMember      = $null
    Action             = 'None'
    Outcome            = 'Planned'
    Error              = $null
  }
  try {
    $c = Get-Comp -Name $h
    $row.Found             = $true
    $row.Enabled           = $c.Enabled
    $row.DistinguishedName = $c.DistinguishedName
    $row.DNSHostName       = $c.DNSHostName
    $row.OUPath            = ($c.DistinguishedName -split '(?<!\\),',2)[1]

    $preflight.Add([pscustomobject]@{
      SnapshotTime      = (Get-Date).ToString('s')
      Hostname          = $h
      DistinguishedName = $c.DistinguishedName
      CanonicalName     = $c.CanonicalName
      ObjectGUID        = $c.ObjectGUID
      DNSHostName       = $c.DNSHostName
      Enabled           = $c.Enabled
      OperatingSystem   = $c.OperatingSystem
      WhenCreated       = $c.whenCreated
      LastLogonDate     = $c.LastLogonDate
      OUPath            = $row.OUPath
      sAMAccountName    = $c.sAMAccountName
    })

    $restore.Add("Remove-ADGroupMember -Identity `"$($Group.Name)`" -Members `"$($c.SamAccountName)`" -Confirm:`$false")

    $already = In-Group -ComputerDN $c.DistinguishedName
    $row.AlreadyMember = $already
    if ($already) {
      $row.Action  = 'NoChange'
      $row.Outcome = 'AlreadyInGroup'
    } else {
      $row.Action = 'AddToGroup'
    }
  } catch {
    $row.Outcome = 'LookupFailed'
    $row.Error   = ($_.Exception.Message -split "`r?`n")[0]
  }
  $results.Add([pscustomobject]$row)
}

# Write snapshot + restore when IO is enabled (PlanOnly or real)
if ($doIO) {
  $preflight | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $preflightCsv
  @("# Undo group membership changes (generated $(Get-Date -Format s))",
    "Import-Module ActiveDirectory",
    $restore) -join [Environment]::NewLine | Set-Content -Path $undoPs1 -Encoding UTF8
}

# Execute changes (skip if PlanOnly or WhatIf)
$todo = $results | Where-Object { $_.Action -eq 'AddToGroup' -and $_.Outcome -ne 'LookupFailed' }
if (-not $PlanOnly -and -not $PSBoundParameters.ContainsKey('WhatIf')) {
  $chunks = @()
  if ($todo.Count -gt 0) {
    $chunks = [System.Linq.Enumerable]::ToList([System.Collections.Generic.List[object]]::new())
    $chunk = @()
    foreach ($item in $todo) {
      $chunk += ,$item
      if ($chunk.Count -ge $ChunkSize) { $chunks.Add($chunk); $chunk=@() }
    }
    if ($chunk.Count -gt 0) { $chunks.Add($chunk) }
  }

  $batch = 0
  foreach ($chunk in $chunks) {
    $batch++
    Write-Host "Processing batch $batch ($($chunk.Count) items)..."
    foreach ($row in $chunk) {
      try {
        $res = Add-WithRetry -ComputerDN $row.DistinguishedName
        $row.Outcome = $res.Outcome
        if ($res.Error) { $row.Error = $res.Error }
      } catch {
        $row.Outcome = 'Failed'
        $row.Error   = ($_.Exception.Message -split "`r?`n")[0]
      }
    }
  }
} else {
  # Simulation path: mark intended changes
  foreach ($row in $todo) { $row.Outcome = 'WouldAdd' }
}

# Results + HTML when IO is enabled
if ($doIO) {
  $results | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $resultsCsv
  ($results | Select-Object Timestamp,Hostname,Found,Enabled,AlreadyMember,Action,Outcome,Error |
    ConvertTo-Html -Title "Add to $GroupName results" |
    Out-String) | Set-Content -Path $htmlPath -Encoding UTF8
}

Write-Host "`nDone."
Write-Host "Local Machine: $env:COMPUTERNAME"
if ($doIO) {
  Write-Host "Preflight: $preflightCsv"
  Write-Host "Undo     : $undoPs1"
  Write-Host "Results  : $resultsCsv"
  Write-Host "HTML     : $htmlPath"
  Write-Host "Log      : $logPath"
} else {
  Write-Host "No files written (pure simulation via -WhatIf)."
}

if ($TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {} }