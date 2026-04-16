# Export-WordPagesToPdf-ByHost.ps1
param(
  [Parameter(Mandatory=$true)] [string]$DocPath,   # e.g. C:\Jobs\75Rock\Generated_TearOff_Labels_v5_75Rock_2up.docx
  [Parameter(Mandatory=$true)] [string]$OutDir,    # e.g. C:\Jobs\75Rock\PagePDFs
  [string]$Prefix = ""                              # optional prefix in filenames
)

# --- Word interop constants ---
$wdExportFormatPDF      = 17
$wdExportOptimizeFor    = 0     # Print
$wdExportRangeFromTo    = 3
$wdExportItemDocContent = 0
$wdGoToPage             = 1
$wdGoToAbsolute         = 1

# --- helpers ---
function Sanitize([string]$s){
  $bad = [IO.Path]::GetInvalidFileNameChars() -join ''
  return ($s -replace "[${bad}]", "_").Trim()
}
function HostLabel([string]$text){
  # capture all "NEW HOST: XXXX" on the page (case-insensitive)
  $m = [regex]::Matches($text, 'NEW\s+HOST:\s*([A-Za-z0-9_\-]+)', 'IgnoreCase')
  if ($m.Count -gt 0){
    ($m | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique) -join '__'
  } else { $null }
}

# --- run ---
$word = New-Object -ComObject Word.Application
$word.Visible = $false
try {
  $doc = $word.Documents.Open($DocPath, $false, $true) # read-only
  $doc.Repaginate()
  $total = $doc.ComputeStatistics([Microsoft.Office.Interop.Word.WdStatistic]::wdStatisticPages)

  if (!(Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

  for ($p = 1; $p -le $total; $p++){
    # get RANGE for this page using the \Page bookmark trick
    $sel = $word.Selection
    $sel.GoTo($wdGoToPage, $wdGoToAbsolute, $p) | Out-Null
    $pageRange = $sel.Bookmarks("\Page").Range

    $pageText  = $pageRange.Text
    $tag       = HostLabel $pageText
    $tag       = if ($tag) { Sanitize $tag } else { "p{0:d2}" -f $p }

    $nameParts = @()
    if ($Prefix) { $nameParts += (Sanitize $Prefix) }
    $nameParts += $tag
    $outFile = Join-Path $OutDir ("{0}.pdf" -f ($nameParts -join "__"))

    $doc.ExportAsFixedFormat(
      $outFile,
      $wdExportFormatPDF,
      $false,                    # OpenAfterExport
      $wdExportOptimizeFor,
      $wdExportRangeFromTo,
      $p, $p,                    # From / To
      $wdExportItemDocContent,
      $true, $false, 1, $true, $true, $true
    )
    Write-Host "Saved $outFile"
  }
}
finally {
  if ($doc) { $doc.Close($false) }
  $word.Quit()
  [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
}
