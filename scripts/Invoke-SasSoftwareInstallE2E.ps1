#Requires -Version 5.1
<#
.SYNOPSIS
Runs the approved software-install workflow end to end against an isolated local fixture target.

.DESCRIPTION
This journey builds a real Windows executable, executes the real Invoke-SasSoftwareInstall.ps1
operator wrapper, traverses the wrapper's real remote-install script block, and launches the generated
executable as a child process. A process-local fixture transport adapter replaces only WinRM and the
approved UNC share. No live target or external network is contacted.

The generated executable installs a dummy file, package manifest, and installer-owned JSONL log.
The journey captures before/after snapshots, an added/changed/removed delta, operator logs and summary,
the executable hash/build manifest, and a final machine-readable E2E result.
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
$generatedInstallerRoot = Join-Path $OutputRoot 'generated-installer'
$fixtureSource = Join-Path $repoRoot 'Tests/fixtures/software-install/DummyInstaller.cs'
$fixtureBuildScript = Join-Path $repoRoot 'scripts/Build-SasSoftwareInstallFixtureExecutable.ps1'
$fixtureInstaller = Join-Path $generatedInstallerRoot 'sysadminsuite-dummy-installer.exe'
$operatorScript = Join-Path $repoRoot 'scripts/Invoke-SasSoftwareInstall.ps1'
$mappedInstaller = '\\nt2kwb972sms01\Software\Fixture\sysadminsuite-dummy-installer.exe'
$packageName = 'SysAdminSuite Fixture Package'
$packageVersion = '1.0.0'
$dummyRelativePath = 'InstalledPackages\SysAdminSuiteFixturePackage\dummy-installed.txt'
$packageMarker = Join-Path $fixtureTargetRoot 'InstalledPackages/SysAdminSuiteFixturePackage/manifest.json'
$dummyFile = Join-Path $fixtureTargetRoot $dummyRelativePath
$installerOwnedLog = Join-Path $fixtureTargetRoot 'InstallerLogs/sysadminsuite-fixture-package.jsonl'

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
        proof_class = 'fixture-software-install-executable-e2e'
        live_target = $false
        external_network_activity = $false
        target_mutation = $false
        data = $Data
    } | ConvertTo-Json -Depth 10 -Compress |
        Add-Content -LiteralPath $eventPath -Encoding UTF8
}

function Get-SasSoftwareInstallSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    if (-not [IO.Directory]::Exists($Root)) {
        return @()
    }

    $rootPrefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    return @(
        Get-ChildItem -LiteralPath $Root -Recurse -Force -File |
            ForEach-Object {
                $relativePath = $_.FullName.Substring($rootPrefix.Length).Replace('\', '/')
                $included = (
                    $relativePath.StartsWith('InstalledPackages/', [StringComparison]::OrdinalIgnoreCase) -or
                    $relativePath.StartsWith('InstallerLogs/', [StringComparison]::OrdinalIgnoreCase) -or
                    $relativePath.StartsWith('ProgramData/SysAdminSuite/', [StringComparison]::OrdinalIgnoreCase)
                )
                if (-not $included) {
                    return
                }

                [ordered]@{
                    relative_path = $relativePath
                    bytes = $_.Length
                    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            } |
            Sort-Object relative_path
    )
}

function Get-SasSoftwareInstallDelta {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Before,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$After
    )

    $beforeByPath = @{}
    foreach ($entry in $Before) {
        $beforeByPath[[string]$entry.relative_path] = $entry
    }
    $afterByPath = @{}
    foreach ($entry in $After) {
        $afterByPath[[string]$entry.relative_path] = $entry
    }

    $added = @(
        $After |
            Where-Object { -not $beforeByPath.ContainsKey([string]$_.relative_path) } |
            Sort-Object relative_path
    )
    $removed = @(
        $Before |
            Where-Object { -not $afterByPath.ContainsKey([string]$_.relative_path) } |
            Sort-Object relative_path
    )
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

    [ordered]@{
        schema_version = 'sas-software-install-delta/v1'
        added_count = $added.Count
        changed_count = $changed.Count
        removed_count = $removed.Count
        added = @($added)
        changed = @($changed)
        removed = @($removed)
    }
}

foreach ($requiredPath in @($fixtureSource, $fixtureBuildScript, $operatorScript)) {
    if (-not [IO.File]::Exists($requiredPath)) {
        throw "Required software-install E2E file is missing: $requiredPath"
    }
}
foreach ($cleanRoot in @($fixtureTargetRoot, $generatedInstallerRoot, $operatorOutputRoot)) {
    if ([IO.Directory]::Exists($cleanRoot)) {
        [IO.Directory]::Delete($cleanRoot, $true)
    }
}
New-Item -ItemType Directory -Path $fixtureProgramData -Force | Out-Null
New-Item -ItemType Directory -Path $operatorOutputRoot -Force | Out-Null
New-Item -ItemType Directory -Path $generatedInstallerRoot -Force | Out-Null

