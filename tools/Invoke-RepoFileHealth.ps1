<#
.SYNOPSIS
  Repository file-health maintenance tool.
.DESCRIPTION
  Scans the repo for common file hygiene issues and optionally fixes them:
    - Removes Zone.Identifier alternate-data-stream locks (Windows "downloaded file" block)
    - Ensures PowerShell (.ps1, .psm1, .psd1) and CSV files are saved with UTF-8 BOM
      encoding so they work correctly in PowerShell 5.1 and Excel.
    - Normalises line endings to CRLF (Windows standard) or LF (Unix) as requested.
    - Reports files with unexpected encoding, missing BOM, or residual locks.
  Safe to re-run. Dry-run by default (-WhatIf).
.PARAMETER Path
  Root path to scan.  Defaults to the repo root (parent of this script's folder).
.PARAMETER Fix
  Actually apply fixes.  Without this switch the tool only reports what it would do.
.PARAMETER LineEnding
  Target line ending style: CRLF (default) or LF.
.PARAMETER IncludeExtensions
  File extensions to inspect.  Defaults to common script/config/data extensions.
.PARAMETER ExcludeDir
  Directory names to skip (e.g. .git, node_modules).
.EXAMPLE
  # Dry-run report
  .\tools\Invoke-RepoFileHealth.ps1

  # Apply all fixes
  .\tools\Invoke-RepoFileHealth.ps1 -Fix
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Path,
  [switch]$Fix,
  [ValidateSet('CRLF','LF')]
  [string]$LineEnding = 'CRLF',
  [string[]]$IncludeExtensions = @('.ps1','.psm1','.psd1','.csv','.txt','.md','.json','.xml','.bat','.py'),
  [string[]]$ExcludeDir = @('.git','node_modules','__pycache__','.vs','bin','obj')
)

if (-not $Path) {
  if ($PSScriptRoot) { $Path = Split-Path -Parent $PSScriptRoot }
  else { $Path = $PWD.Path }
}

$bomBytes   = [byte[]]@(0xEF,0xBB,0xBF)
$bomExts    = @('.ps1','.psm1','.psd1','.csv')   # extensions that NEED UTF-8 BOM
$psExts     = @('.ps1','.psm1','.psd1')           # extensions to scan for non-ASCII
$targetCRLF = ($LineEnding -eq 'CRLF')
$summary    = [ordered]@{ Scanned = 0; LocksRemoved = 0; BOMAdded = 0; LineEndingsFixed = 0; NonAsciiFiles = 0; Skipped = 0 }

