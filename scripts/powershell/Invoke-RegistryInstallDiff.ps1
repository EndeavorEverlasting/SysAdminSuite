<#
.SYNOPSIS
Orchestrates evidence-first registry install diff runs.

.DESCRIPTION
Runs Recon -> Decide -> Act -> Log -> Export workflow for localhost-first registry install diff analysis.
This orchestrator is read-oriented by default and does not perform registry mutation.
It coordinates dependency scripts when present and records MissingDependency status when they are not.

.PARAMETER Mode
Pipeline mode: ReconOnly, SnapshotOnly, AnalyzeInstall, DiffOnly, ExportOnly.

.PARAMETER Target
Single target host (default localhost).

.PARAMETER TargetsCsv
Optional CSV of targets. Remote execution is intentionally unsupported in this slice.

.PARAMETER SoftwareId
Software identifier used for run naming and installer lookup.

.PARAMETER SourceConfigPath
Path to software source configuration file (default Config/sources.yaml).

.PARAMETER RegistryWatchlistPath
Path to registry watchlist JSON.

.PARAMETER OutputRoot
Root output folder for evidence bundles.

.PARAMETER DryRun
Requests dry-run installer execution behavior.

.PARAMETER InstallerPath
Optional installer path override for tracked install runner.

.PARAMETER InstallerType
Optional installer type passed through to tracked install runner.

.PARAMETER SilentArgs
Optional silent arguments passed through to tracked install runner.

.PARAMETER PreSnapshotPath
For DiffOnly mode: path to pre-install snapshot JSON.

.PARAMETER PostSnapshotPath
For DiffOnly mode: path to post-install snapshot JSON.

.PARAMETER ApprovedRemediation
Reserved switch. Not implemented in this sprint slice.

.EXAMPLE
pwsh -File scripts/powershell/Invoke-RegistryInstallDiff.ps1 -Mode ReconOnly -Target localhost

.EXAMPLE
pwsh -File scripts/powershell/Invoke-RegistryInstallDiff.ps1 -Mode SnapshotOnly -Target localhost

.EXAMPLE
pwsh -File scripts/powershell/Invoke-RegistryInstallDiff.ps1 -Mode AnalyzeInstall -Target localhost -SoftwareId EXAMPLE-SOFTWARE-ID -DryRun

.EXAMPLE
pwsh -File scripts/powershell/Invoke-RegistryInstallDiff.ps1 -Mode DiffOnly -Target localhost -PreSnapshotPath .\before.json -PostSnapshotPath .\after.json

.EXAMPLE
pwsh -File scripts/powershell/Invoke-RegistryInstallDiff.ps1 -Mode ReconOnly -Target localhost -OutputRoot exports/registry-install-diff/custom