$build = & $fixtureBuildScript -SourcePath $fixtureSource -OutputPath $fixtureInstaller
if (-not [IO.File]::Exists($fixtureInstaller)) {
    throw "Generated fixture installer is missing: $fixtureInstaller"
}
$fixtureInstallerHash = (Get-FileHash -LiteralPath $fixtureInstaller -Algorithm SHA256).Hash.ToLowerInvariant()
if ($build.executable_sha256 -ne $fixtureInstallerHash) {
    throw 'Generated installer hash does not match the build manifest result.'
}
Write-SasSoftwareInstallE2EEvent -Name 'fixture_executable_built' -Data @{
    executable_path = $fixtureInstaller
    executable_sha256 = $fixtureInstallerHash
    executable_bytes = $build.executable_bytes
    build_manifest_path = $build.build_manifest_path
    compiler = $build.compiler
}

$global:SasSoftwareInstallE2EMappedInstaller = $mappedInstaller
$global:SasSoftwareInstallE2EFixtureInstaller = $fixtureInstaller
$global:SasSoftwareInstallE2EFixtureTargetRoot = $fixtureTargetRoot
$global:SasSoftwareInstallE2EFixtureProgramData = $fixtureProgramData

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
        [Parameter(Mandatory = $false)]
        [Microsoft.PowerShell.Commands.TestPathType]$PathType = [Microsoft.PowerShell.Commands.TestPathType]::Any,
        [Parameter(Mandatory = $false)]
        [switch]$IsValid
    )

    process {
        $values = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { $LiteralPath } else { $Path }
        foreach ($value in $values) {
            $normalized = ([string]$value).Replace('/', '\')
            if ($normalized.Equals(
                $global:SasSoftwareInstallE2EMappedInstaller,
                [StringComparison]::OrdinalIgnoreCase
            )) {
                [IO.File]::Exists($global:SasSoftwareInstallE2EFixtureInstaller)
                continue
            }

            $delegate = @{}
            if ($IsValid) {
                $delegate['IsValid'] = $true
            }
            else {
                $delegate['PathType'] = $PathType
            }
            if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') {
                $delegate['LiteralPath'] = $value
            }
            else {
                $delegate['Path'] = $value
            }
            Microsoft.PowerShell.Management\Test-Path @delegate
        }
    }
}

