#Requires -Version 5.1
<#
.SYNOPSIS
Runs the approved software-install workflow end to end against an isolated local fixture target.

.DESCRIPTION
This journey executes the real Invoke-SasSoftwareInstall.ps1 operator wrapper, the wrapper's real
remote-install script block, and a real child installer process. A local fixture transport adapter
replaces WinRM and the approved UNC share only for this isolated journey. No live target or external
network is contacted.

The journey captures before/after filesystem snapshots, an added/changed/removed delta, the operator
JSONL event stream and summary, fixture installer-owned logs, and a final machine-readable E2E result.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not [IO.Path]::IsPathRooted($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot $OutputRoot
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$approvedOutputRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'survey/output')).TrimEnd('\')
if (-not (
    $OutputRoot.Equals($approvedOutputRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $OutputRoot.StartsWith($approvedOutputRoot + '\', [StringComparison]::OrdinalIgnoreCase)
)) {
    throw "Software-install E2E output must remain under survey/output. Received: $OutputRoot"
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$fixtureTargetRoot = Join-Path $OutputRoot 'fixture-target'
$fixtureProgramData = Join-Path $fixtureTargetRoot 'ProgramData'
$operatorOutputRoot = Join-Path $OutputRoot 'operator'
$fixtureSourceRoot = Join-Path $repoRoot 'Tests/fixtures/software-install'
$fixtureInstaller = Join-Path $fixtureSourceRoot 'fixture-installer.cmd'
$fixtureInstallerScript = Join-Path $fixtureSourceRoot 'fixture-installer.ps1'
$operatorScript = Join-Path $repoRoot 'scripts/Invoke-SasSoftwareInstall.ps1'
$mappedInstaller = '\\nt2kwb972sms01\Software\Fixture\fixture-installer.cmd'
$packageName = 'SysAdminSuite Fixture Package'
$packageMarker = Join-Path $fixtureTargetRoot 'InstalledPackages/SysAdminSuiteFixturePackage/manifest.json'
$installerOwnedLog = Join-Path $fixtureTargetRoot 'InstallerLogs/sysadminsuite-fixture-package.log'

foreach ($requiredPath in @($fixtureInstaller, $fixtureInstallerScript, $operatorScript)) {
    if (-not [IO.File]::Exists($requiredPath)) {
        throw "Required software-install E2E file is missing: $requiredPath"
    }
}

if ([IO.Directory]::Exists($fixtureTargetRoot)) {
    [IO.Directory]::Delete($fixtureTargetRoot, $true)
}
New-Item -ItemType Directory -Path $fixtureProgramData -Force | Out-Null
New-Item -ItemType Directory -Path $operatorOutputRoot -Force | Out-Null

$beforePath = Join-Path $OutputRoot 'software_install_before.json'
$afterPath = Join-Path $OutputRoot 'software_install_after.json'
$deltaPath = Join-Path $OutputRoot 'software_install_delta.json'
$eventPath = Join-Path $OutputRoot 'software_install_e2e_events.jsonl'
$resultPath = Join-Path $OutputRoot 'software_install_e2e_result.json'
$matrixPath = Join-Path $OutputRoot 'software_install_e2e_matrix.txt'

function Write-SasSoftwareInstallE2EEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $false)]
        [hashtable]$Data = @{}
    )

    [ordered]@{
        timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
        event = $Name
        proof_class = 'fixture-software-install-e2e'
        live_target = $false
        external_network_activity = $false
        target_mutation = $false
        data = $Data
    } | ConvertTo-Json -Depth 10 -Compress |
        Add-Content -LiteralPath $eventPath -Encoding UTF8
}

