#Requires -Version 5.1
<#
.SYNOPSIS
    Routes immediate active-user printer materialization to the transport that
    produced the successful machine-wide registration.
#>

[CmdletBinding()]
param(
    [string]$EvidenceRoot,
    [ValidateRange(30,180)][int]$TimeoutSeconds = 90,
    [switch]$KeepRemoteArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$latestPointer = Join-Path $PSScriptRoot 'Logs\LATEST-PATH.txt'
if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    if (-not (Test-Path -LiteralPath $latestPointer -PathType Leaf)) { throw "Latest printer evidence pointer not found: $latestPointer" }
    $EvidenceRoot = ([string](Get-Content -LiteralPath $latestPointer -Raw -ErrorAction Stop)).Trim()
}
if ([string]::IsNullOrWhiteSpace($EvidenceRoot) -or -not (Test-Path -LiteralPath $EvidenceRoot -PathType Container)) {
    throw "Printer evidence root does not exist: $EvidenceRoot"
}
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
$summaryPath = Join-Path $EvidenceRoot 'Summary.json'
if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw "Summary.json not found: $summaryPath" }
$summary = Get-Content -LiteralPath $summaryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
if (-not [bool]$summary.Success) { throw 'Active-user materialization requires an already successful machine-wide mapping run.' }

$transport = ''
if ($null -ne $summary.PSObject.Properties['Transport']) { $transport = ([string]$summary.Transport).Trim() }
if ($transport -eq 'REMOTE_TASK_SCHEDULER+REMOTE_REGISTRY_NO_ADMIN_SHARE') {
    $shareless = Join-Path $PSScriptRoot 'Invoke-NorthwellPrinterSharelessActiveUser.ps1'
    if (-not (Test-Path -LiteralPath $shareless -PathType Leaf)) { throw "Shareless active-user finalizer not found: $shareless" }
    & $shareless -EvidenceRoot $EvidenceRoot -TimeoutSeconds $TimeoutSeconds
    exit 0
}

$canonical = Join-Path $PSScriptRoot 'Confirm-NorthwellPrinterActiveUserMaterialization.ps1'
if (-not (Test-Path -LiteralPath $canonical -PathType Leaf)) { throw "Canonical active-user finalizer not found: $canonical" }
$invoke = @{ EvidenceRoot=$EvidenceRoot; TimeoutSeconds=$TimeoutSeconds }
if ($KeepRemoteArtifacts) { $invoke.KeepRemoteArtifacts = $true }
& $canonical @invoke
exit 0
