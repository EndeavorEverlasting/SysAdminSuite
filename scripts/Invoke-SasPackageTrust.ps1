#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the canonical SysAdminSuite package trust gate with the repository-owned WinTrust interop.
.DESCRIPTION
    Compiles the repository-owned cache-only WinTrust interop, then delegates to the policy engine.
    No package code, custom action, endpoint, target, or VM is executed or contacted.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BaseResultPath,

    [Parameter(Mandatory = $false)]
    [string]$TrustPolicyPath,

    [Parameter(Mandatory = $false)]
    [switch]$ObservationOnly,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 50000)]
    [int]$MaxFiles = 50000,

    [Parameter(Mandatory = $false)]
    [switch]$FixtureMode
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$interopPath = Join-Path $repoRoot 'tools/package-analysis/SasPackageTrustInterop.cs'
$policyEngine = Join-Path $PSScriptRoot 'Test-SasPackageTrust.ps1'

if (-not (Test-Path -LiteralPath $interopPath -PathType Leaf)) {
    throw "Package trust interop source is missing: $interopPath"
}
if (-not (Test-Path -LiteralPath $policyEngine -PathType Leaf)) {
    throw "Package trust policy engine is missing: $policyEngine"
}

if (-not ('Sas.PackageTrust.WinTrustVerifier' -as [type])) {
    Add-Type -Path $interopPath
}

$arguments = @{
    InputPath = $InputPath
    BaseResultPath = $BaseResultPath
    MaxFiles = $MaxFiles
}
if (-not [string]::IsNullOrWhiteSpace($TrustPolicyPath)) { $arguments.TrustPolicyPath = $TrustPolicyPath }
if ($ObservationOnly) { $arguments.ObservationOnly = $true }
if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) { $arguments.OutputRoot = $OutputRoot }
if ($FixtureMode) { $arguments.FixtureMode = $true }

& $policyEngine @arguments
exit $LASTEXITCODE
