#Requires -Version 5.1
<#
.SYNOPSIS
  Shared parsing, normalization, duplicate, and peripherals-site helpers for deployment vs AD reconciliation.
#>

Set-StrictMode -Version Latest

$script:DupIdColumnNames = @(
  'Cybernet Hostname'
  'Cybernet Serial'
  'Neuron Hostname'
  'Neuron MAC'
  'Neuron S/N'
  'Cybernet MAC'
  'Anesthesia S/N'
  'Medical Device S/N'
)

$script:MacStyleColumnNames = @('Neuron MAC', 'Cybernet MAC')

$script:PeripheralsSitePatterns = @(
  '(?i)valley\s+stream'
  '(?i)forest\s+hills'
  '(?i)syosset'
  '(?i)plainview'
)

function Test-IsBlankOrNa {
  param([string]$Value)
  $t = ('' + $Value).Trim()
  if (-not $t) { return $true }
  $l = $t.ToLowerInvariant()
  return ($l -eq 'n/a' -or $l -eq 'na')
}

function ConvertTo-HostnameCompareKey {
  param([string]$Hostname)
  return (('' + $Hostname).Trim().ToUpperInvariant())
}

function ConvertTo-MacCompareKey {
  param([string]$Mac)
  $s = (('' + $Mac).Trim().ToUpperInvariant() -replace '[:\-]', '')
  return $s
}

function Resolve-DeploymentIdNormalized {
  param(
    [Parameter(Mandatory)][string]$ColumnName,
    [string]$Value
  )
  if (Test-IsBlankOrNa -Value $Value) { return '' }
  if ($script:MacStyleColumnNames -contains $ColumnName) {
    return (ConvertTo-MacCompareKey -Mac $Value)
  }
  return (('' + $Value).Trim().ToUpperInvariant())
}

function Get-DeploymentLocationFingerprint {
  param([psobject]$Row)
  $parts = @(
    $Row.'Current Building'
    $Row.'Install Building'
    $Row.'Area/Unit/Dept'
    $Row.Room
    $Row.Bay
  ) | ForEach-Object {
    if ($null -eq $_) { '' } else { ($_.ToString()).Trim().ToLowerInvariant() }
  } | Where-Object { $_ }
  return ($parts -join '|')
}

function Test-PeripheralsAllowedSite {
  param([psobject]$Row)
  $parts = @(
    ($Row.'Current Building')
    ($Row.'Install Building')
    ($Row.'Area/Unit/Dept')
  ) | ForEach-Object { ($_.ToString()).Trim() } | Where-Object { $_ }
  $blob = $parts -join ' '
  if (-not $blob) { return $false }
  foreach ($pat in $script:PeripheralsSitePatterns) {
    if ($blob -match $pat) { return $true }
  }
  return $false
}

function Get-TicketHostnameSet {
  param(
    [Parameter(Mandatory)][object[]]$TicketRows,
    [string]$HostnameColumn = 'Hostname Used'
  )
  $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($r in $TicketRows) {
    $cell = $r.$HostnameColumn
    if ($null -eq $cell) { continue }
    $raw = $cell.ToString()
    foreach ($line in $raw -split "`r?`n") {
      $h = (ConvertTo-HostnameCompareKey -Hostname $line)
      if ($h) { [void]$set.Add($h) }
    }
  }
  return $set
}

function Test-IsDeployedYes {
  param([psobject]$Row)
  $v = ('' + $Row.Deployed).Trim()
  return ($v.ToUpperInvariant() -eq 'YES')
}

function Test-IsNeuronOnlyRow {
  param([psobject]$Row)
  if (-not (Test-IsDeployedYes -Row $Row)) { return $false }
  $dt = ('' + $Row.'Device Type').Trim()
  return ($dt.ToUpperInvariant() -eq 'NEURON')
}

