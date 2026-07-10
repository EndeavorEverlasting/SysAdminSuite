#Requires -Version 5.1
<#
.SYNOPSIS
Runs the SysAdminSuite harness contract checks without requiring Bash.

.DESCRIPTION
This runner is the Windows-native equivalent of Tests/bash/run_harness_contracts.sh. It validates the
tracked harness command surfaces, schemas, fixtures, launcher routes, PR #142 scope boundaries, and then
invokes the synthetic harness validator. It is safe to run from the repository root or through
Run-HarnessContracts.cmd.

It does not read live network state, mutate target machines, delete branches, or clean generated output.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $repoRoot

$failures = New-Object System.Collections.Generic.List[string]

function Add-SasFailure {
    param([string]$Message)
    $script:failures.Add($Message)
    Write-Host "[FAIL] $Message"
}

function Add-SasPass {
    param([string]$Message)
    Write-Host "[PASS] $Message"
}

function Assert-SasPath {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-SasFailure "missing required harness file: $Path"
    }
}

function Get-SasText {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw
}

function Assert-SasContains {
    param([string]$Path, [string]$Fragment)
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-SasFailure "cannot inspect missing file: $Path"
        return
    }
    $text = Get-SasText -Path $Path
    if (-not $text.Contains($Fragment)) {
        Add-SasFailure "$Path missing fragment: $Fragment"
    }
}

function Assert-SasNotContains {
    param([string]$Path, [string]$Fragment)
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-SasFailure "cannot inspect missing file: $Path"
        return
    }
    $text = Get-SasText -Path $Path
    if ($text.Contains($Fragment)) {
        Add-SasFailure "$Path contains forbidden fragment: $Fragment"
    }
}

function Assert-SasNotMatch {
    param([string]$Path, [string]$Pattern, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-SasFailure "cannot inspect missing file: $Path"
        return
    }
    $text = Get-SasText -Path $Path
    if ($text -match $Pattern) {
        Add-SasFailure "$Path matched forbidden pattern: $Label"
    }
}

function Test-SasJsonFile {
    param([string]$Path)
    try {
        Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json | Out-Null
        return $true
    }
    catch {
        Add-SasFailure "invalid JSON: $Path - $($_.Exception.Message)"
        return $false
    }
}

function Resolve-SasPowerShellCommand {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) { return $pwsh.Source }

    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($windowsPowerShell) { return $windowsPowerShell.Source }

    $powershell = Get-Command powershell -ErrorAction SilentlyContinue
    if ($powershell) { return $powershell.Source }

    throw 'PowerShell runtime not found.'
}

Write-Host 'SYSADMIN HARNESS CONTRACTS'
Write-Host "Repo root: $repoRoot"

$requiredFiles = @(
    'Run-HarnessContracts.cmd',
    'Run-HarnessValidation.cmd',
    'Run-EnglishReportFixture.cmd',
    'Run-ExportHarnessEvidence.cmd',
    'docs/handoff/pr142-scope-ledger.md',
    'scripts/Ensure-Pr142HarnessFoundationWorktree.ps1',
    'scripts/Invoke-SasHarnessContracts.ps1',
    'scripts/validate-sysadmin-harness.ps1',
    'scripts/Render-SasEnglishReport.ps1',
    'scripts/run-harness-validation.sh',
    'scripts/render-english-report-fixtures.sh',
    'scripts/show-harness-evidence-paths.sh',
    'Tests/bash/run_harness_contracts.sh',
    'Tests/bash/test_english_log_artifact_contracts.sh',
    'Tests/bash/test_sysadmin_harness_validator_contracts.sh',
    'Tests/survey/test_one_command_harness_proof_contracts.py',
    'Tests/bash/test_harness_command_surface.sh',
    'Tests/bash/test_pr142_scope_boundary_contracts.sh',
    'schemas/harness/run-event.schema.json',
    'schemas/harness/artifact-registry.schema.json',
    'schemas/harness/operator-report.schema.json',
    'survey/fixtures/english-log/serial_preflight_summary.sample.json',
    'survey/fixtures/english-log/serial_preflight_artifact_registry.sample.json',
    'survey/fixtures/english-log/network_preflight_summary.sample.json',
    'survey/fixtures/english-log/network_preflight_artifact_registry.sample.json',
    'survey/workflows/serial-to-preflight.yaml',
    'survey/workflows/network-preflight.yaml',
    'survey/workflows/serial-iteration.yaml'
)