function Start-Process {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$FilePath,
        [Parameter(Mandatory = $false)]
        [object[]]$ArgumentList = @(),
        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    $resolvedFilePath = if ($FilePath.Replace('/', '\').Equals(
        $global:SasSoftwareInstallE2EMappedInstaller,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        $global:SasSoftwareInstallE2EFixtureInstaller
    }
    else {
        $FilePath
    }

    $delegate = @{ FilePath = $resolvedFilePath }
    if ($ArgumentList.Count -gt 0) {
        $delegate['ArgumentList'] = $ArgumentList
    }
    if ($PassThru) {
        $delegate['PassThru'] = $true
    }
    Microsoft.PowerShell.Management\Start-Process @delegate
}

function New-PSSessionOption {
    [CmdletBinding()]
    param(
        [int]$OpenTimeout,
        [int]$OperationTimeout
    )
    [pscustomobject]@{
        OpenTimeout = $OpenTimeout
        OperationTimeout = $OperationTimeout
        FixtureTransport = $true
    }
}

function New-PSSession {
    [CmdletBinding()]
    param(
        [string]$ComputerName,
        [object]$SessionOption
    )
    [pscustomobject]@{
        ComputerName = $ComputerName
        SessionOption = $SessionOption
        FixtureTargetRoot = $global:SasSoftwareInstallE2EFixtureTargetRoot
    }
}

function Invoke-Command {
    [CmdletBinding()]
    param(
        [object]$Session,
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @()
    )

    $previousProgramData = $env:ProgramData
    $env:ProgramData = $global:SasSoftwareInstallE2EFixtureProgramData
    try {
        & $ScriptBlock @ArgumentList
    }
    finally {
        $env:ProgramData = $previousProgramData
    }
}

function Remove-PSSession {
    [CmdletBinding()]
    param([object]$Session)
}

$installerArguments = @(
    ('--target-root="{0}"' -f $fixtureTargetRoot),
    ('--package-name="{0}"' -f $packageName),
    ('--version="{0}"' -f $packageVersion),
    ('--dummy-relative-path="{0}"' -f $dummyRelativePath),
    ('--log-path="{0}"' -f $installerOwnedLog)
)
Write-SasSoftwareInstallE2EEvent -Name 'operator_install_started' -Data @{
    operator_script = $operatorScript
    generated_installer_executable = $fixtureInstaller
    generated_installer_sha256 = $fixtureInstallerHash
    mapped_installer = $mappedInstaller
    target = 'fixture-target'
}

$installParameters = @{
    ComputerName = @('fixture-target')
    PackageName = $packageName
    InstallerRelativePath = 'Software\Fixture\sysadminsuite-dummy-installer.exe'
    SoftwareShareRoot = '\\nt2kwb972sms01\'
    InstallerArguments = $installerArguments
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
$delta | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $deltaPath -Encoding UTF8
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
$installerEvents = if ([IO.File]::Exists($installerOwnedLog)) {
    @(
        Get-Content -LiteralPath $installerOwnedLog |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_ | ConvertFrom-Json }
    )
}
else {
    @()
}
$installerEventNames = @($installerEvents | ForEach-Object { [string]$_.event })
$packageState = if ([IO.File]::Exists($packageMarker)) {
    Get-Content -LiteralPath $packageMarker -Raw | ConvertFrom-Json
}
else {
    $null
}
$repoOwnedStageRoot = Join-Path $fixtureProgramData ("SysAdminSuite\SoftwareInstall\{0}" -f $summary.run_id)

$expectedAddedPaths = @(
    'InstalledPackages/SysAdminSuiteFixturePackage/dummy-installed.txt',
    'InstalledPackages/SysAdminSuiteFixturePackage/manifest.json',
    'InstallerLogs/sysadminsuite-fixture-package.jsonl'
)
$actualAddedPaths = @($delta.added | ForEach-Object { [string]$_.relative_path } | Sort-Object)
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
if (-not $packageState -or
    $packageState.package_name -ne $packageName -or
    $packageState.version -ne $packageVersion -or
    $packageState.installer -ne 'sysadminsuite-dummy-installer.exe') {
    $failures.Add('fixture package manifest is missing or does not report the executable package/version')
}
if (-not [IO.File]::Exists($dummyFile)) {
    $failures.Add('generated executable did not install the required dummy file')
}
if ('dummy_install_completed' -notin $installerEventNames) {
    $failures.Add('generated executable JSONL log is missing dummy_install_completed')
}
if ($delta.added_count -ne 3 -or $delta.changed_count -ne 0 -or $delta.removed_count -ne 0) {
    $failures.Add('before/after delta did not show exactly three added install artifacts')
}
if (@(Compare-Object -ReferenceObject $expectedAddedPaths -DifferenceObject $actualAddedPaths).Count -ne 0) {
    $failures.Add('added delta paths do not match the executable package manifest, dummy file, and installer log')
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
if (-not [IO.File]::Exists([string]$build.build_manifest_path)) {
    $failures.Add('generated executable build manifest is missing')
}

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
$result = [ordered]@{
    schema_version = 'sas-software-install-e2e/v2'
    status = $status
    proof_class = 'fixture-software-install-executable-e2e'
    fixture_transport_adapter = $true
    real_operator_wrapper_executed = $true
    real_installer_executable_executed = ($null -ne $packageState)
    fixture_mutation_performed = $true
    live_target_e2e = $false
    external_network_activity_performed = $false
    target_mutation_performed = $false
    executable = [ordered]@{
        path = $fixtureInstaller
        sha256 = $fixtureInstallerHash
        bytes = $build.executable_bytes
        build_manifest_path = $build.build_manifest_path
        compiler = $build.compiler
        committed_binary = $false
    }
    package = [ordered]@{
        name = $packageName
        expected_version = $packageVersion
        observed_version = $(if ($packageState) { $packageState.version } else { $null })
        manifest_path = $packageMarker
        dummy_file_path = $dummyFile
        installer_owned_log_path = $installerOwnedLog
    }
    delta = [ordered]@{
        added_count = $delta.added_count
        changed_count = $delta.changed_count
        removed_count = $delta.removed_count
        added_paths = $actualAddedPaths
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
        generated_executable = $fixtureInstaller
        build_manifest = $build.build_manifest_path
    }
    failures = @($failures)
}
$result | ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath $resultPath -Encoding UTF8

$matrix = @(
    'SYSADMINSUITE SOFTWARE INSTALL EXECUTABLE E2E',
    "Status: $status",
    'Proof class: fixture-software-install-executable-e2e',
    "Generated executable: $fixtureInstaller",
    "Executable SHA-256: $fixtureInstallerHash",
    "Package: $packageName",
    "Observed version: $($result.package.observed_version)",
    "Dummy file: $dummyFile",
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
    generated_installer_sha256 = $fixtureInstallerHash
    dummy_file_path = $dummyFile
}

$matrix | ForEach-Object { Write-Host $_ }
if ($failures.Count -gt 0) {
    exit 1
}
