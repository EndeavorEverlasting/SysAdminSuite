[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$SourceHost,
  [Parameter(Mandatory)][string[]]$TargetHost,
  [string]$RepoHost = $env:REPO_HOST,
  [string]$RepoRoot,
  [switch]$SkipSupportFiles,
  [switch]$SkipSoftware,
  [switch]$SkipFileHash
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-SASContext {
  param([string]$PreferredRepoRoot, [string]$PreferredRepoHost)

  $anchor =
    if ($PSCommandPath) { Split-Path -Parent $PSCommandPath }
    elseif ($PSScriptRoot) { $PSScriptRoot }
    elseif ($psEditor -and $psEditor.GetEditorContext()) { Split-Path -Parent ($psEditor.GetEditorContext().CurrentFile.Path) }
    else { (Get-Location).Path }

  $cur = Get-Item -LiteralPath $anchor
  while ($cur -and -not (Test-Path (Join-Path $cur.FullName 'config'))) { $cur = $cur.Parent }
  if (-not $cur) { throw "Could not resolve SysAdminSuite root from '$anchor'." }

  $sasRoot = $cur.FullName
  $resolvedRepoRoot =
    if ($PreferredRepoRoot) { $PreferredRepoRoot }
    elseif ($env:REPO_ROOT) { $env:REPO_ROOT }
    elseif ($PreferredRepoHost) { "\\$PreferredRepoHost\SoftwareRepo" }
    elseif (Test-Path (Join-Path $sasRoot 'SoftwareRepo')) { Join-Path $sasRoot 'SoftwareRepo' }
    else { 'C:\SoftwareRepo' }

  foreach ($p in @($resolvedRepoRoot, (Join-Path $resolvedRepoRoot 'inventory'))) {
    if (-not (Test-Path -LiteralPath $p)) {
      New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
  }

  [pscustomobject]@{
    SASRoot  = $sasRoot
    RepoRoot = $resolvedRepoRoot
  }
}

function Ensure-Directory {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Get-SupportFileInventory {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ComputerName,
    [switch]$SkipHash
  )

  $root = "\\$ComputerName\c$\support"
  if (-not (Test-Path -LiteralPath $root)) {
    throw "Support path not reachable: $root"
  }

  $files = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction Stop
  $rows = foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($root.Length).TrimStart('\')
    $hash = $null
    if (-not $SkipHash) {
      try { $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName -ErrorAction Stop).Hash }
      catch { $hash = '[hash-failed]' }
    }

    [pscustomobject]@{
      Host         = $ComputerName
      RootPath     = $root
      RelativePath = $relativePath
      FileName     = $file.Name
      Extension    = $file.Extension
      SizeBytes    = [int64]$file.Length
      LastWriteUtc = $file.LastWriteTimeUtc.ToString('s')
      HashSHA256   = $hash
    }
  }

  @($rows | Sort-Object RelativePath)
}

function New-SupportDiff {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][object[]]$SourceRows,
    [Parameter(Mandatory)][object[]]$TargetRows,
    [Parameter(Mandatory)][string]$SourceHost,
    [Parameter(Mandatory)][string]$TargetHost
  )

  $sourceMap = @{}
  foreach ($r in $SourceRows) { $sourceMap[$r.RelativePath.ToLowerInvariant()] = $r }

  $targetMap = @{}
  foreach ($r in $TargetRows) { $targetMap[$r.RelativePath.ToLowerInvariant()] = $r }

  $allKeys = @($sourceMap.Keys + $targetMap.Keys | Sort-Object -Unique)
  $outRows = foreach ($key in $allKeys) {
    $s = if ($sourceMap.ContainsKey($key)) { $sourceMap[$key] } else { $null }
    $t = if ($targetMap.ContainsKey($key)) { $targetMap[$key] } else { $null }

    $status =
      if ($null -eq $t) { 'MissingOnTarget' }
      elseif ($null -eq $s) { 'ExtraOnTarget' }
      elseif ($s.HashSHA256 -and $t.HashSHA256 -and $s.HashSHA256 -ne $t.HashSHA256) { 'Changed' }
      elseif ($s.SizeBytes -ne $t.SizeBytes -or $s.LastWriteUtc -ne $t.LastWriteUtc) { 'Changed' }
      else { 'Match' }

    [pscustomobject]@{
      SourceHost        = $SourceHost
      TargetHost        = $TargetHost
      Status            = $status
      RelativePath      = if ($s) { $s.RelativePath } else { $t.RelativePath }
      SourceSizeBytes   = if ($s) { $s.SizeBytes } else { $null }
      TargetSizeBytes   = if ($t) { $t.SizeBytes } else { $null }
      SourceLastWrite   = if ($s) { $s.LastWriteUtc } else { $null }
      TargetLastWrite   = if ($t) { $t.LastWriteUtc } else { $null }
      SourceHashSHA256  = if ($s) { $s.HashSHA256 } else { $null }
      TargetHashSHA256  = if ($t) { $t.HashSHA256 } else { $null }
    }
  }

  @($outRows | Sort-Object Status, RelativePath)
}