foreach ($file in $requiredFiles) {
    Assert-SasPath -Path $file
}
if ($failures.Count -eq 0) { Add-SasPass 'required harness files exist' }

foreach ($jsonFile in @(
    'schemas/harness/run-event.schema.json',
    'schemas/harness/artifact-registry.schema.json',
    'schemas/harness/operator-report.schema.json',
    'survey/fixtures/english-log/serial_preflight_summary.sample.json',
    'survey/fixtures/english-log/serial_preflight_artifact_registry.sample.json',
    'survey/fixtures/english-log/network_preflight_summary.sample.json',
    'survey/fixtures/english-log/network_preflight_artifact_registry.sample.json'
)) {
    [void](Test-SasJsonFile -Path $jsonFile)
}
if ($failures.Count -eq 0) { Add-SasPass 'schemas and fixtures parse' }

$requiredSummaryFields = @(
    'workflow_id',
    'run_id',
    'request_summary',
    'source_artifacts',
    'loaded_evidence_artifacts',
    'planner_name',
    'planner_version',
    'network_activity_performed',
    'low_noise_policy_version',
    'started_at',
    'finished_at',
    'operator_handoff_path',
    'summary_json_path',
    'report_markdown_path',
    'next_action'
)

foreach ($summaryPath in @(
    'survey/fixtures/english-log/serial_preflight_summary.sample.json',
    'survey/fixtures/english-log/network_preflight_summary.sample.json'
)) {
    if (Test-Path -LiteralPath $summaryPath) {
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        $present = @($summary.PSObject.Properties.Name)
        foreach ($field in $requiredSummaryFields) {
            if ($present -notcontains $field) {
                Add-SasFailure "$summaryPath missing required field: $field"
            }
        }
    }
}
if ($failures.Count -eq 0) { Add-SasPass 'summary fixtures expose required variables' }

foreach ($registryPath in @(
    'survey/fixtures/english-log/serial_preflight_artifact_registry.sample.json',
    'survey/fixtures/english-log/network_preflight_artifact_registry.sample.json'
)) {
    if (Test-Path -LiteralPath $registryPath) {
        $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
        $roles = @($registry.artifacts | ForEach-Object { $_.role })
        foreach ($role in @('report', 'handoff')) {
            if ($roles -notcontains $role) {
                Add-SasFailure "$registryPath missing artifact role: $role"
            }
        }
        if (($roles -notcontains 'source') -and ($roles -notcontains 'source_serial_list')) {
            Add-SasFailure "$registryPath missing source artifact role"
        }
        if (($roles -notcontains 'summary') -and ($roles -notcontains 'summary_json')) {
            Add-SasFailure "$registryPath missing summary artifact role"
        }
    }
}
if ($failures.Count -eq 0) { Add-SasPass 'artifact registry roles are complete' }

foreach ($workflow in @(
    'survey/workflows/serial-to-preflight.yaml',
    'survey/workflows/network-preflight.yaml',
    'survey/workflows/serial-iteration.yaml'
)) {
    Assert-SasContains -Path $workflow -Fragment 'network_activity_policy:'
    Assert-SasContains -Path $workflow -Fragment 'target_mutation_policy:'
}
if ($failures.Count -eq 0) { Add-SasPass 'workflow specs declare safety policy fields' }