function Test-HasBOM {
  param([string]$FilePath)
  $bytes = [System.IO.File]::ReadAllBytes($FilePath)
  if ($bytes.Length -lt 3) { return $false }
  return ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

function Test-HasZoneId {
  param([string]$FilePath)
  try {
    $streams = Get-Item -LiteralPath $FilePath -Stream * -ErrorAction SilentlyContinue
    return [bool]($streams | Where-Object Stream -eq 'Zone.Identifier')
  } catch { return $false }
}

Write-Host "`n=== Repo File Health Check ===" -ForegroundColor Cyan
Write-Host "Root : $Path"
Write-Host "Mode : $(if ($Fix) { 'FIX (applying changes)' } else { 'DRY-RUN (report only -- use -Fix to apply)' })"
Write-Host "Line endings target: $LineEnding`n"

$files = Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
  Where-Object {
    $relDir = $_.DirectoryName.Replace($Path,'')
    $skip = $false
    foreach ($ex in $ExcludeDir) { if ($relDir -match "(^|[\\/])$([regex]::Escape($ex))([\\/]|$)") { $skip = $true; break } }
    (-not $skip) -and ($IncludeExtensions -contains $_.Extension.ToLower())
  }

foreach ($f in $files) {
  $summary.Scanned++
  $ext = $f.Extension.ToLower()
  $issues = @()

  # 1) Zone.Identifier lock
  if (Test-HasZoneId -FilePath $f.FullName) {
    $issues += 'Zone.Identifier lock'
    if ($Fix) {
      try {
        Unblock-File -LiteralPath $f.FullName -ErrorAction Stop
        Remove-Item -LiteralPath $f.FullName -Stream Zone.Identifier -Force -ErrorAction SilentlyContinue
        $summary.LocksRemoved++
      } catch { Write-Warning "  Could not remove lock on $($f.FullName): $_" }
    }
  }

  # 2) BOM check for extensions that need it
  $needsBOM = ($bomExts -contains $ext)
  if ($needsBOM -and -not (Test-HasBOM -FilePath $f.FullName)) {
    $issues += 'Missing UTF-8 BOM'
    if ($Fix) {
      try {
        $raw = [System.IO.File]::ReadAllBytes($f.FullName)
        # Strip existing BOM if present (shouldn't be, but be safe)
        $start = 0
        if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { $start = 3 }
        $newBytes = $bomBytes + $raw[$start..($raw.Length - 1)]
        [System.IO.File]::WriteAllBytes($f.FullName, $newBytes)
        $summary.BOMAdded++
      } catch { Write-Warning "  Could not add BOM to $($f.FullName): $_" }
    }
  }

  # 3) Line-ending normalisation
  try {
    $raw = [System.IO.File]::ReadAllText($f.FullName)
    $hasCRLF = $raw.Contains("`r`n")
    $hasLF   = $raw.Contains("`n") -and -not $hasCRLF
    $mixed   = $raw.Contains("`r`n") -and ($raw -replace "`r`n",'' ).Contains("`n")
    $needsFix = $mixed -or ($targetCRLF -and $hasLF) -or (-not $targetCRLF -and $hasCRLF)
    if ($needsFix) {
      $issues += "Line endings (want $LineEnding)"
      if ($Fix) {
        $normalised = $raw -replace "`r`n","`n"
        if ($targetCRLF) { $normalised = $normalised -replace "`n","`r`n" }
        $enc = if (Test-HasBOM -FilePath $f.FullName) { New-Object System.Text.UTF8Encoding($true) } else { New-Object System.Text.UTF8Encoding($false) }
        [System.IO.File]::WriteAllText($f.FullName, $normalised, $enc)
        $summary.LineEndingsFixed++
      }
    }
  } catch { <# binary or locked -- skip #> }

  # 4) Non-ASCII character scan (PS files only)
  if ($psExts -contains $ext) {
    try {
      $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction Stop
      $lineNum = 0; $nonAsciiHits = @()
      foreach ($line in $lines) {
        $lineNum++
        $chars = [char[]]$line | Where-Object { [int]$_ -gt 127 }
        if ($chars) {
          $unique = ($chars | Sort-Object -Unique | ForEach-Object { "U+{0:X4}" -f [int]$_ }) -join ','
          $nonAsciiHits += "L${lineNum}($unique)"
        }
      }
      if ($nonAsciiHits.Count) {
        $summary.NonAsciiFiles++
        $issues += "Non-ASCII chars: $($nonAsciiHits -join '; ')"
      }
    } catch { <# binary or locked #> }
  }

  if ($issues.Count) {
    $tag = if ($Fix) { '[FIXED]' } else { '[ISSUE]' }
    $rel = $f.FullName.Replace($Path,'').TrimStart('\','/')
    Write-Host "  $tag $rel  ->  $($issues -join ', ')" -ForegroundColor $(if ($Fix) { 'Green' } else { 'Yellow' })
  }
}

Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "  Files scanned     : $($summary.Scanned)"
Write-Host "  Locks removed     : $($summary.LocksRemoved)"
Write-Host "  BOM added         : $($summary.BOMAdded)"
Write-Host "  Line endings fixed: $($summary.LineEndingsFixed)"
Write-Host "  Non-ASCII files   : $($summary.NonAsciiFiles)"
if (-not $Fix) { Write-Host "`n  Run with -Fix to apply changes." -ForegroundColor DarkYellow }
Write-Host ""