.NOTES
Safety: registry writes are forbidden in this slice. ApprovedRemediation always returns Unsupported.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('ReconOnly','SnapshotOnly','AnalyzeInstall','DiffOnly','ExportOnly')]
    [string]$Mode,
    [string]$Target = 'localhost',
    [string]$TargetsCsv,
    [string]$SoftwareId = 'UNSPECIFIED-SOFTWARE',
    [string]$SourceConfigPath = 'Config/sources.yaml',
    [string]$RegistryWatchlistPath = 'config/registry_watchlist.example.json',
    [string]$OutputRoot = 'exports/registry-install-diff',
    [switch]$DryRun,
    [string]$InstallerPath,
    [ValidateSet('exe','msi','msix','unknown')]
    [string]$InstallerType = 'unknown',
    [string]$SilentArgs,
    [string]$PreSnapshotPath,
    [string]$PostSnapshotPath,
    [switch]$ApprovedRemediation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-JsonFile {
    param([string]$Path,[object]$InputObject)
    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $InputObject | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-Phase {
    param([string]$Name,[scriptblock]$Action)
    try {
        & $Action
        return [pscustomobject]@{ name = $Name; status = 'Success'; error = $null; timestamp = (Get-Date).ToString('o') }
    } catch {
        return [pscustomobject]@{ name = $Name; status = 'Failed'; error = $_.Exception.Message; timestamp = (Get-Date).ToString('o') }
    }
}

$dependencyScripts = @{
    readiness = 'scripts/powershell/Test-TargetReadiness.ps1'
    snapshot = 'scripts/powershell/Get-RegistrySnapshot.ps1'
    install = 'scripts/powershell/Invoke-TrackedInstall.ps1'
    diff = 'scripts/powershell/Compare-RegistrySnapshots.ps1'
}

$targets = @()
if ($Target) { $targets += $Target }
if ($TargetsCsv -and (Test-Path -LiteralPath $TargetsCsv)) {
    try {
        $csvTargets = Import-Csv -LiteralPath $TargetsCsv | ForEach-Object { $_.Target }
        $targets += $csvTargets
    } catch {}
}
$targets = $targets | Where-Object { $_ } | Select-Object -Unique
if ($targets.Count -eq 0) { $targets = @('localhost') }

$nonLocal = $targets | Where-Object { $_ -ne 'localhost' -and $_ -ne '.' -and $_ -ne $env:COMPUTERNAME }
if ($nonLocal.Count -gt 0) {
    throw "Unsupported: remote target execution is not implemented in this agent slice. Targets: $($nonLocal -join ', ')"
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$safeSoftware = ($SoftwareId -replace '[^A-Za-z0-9._-]', '_')
$runId = "${timestamp}_${safeSoftware}"
$runDir = Join-Path -Path $OutputRoot -ChildPath $runId
$targetsDir = Join-Path -Path $runDir -ChildPath 'targets'
New-Item -ItemType Directory -Path $targetsDir -Force | Out-Null

$manifest = [ordered]@{
    schema_version = '1.0'
    run_id = $runId
    created_at = (Get-Date).ToString('o')
    mode = $Mode
    dry_run = [bool]$DryRun
    software_id = $SoftwareId
    source_config_path = $SourceConfigPath
    registry_watchlist_path = $RegistryWatchlistPath
    output_root = $OutputRoot
    target_count = $targets.Count
    targets = $targets
    dependency_scripts = @{}
    phases = @()
    safety_flags = [ordered]@{
        registry_mutation_allowed = $false
        remote_install_allowed = $false
        dry_run = [bool]$DryRun
        approved_remediation_mode = [bool]$ApprovedRemediation
    }
}

foreach ($k in $dependencyScripts.Keys) {
    $p = $dependencyScripts[$k]
    $manifest.dependency_scripts[$k] = [ordered]@{ path = $p; exists = (Test-Path -LiteralPath $p) }
}

if ($ApprovedRemediation) {
    $manifest.phases += [pscustomobject]@{ name='ApprovedRemediation'; status='Unsupported'; reason='ApprovedRemediationNotImplemented' }
    Write-JsonFile -Path (Join-Path $runDir 'run_manifest.json') -InputObject $manifest
    "Unsupported: ApprovedRemediationNotImplemented"
    exit 2
}

$summaryRows = @()
foreach ($t in $targets) {
    $targetDir = Join-Path $targetsDir ($t -replace '[^A-Za-z0-9._-]','_')
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

    $row = [ordered]@{run_id=$runId;target=$t;software_id=$SoftwareId;mode=$Mode;readiness_status='Skipped';install_status='Skipped';diff_status='Skipped';total_changes='';suspicious_changes='';remediation_candidates='';evidence_path=$targetDir;notes=''}

    if ($Mode -in @('ReconOnly','AnalyzeInstall','SnapshotOnly')) {
        if (-not (Test-Path $dependencyScripts.readiness)) {
            $row.readiness_status = 'MissingDependency'
            $row.notes = "MissingDependency: $($dependencyScripts.readiness)"
        } else {
            $ph = Invoke-Phase -Name "Readiness:$t" -Action {
                & $dependencyScripts.readiness -Target $t | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $targetDir 'readiness.json') -Encoding UTF8
            }
            $manifest.phases += $ph
            $row.readiness_status = $ph.status
        }
    }

    if ($Mode -in @('SnapshotOnly','AnalyzeInstall')) {
        if (-not (Test-Path $dependencyScripts.snapshot)) {
            $row.notes = ($row.notes + ' MissingDependency: ' + $dependencyScripts.snapshot).Trim()
        } else {
            $manifest.phases += Invoke-Phase -Name "SnapshotBefore:$t" -Action {
                & $dependencyScripts.snapshot -Target $t -WatchlistPath $RegistryWatchlistPath | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $targetDir 'registry_before.json') -Encoding UTF8
            }
        }
    }

    if ($Mode -eq 'AnalyzeInstall') {
        if (-not (Test-Path $dependencyScripts.install)) {
            $row.install_status = 'MissingDependency'
            $row.notes = ($row.notes + ' MissingDependency: ' + $dependencyScripts.install).Trim()
        } else {
            $installPhase = Invoke-Phase -Name "Install:$t" -Action {
                $args = @('-Target', $t, '-SoftwareId', $SoftwareId, '-SourceConfigPath', $SourceConfigPath)
                if ($DryRun) { $args += '-DryRun' }
                if ($InstallerPath) { $args += @('-InstallerPath', $InstallerPath) }
                if ($InstallerType) { $args += @('-InstallerType', $InstallerType) }
                if ($SilentArgs) { $args += @('-SilentArgs', $SilentArgs) }
                & $dependencyScripts.install @args | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $targetDir 'installer_result.json') -Encoding UTF8
            }
            $manifest.phases += $installPhase
            $row.install_status = $installPhase.status
        }

        if (Test-Path $dependencyScripts.snapshot) {
            $manifest.phases += Invoke-Phase -Name "SnapshotAfter:$t" -Action {
                & $dependencyScripts.snapshot -Target $t -WatchlistPath $RegistryWatchlistPath | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $targetDir 'registry_after.json') -Encoding UTF8
            }
        }

        if (-not (Test-Path $dependencyScripts.diff)) {
            $row.diff_status = 'MissingDependency'
            $row.notes = ($row.notes + ' MissingDependency: ' + $dependencyScripts.diff).Trim()
        } else {
            $beforePath = Join-Path $targetDir 'registry_before.json'
            $afterPath = Join-Path $targetDir 'registry_after.json'
            if ((Test-Path $beforePath) -and (Test-Path $afterPath)) {
                $diffPhase = Invoke-Phase -Name "Diff:$t" -Action {
                    & $dependencyScripts.diff -BeforePath $beforePath -AfterPath $afterPath -WatchlistPath $RegistryWatchlistPath | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $targetDir 'registry_diff.json') -Encoding UTF8
                }
                $manifest.phases += $diffPhase
                $row.diff_status = $diffPhase.status
            } else {
                $row.diff_status = 'Skipped'
                Write-JsonFile -Path (Join-Path $targetDir 'registry_diff.json') -InputObject @{status='Skipped';reason='MissingSnapshotEvidence'}
            }
        }
    }

    if ($Mode -eq 'DiffOnly') {
        $beforePath = $PreSnapshotPath
        $afterPath = $PostSnapshotPath
        if (-not (Test-Path $dependencyScripts.diff)) {
            $row.diff_status = 'MissingDependency'
            $row.notes = "MissingDependency: $($dependencyScripts.diff)"
        } elseif (-not $beforePath -or -not $afterPath) {
            $row.diff_status = 'Failed'
            $row.notes = 'DiffOnly requires -PreSnapshotPath and -PostSnapshotPath'
        } else {
            $diffPhase = Invoke-Phase -Name "Diff:$t" -Action {
                & $dependencyScripts.diff -BeforePath $beforePath -AfterPath $afterPath -WatchlistPath $RegistryWatchlistPath | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $targetDir 'registry_diff.json') -Encoding UTF8
            }
            $manifest.phases += $diffPhase
            $row.diff_status = $diffPhase.status
        }
    }

    $summaryRows += [pscustomobject]$row
}