function New-SoftwareDiff {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][object[]]$SourceRows,
    [Parameter(Mandatory)][object[]]$TargetRows,
    [Parameter(Mandatory)][string]$SourceHost,
    [Parameter(Mandatory)][string]$TargetHost
  )

  function Get-SoftwareKey {
    param([object]$Row)
    $name = "$($Row.Name)".Trim().ToLowerInvariant()
    $publisher = "$($Row.Publisher)".Trim().ToLowerInvariant()
    "$name|$publisher"
  }

  $sourceMap = @{}
  foreach ($r in $SourceRows) { $sourceMap[(Get-SoftwareKey -Row $r)] = $r }

  $targetMap = @{}
  foreach ($r in $TargetRows) { $targetMap[(Get-SoftwareKey -Row $r)] = $r }

  $allKeys = @($sourceMap.Keys + $targetMap.Keys | Sort-Object -Unique)
  $outRows = foreach ($key in $allKeys) {
    $s = if ($sourceMap.ContainsKey($key)) { $sourceMap[$key] } else { $null }
    $t = if ($targetMap.ContainsKey($key)) { $targetMap[$key] } else { $null }

    $status =
      if ($null -eq $t) { 'MissingOnTarget' }
      elseif ($null -eq $s) { 'ExtraOnTarget' }
      elseif ("$($s.Version)".Trim() -ne "$($t.Version)".Trim()) { 'VersionMismatch' }
      else { 'Match' }

    [pscustomobject]@{
      SourceHost    = $SourceHost
      TargetHost    = $TargetHost
      Status        = $status
      Name          = if ($s) { $s.Name } else { $t.Name }
      Publisher     = if ($s) { $s.Publisher } else { $t.Publisher }
      SourceVersion = if ($s) { $s.Version } else { $null }
      TargetVersion = if ($t) { $t.Version } else { $null }
    }
  }

  @($outRows | Sort-Object Status, Name, Publisher)
}

function Write-SuiteTableReport {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][object[]]$Rows,
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$Subtitle,
    [Parameter(Mandatory)][string]$OutputPath,
    [string[]]$Columns
  )

  $helper = Join-Path $PSScriptRoot '..\tools\ConvertTo-SuiteHtml.ps1'
  if (-not (Test-Path -LiteralPath $helper)) {
    throw "Missing helper: $helper"
  }
  . $helper

  $chips = @(
    "Rows: $($Rows.Count)"
  )

  if ($Rows.Count -gt 0 -and ($Rows[0].PSObject.Properties.Name -contains 'Status')) {
    $chips += ($Rows | Group-Object Status | Sort-Object Name | ForEach-Object { "$($_.Name): $($_.Count)" })
  }

  $view = if ($Columns -and $Columns.Count -gt 0) { $Rows | Select-Object -Property $Columns } else { $Rows }
  $fragment = $view | ConvertTo-Html -Fragment
  ConvertTo-SuiteHtml -Title $Title -Subtitle $Subtitle -SummaryChips $chips -OutputPath $OutputPath -BodyFragment $fragment
}

$ctx = Resolve-SASContext -PreferredRepoRoot $RepoRoot -PreferredRepoHost $RepoHost
$resolvedRepoRoot = $ctx.RepoRoot
$inventoryRoot = Join-Path $resolvedRepoRoot 'inventory'
Ensure-Directory -Path $inventoryRoot

