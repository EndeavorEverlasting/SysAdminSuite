<#
.SYNOPSIS
  Retrieves the Windows product key from the local or a remote machine.

.DESCRIPTION
  Pulls the OEM/retail product key from SoftwareLicensingService (WMI) and
  falls back to the registry OA3 Digital Product Id when the WMI class
  returns a blank value (common on OEM installs activated with a digital
  entitlement).

  Output is a PSCustomObject per target with Timestamp, HostName, ProductKey,
  KeySource, Edition, Status, and ErrorMessage columns — the same shape used
  by the other GetInfo scripts so the GUI can display it in a table.

.PARAMETER Targets
  One or more computer names or IPs. Defaults to the local machine.

.PARAMETER OutputPath
  CSV path to write results. Parent directory is created if missing.

.EXAMPLE
  .\Get-WindowsKey.ps1
  # Shows the local machine's key.

.EXAMPLE
  .\Get-WindowsKey.ps1 -Targets SERVER01,PC-LAB02 -OutputPath C:\Temp\Keys.csv
#>

[CmdletBinding()]
param(
  [string[]]$Targets = @($env:COMPUTERNAME),

  [string]$OutputPath = (Join-Path $PSScriptRoot 'Output\WindowsKey\WindowsKey_Output.csv')
)

$ErrorActionPreference = 'Stop'

function Get-KeyFromRegistry {
  <# Try OA3 digital product ID stored by BIOS/UEFI (OEM machines). #>
  param([string]$Computer)
  $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareLicensingTokens'
  $regOA3  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

  $key = $null
  if ($Computer -eq $env:COMPUTERNAME -or $Computer -eq 'localhost' -or $Computer -eq '127.0.0.1') {
    # Local registry
    $key = (Get-ItemProperty -Path $regOA3 -Name 'DigitalProductId' -ErrorAction SilentlyContinue).DigitalProductId
    if (-not $key) {
      # Fallback: OA3xOriginalProductKey (populated on OEM UEFI installs)
      $key = (Get-ItemProperty -Path $regOA3 -Name 'OA3xOriginalProductKey' -ErrorAction SilentlyContinue).OA3xOriginalProductKey
      if ($key) { return @{ Key = $key; Source = 'Registry OA3xOriginalProductKey' } }
    }
  } else {
    # Remote via WinRM
    $key = Invoke-Command -ComputerName $Computer -ScriptBlock {
      $p = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
      $k = (Get-ItemProperty -Path $p -Name 'OA3xOriginalProductKey' -ErrorAction SilentlyContinue).OA3xOriginalProductKey
      if ($k) { return $k }
      return $null
    } -ErrorAction SilentlyContinue
    if ($key) { return @{ Key = $key; Source = 'Registry OA3xOriginalProductKey (remote)' } }
  }
  return $null
}

function Get-KeyFromWMI {
  param([string]$Computer)
  $isLocal = $Computer -eq $env:COMPUTERNAME -or $Computer -eq 'localhost' -or $Computer -eq '127.0.0.1'
  $sls = if ($isLocal) {
    Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction SilentlyContinue
  } else {
    Get-CimInstance -ClassName SoftwareLicensingService -ComputerName $Computer -ErrorAction SilentlyContinue
  }
  if ($sls -and $sls.OA3xOriginalProductKey) {
    return @{ Key = $sls.OA3xOriginalProductKey; Source = 'WMI SoftwareLicensingService' }
  }
  return $null
}

function Get-Edition {
  param([string]$Computer)
  $isLocal = $Computer -eq $env:COMPUTERNAME -or $Computer -eq 'localhost' -or $Computer -eq '127.0.0.1'
  $os = if ($isLocal) {
    Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
  } else {
    Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $Computer -ErrorAction SilentlyContinue
  }
  if ($os) { return $os.Caption }
  return 'Unknown'
}

$results = foreach ($target in $Targets) {
  $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  try {
    $edition = Get-Edition -Computer $target

    # Try WMI first, then registry fallback
    $found = Get-KeyFromWMI -Computer $target
    if (-not $found) { $found = Get-KeyFromRegistry -Computer $target }

    if ($found) {
      [pscustomobject]@{
        Timestamp   = $timestamp
        HostName    = $target
        ProductKey  = $found.Key
        KeySource   = $found.Source
        Edition     = $edition
        Status      = 'OK'
        ErrorMessage = ''
      }
    } else {
      [pscustomobject]@{
        Timestamp   = $timestamp
        HostName    = $target
        ProductKey  = '(not available — digital entitlement or volume license)'
        KeySource   = 'None'
        Edition     = $edition
        Status      = 'NoKey'
        ErrorMessage = ''
      }
    }
  } catch {
    [pscustomobject]@{
      Timestamp    = $timestamp
      HostName     = $target
      ProductKey   = ''
      KeySource    = ''
      Edition      = ''
      Status       = 'Error'
      ErrorMessage = ($_.Exception.Message -split "`r?`n")[0]
    }
  }
}

$results = @($results)
$results | Format-Table HostName, ProductKey, KeySource, Edition, Status -AutoSize | Out-Host

$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
Write-Host "Saved: $OutputPath" -ForegroundColor Green
$results

