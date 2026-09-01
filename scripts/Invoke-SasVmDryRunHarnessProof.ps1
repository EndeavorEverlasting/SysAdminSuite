#Requires -Version 5.1
<#
.SYNOPSIS
Runs the canonical synthetic harness validator, private-ledger contract validator, and offline VM dry-run readiness validator as one proof.

.DESCRIPTION
This composition layer executes repository-owned validators only. It does not write private ledger history, start a VM,
execute a real package, launch an application or browser, contact a target, probe a network, or mutate host configuration.
It flattens child PASS/SKIP/FAIL evidence into one schema-backed harness result, preserving the exact repository head,
canonical user/machine profile, validator set, Prompt Kit owner, and honest skip disposition.
#>
[CmdletBinding()]
param(
    [string]$OutputRoot,
    [string[]]$AdditionalRequiredPath = @(),
    [string]$VmProfilePath = 'harness/e2e/vm-dry-run-readiness.json',
    [string]$MachineProfile,
    [ValidateSet('auto','windows','linux','macos')][string]$ProfileOs = 'auto',
    [string]$ProfileUser,
    [ValidateSet('auto','true','false')][string]$OneDriveEnabled = 'auto',
    [string]$DesktopDevRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$callerLocation = (Get-Location).Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$desktopDevRootOverride = $DesktopDevRoot
if (-not [string]::IsNullOrWhiteSpace($desktopDevRootOverride)) {
    if ([IO.Path]::IsPathRooted($desktopDevRootOverride)) {
        $desktopDevRootOverride = [IO.Path]::GetFullPath($desktopDevRootOverride)
    }
    else {
        $desktopDevRootOverride = [IO.Path]::GetFullPath((Join-Path $callerLocation $desktopDevRootOverride))
    }
}
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
$privateLedgerValidator = 'harness/validators/validate-private-repository-ledger.py'

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

function Resolve-SasPythonCommand {
    foreach ($name in @('python3', 'python')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
    }
    return $null
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

function Invoke-SasPythonValidatorChild {
    param([AllowNull()][string]$Python, [string]$Script)
    if ([string]::IsNullOrWhiteSpace($Python)) {
        return [pscustomobject]@{ exit_code = 127; output = @(); detail = 'python_runtime_not_available' }
    }
    $lines = @(& $Python $Script 2>&1 | ForEach-Object { $_.ToString() })
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

function Get-CheckDisposition {
    param($Check)
    if (@($Check.PSObject.Properties.Name) -contains 'disposition' -and -not [string]::IsNullOrWhiteSpace([string]$Check.disposition)) {
        return [string]$Check.disposition
    }
    if ([bool]$Check.required) { return 'required' }
    if ([string]$Check.status -eq 'SKIP') {
        if ([string]$Check.detail -in @('vm_provider_not_available','lsp_project_not_loaded','git_bash_not_available','python_runtime_not_available','mcp_catalog_unavailable')) {
            return 'environment_blocked'
        }
        return 'inapplicable'
    }
    return 'optional'
}

$powerShell = Resolve-SasPowerShellCommand
$python = Resolve-SasPythonCommand
$baseArguments = [Collections.Generic.List[string]]::new()
$baseArguments.Add('-OutputRoot')
$baseArguments.Add($baseOutput)
foreach ($requiredPath in $AdditionalRequiredPath) {
    $baseArguments.Add('-AdditionalRequiredPath')
    $baseArguments.Add([string]$requiredPath)
}
foreach ($pair in @(
    @('-MachineProfile', $MachineProfile),
    @('-ProfileOs', $ProfileOs),
    @('-ProfileUser', $ProfileUser),
    @('-OneDriveEnabled', $OneDriveEnabled),
    @('-DesktopDevRoot', $desktopDevRootOverride)
)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$pair[1])) {
        $baseArguments.Add([string]$pair[0])
        $baseArguments.Add([string]$pair[1])
    }
}
$baseRun = Invoke-SasValidatorChild -PowerShell $powerShell -Script (Join-Path $repoRoot 'scripts/validate-sysadmin-harness.ps1') -Arguments @($baseArguments)
$privateLedgerRun = Invoke-SasPythonValidatorChild -Python $python -Script (Join-Path $repoRoot $privateLedgerValidator)
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
            disposition = Get-CheckDisposition -Check $check
        })
    }
}
else {
    $checks.Add([pscustomobject]@{
        status = 'FAIL'; name = 'base harness result'; detail = "result_missing; child_exit_$($baseRun.exit_code): $($baseRun.detail)"; required = $true; disposition = 'required'
    })
}

if ($privateLedgerRun.exit_code -eq 0) {
    $checks.Add([pscustomobject]@{
        status = 'PASS'; name = 'private repository ledger'; detail = $privateLedgerRun.detail; required = $true; disposition = 'required'
    })
}
else {
    $checks.Add([pscustomobject]@{
        status = 'FAIL'; name = 'private repository ledger'; detail = "child_exit_$($privateLedgerRun.exit_code): $($privateLedgerRun.detail)"; required = $true; disposition = 'required'
    })
}

if ($vmResult) {
    foreach ($check in @($vmResult.checks)) {
        $checks.Add([pscustomobject]@{
            status = [string]$check.status
            name = "VM dry run: $([string]$check.name)"
            detail = [string]$check.detail
            required = [bool]$check.required
            disposition = Get-CheckDisposition -Check $check
        })
    }
}
else {
    $checks.Add([pscustomobject]@{
        status = 'FAIL'; name = 'VM dry-run result'; detail = "result_missing; child_exit_$($vmRun.exit_code): $($vmRun.detail)"; required = $true; disposition = 'required'
    })
}