function Set-DeploymentDupMetadata {
  param(
    [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Rows,
    [string[]]$IdColumns = $script:DupIdColumnNames
  )

  $presentCols = @()
  if ($Rows.Count -gt 0) {
    $names = $Rows[0].PSObject.Properties.Name
    foreach ($c in $IdColumns) {
      if ($names -contains $c) { $presentCols += $c }
    }
  }

  # Count normalized values per column among deployed=yes rows only
  $counts = @{}
  foreach ($col in $presentCols) {
    $counts[$col] = @{}
  }

  foreach ($r in $Rows) {
    if (-not (Test-IsDeployedYes -Row $r)) { continue }
    foreach ($col in $presentCols) {
      $nv = Resolve-DeploymentIdNormalized -ColumnName $col -Value ($r.$col)
      if (-not $nv) { continue }
      if (-not $counts[$col].ContainsKey($nv)) { $counts[$col][$nv] = 0 }
      $counts[$col][$nv]++
    }
  }

  # Map (column, normId) -> distinct location fingerprints
  $locMap = @{}
  foreach ($r in $Rows) {
    if (-not (Test-IsDeployedYes -Row $r)) { continue }
    $fp = Get-DeploymentLocationFingerprint -Row $r
    foreach ($col in $presentCols) {
      $nv = Resolve-DeploymentIdNormalized -ColumnName $col -Value ($r.$col)
      if (-not $nv) { continue }
      $key = "$col|$nv"
      if (-not $locMap.ContainsKey($key)) {
        $locMap[$key] = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
      }
      [void]$locMap[$key].Add($fp)
    }
  }

  foreach ($r in $Rows) {
    $dup = $false
    $probCols = [System.Collections.Generic.List[string]]::new()
    if (Test-IsDeployedYes -Row $r) {
      foreach ($col in $presentCols) {
        $nv = Resolve-DeploymentIdNormalized -ColumnName $col -Value ($r.$col)
        if (-not $nv) { continue }
        if ($counts[$col][$nv] -gt 1) { $dup = $true }
        $key = "$col|$nv"
        if ($locMap.ContainsKey($key) -and $locMap[$key].Count -gt 1) {
          $probCols.Add($col)
        }
      }
    }
    $r | Add-Member -NotePropertyName 'DupDeployedCalculated' -NotePropertyValue ($(if ($dup) { 'Yes' } else { 'No' })) -Force
    $r | Add-Member -NotePropertyName 'DuplicateProblematicColumns' -NotePropertyValue (($probCols | Sort-Object -Unique) -join '; ') -Force
    $r | Add-Member -NotePropertyName 'IsNeuronOnly' -NotePropertyValue ($(Test-IsNeuronOnlyRow -Row $r)) -Force
    $dt = ('' + $r.'Device Type').Trim()
    if ($dt.ToUpperInvariant() -eq 'PERIPHERALS') {
      $ok = Test-PeripheralsAllowedSite -Row $r
      $r | Add-Member -NotePropertyName 'PeripheralsAllowedSite' -NotePropertyValue $ok -Force
    }
    else {
      $r | Add-Member -NotePropertyName 'PeripheralsAllowedSite' -NotePropertyValue $null -Force
    }
  }
}

function Set-CybernetReconcileMetadata {
  param(
    [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Rows,
    [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$TicketHostSet,
    [hashtable]$AdLookup
  )

  foreach ($r in $Rows) {
    $cy = ConvertTo-HostnameCompareKey -Hostname ($r.'Cybernet Hostname')
    $inDep = [bool]$cy
    $inTix = $cy -and $TicketHostSet.Contains($cy)
    $inAd = $false
    $adDetail = ''
    if ($cy -and $AdLookup -and $AdLookup.ContainsKey($cy)) {
      $detail = [string]$AdLookup[$cy]
      if ($detail -eq 'NOT_FOUND') {
        $adDetail = 'NOT_FOUND'
      }
      else {
        $inAd = $true
        $adDetail = $detail
      }
    }
    $ours = $inDep -or $inTix
    $onNet = $ours -and $inAd
    $r | Add-Member -NotePropertyName 'Cybernet_InDeployment' -NotePropertyValue $inDep -Force
    $r | Add-Member -NotePropertyName 'Cybernet_InTicketHostnameUsed' -NotePropertyValue $inTix -Force
    $r | Add-Member -NotePropertyName 'Cybernet_Ours' -NotePropertyValue $ours -Force
    $r | Add-Member -NotePropertyName 'Cybernet_InAd' -NotePropertyValue $inAd -Force
    $r | Add-Member -NotePropertyName 'Cybernet_OnNetwork' -NotePropertyValue $onNet -Force
    $r | Add-Member -NotePropertyName 'Cybernet_AdNote' -NotePropertyValue $adDetail -Force
    $r | Add-Member -NotePropertyName 'Neuron_AdLookupSkipped' -NotePropertyValue 'Neurons not queried in AD (hub/medical device)' -Force
  }
}

Export-ModuleMember -Function @(
  'ConvertTo-HostnameCompareKey'
  'ConvertTo-MacCompareKey'
  'Resolve-DeploymentIdNormalized'
  'Get-DeploymentLocationFingerprint'
  'Test-PeripheralsAllowedSite'
  'Get-TicketHostnameSet'
  'Test-IsDeployedYes'
  'Test-IsNeuronOnlyRow'
  'Set-DeploymentDupMetadata'
  'Set-CybernetReconcileMetadata'
  'Test-IsBlankOrNa'
)
