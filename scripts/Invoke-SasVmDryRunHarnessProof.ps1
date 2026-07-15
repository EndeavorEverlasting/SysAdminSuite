#Requires -Version 5.1
<#
.SYNOPSIS
Runs the canonical synthetic harness validator and the offline VM dry-run readiness validator as one proof.

.DESCRIPTION
This composition layer executes repository-owned validators only. It does not start a VM, execute a real
package, launch an application or browser, contact a target, probe a network, or mutate host configuration.
It flattens both child PASS/SKIP/FAIL matrices into one schema-backed harness result.
#>
[CmdletBinding()]
param(
    [string]$OutputRoot,
    [string[]]$AdditionalRequiredPath = @(),
    [string]$VmProfilePath = 'harness/e2e/vm-dry-run-readiness.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot 'survey/output/vm-dry-run-harness-proof'
}
elseif (-not [IO.Path]::IsPathRooted($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot $OutputRoot
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$approvedOutputRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'survey/output')).TrimEnd('\', '/')
if (-not (
    $OutputRoot.Equals($approvedOutputRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $OutputRoot.StartsWith($approvedOutputRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
)) {
    throw "VM dry-run harness output must remain under survey/output. Received: $OutputRoot"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$baseOutput = Join-Path $OutputRoot 'base-harness'
$vmOutput = Join-Path $OutputRoot 'vm-readiness'
$matrixPath = Join-Path $OutputRoot 'harness_validation_matrix.txt'
$jsonPath = Join-Path $OutputRoot 'harness_validation_result.json'

function Resolve-SasPowerShellCommand {
    $currentPwsh = Join-Path $PSHOME 'pwsh.exe'
    if (Test-Path -LiteralPath $currentPwsh -PathType Leaf) { return $currentPwsh }
    $currentPowerShell = Join-Path $PSHOME 'powershell.exe'
    if (Test-Path -LiteralPath $currentPowerShell -PathType Leaf) { return $currentPowerShell }
    foreach ($name in @('pwsh', 'powershell.exe', 'powershell')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
    }
    throw 'PowerShell runtime not found.'
}

function Invoke-SasValidatorChild {
    param([string]$PowerShell, [string]$Script, [string[]]$Arguments)
    $lines = @(& $PowerShell -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    return [pscustomobject]@{
        exit_code = $LASTEXITCODE
        output = $lines
        detail = $(if ($lines.Count -gt 0) { $lines[-1] } else { 'completed without console output' })
    }
}

function Read-SasHarnessResult {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

$powerShell = Resolve-SasPowerShellCommand
$baseArguments = [Collections.Generic.List[string]]::new()
$baseArguments.Add('-OutputRoot')
$baseArguments.Add($baseOutput)
foreach ($requiredPath in $AdditionalRequiredPath) {
    $baseArguments.Add('-AdditionalRequiredPath')
    $baseArguments.Add([string]$requiredPath)
}
$baseRun = Invoke-SasValidatorChild -PowerShell $powerShell -Script (Join-Path $repoRoot 'scripts/validate-sysadmin-harness.ps1') -Arguments @($baseArguments)
$vmRun = Invoke-SasValidatorChild -PowerShell $powerShell -Script (Join-Path $repoRoot 'scripts/Test-SasVmDryRunReadiness.ps1') -Arguments @(
    '-OutputRoot', $vmOutput,
    '-ProfilePath', $VmProfilePath
)

$baseResultFile = Get-ChildItem -LiteralPath $baseOutput -Filter 'harness_validation_result.json' -Recurse -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc |
    Select-Object -Last 1
$baseResult = if ($baseResultFile) { Read-SasHarnessResult -Path $baseResultFile.FullName } else { $null }
$vmResultPath = Join-Path $vmOutput 'vm_dry_run_readiness_result.json'
$vmResult = Read-SasHarnessResult -Path $vmResultPath

$checks = [Collections.Generic.List[object]]::new()
if ($baseResult) {
    foreach ($check in @($baseResult.checks)) {
        $checks.Add([pscustomobject]@{
            status = [string]$check.status
            name = [string]$check.name
            detail = [string]$check.detail
            required = [bool]$check.required
        })
    }
}
else {
    $checks.Add([pscustomobject]@{
        status = 'FAIL'
        name = 'base harness result'
        detail = "result_missing; child_exit_$($baseRun.exit_code): $($baseRun.detail)"
        required = $true
    })
}

if ($vmResult) {
    foreach ($check in @($vmResult.checks)) {
        $checks.Add([pscustomobject]@{
            status = [string]$check.status
            name = "VM dry run: $([string]$check.name)"
            detail = [string]$check.detail
            required = [bool]$check.required
        })
    }
}
else {
    $checks.Add([pscustomobject]@{
        status = 'FAIL'
        name = 'VM dry-run result'
        detail = "result_missing; child_exit_$($vmRun.exit_code): $($vmRun.detail)"
        required = $true
    })
}

if ($baseRun.exit_code -ne 0 -and $baseResult -and @($baseResult.checks | Where-Object status -eq 'FAIL').Count -eq 0) {
    $checks.Add([pscustomobject]@{
        status = 'FAIL'
        name = 'base harness child exit'
        detail = "unexpected_exit_$($baseRun.exit_code): $($baseRun.detail)"
        required = $true
    })
}
if ($vmRun.exit_code -ne 0 -and $vmResult -and @($vmResult.checks | Where-Object status -eq 'FAIL').Count -eq 0) {
    $checks.Add([pscustomobject]@{
        status = 'FAIL'
        name = 'VM dry-run child exit'
        detail = "unexpected_exit_$($vmRun.exit_code): $($vmRun.detail)"
        required = $true
    })
}

$dependencies = [ordered]@{}
if ($baseResult) {
    foreach ($property in $baseResult.dependencies.PSObject.Properties) {
        $dependencies[$property.Name] = $property.Value
    }
}
$dependencies.vm_readiness_validator = 'scripts/Test-SasVmDryRunReadiness.ps1'
$dependencies.vm_provider = if ($vmResult) { $vmResult.dependencies.vm_provider } else { $null }

$branch = if ($baseResult) { [string]$baseResult.branch } else { 'unknown' }
$commit = if ($baseResult) { [string]$baseResult.commit } else { 'unknown' }
$passed = @($checks | Where-Object status -eq 'PASS').Count
$skipped = @($checks | Where-Object status -eq 'SKIP').Count
$failed = @($checks | Where-Object status -eq 'FAIL').Count

$matrix = [Collections.Generic.List[string]]::new()
$matrix.Add('APP HARNESS VALIDATION')
$matrix.Add("Repo: $repoRoot")
$matrix.Add("Branch: $branch")
$matrix.Add("Commit: $commit")
$matrix.Add('Proof: synthetic_offline (VM readiness only; no VM started, real package executed, network probe, launcher, or target mutation)')
$matrix.Add('')
foreach ($check in $checks) {
    $suffix = if ($check.detail) { " - $($check.detail)" } else { '' }
    $matrix.Add("[$($check.status)] $($check.name)$suffix")
}
$matrix.Add('')
$matrix.Add("Result: $passed passed / $skipped skipped / $failed failed")
$matrix.Add("JSON: $jsonPath")

$result = [ordered]@{
    schema_version = 'sas-harness-proof/v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    repo_root = $repoRoot
    branch = $branch
    commit = $commit
    proof_level = 'synthetic_offline'
    runtime_proof = $false
    network_activity_performed = $false
    launcher_execution_performed = $false
    target_mutation_performed = $false
    data_mutation_performed = $false
    counts = [ordered]@{
        passed = $passed
        skipped = $skipped
        failed = $failed
    }
    dependencies = $dependencies
    checks = @($checks)
    artifacts = [ordered]@{
        matrix = $matrixPath
        json = $jsonPath
        run_root = $(if ($baseResult) { $baseResult.artifacts.run_root } else { $null })
        artifact_registry = $(if ($baseResult) { $baseResult.artifacts.artifact_registry } else { $null })
    }
}

$matrix | Set-Content -LiteralPath $matrixPath -Encoding UTF8
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

if ($baseResult -and $baseResult.artifacts.artifact_registry -and
    (Test-Path -LiteralPath ([string]$baseResult.artifacts.artifact_registry) -PathType Leaf)) {
    Import-Module (Join-Path $repoRoot 'scripts/SasRunContext.psm1') -Force
    [void](Register-SasArtifact -RegistryPath ([string]$baseResult.artifacts.artifact_registry) -Role validation_matrix -Path $matrixPath -Tracked $false -LiveData $false -Generated $true -Description 'Combined harness and VM dry-run readiness matrix.' -CreatedBy 'Invoke-SasVmDryRunHarnessProof')
    [void](Register-SasArtifact -RegistryPath ([string]$baseResult.artifacts.artifact_registry) -Role validation_result -Path $jsonPath -Tracked $false -LiveData $false -Generated $true -Description 'Combined machine-readable harness and VM dry-run readiness proof.' -CreatedBy 'Invoke-SasVmDryRunHarnessProof')
}

$matrix | ForEach-Object { Write-Host $_ }
if ($failed -gt 0) {
    exit 1
}