function Get-SasSoftwareInstallSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not [IO.Directory]::Exists($Root)) { return @() }
    $rootPrefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    return @(
        Get-ChildItem -LiteralPath $Root -Recurse -Force -File |
            ForEach-Object {
                [ordered]@{
                    relative_path = $_.FullName.Substring($rootPrefix.Length).Replace('\', '/')
                    bytes = $_.Length
                    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            } | Sort-Object relative_path
    )
}

function Get-SasSoftwareInstallDelta {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Before,
        [Parameter(Mandatory = $true)][object[]]$After
    )

    $beforeByPath = @{}
    foreach ($entry in $Before) { $beforeByPath[[string]$entry.relative_path] = $entry }
    $afterByPath = @{}
    foreach ($entry in $After) { $afterByPath[[string]$entry.relative_path] = $entry }

    $added = @($After | Where-Object {
        -not $beforeByPath.ContainsKey([string]$_.relative_path)
    } | Sort-Object relative_path)
    $removed = @($Before | Where-Object {
        -not $afterByPath.ContainsKey([string]$_.relative_path)
    } | Sort-Object relative_path)
    $changed = @(
        foreach ($entry in $After) {
            $path = [string]$entry.relative_path
            if ($beforeByPath.ContainsKey($path) -and $beforeByPath[$path].sha256 -ne $entry.sha256) {
                [ordered]@{
                    relative_path = $path
                    before_sha256 = $beforeByPath[$path].sha256
                    after_sha256 = $entry.sha256
                    before_bytes = $beforeByPath[$path].bytes
                    after_bytes = $entry.bytes
                }
            }
        }
    )

    return [ordered]@{
        schema_version = 'sas-software-install-delta/v1'
        added_count = $added.Count
        changed_count = $changed.Count
        removed_count = $removed.Count
        added = @($added)
        changed = @($changed)
        removed = @($removed)
    }
}

$before = @(Get-SasSoftwareInstallSnapshot -Root $fixtureTargetRoot)
ConvertTo-Json -InputObject $before -Depth 8 |
    Set-Content -LiteralPath $beforePath -Encoding UTF8
Write-SasSoftwareInstallE2EEvent -Name 'before_snapshot_captured' -Data @{
    file_count = $before.Count
    snapshot_path = $beforePath
}

# Process-local adapters let the production wrapper traverse its real session and remote-install
# branches while redirecting only transport and the approved UNC lookup to the fixture target.
function Test-Path {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ParameterSetName = 'Path')]
        [string[]]$Path,
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'LiteralPath')]
        [Alias('PSPath')]
        [string[]]$LiteralPath,
        [Microsoft.PowerShell.Commands.TestPathType]$PathType = [Microsoft.PowerShell.Commands.TestPathType]::Any,
        [switch]$IsValid
    )

    process {
        $values = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { $LiteralPath } else { $Path }
        foreach ($value in $values) {
            $normalized = ([string]$value).Replace('/', '\')
            if ($normalized.Equals($script:mappedInstaller, [StringComparison]::OrdinalIgnoreCase)) {
                [IO.File]::Exists($script:fixtureInstaller)
                continue
            }

            $delegate = @{}
            if ($IsValid) { $delegate['IsValid'] = $true } else { $delegate['PathType'] = $PathType }
            if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') {
                $delegate['LiteralPath'] = $value
            } else {
                $delegate['Path'] = $value
            }
            Microsoft.PowerShell.Management\Test-Path @delegate
        }
    }
}

function Start-Process {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$FilePath,
        [object[]]$ArgumentList = @(),
        [switch]$PassThru
    )

    $resolvedFilePath = if ($FilePath.Replace('/', '\').Equals(
        $script:mappedInstaller,
        [StringComparison]::OrdinalIgnoreCase
    )) { $script:fixtureInstaller } else { $FilePath }

    $delegate = @{ FilePath = $resolvedFilePath }
    if ($ArgumentList.Count -gt 0) { $delegate['ArgumentList'] = $ArgumentList }
    if ($PassThru) { $delegate['PassThru'] = $true }
    Microsoft.PowerShell.Management\Start-Process @delegate
}

function New-PSSessionOption {
    [CmdletBinding()]
    param([int]$OpenTimeout, [int]$OperationTimeout)
    [pscustomobject]@{
        OpenTimeout = $OpenTimeout
        OperationTimeout = $OperationTimeout
        FixtureTransport = $true
    }
}

