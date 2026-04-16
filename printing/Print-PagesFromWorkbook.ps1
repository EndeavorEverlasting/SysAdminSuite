<#
.SYNOPSIS
  Print selected pages from a DOCX in the EXACT order listed across tabs in an XLSX.

.DESCRIPTION
  - Reads a 4-tab (or any-tab) workbook. Each tab can list either:
      * Page numbers (col header: Page/Pages/Number/Num/#), or
      * Hostnames (col header: Host/Hostname/New Host/Old Host) — script extracts trailing 3 digits.
  - Keeps list order. No sorting. Prints page-by-page to avoid Word auto-sorting.
  - Optional: export per-tab subset PDFs before/without printing.

.PARAMETER Docx
  Path to the full MOVE deck (DOCX).

.PARAMETER Xlsx
  Path to the ordered workbook.

.PARAMETER PrinterName
  Optional. If omitted, uses Word’s default printer.

.PARAMETER Sheets
  Optional subset of sheet names to run.

.PARAMETER ExportPdf
  Also export per-tab subset PDFs (named <Sheet>.pdf) to OutDir.

.PARAMETER OutDir
  Output directory for PDFs and logs. Defaults beside XLSX.

.PARAMETER WhatIf
  Dry run. Shows planned pages in order; no print.

.EXAMPLE
  .\Print-PagesFromWorkbook.ps1 -Docx '.\FULL_001_262_Landscape.docx' `
    -Xlsx '.\Labels in Ibrahim''s Order.xlsx' -PrinterName 'Xerox B8155' -WhatIf

.EXAMPLE
  .\Print-PagesFromWorkbook.ps1 -Docx '.\FULL_001_262_Landscape.docx' `
    -Xlsx '.\Labels in Ibrahim''s Order.xlsx' -ExportPdf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)][string]$Docx,
  [Parameter(Mandatory)][string]$Xlsx,
  [string]$PrinterName,
  [string[]]$Sheets,
  [switch]$ExportPdf,
  [string]$OutDir,
  [switch]$WhatIf
)

# --- guardrails ---------------------------------------------------------------
function Stop-IfMissing($p){ if(-not (Test-Path $p)){ throw "Missing path: $p" } }
Stop-IfMissing $Docx; Stop-IfMissing $Xlsx
$OutDir = $OutDir ?? (Join-Path (Split-Path -Path $Xlsx -Parent) "Printing_Output")
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$sessionLog = Join-Path $OutDir ("PrintSession_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
"[$(Get-Date -f s)] Start" | Out-File -FilePath $sessionLog -Encoding utf8

# --- helpers ------------------------------------------------------------------
function Get-OrderedPagesFromSheet {
  param([object]$ws)
  $hdrRow  = 1
  $lastCol = $ws.UsedRange.Columns.Count
  $lastRow = $ws.UsedRange.Rows.Count

  $col = $null; $mode = $null
  for($c=1;$c -le $lastCol;$c++){
    $name = ($ws.Cells.Item($hdrRow,$c).Text -as [string]).Trim().ToLower()
    if($name -in @('page','pages','number','num','#')) { $col=$c; $mode='page'; break }
    if($name -in @('host','hostname','new host','old host')) { $col=$c; $mode='host'; break }
  }
  if(-not $col){ throw "No suitable header on sheet '$($ws.Name)'" }

  $ordered = New-Object System.Collections.Generic.List[int]
  for($r=$hdrRow+1; $r -le $lastRow; $r++){
    $raw = ($ws.Cells.Item($r,$col).Text -as [string]).Trim()
    if([string]::IsNullOrWhiteSpace($raw)){ continue }

    if($mode -eq 'page'){
      foreach($chunk in $raw.Split(','))
      {
        $v = $chunk.Trim()
        if($v -match '^\d+$'){ [void]$ordered.Add([int]$v) }
      }
    } else {
      # host: take trailing 3 digits, allow leading zeros
      if($raw -match '(\d{3})$'){
        [void]$ordered.Add([int]$Matches[1])
      }
    }
  }
  return ,$ordered  # keep order as-is
}

function New-PdfSubset {
  param(
    [string]$SourcePdf,
    [int[]]$Pages,
    [string]$OutPdf
  )
  Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
  # Use Word to print-to-PDF page-by-page and merge via .NET PdfDocument (Windows 10+ has no native merge).
  # Simple fallback: create a print parameter string (e.g., "5,7,13") and let Word export directly.
  # This keeps it fast and avoids extra libs.
  $pagesParam = ($Pages | ForEach-Object { $_ }) -join ','
  $global:__wd.ActiveDocument.ExportAsFixedFormat($OutPdf,17,$false,0,0,0,0,0,7,$false,$false,$false,$false,$false,$false,$pagesParam)
}

# --- Excel ingest -------------------------------------------------------------
$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$wb = $excel.Workbooks.Open($Xlsx)

$plan = @()
foreach($ws in $wb.Worksheets){
  if($Sheets -and ($Sheets -notcontains $ws.Name)){ continue }
  try{
    $pages = Get-OrderedPagesFromSheet -ws $ws
    if($pages.Count -gt 0){
      $plan += [pscustomobject]@{ Sheet=$ws.Name; Pages=$pages }
      "Sheet '$($ws.Name)': $($pages.Count) pages" | Tee-Object -FilePath $sessionLog -Append
    }
  } catch {
    "WARN $($_.Exception.Message)" | Tee-Object -FilePath $sessionLog -Append
  }
}
$wb.Close($false); $excel.Quit()

if($plan.Count -eq 0){ throw "No pages found from workbook." }

# --- Word & printer -----------------------------------------------------------
$wd = New-Object -ComObject Word.Application
$wd.Visible = $false
$doc = $wd.Documents.Open($Docx)
if($PrinterName){ $wd.ActivePrinter = $PrinterName }

# --- optional: full-deck PDF path (for subset export) ------------------------
$deckPdf = Join-Path $OutDir ([IO.Path]::GetFileNameWithoutExtension($Docx) + ".pdf")
$doc.SaveAs([ref]$deckPdf, [ref]17)  # wdFormatPDF

# --- execute -----------------------------------------------------------------
foreach($job in $plan){
  $sheet = $job.Sheet
  $pages = $job.Pages

  Write-Host ">> $sheet" ; ">> $sheet : $($pages -join ', ')" | Tee-Object $sessionLog -Append

  if($ExportPdf){
    $subsetPdf = Join-Path $OutDir ($sheet + ".pdf")
    # Word can export arbitrary page lists directly from the DOCX:
    if(-not $WhatIf){
      $doc.ExportA
