#Requires -Version 5.1
[CmdletBinding()]
param(
  [string]$ScriptPath = (Join-Path $PSScriptRoot 'Invoke-CybernetComPortAutoFix.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
  throw "AutoFix script not found: $ScriptPath"
}

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path -LiteralPath $ScriptPath),
  [ref]$tokens,
  [ref]$parseErrors
) | Out-Null

if ($parseErrors.Count -gt 0) {
  $detail = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
  throw "AutoFix parser check failed: $detail"
}

Write-Output 'PARSE OK'