$scopeLedger = 'docs/handoff/pr142-scope-ledger.md'
foreach ($fragment in @(
    'PR #142 is intentionally a broad harness-foundation PR',
    '## Owned lanes',
    '## Explicit non-owned lanes',
    '## Merge-risk controls',
    '## Merge-readiness rule',
    'Canonical run context module',
    'Target reduction planner',
    'Low-noise port policy',
    'Windows log classifier',
    'Manifest-driven deployment',
    'Windows .cmd launchers must be PowerShell-native',
    'scripts/SasRunContext.psm1 remains outside PR #142-owned changes'
)) {
    Assert-SasContains -Path $scopeLedger -Fragment $fragment
}
$runContextBoundary = 'Tests/bash/RUN_CONTEXT_LANE_BOUNDARY.md'
foreach ($fragment in @(
    'PR #146',
    'must consume that module after rebasing',
    'Do not add new foundation-contract assertions here that make this PR the behavioral owner'
)) {
    Assert-SasContains -Path $runContextBoundary -Fragment $fragment
}
if ($failures.Count -eq 0) { Add-SasPass 'PR142 scope ledger controls broad PR risk' }

Assert-SasContains -Path 'Run-HarnessContracts.cmd' -Fragment 'scripts\Invoke-SasHarnessContracts.ps1'
Assert-SasContains -Path 'Run-HarnessValidation.cmd' -Fragment 'scripts\validate-sysadmin-harness.ps1'
Assert-SasContains -Path 'Run-EnglishReportFixture.cmd' -Fragment 'scripts\Render-SasEnglishReport.ps1'
Assert-SasContains -Path 'Run-ExportHarnessEvidence.cmd' -Fragment 'Harness output locations'
Assert-SasContains -Path 'Run-HarnessContracts.cmd' -Fragment 'exit /b %SAS_EXIT%'
Assert-SasContains -Path 'Run-HarnessValidation.cmd' -Fragment 'exit /b %SAS_EXIT%'
Assert-SasContains -Path 'Run-EnglishReportFixture.cmd' -Fragment 'exit /b %SAS_EXIT%'
Assert-SasContains -Path 'Run-ExportHarnessEvidence.cmd' -Fragment 'exit /b %SAS_EXIT%'
Assert-SasNotContains -Path 'Run-HarnessContracts.cmd' -Fragment 'bash '
Assert-SasNotContains -Path 'Run-HarnessValidation.cmd' -Fragment 'bash '
Assert-SasNotContains -Path 'Run-EnglishReportFixture.cmd' -Fragment 'bash '
Assert-SasNotContains -Path 'Run-ExportHarnessEvidence.cmd' -Fragment 'bash '
if ($failures.Count -eq 0) { Add-SasPass 'root command wrappers are PowerShell-native' }

Assert-SasContains -Path 'scripts/Render-SasEnglishReport.ps1' -Fragment 'function Format-SasInlineCode'
Assert-SasContains -Path 'scripts/Render-SasEnglishReport.ps1' -Fragment '${name}:'
Assert-SasNotContains -Path 'scripts/Render-SasEnglishReport.ps1' -Fragment '"`$path`"'
Assert-SasNotMatch -Path 'scripts/Render-SasEnglishReport.ps1' -Pattern 'Test-NetConnection|Resolve-DnsName|naabu|nmap|socket|packet|ping|nslookup|curl' -Label 'blocked network command text'
if ($failures.Count -eq 0) { Add-SasPass 'renderer static contract passed' }

$fixtureText = Get-ChildItem -LiteralPath 'survey/fixtures/english-log' -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
$joinedFixtures = $fixtureText -join "`n"
$livePattern = '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}|\b(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)|\b(WMH|WNH|CYB)[A-Za-z0-9-]+'
if ($joinedFixtures -match $livePattern) {
    Add-SasFailure 'fixture contains live-looking operational identifier'
}
else {
    Add-SasPass 'fixtures avoid live-looking identifiers'
}

$ps = Resolve-SasPowerShellCommand
Write-Host "[SAS] Running synthetic harness validator through $ps"
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts/validate-sysadmin-harness.ps1')
if ($LASTEXITCODE -ne 0) {
    Add-SasFailure "synthetic harness validator failed with exit code $LASTEXITCODE"
}
else {
    Add-SasPass 'synthetic harness validator passed'
}

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host 'Harness contract failures:'
    foreach ($failure in $failures) {
        Write-Host "- $failure"
    }
    exit 1
}

Write-Host ''
Write-Host 'SysAdminSuite harness contracts passed.'
