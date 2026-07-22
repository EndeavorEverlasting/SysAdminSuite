#Requires -Version 5.1
<#
.SYNOPSIS
Executes the canonical SMB scheduled-task lifecycle failure matrix without network activity.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not [IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot = Join-Path $repoRoot $OutputRoot }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$approvedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'survey/output')).TrimEnd('\')
if (-not $OutputRoot.StartsWith($approvedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'SMB scheduled-task fixture output must be a child of survey/output.'
}

$modulePath = Join-Path $PSScriptRoot 'SasSoftwareDeploymentAdapter.psm1'
$scenarioPath = Join-Path $repoRoot 'Tests/Fixtures/smb-scheduled-task-deployment/scenarios.json'
Import-Module $modulePath -Force
$scenarios = Get-Content -LiteralPath $scenarioPath -Raw -Encoding UTF8 | ConvertFrom-Json

if (Test-Path -LiteralPath $OutputRoot) { Remove-Item -LiteralPath $OutputRoot -Recurse -Force }
$resultRoot = Join-Path $OutputRoot 'results'
$targetRoot = Join-Path $OutputRoot 'fixture-targets'
New-Item -ItemType Directory -Path $resultRoot, $targetRoot -Force | Out-Null
$rows = @()
try {
    foreach ($scenario in @($scenarios.scenarios)) {
        $id = [string]$scenario.id
        $fixtureRoot = Join-Path $targetRoot $id
        $result = Invoke-SasSmbScheduledTaskDeploymentFixture -FixtureRoot $fixtureRoot -Scenario $id
        if ([string]$result.status -ne [string]$scenario.expected_status) {
            throw "Fixture $id returned $($result.status); expected $($scenario.expected_status)."
        }
        if ($result.network_activity_performed -or $result.fallback_attempted) {
            throw "Fixture $id crossed its zero-network/no-fallback boundary."
        }
        $resultPath = Join-Path $resultRoot "$id.result.json"
        $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        $rows += [pscustomobject][ordered]@{ scenario = $id; status = [string]$result.status; result_path = $resultPath }
    }
}
finally {
    if (Test-Path -LiteralPath $targetRoot) { Remove-Item -LiteralPath $targetRoot -Recurse -Force }
}

$summary = [pscustomobject][ordered]@{
    schema_version = 'sas-smb-scheduled-task-fixture-summary/v1'
    status = 'PASS'
    scenario_count = $rows.Count
    network_activity_performed = $false
    target_mutation_performed = $false
    live_target_proof = $false
    results = $rows
}
$summaryPath = Join-Path $OutputRoot 'fixture-summary.json'
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
if ($PassThru) { return $summary }
Write-Host "Canonical SMB scheduled-task fixture matrix: PASS ($($rows.Count) scenarios)"