function New-PSSession {
    [CmdletBinding()]
    param([string]$ComputerName, [object]$SessionOption)
    [pscustomobject]@{
        ComputerName = $ComputerName
        SessionOption = $SessionOption
        FixtureTargetRoot = $script:fixtureTargetRoot
    }
}

function Invoke-Command {
    [CmdletBinding()]
    param([object]$Session, [scriptblock]$ScriptBlock, [object[]]$ArgumentList = @())

    $previousProgramData = $env:ProgramData
    $previousFixtureRoot = $env:SAS_FIXTURE_INSTALL_ROOT
    $env:ProgramData = $script:fixtureProgramData
    $env:SAS_FIXTURE_INSTALL_ROOT = $script:fixtureTargetRoot
    try { & $ScriptBlock @ArgumentList }
    finally {
        $env:ProgramData = $previousProgramData
        if ($null -eq $previousFixtureRoot) {
            Remove-Item Env:SAS_FIXTURE_INSTALL_ROOT -ErrorAction SilentlyContinue
        } else {
            $env:SAS_FIXTURE_INSTALL_ROOT = $previousFixtureRoot
        }
    }
}

function Remove-PSSession {
    [CmdletBinding()]
    param([object]$Session)
}

Write-SasSoftwareInstallE2EEvent -Name 'operator_install_started' -Data @{
    operator_script = $operatorScript
    fixture_installer = $fixtureInstaller
    mapped_installer = $mappedInstaller
    target = 'fixture-target'
}

$installParameters = @{
    ComputerName = @('fixture-target')
    PackageName = $packageName
    InstallerRelativePath = 'Software\Fixture\fixture-installer.cmd'
    SoftwareShareRoot = '\\nt2kwb972sms01\'
    InstallerArguments = @()
    InstallMode = 'UncDirect'
    OutputRoot = $operatorOutputRoot
    AllowTargetMutation = $true
    Confirm = $false
}
$summary = & $operatorScript @installParameters

Write-SasSoftwareInstallE2EEvent -Name 'operator_install_completed' -Data @{
    run_id = $summary.run_id
    completed_count = $summary.completed_count
    failed_count = $summary.failed_count
    cleanup_failure_count = $summary.cleanup_failure_count
    repo_artifact_remaining_count = $summary.repo_artifact_remaining_count
    operator_event_path = $summary.event_path
}

$after = @(Get-SasSoftwareInstallSnapshot -Root $fixtureTargetRoot)
ConvertTo-Json -InputObject $after -Depth 8 |
    Set-Content -LiteralPath $afterPath -Encoding UTF8
Write-SasSoftwareInstallE2EEvent -Name 'after_snapshot_captured' -Data @{
    file_count = $after.Count
    snapshot_path = $afterPath
}

$delta = Get-SasSoftwareInstallDelta -Before $before -After $after
$delta | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $deltaPath -Encoding UTF8
Write-SasSoftwareInstallE2EEvent -Name 'delta_computed' -Data @{
    delta_path = $deltaPath
    added_count = $delta.added_count
    changed_count = $delta.changed_count
    removed_count = $delta.removed_count
}

$operatorRunRoot = Split-Path -Parent ([string]$summary.event_path)
$operatorSummaryPath = Join-Path $operatorRunRoot 'software_install_summary.json'
$operatorEvents = @(
    Get-Content -LiteralPath $summary.event_path |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_ | ConvertFrom-Json }
)
$operatorEventNames = @($operatorEvents | ForEach-Object { [string]$_.event })
$packageState = if ([IO.File]::Exists($packageMarker)) {
    Get-Content -LiteralPath $packageMarker -Raw | ConvertFrom-Json
} else { $null }
$repoOwnedStageRoot = Join-Path $fixtureProgramData (
    "SysAdminSuite\SoftwareInstall\{0}" -f $summary.run_id
)