Write-JsonFile -Path (Join-Path $runDir 'run_manifest.json') -InputObject $manifest
$summaryCsvPath = Join-Path $runDir 'summary.csv'
$summaryRows | Export-Csv -Path $summaryCsvPath -NoTypeInformation -Encoding UTF8

$phaseBullets = if ($manifest.phases.Count -gt 0) {
    ($manifest.phases | ForEach-Object { "- $($_.name): $($_.status)" }) -join "`n"
} else {
    '- No phases executed.'
}

$summaryMd = @"
# Registry Install Diff Summary

- **Run ID:** $runId
- **Software ID:** $SoftwareId
- **Mode:** $Mode
- **Targets:** $($targets -join ', ')

## Phase Results
$phaseBullets

## Evidence Files
- run_manifest.json
- summary.md
- summary.csv
- targets/<target>/readiness.json (when available)
- targets/<target>/registry_before.json (when available)
- targets/<target>/installer_result.json (when available)
- targets/<target>/registry_after.json (when available)
- targets/<target>/registry_diff.json (when available or skipped with reason)

## Failures / Skips
- Missing dependencies are recorded as **MissingDependency** and include script paths.
- Remote target execution is unsupported in this slice.

## Next Action
- Validate dependency script availability and rerun in localhost dry-run mode first.

> Warning: Registry edits were not performed by this orchestrator.
"@
$summaryMd | Set-Content -Path (Join-Path $runDir 'summary.md') -Encoding UTF8

Write-Output "RunComplete: $runDir"
