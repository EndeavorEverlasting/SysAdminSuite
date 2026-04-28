#Requires -Version 5.1
<#
.SYNOPSIS
  Converts a downloaded deployment tracker workbook into SysAdminSuite target CSV files.

.DESCRIPTION
  Reads .xlsx files directly as Open XML zip packages. No Excel COM, no ImportExcel module, and no workbook edits.
  The first implementation is tuned for Neuron inventory, but the column alias map is intentionally expandable for Cybernets and other device classes.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$WorkbookPath,

  [ValidateSet('Neuron','Cybernet','Generic')]
  [string]$DeviceType = 'Neuron',

  [string]$WorksheetName,

  [string]$OutputPath = (Join-Path $PSScriptRoot 'Config/NeuronTargets.csv'),

  [string]$UnresolvedOutputPath,

  [int]$HeaderScanRows = 40
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Normalize-HeaderKey {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
  return (($Value.ToLowerInvariant().ToCharArray() | Where-Object { $_ -match '[a-z0-9]' }) -join '')
}

function Get-ZipEntryText {
  param(
    [System.IO.Compression.ZipArchive]$Zip,
    [string]$EntryName
  )
  $normalized = $EntryName.Replace('\\','/')
  $entry = $Zip.GetEntry($normalized)
  if (-not $entry) { return $null }
  $reader = New-Object System.IO.StreamReader($entry.Open())
  try { return $reader.ReadToEnd() }
  finally { $reader.Dispose() }
}

function Get-AttrValueByLocalName {
  param(
    [System.Xml.XmlNode]$Node,
    [string]$LocalName
  )
  foreach ($attr in $Node.Attributes) {
    if ($attr.LocalName -eq $LocalName) { return $attr.Value }
  }
  return ''
}

function Convert-ExcelColumnToNumber {
  param([string]$ColumnName)
  $sum = 0
  foreach ($char in $ColumnName.ToUpperInvariant().ToCharArray()) {
    if ($char -lt 'A' -or $char -gt 'Z') { continue }
    $sum = ($sum * 26) + ([int][char]$char - [int][char]'A' + 1)
  }
  return $sum
}

function Resolve-SheetPath {
  param([string]$Target)
  $clean = $Target.Replace('\\','/').TrimStart('/')
  if ($clean.StartsWith('xl/')) { return $clean }
  return ('xl/{0}' -f $clean)
}

function Get-SharedStrings {
  param([System.IO.Compression.ZipArchive]$Zip)
  $text = Get-ZipEntryText -Zip $Zip -EntryName 'xl/sharedStrings.xml'
  if ([string]::IsNullOrWhiteSpace($text)) { return @() }
  [xml]$xml = $text
  $items = New-Object System.Collections.Generic.List[string]
  foreach ($si in $xml.SelectNodes("//*[local-name()='si']")) {
    $parts = @()
    foreach ($t in $si.SelectNodes(".//*[local-name()='t']")) { $parts += $t.InnerText }
    $items.Add(($parts -join '')) | Out-Null
  }
  return $items.ToArray()
}

function Get-WorkbookSheets {
  param([System.IO.Compression.ZipArchive]$Zip)
  [xml]$workbook = Get-ZipEntryText -Zip $Zip -EntryName 'xl/workbook.xml'
  [xml]$rels = Get-ZipEntryText -Zip $Zip -EntryName 'xl/_rels/workbook.xml.rels'

  $relMap = @{}
  foreach ($rel in $rels.SelectNodes("//*[local-name()='Relationship']")) {
    $relMap[$rel.Id] = $rel.Target
  }

  $sheets = @()
  foreach ($sheet in $workbook.SelectNodes("//*[local-name()='sheet']")) {
    $id = Get-AttrValueByLocalName -Node $sheet -LocalName 'id'
    if (-not $relMap.ContainsKey($id)) { continue }
    $sheets += [pscustomobject]@{
      Name = $sheet.name
      Path = Resolve-SheetPath -Target $relMap[$id]
    }
  }
  return $sheets
}

function Get-CellText {
  param(
    [System.Xml.XmlNode]$Cell,
    [string[]]$SharedStrings
  )

  $type = $Cell.GetAttribute('t')
  if ($type -eq 'inlineStr') {
    $inlineText = $Cell.SelectSingleNode(".//*[local-name()='t']")
    if ($inlineText) { return $inlineText.InnerText }
    return ''
  }

  $valueNode = $Cell.SelectSingleNode("./*[local-name()='v']")
  if (-not $valueNode) { return '' }
  $raw = $valueNode.InnerText

  if ($type -eq 's') {
    $index = 0
    if ([int]::TryParse($raw, [ref]$index) -and $index -ge 0 -and $index -lt $SharedStrings.Count) {
      return $SharedStrings[$index]
    }
  }

  return $raw
}