$failures = [Collections.Generic.List[string]]::new()
if ($summary.completed_count -ne 1) {
    $failures.Add("expected one completed fixture installation; observed $($summary.completed_count)")
}
if ($summary.failed_count -ne 0) {
    $failures.Add("operator summary reported $($summary.failed_count) failed or unresolved targets")
}
if ($summary.cleanup_failure_count -ne 0 -or $summary.repo_artifact_remaining_count -ne 0) {
    $failures.Add('operator summary reported cleanup failure or repo-owned target remnants')
}
if (-not $packageState -or $packageState.package_name -ne $packageName -or $packageState.version -ne '1.0.0') {
    $failures.Add('fixture package manifest is missing or does not report the installed package/version')
}
if (-not [IO.File]::Exists($installerOwnedLog)) {
    $failures.Add('fixture installer-owned log was not created')
}
if ($delta.added_count -lt 2 -or $delta.changed_count -ne 0 -or $delta.removed_count -ne 0) {
    $failures.Add('before/after delta did not show the expected added package state and installer log')
}
foreach ($requiredEvent in @('run_started', 'target_started', 'target_completed', 'run_completed')) {
    if ($requiredEvent -notin $operatorEventNames) {
        $failures.Add("operator JSONL log is missing event '$requiredEvent'")
    }
}
if ([IO.Directory]::Exists($repoOwnedStageRoot)) {
    $failures.Add("repo-owned fixture staging remains: $repoOwnedStageRoot")
}
if (-not [IO.File]::Exists($operatorSummaryPath)) {
    $failures.Add('operator software_install_summary.json is missing')
}

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
$result = [ordered]@{
    schema_version = 'sas-software-install-e2e/v1'
    status = $status
    proof_class = 'fixture-software-install-e2e'
    fixture_transport_adapter = $true
    real_operator_wrapper_executed = $true
    real_installer_process_executed = ($null -ne $packageState)
    fixture_mutation_performed = $true
    live_target_e2e = $false
    external_network_activity_performed = $false
    target_mutation_performed = $false
    package = [ordered]@{
        name = $packageName
        expected_version = '1.0.0'
        observed_version = $(if ($packageState) { $packageState.version } else { $null })
        manifest_path = $packageMarker
        installer_owned_log_path = $installerOwnedLog
    }
    delta = [ordered]@{
        added_count = $delta.added_count
        changed_count = $delta.changed_count
        removed_count = $delta.removed_count
    }
    operator = [ordered]@{
        run_id = $summary.run_id
        completed_count = $summary.completed_count
        failed_count = $summary.failed_count
        cleanup_failure_count = $summary.cleanup_failure_count
        repo_artifact_remaining_count = $summary.repo_artifact_remaining_count
        summary_path = $operatorSummaryPath
        event_path = $summary.event_path
    }
    artifacts = [ordered]@{
        before_snapshot = $beforePath
        after_snapshot = $afterPath
        delta = $deltaPath
        events = $eventPath
        result = $resultPath
        matrix = $matrixPath
    }
    failures = @($failures)
}
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8

$matrix = @(
    'SYSADMINSUITE SOFTWARE INSTALL E2E',
    "Status: $status",
    'Proof class: fixture-software-install-e2e',
    "Package: $packageName",
    "Observed version: $($result.package.observed_version)",
    "Delta: $($delta.added_count) added / $($delta.changed_count) changed / $($delta.removed_count) removed",
    "Operator run: $($summary.run_id)",
    "Operator events: $($summary.event_path)",
    "Result: $resultPath",
    'Live target proof: false'
)
if ($failures.Count -gt 0) {
    $matrix += ''
    $matrix += 'Failures:'
    $matrix += @($failures | ForEach-Object { "- $_" })
}
$matrix | Set-Content -LiteralPath $matrixPath -Encoding UTF8

Write-SasSoftwareInstallE2EEvent -Name 'validation_completed' -Data @{
    status = $status
    result_path = $resultPath
    failure_count = $failures.Count
}

$matrix | ForEach-Object { Write-Host $_ }
if ($failures.Count -gt 0) { exit 1 }
