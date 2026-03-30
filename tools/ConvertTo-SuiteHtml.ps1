<#
.SYNOPSIS
  Shared HTML wrapper for SysAdminSuite reports.
  Produces a dark-themed, responsive HTML document consistent with all suite output.

.DESCRIPTION
  Dot-source this file to get the ConvertTo-SuiteHtml function.
  It wraps any body content (table fragment, pre-formatted text, etc.) in the
  standard dark theme used by Map-MachineWide, RPM-Recon, and MonitorInfo reports.

.EXAMPLE
  . "$PSScriptRoot\ConvertTo-SuiteHtml.ps1"
  $rows | ConvertTo-Html -Fragment | ConvertTo-SuiteHtml -Title 'My Report' -OutputPath out.html

.EXAMPLE
  $body = $data | ConvertTo-Html -Fragment -PreContent '<h3>Detail</h3>'
  ConvertTo-SuiteHtml -Title 'Inventory' -BodyFragment $body -OutputPath report.html -Open
#>

function ConvertTo-SuiteHtml {
  [CmdletBinding()]
  param(
    # Report title shown in the browser tab and page heading.
    [Parameter(Mandatory)][string]$Title,

    # HTML body content (table fragments, log sections, etc.).
    # Also accepted from the pipeline.
    [Parameter(ValueFromPipeline)][string[]]$BodyFragment,

    # Optional subtitle line below the heading (e.g. hostname, timestamp).
    [string]$Subtitle,

    # Optional summary chips shown in a bar between the subtitle and body.
    # Each entry becomes a <span class="chip">…</span>.  Accepts plain text
    # or pre-built HTML strings.
    [string[]]$SummaryChips,

    # File path to write the HTML. When omitted the HTML string is returned instead.
    [string]$OutputPath,

    # Open the file in the default browser after writing. Requires -OutputPath.
    [switch]$Open
  )

  begin { $parts = [System.Collections.Generic.List[string]]::new() }
  process { if ($BodyFragment) { foreach ($f in $BodyFragment) { $parts.Add($f) } } }
  end {
    $body = $parts -join "`n"
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $subtitleHtml = if ($Subtitle) { "<p class='meta'>$([System.Net.WebUtility]::HtmlEncode($Subtitle)) &mdash; $timestamp</p>" } else { '' }

    # Summary bar: user-supplied chips + auto Generated chip
    $chipHtml = ''
    if ($SummaryChips) {
      foreach ($c in $SummaryChips) { $chipHtml += "<span class=`"chip`">$c</span>" }
    }
    $chipHtml += "<span class=`"chip`">Generated: $timestamp</span>"
    $summaryBar = "<div class=`"summary-bar`">$chipHtml</div>"

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>$([System.Net.WebUtility]::HtmlEncode($Title))</title>
<style>
  *, *::before, *::after { box-sizing: border-box; }
  body {
    font-family: 'Segoe UI', system-ui, -apple-system, Arial, sans-serif;
    background: #0b0b0f; color: #eaeaf0; padding: 24px; margin: 0;
    line-height: 1.5;
  }
  h1 { color: #8ed0ff; margin: 0 0 4px 0; }
  h2 { color: #c0c0d0; border-bottom: 1px solid #2a2a34; padding-bottom: 6px; margin-top: 28px; }
  h3 { color: #a0a0b8; }
  a { color: #8ed0ff; text-decoration: none; }
  a:hover { text-decoration: underline; }
  .meta { color: #888; font-size: 13px; margin-bottom: 18px; }
  .summary-bar { margin: 12px 0; }
  .chip {
    display: inline-block; background: #1a1a22; border: 1px solid #2a2a34;
    padding: 3px 10px; border-radius: 999px; margin-right: 8px; font-size: 12px;
  }
  table { border-collapse: collapse; width: 100%; margin-top: 8px; }
  th, td { border: 1px solid #2a2a34; padding: 7px 10px; font-size: 13px; text-align: left; }
  th { background: #171720; color: #b0b0c0; font-weight: 600; position: sticky; top: 0; z-index: 1; }
  tr:nth-child(even) { background: #0f0f16; }
  tr:hover { background: #1a1a28; }
  /* Badge system */
  .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: 600; }
  .primary { background: #1a3a1a; color: #6fdf6f; border: 1px solid #2a5a2a; }
  .disconnected { background: #3a1a1a; color: #df6f6f; border: 1px solid #5a2a2a; }
  /* Phantom / ghost row styling */
  .phantom { color: #ff6666; font-weight: bold; }
  .phantom-row { opacity: 0.5; background: #1a0a0a; }
  .phantom-row:hover { opacity: 0.8; }
  /* Diff row styling */
  .diff-gone { background: #2a0a0a; }
  .diff-new { background: #0a2a0a; }
  .diff-changed { background: #2a2a0a; }
  .diff-same { opacity: 0.6; }
  /* Insights panel */
  .insights { background: #12121a; border: 1px solid #2a2a34; border-radius: 8px; padding: 12px 18px; margin-top: 8px; }
  .phantom-list li { color: #ff9966; }
  .hint { color: #888; font-size: 12px; font-style: italic; margin-top: 8px; }
  code { background: #1a1a28; padding: 1px 5px; border-radius: 3px; font-size: 12px; color: #c0d0ff; }
  pre {
    white-space: pre-wrap; word-break: break-all;
    background: #13131a; border: 1px solid #232330; border-radius: 8px; padding: 12px;
    font-family: 'Cascadia Mono', 'Consolas', monospace; font-size: 12px;
    max-height: 60vh; overflow: auto;
  }
  .footer { color: #555; font-size: 11px; margin-top: 32px; border-top: 1px solid #1a1a22; padding-top: 8px; }
  @media print {
    body { background: #fff; color: #111; }
    th { background: #e0e0e0; }
    tr:nth-child(even) { background: #f5f5f5; }
    tr:hover { background: inherit; }
    .phantom-row { opacity: 1; background: #ffe0e0; }
    .diff-gone { background: #ffe0e0; } .diff-new { background: #e0ffe0; }
    .diff-changed { background: #fffde0; } .diff-same { opacity: 1; }
    pre { background: #f0f0f0; border-color: #ccc; max-height: none; }
    a { color: #0056b3; }
  }
  @media (max-width: 600px) {
    body { padding: 10px; }
    table { font-size: 11px; }
  }
</style>
</head>
<body>
<h1>$([System.Net.WebUtility]::HtmlEncode($Title))</h1>
$subtitleHtml
$summaryBar
$body
<div class="footer">SysAdminSuite &mdash; $timestamp</div>
</body>
</html>
"@

    if ($OutputPath) {
      $outDir = Split-Path $OutputPath -Parent
      if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
      Set-Content -LiteralPath $OutputPath -Value $html -Encoding UTF8
      Write-Host "HTML report written: $OutputPath" -ForegroundColor Green
      if ($Open) { Start-Process $OutputPath }
    } else {
      return $html
    }
  }
}