$targets = @($TargetHost | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
if ($targets.Count -eq 0) { throw 'TargetHost list is empty.' }
if ($targets -contains $SourceHost) {
  $targets = @($targets | Where-Object { $_ -ne $SourceHost })
  Write-Warning "Removed source host '$SourceHost' from target list."
}
if ($targets.Count -eq 0) { throw 'TargetHost list only contained SourceHost.' }

$allHosts = @($SourceHost) + $targets
$comparisonRoot = Join-Path $inventoryRoot 'comparisons'
Ensure-Directory -Path $comparisonRoot
$runRoot = Join-Path $comparisonRoot ("run_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
Ensure-Directory -Path $runRoot

Write-Host "Using RepoRoot: $resolvedRepoRoot" -ForegroundColor Cyan
Write-Host "Comparison output: $runRoot" -ForegroundColor Cyan

$supportInventoryByHost = @{}
if (-not $SkipSupportFiles) {
  Write-Host 'Collecting support file inventories...' -ForegroundColor Cyan
  foreach ($hostName in $allHosts) {
    $rows = Get-SupportFileInventory -ComputerName $hostName -SkipHash:$SkipFileHash
    $supportInventoryByHost[$hostName] = $rows

    $hostDir = Join-Path $inventoryRoot $hostName
    Ensure-Directory -Path $hostDir
    $csvPath = Join-Path $hostDir ("support_files_{0}.csv" -f $hostName)
    $htmlPath = [IO.Path]::ChangeExtension($csvPath, '.html')

    $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csvPath
    Write-SuiteTableReport -Rows $rows -Title "Support File Inventory - $hostName" -Subtitle "\\$hostName\c$\support" -OutputPath $htmlPath -Columns @('RelativePath', 'SizeBytes', 'LastWriteUtc', 'HashSHA256')
    Write-Host "Wrote support inventory for $hostName => $csvPath" -ForegroundColor Green
  }

  foreach ($target in $targets) {
    $diff = New-SupportDiff -SourceRows $supportInventoryByHost[$SourceHost] -TargetRows $supportInventoryByHost[$target] -SourceHost $SourceHost -TargetHost $target
    $diffCsv = Join-Path $runRoot ("support_diff_{0}_vs_{1}.csv" -f $SourceHost, $target)
    $diffHtml = [IO.Path]::ChangeExtension($diffCsv, '.html')
    $diff | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $diffCsv
    Write-SuiteTableReport -Rows $diff -Title "Support File Diff - $SourceHost vs $target" -Subtitle "\\$SourceHost\c$\support compared to \\$target\c$\support" -OutputPath $diffHtml -Columns @('Status', 'RelativePath', 'SourceSizeBytes', 'TargetSizeBytes', 'SourceLastWrite', 'TargetLastWrite')
    Write-Host "Wrote support diff => $diffCsv" -ForegroundColor Green
  }
}

$softwareInventoryByHost = @{}
if (-not $SkipSoftware) {
  Write-Host 'Collecting software inventories...' -ForegroundColor Cyan
  $invSoftwareScript = Join-Path $PSScriptRoot 'Inventory-Software.ps1'
  if (-not (Test-Path -LiteralPath $invSoftwareScript)) {
    throw "Missing software inventory script: $invSoftwareScript"
  }
  & $invSoftwareScript -ComputerName $allHosts -RepoRoot $resolvedRepoRoot

  foreach ($hostName in $allHosts) {
    $hostCsv = Join-Path (Join-Path $inventoryRoot $hostName) ("installed_software_{0}.csv" -f $hostName)
    if (-not (Test-Path -LiteralPath $hostCsv)) {
      throw "Expected software inventory missing: $hostCsv"
    }
    $softwareInventoryByHost[$hostName] = @(Import-Csv -Path $hostCsv)
  }

  foreach ($target in $targets) {
    $diff = New-SoftwareDiff -SourceRows $softwareInventoryByHost[$SourceHost] -TargetRows $softwareInventoryByHost[$target] -SourceHost $SourceHost -TargetHost $target
    $diffCsv = Join-Path $runRoot ("software_diff_{0}_vs_{1}.csv" -f $SourceHost, $target)
    $diffHtml = [IO.Path]::ChangeExtension($diffCsv, '.html')
    $diff | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $diffCsv
    Write-SuiteTableReport -Rows $diff -Title "Software Diff - $SourceHost vs $target" -Subtitle "Installed software comparison" -OutputPath $diffHtml -Columns @('Status', 'Name', 'Publisher', 'SourceVersion', 'TargetVersion')
    Write-Host "Wrote software diff => $diffCsv" -ForegroundColor Green
  }
}

Write-Host 'Compare-HostInventory complete.' -ForegroundColor Green