function Read-WorksheetRows {
  param(
    [System.IO.Compression.ZipArchive]$Zip,
    [string]$SheetPath,
    [string[]]$SharedStrings
  )

  $sheetText = Get-ZipEntryText -Zip $Zip -EntryName $SheetPath
  if ([string]::IsNullOrWhiteSpace($sheetText)) { return @() }
  [xml]$sheetXml = $sheetText

  $rows = @()
  foreach ($rowNode in $sheetXml.SelectNodes("//*[local-name()='sheetData']/*[local-name()='row']")) {
    $rowIndex = [int]$rowNode.GetAttribute('r')
    $cells = @{}
    $maxColumn = 0
    foreach ($cell in $rowNode.SelectNodes("./*[local-name()='c']")) {
      $ref = $cell.GetAttribute('r')
      if ($ref -match '^([A-Z]+)') {
        $columnIndex = Convert-ExcelColumnToNumber -ColumnName $Matches[1]
        $cells[$columnIndex] = Get-CellText -Cell $cell -SharedStrings $SharedStrings
        if ($columnIndex -gt $maxColumn) { $maxColumn = $columnIndex }
      }
    }
    $values = for ($i = 1; $i -le $maxColumn; $i++) {
      if ($cells.ContainsKey($i)) { [string]$cells[$i] } else { '' }
    }
    $rows += [pscustomobject]@{ RowNumber = $rowIndex; Values = @($values) }
  }
  return $rows
}

function Get-AliasMap {
  param([string]$Type)

  $common = @{
    Site = @('site','building','facility','currentbuilding','installbuilding')
    Room = @('room','location','area','or','orroom','installroom','currentroom')
    Notes = @('notes','note','comments','comment','deploymentnotes')
    DeviceClass = @('devicetype','deviceclass','medicaldeviceclass','class','type')
  }

  switch ($Type) {
    'Neuron' {
      return $common + @{
        Host = @('neuronhostname','neuronhost','neuronname','neuronpc','neuroncomputername','neuron')
        Mac = @('neuronmac','neuronmacaddress','macaddress','mac')
        Serial = @('neuronserial','neuronserialnumber','serialnumber','serial','neurondeviceserial')
      }
    }
    'Cybernet' {
      return $common + @{
        Host = @('cybernethostname','cybernethost','cybernetname','computername','hostname')
        Mac = @('cybernetmac','cybernetmacaddress','macaddress','mac')
        Serial = @('cybernetserial','cybernetserialnumber','serialnumber','serial')
      }
    }
    default {
      return $common + @{
        Host = @('hostname','host','computername','target','name')
        Mac = @('mac','macaddress','expectedmac')
        Serial = @('serial','serialnumber','expectedserial')
      }
    }
  }
}

function Find-HeaderRow {
  param(
    [object[]]$Rows,
    [hashtable]$AliasMap,
    [int]$ScanLimit
  )

  $aliases = @{}
  foreach ($key in $AliasMap.Keys) {
    foreach ($alias in $AliasMap[$key]) { $aliases[$alias] = $key }
  }

  foreach ($row in ($Rows | Select-Object -First $ScanLimit)) {
    $score = 0
    foreach ($value in $row.Values) {
      $header = Normalize-HeaderKey $value
      if ($aliases.ContainsKey($header)) { $score++ }
    }
    if ($score -ge 2) { return $row }
  }
  return $null
}

function Build-ColumnMap {
  param(
    [object]$HeaderRow,
    [hashtable]$AliasMap
  )

  $columnMap = @{}
  for ($i = 0; $i -lt $HeaderRow.Values.Count; $i++) {
    $header = Normalize-HeaderKey $HeaderRow.Values[$i]
    foreach ($field in $AliasMap.Keys) {
      if ($AliasMap[$field] -contains $header -and -not $columnMap.ContainsKey($field)) {
        $columnMap[$field] = $i
      }
    }
  }
  return $columnMap
}

function Get-ValueFromColumnMap {
  param(
    [object]$Row,
    [hashtable]$ColumnMap,
    [string]$Field
  )
  if (-not $ColumnMap.ContainsKey($Field)) { return '' }
  $index = $ColumnMap[$Field]
  if ($index -ge $Row.Values.Count) { return '' }
  return ([string]$Row.Values[$index]).Trim()
}

