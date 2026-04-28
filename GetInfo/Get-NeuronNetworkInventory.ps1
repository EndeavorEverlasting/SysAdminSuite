#Requires -Version 5.1
<#
.SYNOPSIS
  Surveys Neuron hosts from an admin workstation and writes inventory artifacts locally.

.DESCRIPTION
  Reads a target list of known or partially tracked Neuron hosts, queries each host remotely for BIOS serial, model, IP, and MAC data, then exports CSV, JSON, and optional HTML artifacts on the admin box.

  This script does not copy payloads, create scheduled tasks, or write artifacts on target machines.
#>
[CmdletBinding()]
param(
  [string]$ListPath = (Join-Path $PSScriptRoot 'Config/NeuronTargets.csv'),
  [string[]]$Targets,
  [string]$OutputDirectory = (Join-Path $PSScriptRoot 'Output/NeuronNetworkInventory'),
  [int]$Throttle = 15,
  [int]$PingCount = 1,
  [switch]$SkipPing,
  [switch]$NoHtml,
  [System.Management.Automation.PSCredential]$Credential
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Normalize-MacAddress {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
  $clean = ($Value.ToUpperInvariant().ToCharArray() | Where-Object { $_ -match '[0-9A-F]' }) -join ''
  if ($clean.Length -ne 12) { return $clean }
  $pairs = for ($i = 0; $i -lt 12; $i += 2) { $clean.Substring($i, 2) }
  return ($pairs -join ':')
}

function Split-IdentifierList {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
  return @($Value -split '[;, ]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-FirstPropertyValue {
  param(
    [object]$Row,
    [string[]]$Names
  )
  foreach ($name in $Names) {
    $prop = $Row.PSObject.Properties[$name]
    if ($prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
      return ([string]$prop.Value).Trim()
    }
  }
  return ''
}

function New-NeuronTarget {
  param(
    [string]$HostName,
    [string]$ExpectedMac,
    [string]$ExpectedSerial,
    [string]$Site,
    [string]$Room,
    [string]$Notes
  )
  [pscustomobject]@{
    HostName = $HostName
    ExpectedMAC = $ExpectedMac
    ExpectedSerial = $ExpectedSerial
    Site = $Site
    Room = $Room
    Notes = $Notes
  }
}

function Import-NeuronTargets {
  param(
    [string]$Path,
    [string[]]$DirectTargets
  )

  if ($DirectTargets -and $DirectTargets.Count -gt 0) {
    return @($DirectTargets | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
      New-NeuronTarget -HostName $_.Trim() -ExpectedMac '' -ExpectedSerial '' -Site '' -Room '' -Notes 'Direct target'
    })
  }

  if (-not (Test-Path -LiteralPath $Path)) { throw ('Target list not found: {0}' -f $Path) }

  $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
  if ($extension -eq '.csv') {
    $rows = @(Import-Csv -LiteralPath $Path)
    return @($rows | ForEach-Object {
      $hostName = Get-FirstPropertyValue -Row $_ -Names @('NeuronHost','HostName','ComputerName','Target','Name')
      if ([string]::IsNullOrWhiteSpace($hostName)) { return }
      New-NeuronTarget `
        -HostName $hostName `
        -ExpectedMac (Get-FirstPropertyValue -Row $_ -Names @('ExpectedMAC','ExpectedMac','NeuronMAC','MACAddress','MAC')) `
        -ExpectedSerial (Get-FirstPropertyValue -Row $_ -Names @('ExpectedSerial','NeuronSerial','SerialNumber','Serial')) `
        -Site (Get-FirstPropertyValue -Row $_ -Names @('Site','Building','Facility')) `
        -Room (Get-FirstPropertyValue -Row $_ -Names @('Room','Location','Area')) `
        -Notes (Get-FirstPropertyValue -Row $_ -Names @('Notes','Comment','Comments'))
    })
  }

  return @(Get-Content -LiteralPath $Path | ForEach-Object { $_.Trim() } | Where-Object {
    $_ -and -not $_.StartsWith('#')
  } | ForEach-Object {
    New-NeuronTarget -HostName $_ -ExpectedMac '' -ExpectedSerial '' -Site '' -Room '' -Notes 'Text target'
  })
}

function Start-NeuronInventoryJob {
  param(
    [pscustomobject]$Target,
    [int]$PingCountValue,
    [bool]$SkipPingValue,
    [System.Management.Automation.PSCredential]$CredentialValue
  )

  Start-Job -Name ('Neuron_{0}' -f $Target.HostName) -ScriptBlock {
    param($Target, $PingCountValue, $SkipPingValue, $CredentialValue)

    function Normalize-MacAddressInner {
      param([string]$Value)
      if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
      $clean = ($Value.ToUpperInvariant().ToCharArray() | Where-Object { $_ -match '[0-9A-F]' }) -join ''
      if ($clean.Length -ne 12) { return $clean }
      $pairs = for ($i = 0; $i -lt 12; $i += 2) { $clean.Substring($i, 2) }
      return ($pairs -join ':')
    }

    function Split-IdentifierListInner {
      param([string]$Value)
      if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
      return @($Value -split '[;, ]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    function New-ResultRow {
      param(
        [string]$Status,
        [string]$ErrorMessage,
        [string]$ResolvedName,
        [string]$IPAddress,
        [string]$MACAddress,
        [string]$PrimaryMAC,
        [string]$SerialNumber,
        [string]$SystemSerialNumber,
        [string]$UUID,
        [string]$Manufacturer,
        [string]$Model,
        [string]$AdapterNames,
        [string]$MatchExpectedMac,
        [string]$MatchExpectedSerial
      )
      [pscustomobject]@{
        Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        TargetHost = $Target.HostName
        ResolvedName = $ResolvedName
        Site = $Target.Site
        Room = $Target.Room
        ExpectedMAC = $Target.ExpectedMAC
        ExpectedSerial = $Target.ExpectedSerial
        IPAddress = $IPAddress
        MACAddress = $MACAddress
        PrimaryMAC = $PrimaryMAC
        SerialNumber = $SerialNumber
        SystemSerialNumber = $SystemSerialNumber
        UUID = $UUID
        Manufacturer = $Manufacturer
        Model = $Model
        NetworkAdapterNames = $AdapterNames
        MatchExpectedMAC = $MatchExpectedMac
        MatchExpectedSerial = $MatchExpectedSerial
        Status = $Status
        ErrorMessage = $ErrorMessage
        TargetSideArtifacts = 'None'
        Notes = $Target.Notes
      }
    }

    function Invoke-WmiQuery {
      param(
        [string]$ClassName,
        [string]$ComputerName,
        [bool]$Local,
        [string]$Filter
      )
      $params = @{ Class = $ClassName; ErrorAction = 'Stop' }
      if (-not [string]::IsNullOrWhiteSpace($Filter)) { $params.Filter = $Filter }
      if (-not $Local) { $params.ComputerName = $ComputerName }
      if ($CredentialValue -and -not $Local) { $params.Credential = $CredentialValue }
      Get-WmiObject @params
    }

    $computerName = $Target.HostName
    $isLocal = $computerName -eq $env:COMPUTERNAME -or $computerName -eq 'localhost' -or $computerName -eq '127.0.0.1' -or $computerName -eq '.'
    $resolvedName = ''

    try {
      $dns = [System.Net.Dns]::GetHostEntry($computerName)
      if ($dns -and $dns.HostName) { $resolvedName = $dns.HostName }
    } catch { }

    $reachable = $true
    if (-not $isLocal -and -not $SkipPingValue) {
      $reachable = Test-Connection -ComputerName $computerName -Count $PingCountValue -Quiet -ErrorAction SilentlyContinue
    }

    if (-not $reachable) {
      return New-ResultRow -Status 'Offline' -ErrorMessage '' -ResolvedName $resolvedName -IPAddress '' -MACAddress '' -PrimaryMAC '' -SerialNumber '' -SystemSerialNumber '' -UUID '' -Manufacturer '' -Model '' -AdapterNames '' -MatchExpectedMac 'NotChecked' -MatchExpectedSerial 'NotChecked'
    }

    try {
      $bios = Invoke-WmiQuery -ClassName 'Win32_BIOS' -ComputerName $computerName -Local $isLocal
      $system = Invoke-WmiQuery -ClassName 'Win32_ComputerSystem' -ComputerName $computerName -Local $isLocal
      $product = Invoke-WmiQuery -ClassName 'Win32_ComputerSystemProduct' -ComputerName $computerName -Local $isLocal
      $nics = @(Invoke-WmiQuery -ClassName 'Win32_NetworkAdapterConfiguration' -ComputerName $computerName -Local $isLocal -Filter 'IPEnabled=TRUE')

      $ipv4s = @()
      $macs = @()
      $adapterNames = @()
      foreach ($nic in $nics) {
        foreach ($addr in @($nic.IPAddress)) {
          $parsed = $null
          if ([System.Net.IPAddress]::TryParse([string]$addr, [ref]$parsed) -and $parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
            $ipv4s += [string]$addr
          }
        }
        if ($nic.MACAddress) { $macs += (Normalize-MacAddressInner $nic.MACAddress) }
        if ($nic.Description) { $adapterNames += $nic.Description }
      }

      $expectedMacs = @(Split-IdentifierListInner $Target.ExpectedMAC | ForEach-Object { Normalize-MacAddressInner $_ } | Where-Object { $_ })
      $actualMacs = @($macs | Where-Object { $_ } | Sort-Object -Unique)
      $matchMac = 'NotProvided'
      if ($expectedMacs.Count -gt 0) {
        $matchMac = 'No'
        foreach ($expected in $expectedMacs) {
          if ($actualMacs -contains $expected) { $matchMac = 'Yes' }
        }
      }

      $serial = [string]$bios.SerialNumber
      $systemSerial = [string]$product.IdentifyingNumber
      $uuid = [string]$product.UUID
      $expectedSerials = @(Split-IdentifierListInner $Target.ExpectedSerial | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ })
      $actualSerials = @($serial, $systemSerial | ForEach-Object { ([string]$_).Trim().ToUpperInvariant() } | Where-Object { $_ })
      $matchSerial = 'NotProvided'
      if ($expectedSerials.Count -gt 0) {
        $matchSerial = 'No'
        foreach ($expectedSerial in $expectedSerials) {
          if ($actualSerials -contains $expectedSerial) { $matchSerial = 'Yes' }
        }
      }

      return New-ResultRow `
        -Status 'OK' `
        -ErrorMessage '' `
        -ResolvedName $resolvedName `
        -IPAddress (($ipv4s | Sort-Object -Unique) -join ';') `
        -MACAddress ($actualMacs -join ';') `
        -PrimaryMAC ($actualMacs | Select-Object -First 1) `
        -SerialNumber $serial `
        -SystemSerialNumber $systemSerial `
        -UUID $uuid `
        -Manufacturer ([string]$system.Manufacturer) `
        -Model ([string]$system.Model) `
        -AdapterNames (($adapterNames | Sort-Object -Unique) -join ';') `
        -MatchExpectedMac $matchMac `
        -MatchExpectedSerial $matchSerial
    }
    catch {
      return New-ResultRow -Status 'Query Failed' -ErrorMessage $_.Exception.Message -ResolvedName $resolvedName -IPAddress '' -MACAddress '' -PrimaryMAC '' -SerialNumber '' -SystemSerialNumber '' -UUID '' -Manufacturer '' -Model '' -AdapterNames '' -MatchExpectedMac 'NotChecked' -MatchExpectedSerial 'NotChecked'
    }
  } -ArgumentList $Target, $PingCountValue, $SkipPingValue, $CredentialValue
}

$targetRows = @(Import-NeuronTargets -Path $ListPath -DirectTargets $Targets)
if (-not $targetRows -or $targetRows.Count -eq 0) { throw 'No Neuron targets were found.' }

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
  New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$runStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvPath = Join-Path $OutputDirectory ('NeuronNetworkInventory_{0}.csv' -f $runStamp)
$jsonPath = Join-Path $OutputDirectory ('NeuronNetworkInventory_{0}.json' -f $runStamp)
$htmlPath = Join-Path $OutputDirectory ('NeuronNetworkInventory_{0}.html' -f $runStamp)

$jobs = @()
foreach ($targetRow in $targetRows) {
  $runningJobs = @($jobs | Where-Object { $_.State -eq 'Running' })
  while ($runningJobs.Count -ge $Throttle) {
    Wait-Job -Any $runningJobs | Out-Null
    $runningJobs = @($jobs | Where-Object { $_.State -eq 'Running' })
  }
  $jobs += Start-NeuronInventoryJob -Target $targetRow -PingCountValue $PingCount -SkipPingValue $SkipPing.IsPresent -CredentialValue $Credential
}

if ($jobs.Count -gt 0) { Wait-Job -Job $jobs | Out-Null }
$results = @($jobs | Receive-Job)
$jobs | Remove-Job -Force | Out-Null

$sorted = @($results | Sort-Object TargetHost)
$sorted | Export-Csv -LiteralPath $csvPath -NoTypeInformation
$sorted | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

if (-not $NoHtml) {
  $suiteHtmlHelper = Join-Path $PSScriptRoot '../tools/ConvertTo-SuiteHtml.ps1'
  if (Test-Path -LiteralPath $suiteHtmlHelper) {
    . $suiteHtmlHelper
    $subtitle = ('{0} target(s). Artifacts written on admin box only.' -f $sorted.Count)
    $sorted |
      Select-Object TargetHost,Site,Room,IPAddress,PrimaryMAC,MACAddress,SerialNumber,SystemSerialNumber,Model,MatchExpectedMAC,MatchExpectedSerial,Status,ErrorMessage,TargetSideArtifacts |
      ConvertTo-Html -Fragment -PreContent '<h2>Neuron Network Inventory</h2>' |
      ConvertTo-SuiteHtml -Title 'Neuron Network Inventory' -Subtitle $subtitle -OutputPath $htmlPath
  }
}

Write-Host ('Neuron inventory complete. CSV: {0}' -f $csvPath) -ForegroundColor Green
Write-Host ('JSON: {0}' -f $jsonPath) -ForegroundColor Green
if ((Test-Path -LiteralPath $htmlPath) -and -not $NoHtml) { Write-Host ('HTML: {0}' -f $htmlPath) -ForegroundColor Green }
$sorted
