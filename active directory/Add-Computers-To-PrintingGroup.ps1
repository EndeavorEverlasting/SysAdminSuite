<#
SYNOPSIS
  Batch-adds computer objects to an AD group with robust logging and a preflight OU snapshot.

PARAMS
  -HostListPath   Text file with one hostname per line.
  -GroupName      Target AD group. Default: GP_TSE_AllowWin10Printing
  -WhatIf         Simulate group adds; still writes all logs/snapshots.

OUTPUTS (in C:\Temp\ADGroupEnroll\<timestamp>\)
  - Preflight.csv     Current state per computer (OUPath, DN, GUID, etc.)
  - Restore-OU.ps1    Rollback script to move each object back to its OU using ObjectGUID
  - Results.csv       Outcome of group additions
  - Results.html      PM-friendly summary
  - Run.log           Transcript
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [Parameter(Mandatory=$true)]
  [string]$HostListPath,

  [string]$GroupName = "GP_TSE_AllowWin10Printing"
)

# --- Prep --------------------------------------------------------------------
$ErrorActionPreference = "Stop"

try { Import-Module ActiveDirectory -ErrorAction Stop }
catch { throw "ActiveDirectory module is required (RSAT). $_" }

if (-not (Test-Path -LiteralPath $HostListPath)) {
  throw "Host list not found: $HostListPath"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

# Get the hostname of the machine running this script
$localHost = $env:COMPUTERNAME

# UNC base path on the machine’s C$ share
$Base = "\\$localHost\c$\SysAdminSuite\ADGroupEnroll"
$OutDir = Join-Path $Base $stamp

# Try to create the directory on the fileshare; fallback to memory-only mode if it fails
try {
    if (-not (Test-Path $OutDir)) {
        New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    }
}
catch {
    Write-Warning "Could not create or access $OutDir. Falling back to memory-only mode."
    $OutDir = $null
}

# Define output paths only if $OutDir is available
if ($OutDir) {
    $CsvPath      = Join-Path $OutDir "Results.csv"
    $HtmlPath     = Join-Path $OutDir "Results.html"
    $LogPath      = Join-Path $OutDir "Run.log"
    $PreflightCsv = Join-Path $OutDir "Preflight.csv"
    $RestorePs1   = Join-Path $OutDir "Restore-OU.ps1"

    Start-Transcript -Path $LogPath -Force | Out-Null
    Write-Host "Output folder: $OutDir"
}
else {
    # In memory-only mode, just use temp variables (no files written to client)
    $CsvPath = $null
    $HtmlPath = $null
    $LogPath = $null
    $PreflightCsv = $null
    $RestorePs1 = $null
}

# Validate group
try {
  $Group = Get-ADGroup -Identity $GroupName -Properties Member -ErrorAction Stop
} catch {
  Stop-Transcript | Out-Null
  throw "AD group '$GroupName' not found or inaccessible. $_"
}

# Load hostnames
$Hosts = Get-Content -LiteralPath $HostListPath |
  ForEach-Object { $_.Trim() } |
  Where-Object { $_ } |
  Sort-Object -Unique

if (-not $Hosts) {
  Stop-Transcript | Out-Null
  throw "No hostnames found in $HostListPath."
}

# --- Helpers -----------------------------------------------------------------
function Resolve-Computer {
  param([string]$Name)
  try {
    $props = 'Enabled','DistinguishedName','DNSHostName','CanonicalName','ObjectGUID','OperatingSystem','whenCreated','lastLogonDate','sAMAccountName'
    $c = Get-ADComputer -Filter "Name -eq '$Name'" -Properties $props
    if ($c.Count -gt 1) { return @{ Status="DuplicateMatch"; Objects=$c } }
    if ($c) { return @{ Status="Found"; Object=$c } }

    # Fallback: sAMAccountName with $
    $sam = "$Name`$"
    $c = Get-ADComputer -LDAPFilter "(sAMAccountName=$sam)" -Properties $props
    if ($c.Count -gt 1) { return @{ Status="DuplicateMatch"; Objects=$c } }
    if ($c) { return @{ Status="Found"; Object=$c } }

    return @{ Status="NotFound" }
  } catch {
    return @{ Status="LookupError"; Error="$($_.Exception.Message)" }
  }
}

function Test-Membership {
  param($Group, $ComputerDN)
  try { return ($Group.Member -contains $ComputerDN) }
  catch { return $false }
}

# --- Collections --------------------------------------------------------------
$results      = New-Object System.Collections.Generic.List[Object]
$preflight    = New-Object System.Collections.Generic.List[Object]
$restoreLines = New-Object System.Collections.Generic.List[string]

# --- Process -----------------------------------------------------------------
foreach ($h in $Hosts) {

  # Default result row
  $row = [ordered]@{
    Timestamp         = (Get-Date).ToString("s")
    InputHostname     = $h
    ResolvedName      = $null
    DistinguishedName = $null
    OUPath            = $null
    DNSHostName       = $null
    ExistsInAD        = $false
    IsDisabled        = $null
    AlreadyMember     = $false
    Action            = "None"
    Outcome           = "Skipped"
    Roadblock         = $null
    ErrorMessage      = $null
  }

  $res = Resolve-Computer -Name $h

  switch ($res.Status) {
    "Found" {
      $c = $res.Object
      $ouPath = ($c.DistinguishedName -replace '^CN=[^,]+,','')  # strip CN=..., keep OU/DC chain

      # --- Preflight snapshot row
      $preflight.Add([pscustomobject][ordered]@{
        SnapshotTime      = (Get-Date).ToString("s")
        InputHostname     = $h
        ResolvedName      = $c.Name
        OUPath            = $ouPath
        DistinguishedName = $c.DistinguishedName
        CanonicalName     = $c.CanonicalName
        ObjectGUID        = $c.ObjectGUID
        DNSHostName       = $c.DNSHostName
        Enabled           = $c.Enabled
        OperatingSystem   = $c.OperatingSystem
        WhenCreated       = $c.whenCreated
        LastLogonDate     = $c.lastLogonDate
        sAMAccountName    = $c.sAMAccountName
      })

      # --- Build rollback line (GUID-based safe restore)
      $restoreLines.Add("Move-ADObject -Identity `"$($c.ObjectGUID)`" -TargetPath `"$ouPath`"  # $($c.Name)")

      # --- Proceed with group logic
      $row.ExistsInAD        = $true
      $row.ResolvedName      = $c.Name
      $row.DistinguishedName = $c.DistinguishedName
      $row.OUPath            = $ouPath
      $row.DNSHostName       = $c.DNSHostName
      $row.IsDisabled        = $c.Enabled -eq $false

      if ($row.IsDisabled) {
        $row.Roadblock = "Computer account is DISABLED"
        $results.Add([pscustomobject]$row)
        continue
      }

      $already = Test-Membership -Group $Group -ComputerDN $c.DistinguishedName
      $row.AlreadyMember = $already

      if ($already) {
        $row.Action  = "NoChange"
        $row.Outcome = "AlreadyInGroup"
        $results.Add([pscustomobject]$row)
        continue
      }

      try {
        $row.Action = "AddToGroup"
        $target     = $c.DistinguishedName
        $desc       = "Add '$($c.Name)' to '$($Group.Name)'"
        if ($PSCmdlet.ShouldProcess($desc)) {
          Add-ADGroupMember -Identity $Group -Members $target -ErrorAction Stop
        }
        $row.Outcome = "Added"
      } catch {
        $row.Outcome      = "Failed"
        $row.Roadblock    = (($_.Exception.Message) -split "`r?`n")[0]
        $row.ErrorMessage = $_.Exception.ToString()
      }

      $results.Add([pscustomobject]$row)
    }

    "DuplicateMatch" {
      $dnList = ($res.Objects | Select-Object -Expand DistinguishedName) -join '; '
      $preflight.Add([pscustomobject]@{
        SnapshotTime      = (Get-Date).ToString("s")
        InputHostname     = $h
        ResolvedName      = $null
        OUPath            = $null
        DistinguishedName = "AMBIGUOUS: $dnList"
        CanonicalName     = $null
        ObjectGUID        = $null
        DNSHostName       = $null
        Enabled           = $null
        OperatingSystem   = $null
        WhenCreated       = $null
        LastLogonDate     = $null
        sAMAccountName    = $null
      })
      $row.Roadblock    = "Duplicate AD matches (ambiguous name)"
      $row.ErrorMessage = $dnList
      $results.Add([pscustomobject]$row)
    }

    "NotFound" {
      $preflight.Add([pscustomobject]@{
        SnapshotTime      = (Get-Date).ToString("s")
        InputHostname     = $h
        ResolvedName      = $null
        OUPath            = $null
        DistinguishedName = "NOT FOUND"
        CanonicalName     = $null
        ObjectGUID        = $null
        DNSHostName       = $null
        Enabled           = $null
        OperatingSystem   = $null
        WhenCreated       = $null
        LastLogonDate     = $null
        sAMAccountName    = $null
      })
      $row.Roadblock = "Computer not found in AD"
      $results.Add([pscustomobject]$row)
    }

    "LookupError" {
      $preflight.Add([pscustomobject]@{
        SnapshotTime      = (Get-Date).ToString("s")
        InputHostname     = $h
        ResolvedName      = $null
        OUPath            = $null
        DistinguishedName = "LOOKUP ERROR"
        CanonicalName     = $null
        ObjectGUID        = $null
        DNSHostName       = $null
        Enabled           = $null
        OperatingSystem   = $null
        WhenCreated       = $null
        LastLogonDate     = $null
        sAMAccountName    = $null
      })
      $row.Roadblock    = "Directory lookup error"
      $row.ErrorMessage = $res.Error
      $results.Add([pscustomobject]$row)
    }
  }
}

# --- Write snapshot / results -------------------------------------------------
if ($PreflightCsv) {
  $preflight | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $PreflightCsv
  "# Restore original OU placement for each computer (generated $((Get-Date).ToString('s')))
  Import-Module ActiveDirectory
  " | Set-Content -Path $RestorePs1 -Encoding UTF8
  $restoreLines | Add-Content -Path $RestorePs1 -Encoding UTF8

  $results | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $CsvPath

  # Summary HTML
  $added     = ($results | Where-Object Outcome -eq "Added").Count
  $already   = ($results | Where-Object Outcome -eq "AlreadyInGroup").Count
  $failed    = ($results | Where-Object Outcome -eq "Failed").Count
  $notfound  = ($results | Where-Object Roadblock -eq "Computer not found in AD").Count
  $disabled  = ($results | Where-Object Roadblock -eq "Computer account is DISABLED").Count
  $ambiguous = ($results | Where-Object Roadblock -like "Duplicate AD matches*").Count
  $total     = $results.Count

  $summary = @"
  <h2>Windows 10 Printing Group Enrollment</h2>
  <p><b>Group:</b> $($Group.Name)<br/>
  <b>Run Time:</b> $(Get-Date)<br/>
  <b>Total Inputs:</b> $total<br/>
  <b>Added:</b> $added &nbsp; | &nbsp; <b>Already Members:</b> $already &nbsp; | &nbsp; <b>Failed:</b> $failed<br/>
  <b>Not Found:</b> $notfound &nbsp; | &nbsp; <b>Disabled:</b> $disabled &nbsp; | &nbsp; <b>Ambiguous:</b> $ambiguous</p>
  <p><i>Note:</i> See <b>Preflight.csv</b> for each object’s original OU and GUID.
  Use <b>Restore-OU.ps1</b> to revert OU placement if needed.</p>
"@

  ($summary + ($results |
    Select-Object Timestamp,InputHostname,ResolvedName,OUPath,ExistsInAD,IsDisabled,AlreadyMember,Action,Outcome,Roadblock |
    ConvertTo-Html -PreContent "<h3>Per-Host Results</h3>" -As Table |
    Out-String)) |
    Set-Content -Path $HtmlPath -Encoding UTF8

  Stop-Transcript | Out-Null

  Write-Host "`nDone." -ForegroundColor Green
  Write-Host "Preflight snapshot : $PreflightCsv"
  Write-Host "Restore script     : $RestorePs1"
  Write-Host "Results CSV        : $CsvPath"
  Write-Host "HTML summary       : $HtmlPath"
  Write-Host "Transcript         : $LogPath"
}
else {
  Write-Warning "No output directory available. Dumping results to console only."
  $results | Format-Table -AutoSize
}

