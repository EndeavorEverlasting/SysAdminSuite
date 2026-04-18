#Requires -Version 5.1
<#
.SYNOPSIS
  Locates a built SysAdminSuite.Mapping.Worker.exe and verifies it runs (/ ? -> exit 2).
#>
param(
  [string]$BuildRoot = (Join-Path $PSScriptRoot '..\mapping\native\build')
)

$ErrorActionPreference = 'Stop'
$exe = Get-ChildItem -Path $BuildRoot -Recurse -Filter 'SysAdminSuite.Mapping.Worker.exe' -ErrorAction SilentlyContinue |
  Select-Object -First 1
if (-not $exe) {
  Write-Warning "No Worker exe under $BuildRoot — configure CMake first (see mapping\native\README.md)."
  exit 0
}
& $exe.FullName /? 2>&1 | Out-Null
if ($LASTEXITCODE -ne 2) {
  throw "Expected exit code 2 from Worker /?, got $LASTEXITCODE"
}
Write-Host "OK: $($exe.FullName)"
