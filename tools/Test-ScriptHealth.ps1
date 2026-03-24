<#
.SYNOPSIS
  Validates PowerShell scripts: parse check, BOM check, non-ASCII scan.
.DESCRIPTION
  Runs three checks on every .ps1/.psm1/.psd1 file in the repo:
    1. Parse check   -- tokenizes the file and reports syntax errors.
    2. BOM check     -- flags files missing the UTF-8 BOM.
    3. Non-ASCII scan -- flags lines with characters > U+007F that may
       break PowerShell 5.1 without a BOM.

  Returns exit code 0 if all files pass, 1 if any issues found.

.PARAMETER Path
  Root directory to scan. Defaults to the repository root.
.PARAMETER SkipParse
  Skip the parse-error check.
.PARAMETER SkipBom
  Skip the BOM check.
.PARAMETER SkipNonAscii
  Skip the non-ASCII character scan.
.EXAMPLE
  .\Test-ScriptHealth.ps1                # full check from repo root
  .\Test-ScriptHealth.ps1 -SkipNonAscii  # parse + BOM only
#>
[CmdletBinding()]
param(
    [string]$Path,
    [switch]$SkipParse,
    [switch]$SkipBom,
    [switch]$SkipNonAscii
)

if (-not $Path) {
    if ($PSScriptRoot) { $Path = Split-Path $PSScriptRoot -Parent }
    else { $Path = $PWD.Path }
}

$exclude = @('.git','node_modules','__pycache__','Output','Archive',
             '_scan_nonascii.ps1','_scan_bom.ps1','_fix_nonascii.ps1')
$exts = @('*.ps1','*.psm1','*.psd1')

$files = foreach ($ext in $exts) {
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

$totalIssues = 0
$summary = @{ ParseErrors = 0; MissingBom = 0; NonAsciiFiles = 0 }

Write-Host "`n=== Script Health Check ===" -ForegroundColor Cyan
Write-Host "Root  : $Path"
Write-Host "Files : $($files.Count)`n"

foreach ($f in $files) {
    $rel = $f.FullName.Replace($Path,'').TrimStart('\','/')
    $fileIssues = @()

    # 1. Parse check
    if (-not $SkipParse) {
        $tokens = $null; $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $f.FullName, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) {
            $summary.ParseErrors++
            foreach ($e in $errors) {
                $fileIssues += "PARSE: $($e.Message) (line $($e.Extent.StartLineNumber))"
            }
        }
    }

    # 2. BOM check
    if (-not $SkipBom) {
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        if (-not $hasBom) {
            $summary.MissingBom++
            $fileIssues += 'NO-BOM'
        }
    }

    # 3. Non-ASCII scan
    if (-not $SkipNonAscii) {
        try {
            $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction Stop
            $lineNum = 0
            $hits = @()
            foreach ($line in $lines) {
                $lineNum++
                $chars = [char[]]$line | Where-Object { [int]$_ -gt 127 }
                if ($chars) {
                    $unique = ($chars | Sort-Object -Unique | ForEach-Object {
                        "U+{0:X4}" -f [int]$_
                    }) -join ','
                    $hits += "L${lineNum}($unique)"
                }
            }
            if ($hits.Count) {
                $summary.NonAsciiFiles++
                $fileIssues += "NON-ASCII: $($hits -join '; ')"
            }
        } catch { <# binary or locked #> }
    }

    if ($fileIssues.Count) {
        $totalIssues += $fileIssues.Count
        Write-Host "  [WARN] $rel" -ForegroundColor Yellow
        foreach ($issue in $fileIssues) {
            Write-Host "         $issue" -ForegroundColor DarkYellow
        }
    }
}

Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "  Parse errors    : $($summary.ParseErrors)"
Write-Host "  Missing BOM     : $($summary.MissingBom)"
Write-Host "  Non-ASCII files : $($summary.NonAsciiFiles)"

if ($totalIssues -gt 0) {
    Write-Host "`n  $totalIssues issue(s) found. Run Add-Utf8Bom.ps1 -Fix to add BOMs." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "`n  All scripts healthy." -ForegroundColor Green
    exit 0
}

