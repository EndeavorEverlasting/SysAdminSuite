#Requires -Version 5.1
<#
.SYNOPSIS
Validates the tracked virtual-machine dry-run contract without starting a VM or executing a real package.

.DESCRIPTION
This validator inspects only repository contracts, fixture-safe E2E journeys, and optional provider command
presence. It never starts a hypervisor, launches an installer, contacts a target, probes a network, changes
AutoLogon, or mutates host configuration. Generated evidence remains under survey/output.
#>
[CmdletBinding()]
param(
    [string]$ProfilePath = 'harness/e2e/vm-dry-run-readiness.json',
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot 'survey/output/vm-dry-run-readiness'
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
    throw "VM dry-run readiness output must remain under survey/output. Received: $OutputRoot"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$matrixPath = Join-Path $OutputRoot 'vm_dry_run_readiness_matrix.txt'
$resultPath = Join-Path $OutputRoot 'vm_dry_run_readiness_result.json'
$checks = [Collections.Generic.List[object]]::new()
$dependencies = [ordered]@{}

function Add-SasVmReadinessCheck {
    param(
        [ValidateSet('PASS', 'SKIP', 'FAIL')]
        [string]$Status,
        [string]$Name,
        [string]$Detail = '',
        [bool]$Required = $true
    )
    $script:checks.Add([pscustomobject]@{
        status = $Status
        name = $Name
        detail = $Detail
        required = $Required
    })
}

function Test-SasPathUnderRoot {
    param([string]$Path, [string]$Root)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    return (
        $fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($fullRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
    )
}

function ConvertTo-SasRepoRelativePath {
    param([string]$Path)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $rootPrefix = [IO.Path]::GetFullPath($repoRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        return [IO.Path]::GetFileName($fullPath)
    }
    return $fullPath.Substring($rootPrefix.Length).Replace('\', '/')
}

$git = Get-Command git -ErrorAction SilentlyContinue
$branchValue = if ($git) { & $git.Source -C $repoRoot branch --show-current | Select-Object -First 1 } else { $null }
$commitValue = if ($git) { & $git.Source -C $repoRoot rev-parse HEAD | Select-Object -First 1 } else { $null }
$branch = if ([string]::IsNullOrWhiteSpace([string]$branchValue)) { 'detached' } else { ([string]$branchValue).Trim() }
$commit = if ([string]::IsNullOrWhiteSpace([string]$commitValue)) { 'unknown' } else { ([string]$commitValue).Trim().ToLowerInvariant() }
$dependencies.git = if ($git) { $git.Source } else { $null }
$dependencies.powershell = $PSHOME
$dependencies.vm_provider = $null

$resolvedProfilePath = if ([IO.Path]::IsPathRooted($ProfilePath)) {
    [IO.Path]::GetFullPath($ProfilePath)
}
else {
    [IO.Path]::GetFullPath((Join-Path $repoRoot $ProfilePath))
}

$profile = $null
try {
    $requiredPaths = @(
        $resolvedProfilePath,
        (Join-Path $repoRoot 'schemas/harness/vm-dry-run-readiness.schema.json'),
        (Join-Path $repoRoot 'schemas/harness/harness-proof-result.schema.json'),
        (Join-Path $repoRoot 'harness/e2e/e2e-profiles.json'),
        (Join-Path $repoRoot 'scripts/Invoke-SasSoftwareInstallE2E.ps1'),
        (Join-Path $repoRoot 'scripts/Invoke-SasValidatedSoftwareDeploymentE2E.ps1'),
        (Join-Path $repoRoot 'scripts/Show-SasValidatedSoftwareDeploymentResult.ps1'),
        (Join-Path $repoRoot 'scripts/Invoke-SasSoftwareInstall.ps1'),
        (Join-Path $repoRoot 'Tests/Pester/SoftwareInstallHarness.Tests.ps1'),
        (Join-Path $repoRoot 'docs/SOFTWARE_INSTALL_E2E.md')
    )
    $missing = @($requiredPaths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missing.Count -gt 0) {
        $display = @($missing | ForEach-Object {
            if (Test-SasPathUnderRoot -Path $_ -Root $repoRoot) {
                ConvertTo-SasRepoRelativePath -Path $_
            }
            else {
                [IO.Path]::GetFileName($_)
            }
        })
        Add-SasVmReadinessCheck FAIL 'required files' ('missing_required_path: ' + ($display -join ', '))
    }
    else {
        Add-SasVmReadinessCheck PASS 'required files' "$($requiredPaths.Count) VM dry-run paths present"
    }

    if (-not (Test-SasPathUnderRoot -Path $resolvedProfilePath -Root $repoRoot)) {
        Add-SasVmReadinessCheck FAIL 'VM dry-run profile' 'profile_path_outside_repository'
    }
    elseif (Test-Path -LiteralPath $resolvedProfilePath -PathType Leaf) {
        try {
            $profile = Get-Content -LiteralPath $resolvedProfilePath -Raw | ConvertFrom-Json
            $safety = $profile.safety
            $profileProblems = [Collections.Generic.List[string]]::new()
            if ($profile.schema_version -ne 'sas-vm-dry-run-readiness/v1') { $profileProblems.Add('schema_version') }
            if ($profile.schema_path -ne 'schemas/harness/vm-dry-run-readiness.schema.json') { $profileProblems.Add('schema_path') }
            if ($profile.proof_class -ne 'synthetic_offline_vm_readiness') { $profileProblems.Add('proof_class') }
            if ($profile.proof_ceiling -ne 'readiness_only_no_vm_started') { $profileProblems.Add('proof_ceiling') }
            foreach ($field in @(
                'readiness_validator_starts_vm',
                'readiness_validator_executes_real_package',
                'readiness_validator_mutates_host',
                'readiness_validator_contacts_target',
                'readiness_validator_uses_external_network',
                'autologon_allowed'
            )) {
                if ($safety.$field -ne $false) { $profileProblems.Add($field) }
            }
            foreach ($field in @(
                'runtime_vm_must_be_disposable',
                'rollback_or_destroy_required',
                'one_package_per_clean_snapshot'
            )) {
                if ($safety.$field -ne $true) { $profileProblems.Add($field) }
            }
            if ($profile.provider_detection.mode -ne 'command_presence_only' -or
                $profile.provider_detection.required_for_offline_readiness -ne $false) {
                $profileProblems.Add('provider_detection')
            }
            if ($profileProblems.Count -gt 0) {
                Add-SasVmReadinessCheck FAIL 'VM dry-run profile' ('unsafe_or_incomplete_field: ' + ($profileProblems -join ', '))
            }
            else {
                Add-SasVmReadinessCheck PASS 'VM dry-run profile' 'fail-closed synthetic readiness posture'
            }
        }
        catch {
            Add-SasVmReadinessCheck FAIL 'VM dry-run profile' $_.Exception.Message
        }
    }

    if ($profile) {
        try {
            $e2eProfiles = Get-Content -LiteralPath (Join-Path $repoRoot 'harness/e2e/e2e-profiles.json') -Raw | ConvertFrom-Json
            $journeys = @{}
            foreach ($journey in @($e2eProfiles.journeys)) {
                $journeys[[string]$journey.id] = $journey
            }
            $journeyProblems = [Collections.Generic.List[string]]::new()
            foreach ($journeyId in @($profile.dry_run_journey_ids)) {
                if (-not $journeys.ContainsKey([string]$journeyId)) {
                    $journeyProblems.Add("missing:$journeyId")
                    continue
                }
                $journey = $journeys[[string]$journeyId]
                if ($journey.network_scope -ne 'none') { $journeyProblems.Add("network_scope:$journeyId") }
                if ($journey.target_mutation -ne $false) { $journeyProblems.Add("target_mutation:$journeyId") }
                if ($journey.required -ne $true) { $journeyProblems.Add("not_required:$journeyId") }
                if (-not (Test-Path -LiteralPath (Join-Path $repoRoot ([string]$journey.script)) -PathType Leaf)) {
                    $journeyProblems.Add("script_missing:$journeyId")
                }
            }
            if ($journeyProblems.Count -gt 0) {
                Add-SasVmReadinessCheck FAIL 'fixture dry-run journeys' ($journeyProblems -join ', ')
            }
            else {
                Add-SasVmReadinessCheck PASS 'fixture dry-run journeys' "$(@($profile.dry_run_journey_ids).Count) isolated journeys are required and network-free"
            }
        }
        catch {
            Add-SasVmReadinessCheck FAIL 'fixture dry-run journeys' $_.Exception.Message
        }

        try {
            $installScript = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts/Invoke-SasSoftwareInstall.ps1') -Raw
            $pester = Get-Content -LiteralPath (Join-Path $repoRoot 'Tests/Pester/SoftwareInstallHarness.Tests.ps1') -Raw
            $e2eScript = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts/Invoke-SasSoftwareInstallE2E.ps1') -Raw
            $requiredFragments = @(
                'if (-not $WhatIfPreference -and -not (Test-Path -LiteralPath $installerPath',
                'keeps WhatIf local and does not probe the share or target',
                'No live target or external network is contacted.',
                "live_target_e2e = `$false",
                "external_network_activity_performed = `$false",
                "target_mutation_performed = `$false"
            )
            $combined = $installScript + "`n" + $pester + "`n" + $e2eScript
            $missingFragments = @($requiredFragments | Where-Object { -not $combined.Contains($_) })
            if ($missingFragments.Count -gt 0) {
                Add-SasVmReadinessCheck FAIL 'request-only dry run' ('missing_contract: ' + ($missingFragments -join ' | '))
            }
            else {
                Add-SasVmReadinessCheck PASS 'request-only dry run' 'WhatIf remains local; fixture proof declares no live target or external network'
            }
        }
        catch {
            Add-SasVmReadinessCheck FAIL 'request-only dry run' $_.Exception.Message
        }

        $requiredRuntimeEntries = @(
            'provider_selected',
            'clean_checkpoint_or_ephemeral_guest',
            'host_negative_gate_passed',
            'approved_package_identity_available',
            'supported_installer_arguments_available',
            'guest_evidence_root_selected',
            'rollback_or_destroy_plan_recorded',
            'autologon_excluded'
        )
        $requiredEvidence = @(
            'host_preflight',
            'guest_baseline',
            'package_identity',
            'dry_run_plan',
            'install_result',
            'application_acceptance',
            'guest_delta',
            'rollback_or_destroy_result',
            'host_postflight'
        )
        $missingRuntime = @($requiredRuntimeEntries | Where-Object { @($profile.runtime_entry_requirements) -notcontains $_ })
        $missingEvidence = @($requiredEvidence | Where-Object { @($profile.required_evidence) -notcontains $_ })
        if ($missingRuntime.Count -gt 0 -or $missingEvidence.Count -gt 0) {
            Add-SasVmReadinessCheck FAIL 'runtime entry gate' ("missing_runtime=" + ($missingRuntime -join ',') + "; missing_evidence=" + ($missingEvidence -join ','))
        }
        else {
            Add-SasVmReadinessCheck PASS 'runtime entry gate' 'provider, clean guest, package identity, rollback, acceptance, and host postflight are required'
        }

        $detectedProviders = [Collections.Generic.List[string]]::new()
        foreach ($candidate in @($profile.provider_detection.commands)) {
            $command = Get-Command ([string]$candidate) -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($command) {
                $detectedProviders.Add(([string]$candidate))
            }
        }
        if ($detectedProviders.Count -gt 0) {
            $dependencies.vm_provider = ($detectedProviders -join ',')
            Add-SasVmReadinessCheck PASS 'optional VM provider smoke' ("command_presence_only: " + ($detectedProviders -join ', ')) $false
        }
        else {
            Add-SasVmReadinessCheck SKIP 'optional VM provider smoke' 'vm_provider_not_available' $false
        }
    }
}
catch {
    Add-SasVmReadinessCheck FAIL 'VM dry-run readiness' $_.Exception.Message
}

$passed = @($checks | Where-Object status -eq 'PASS').Count
$skipped = @($checks | Where-Object status -eq 'SKIP').Count
$failed = @($checks | Where-Object status -eq 'FAIL').Count
$matrix = [Collections.Generic.List[string]]::new()
$matrix.Add('VM DRY-RUN READINESS')
$matrix.Add("Repo: $repoRoot")
$matrix.Add("Branch: $branch")
$matrix.Add("Commit: $commit")
$matrix.Add('Proof: synthetic_offline (no VM started, no real package executed, no target contact, no host mutation)')
$matrix.Add('')
foreach ($check in $checks) {
    $suffix = if ($check.detail) { " - $($check.detail)" } else { '' }
    $matrix.Add("[$($check.status)] $($check.name)$suffix")
}
$matrix.Add('')
$matrix.Add("Result: $passed passed / $skipped skipped / $failed failed")
$matrix.Add("JSON: $resultPath")

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
        json = $resultPath
        run_root = $null
        artifact_registry = $null
    }
}

$matrix | Set-Content -LiteralPath $matrixPath -Encoding UTF8
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
$matrix | ForEach-Object { Write-Host $_ }
if ($failed -gt 0) {
    exit 1
}