if (-not (Test-Path -LiteralPath $WorkbookPath)) { throw ('Workbook not found: {0}' -f $WorkbookPath) }
if ([IO.Path]::GetExtension($WorkbookPath).ToLowerInvariant() -ne '.xlsx') { throw 'Only .xlsx workbooks are supported.' }

if ([string]::IsNullOrWhiteSpace($UnresolvedOutputPath)) {
  $directory = Split-Path -Path $OutputPath -Parent
  if ([string]::IsNullOrWhiteSpace($directory)) { $directory = (Get-Location).Path }
  $baseName = [IO.Path]::GetFileNameWithoutExtension($OutputPath)
  $UnresolvedOutputPath = Join-Path $directory ('{0}.unresolved.csv' -f $baseName)
}

$outDir = Split-Path -Path $OutputPath -Parent
if ([string]::IsNullOrWhiteSpace($outDir)) { $outDir = (Get-Location).Path }
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$unresolvedDir = Split-Path -Path $UnresolvedOutputPath -Parent
if ([string]::IsNullOrWhiteSpace($unresolvedDir)) { $unresolvedDir = (Get-Location).Path }
if (-not (Test-Path -LiteralPath $unresolvedDir)) { New-Item -ItemType Directory -Path $unresolvedDir -Force | Out-Null }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $WorkbookPath).Path)
try {
  $sharedStrings = @(Get-SharedStrings -Zip $zip)
  $sheets = @(Get-WorkbookSheets -Zip $zip)
  if ($WorksheetName) { $sheets = @($sheets | Where-Object { $_.Name -eq $WorksheetName }) }
  if (-not $sheets -or $sheets.Count -eq 0) { throw 'No matching worksheet was found.' }

  $aliasMap = Get-AliasMap -Type $DeviceType
  $targets = @()
  $unresolved = @()

  foreach ($sheet in $sheets) {
    $rows = @(Read-WorksheetRows -Zip $zip -SheetPath $sheet.Path -SharedStrings $sharedStrings)
    if (-not $rows -or $rows.Count -eq 0) { continue }

    $headerRow = Find-HeaderRow -Rows $rows -AliasMap $aliasMap -ScanLimit $HeaderScanRows
    if (-not $headerRow) { continue }
    $columnMap = Build-ColumnMap -HeaderRow $headerRow -AliasMap $aliasMap

    foreach ($row in ($rows | Where-Object { $_.RowNumber -gt $headerRow.RowNumber })) {
      $host = Get-ValueFromColumnMap -Row $row -ColumnMap $columnMap -Field 'Host'
      $mac = Get-ValueFromColumnMap -Row $row -ColumnMap $columnMap -Field 'Mac'
      $serial = Get-ValueFromColumnMap -Row $row -ColumnMap $columnMap -Field 'Serial'
      $site = Get-ValueFromColumnMap -Row $row -ColumnMap $columnMap -Field 'Site'
      $room = Get-ValueFromColumnMap -Row $row -ColumnMap $columnMap -Field 'Room'
      $notes = Get-ValueFromColumnMap -Row $row -ColumnMap $columnMap -Field 'Notes'

      if ([string]::IsNullOrWhiteSpace($host) -and [string]::IsNullOrWhiteSpace($mac) -and [string]::IsNullOrWhiteSpace($serial)) { continue }

      $record = [pscustomobject]@{
        NeuronHost = $host
        ExpectedMAC = $mac
        ExpectedSerial = $serial
        Site = $site
        Room = $room
        Notes = (($notes, ('Source={0};Row={1};DeviceType={2}' -f $sheet.Name, $row.RowNumber, $DeviceType)) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' | '
        SourceWorksheet = $sheet.Name
        SourceRow = $row.RowNumber
        IdentifierStatus = if ([string]::IsNullOrWhiteSpace($host)) { 'MissingHost' } else { 'ReadyForSurvey' }
      }

      if ([string]::IsNullOrWhiteSpace($host)) { $unresolved += $record } else { $targets += $record }
    }
  }

  $targets | Sort-Object NeuronHost -Unique | Export-Csv -LiteralPath $OutputPath -NoTypeInformation
  $unresolved | Sort-Object ExpectedMAC, ExpectedSerial -Unique | Export-Csv -LiteralPath $UnresolvedOutputPath -NoTypeInformation

  [pscustomobject]@{
    WorkbookPath = $WorkbookPath
    DeviceType = $DeviceType
    OutputPath = $OutputPath
    UnresolvedOutputPath = $UnresolvedOutputPath
    ReadyTargetCount = @($targets).Count
    UnresolvedIdentifierCount = @($unresolved).Count
    TargetSideArtifacts = 'None'
  }
}
finally {
  $zip.Dispose()
}