if ($baseRun.exit_code -ne 0 -and $baseResult -and @($baseResult.checks | Where-Object status -eq 'FAIL').Count -eq 0) {
    $checks.Add([pscustomobject]@{
        status = 'FAIL'; name = 'base harness child exit'; detail = "unexpected_exit_$($baseRun.exit_code): $($baseRun.detail)"; required = $true; disposition = 'required'
    })
}
if ($vmRun.exit_code -ne 0 -and $vmResult -and @($vmResult.checks | Where-Object status -eq 'FAIL').Count -eq 0) {
    $checks.Add([pscustomobject]@{
        status = 'FAIL'; name = 'VM dry-run child exit'; detail = "unexpected_exit_$($vmRun.exit_code): $($vmRun.detail)"; required = $true; disposition = 'required'
    })
}

$requiredSkips = @($checks | Where-Object { $_.required -and $_.status -eq 'SKIP' })
if ($requiredSkips.Count -gt 0) {
    $checks.Add([pscustomobject]@{
        status = 'FAIL'; name = 'required proof unavailable'; detail = (($requiredSkips | ForEach-Object name) -join ', '); required = $true; disposition = 'required'
    })
}

$dependencies = [ordered]@{}
if ($baseResult) {
    foreach ($property in $baseResult.dependencies.PSObject.Properties) {
        $dependencies[$property.Name] = $property.Value
    }
}
$dependencies.private_ledger_validator = $privateLedgerValidator
$dependencies.private_ledger_python = $python
$dependencies.vm_readiness_validator = 'scripts/Test-SasVmDryRunReadiness.ps1'
$dependencies.vm_provider = if ($vmResult) { $vmResult.dependencies.vm_provider } else { $null }

$branch = if ($baseResult) { [string]$baseResult.branch } else { 'unknown' }
$commit = if ($baseResult) { [string]$baseResult.commit } else { 'unknown' }
$validatorSet = [Collections.Generic.List[string]]::new()
if ($baseResult -and @($baseResult.PSObject.Properties.Name) -contains 'validator_set') {
    foreach ($validator in @($baseResult.validator_set)) { $validatorSet.Add([string]$validator) }
}
$validatorSet.Add($privateLedgerValidator)
$validatorSet.Add('scripts/Test-SasVmDryRunReadiness.ps1')
$validatorSet.Add('scripts/Invoke-SasVmDryRunHarnessProof.ps1')
$profile = if ($baseResult -and @($baseResult.PSObject.Properties.Name) -contains 'profile') { $baseResult.profile } else { $null }
$promptOwner = if ($baseResult -and @($baseResult.PSObject.Properties.Name) -contains 'prompt_owner') { $baseResult.prompt_owner } else { $null }

$passed = @($checks | Where-Object status -eq 'PASS').Count
$skipped = @($checks | Where-Object status -eq 'SKIP').Count
$failed = @($checks | Where-Object status -eq 'FAIL').Count
$finalStatus = if ($failed -eq 0) { 'PASS' } else { 'FAIL' }

$matrix = [Collections.Generic.List[string]]::new()
$matrix.Add('APP HARNESS VALIDATION')
$matrix.Add("Repo: $repoRoot")
$matrix.Add("Branch: $branch")
$matrix.Add("Commit: $commit")
if ($promptOwner) { $matrix.Add("Prompt: $($promptOwner.id) | $($promptOwner.name) | $($promptOwner.purpose)") }
else { $matrix.Add('Prompt: unresolved') }
if ($profile) { $matrix.Add("Profile: $($profile.machine_profile) | os=$($profile.os) | user=$($profile.user) | onedrive_enabled=$($profile.onedrive_enabled) | desktop_dev_root=$($profile.desktop_dev_root)") }
else { $matrix.Add('Profile: unresolved') }
$matrix.Add('Proof: synthetic_offline (private ledger contract + VM readiness only; no ledger history write, VM start, real package execution, network probe, launcher, or target mutation)')
$matrix.Add('')
foreach ($check in $checks) {
    $suffix = if ($check.detail) { " - $($check.detail)" } else { '' }
    $matrix.Add("[$($check.status)] $($check.name)$suffix")
}
$matrix.Add('')
$matrix.Add("Result: $passed passed / $skipped skipped / $failed failed")
$matrix.Add("Final status: $finalStatus")
$matrix.Add("JSON: $jsonPath")

$result = [ordered]@{
    schema_version = 'sas-harness-proof/v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    repo_root = $repoRoot
    branch = $branch
    commit = $commit
    proof_level = 'synthetic_offline'
    final_status = $finalStatus
    runtime_proof = $false
    network_activity_performed = $false
    launcher_execution_performed = $false
    target_mutation_performed = $false
    data_mutation_performed = $false
    counts = [ordered]@{ passed = $passed; skipped = $skipped; failed = $failed }
    dependencies = $dependencies
    validator_set = @($validatorSet)
    profile = $profile
    prompt_owner = $promptOwner
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
    [void](Register-SasArtifact -RegistryPath ([string]$baseResult.artifacts.artifact_registry) -Role validation_matrix -Path $matrixPath -Tracked $false -LiveData $false -Generated $true -Description 'Combined harness, private-ledger contract, and VM dry-run readiness matrix.' -CreatedBy 'Invoke-SasVmDryRunHarnessProof')
    [void](Register-SasArtifact -RegistryPath ([string]$baseResult.artifacts.artifact_registry) -Role validation_result -Path $jsonPath -Tracked $false -LiveData $false -Generated $true -Description 'Combined machine-readable harness, private-ledger contract, and VM dry-run readiness proof.' -CreatedBy 'Invoke-SasVmDryRunHarnessProof')
}

$matrix | ForEach-Object { Write-Host $_ }
if ($failed -gt 0) { exit 1 }
