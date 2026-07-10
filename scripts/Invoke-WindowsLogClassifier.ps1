#Requires -Version 5.1
<#
.SYNOPSIS
Classifies Windows log operation requests through the SysAdminSuite taxonomy-backed classifier.

.DESCRIPTION
This is a Windows-friendly wrapper around harness/windows_log_classifier.py. It does not read,
write, clear, remove, or reconfigure host logs directly. It invokes the repository classifier so
operators can classify a log target/action, build an operation plan, and render a handoff before
any explicit operator-run host action.

.EXAMPLE
.\scripts\Invoke-WindowsLogClassifier.ps1 -Target System -Operation 'show recent errors' -Emit plan

.EXAMPLE
.\scripts\Invoke-WindowsLogClassifier.ps1 `
  -Target Application `
  -Operation 'write event' `
  -OutputRoot 'survey/output/windows-log-classifier/demo' `
  -Emit all `
  -Write
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Target,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Operation,

    [Parameter(Mandatory = $false)]
    [ValidateSet('classification', 'plan', 'powershell', 'all')]
    [string]$Emit = 'classification',

    [Parameter(Mandatory = $false)]
    [string]$TaxonomyPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [switch]$Write,

    [Parameter(Mandatory = $false)]
    [string]$PythonCommand
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$classifierPath = Join-Path $repoRoot 'harness/windows_log_classifier.py'
if (-not (Test-Path -LiteralPath $classifierPath)) {
    throw "Missing Windows log classifier implementation: $classifierPath"
}

if ([string]::IsNullOrWhiteSpace($TaxonomyPath)) {
    $TaxonomyPath = Join-Path $repoRoot 'harness/taxonomy/windows-log-taxonomy.json'
}
if (-not (Test-Path -LiteralPath $TaxonomyPath)) {
    throw "Missing Windows log taxonomy: $TaxonomyPath"
}

function Resolve-SasPythonCommand {
    param([string]$RequestedCommand)

    if (-not [string]::IsNullOrWhiteSpace($RequestedCommand)) {
        return $RequestedCommand
    }

    foreach ($candidate in @('python3', 'python', 'py')) {
        $resolved = Get-Command -Name $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $resolved) {
            return $resolved.Source
        }
    }

    throw 'Python was not found. Install Python or pass -PythonCommand.'
}

$python = Resolve-SasPythonCommand -RequestedCommand $PythonCommand

$arguments = @(
    $classifierPath,
    '--target', $Target,
    '--operation', $Operation,
    '--taxonomy', $TaxonomyPath,
    '--emit', $Emit
)

if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) {
    $arguments += @('--output-root', $OutputRoot)
}

if ($Write.IsPresent) {
    $arguments += '--write'
}

& $python @arguments
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    throw "Windows log classifier failed with exit code $exitCode"
}
