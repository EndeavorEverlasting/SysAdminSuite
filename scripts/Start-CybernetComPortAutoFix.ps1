#Requires -Version 5.1
[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidateSet('DryRun', 'Apply')]
  [string]$Mode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$corePath = Join-Path $PSScriptRoot 'Invoke-CybernetComPortAutoFix.ps1'

function Test-RunningAsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Path -LiteralPath $corePath -PathType Leaf)) {
  throw "Cybernet COM AutoFix implementation not found: $corePath"
}

if (-not (Test-RunningAsAdministrator)) {
  Write-Host 'Requesting Administrator permission for Cybernet COM Port AutoFix...'
  $powerShellPath = (Get-Command powershell.exe -ErrorAction Stop).Source
  $arguments = @(
    '-NoProfile',
    '-File',
    ('"{0}"' -f $PSCommandPath),
    '-Mode',
    $Mode
  )
  $process = Start-Process `
    -FilePath $powerShellPath `
    -ArgumentList $arguments `
    -WorkingDirectory $repoRoot `
    -Verb RunAs `
    -Wait `
    -PassThru
  exit $process.ExitCode
}

try {
  if ($Mode -eq 'Apply') {
    & $corePath -Apply -Restart
  }
  else {
    & $corePath
  }
  exit 0
}
catch {
  Write-Error $_
  exit 1
}
