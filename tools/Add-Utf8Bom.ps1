<#
.SYNOPSIS
  Adds a UTF-8 BOM (Byte Order Mark) to PowerShell script files.
.DESCRIPTION
  PowerShell 5.1 requires a UTF-8 BOM to correctly parse scripts that contain
  non-ASCII characters in strings or comments. This tool ensures all targeted
  files have the BOM prefix (EF BB BF).

  By default runs in DRY-RUN mode -- use -Fix to apply changes.

.PARAMETER Path
  Root directory to scan. Defaults to the repository root.
.PARAMETER Filter
  File extensions to process. Defaults to *.ps1, *.psm1, *.psd1.
.PARAMETER Fix
  Apply changes. Without this switch the tool only reports.
.EXAMPLE
  .\Add-Utf8Bom.ps1                     # dry-run from repo root
  .\Add-Utf8Bom.ps1 -Fix                # apply BOM to all PS files
  .\Add-Utf8Bom.ps1 -Path .\GUI -Fix    # apply BOM to GUI folder only
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Path,
    [string[]]$Filter = @('*.ps1','*.psm1','*.psd1'),
    [switch]$Fix
)

if (-not $Path) {
    if ($PSScriptRoot) { $Path = Split-Path $PSScriptRoot -Parent }
    else { $Path = $PWD.Path }
}

$exclude = @('.git','node_modules','__pycache__','Output','Archive','dist')

$files = foreach ($ext in $Filter) {
    Get-ChildItem -Path $Path -Recurse -Filter $ext -File -ErrorAction SilentlyContinue
}
$files = $files | Where-Object {
    $rel = $_.FullName.Replace($Path,'')
    $skip = $false
    foreach ($ex in $exclude) {
        if ($rel -match "(^|[\\/])$([regex]::Escape($ex))([\\/]|$)") { $skip = $true; break }
    }
    -not $skip
}

$bom = [byte[]](0xEF, 0xBB, 0xBF)
$added = 0; $skipped = 0; $scanned = 0

Write-Host "`n=== Add-Utf8Bom ===" -ForegroundColor Cyan
Write-Host "Root : $Path"
Write-Host "Mode : $(if ($Fix) { 'FIX' } else { 'DRY-RUN (use -Fix to apply)' })`n"

foreach ($f in $files) {
    $scanned++
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF

    if ($hasBom) {
        $skipped++
        continue
    }

    $rel = $f.FullName.Replace($Path,'').TrimStart('\','/')
    if ($Fix) {
        $newBytes = $bom + $bytes
        [System.IO.File]::WriteAllBytes($f.FullName, $newBytes)
        Write-Host "  [ADDED BOM] $rel" -ForegroundColor Green
    } else {
        Write-Host "  [NEEDS BOM] $rel" -ForegroundColor Yellow
    }
    $added++
}

Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "  Files scanned : $scanned"
Write-Host "  Already have BOM: $skipped"
Write-Host "  $(if ($Fix) { 'BOM added' } else { 'Need BOM' })  : $added"
if (-not $Fix -and $added -gt 0) {
    Write-Host "`n  Run with -Fix to apply changes." -ForegroundColor Yellow
}

