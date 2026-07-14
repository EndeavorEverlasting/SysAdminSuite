#Requires -Version 5.1
<#
.SYNOPSIS
Runs the validated install, package verification, teardown, and preservation chain against an isolated fixture target.
#>

[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$OutputRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not [IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot = Join-Path $repoRoot $OutputRoot }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$approvedE2ERoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'survey/output/e2e-validation')).TrimEnd('\')
if ($OutputRoot.Equals($approvedE2ERoot, [StringComparison]::OrdinalIgnoreCase) -or
    -not $OutputRoot.StartsWith($approvedE2ERoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Validated deployment E2E output must be a journey-owned child directory under survey/output/e2e-validation.'
}

$targetRoot = Join-Path $OutputRoot 'fixture-target'
$programData = Join-Path $targetRoot 'ProgramData'
$generatedRoot = Join-Path $OutputRoot 'generated-installer'
$operatorRoot = Join-Path $OutputRoot 'operator'
$requestPath = Join-Path $OutputRoot 'validated-deployment-request.json'
$resultPath = Join-Path $OutputRoot 'validated-deployment-e2e-result.json'
$matrixPath = Join-Path $OutputRoot 'validated-deployment-e2e-matrix.txt'
$sourcePath = Join-Path $repoRoot 'Tests/fixtures/software-install/DummyInstaller.cs'
$buildScript = Join-Path $repoRoot 'scripts/Build-SasSoftwareInstallFixtureExecutable.ps1'
$orchestrator = Join-Path $repoRoot 'scripts/Invoke-SasValidatedSoftwareDeployment.ps1'
$installer = Join-Path $generatedRoot 'sysadminsuite-dummy-installer.exe'
$mappedInstaller = '\\nt2kwb972sms01\Software\Fixture\sysadminsuite-dummy-installer.exe'
$packageName = 'SysAdminSuite Fixture Package'
$packageVersion = '1.0.0'
$dummyRelative = 'InstalledPackages\SysAdminSuiteFixturePackage\dummy-installed.txt'
$dummyFile = Join-Path $targetRoot $dummyRelative
$manifestFile = Join-Path $targetRoot 'InstalledPackages/SysAdminSuiteFixturePackage/manifest.json'
$installerLog = Join-Path $targetRoot 'InstallerLogs/sysadminsuite-fixture-package.jsonl'

foreach ($path in @($sourcePath, $buildScript, $orchestrator)) {
    if (-not [IO.File]::Exists($path)) { throw "Missing fixture dependency: $path" }
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
foreach ($ownedPath in @($targetRoot, $generatedRoot, $operatorRoot, $requestPath, $resultPath, $matrixPath)) {
    if ([IO.Directory]::Exists($ownedPath)) { [IO.Directory]::Delete($ownedPath, $true) }
    elseif ([IO.File]::Exists($ownedPath)) { [IO.File]::Delete($ownedPath) }
}
New-Item -ItemType Directory -Path $programData, $generatedRoot, $operatorRoot -Force | Out-Null
$build = & $buildScript -SourcePath $sourcePath -OutputPath $installer
$installerHash = (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()

$request = [ordered]@{
    schema_version = 'sas-validated-software-deployment-request/v1'
    request_id = 'fixture-validated-finalization'
    package_name = $packageName
    software_share_root = '\\nt2kwb972sms01\'
    installer_relative_path = 'Software\Fixture\sysadminsuite-dummy-installer.exe'
    installer_sha256 = $installerHash
    installer_arguments = @(
        ('--target-root="{0}"' -f $targetRoot),
        ('--package-name="{0}"' -f $packageName),
        ('--version="{0}"' -f $packageVersion),
        ('--dummy-relative-path="{0}"' -f $dummyRelative),
        ('--log-path="{0}"' -f $installerLog)
    )
    installer_arguments_reference = 'synthetic executable fixture contract'
    install_mode = 'CopyThenInstall'
    targets = @('fixture-target')
    authorization = [ordered]@{
        authorized_by = 'synthetic-ci'
        request_reference = 'REQ-FIXTURE-001'
        change_reference = 'CHG-FIXTURE-001'
        ticket_reference = 'TASK-FIXTURE-001'
    }
    validation = [ordered]@{
        checks = @(
            [ordered]@{ id = 'dummy-file'; type = 'FileExists'; required = $true; path = $dummyFile },
            [ordered]@{ id = 'manifest-package'; type = 'JsonPropertyEquals'; required = $true; path = $manifestFile; property_path = 'package_name'; expected_value = $packageName },
            [ordered]@{ id = 'manifest-version'; type = 'JsonPropertyEquals'; required = $true; path = $manifestFile; property_path = 'version'; expected_value = $packageVersion },
            [ordered]@{ id = 'installer-owned-log'; type = 'FileExists'; required = $true; path = $installerLog }
        )
    }
    cleanup_policy = 'repo_owned_run_scoped_only'
    require_valid_signature = $false
}
$request | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $requestPath -Encoding UTF8

$global:SasValidatedE2EMappedInstaller = $mappedInstaller
$global:SasValidatedE2EFixtureInstaller = $installer
$global:SasValidatedE2EProgramData = $programData
$global:SasValidatedE2ELastStageRoot = $null
$global:SasValidatedE2EInjectedTransient = $null
$global:SasValidatedE2ESessionCloseCount = 0
$global:SasValidatedE2EStagedCopyVerified = $false

function Test-Path {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ParameterSetName = 'Path')][string[]]$Path,
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'LiteralPath')][Alias('PSPath')][string[]]$LiteralPath,
        [Microsoft.PowerShell.Commands.TestPathType]$PathType = [Microsoft.PowerShell.Commands.TestPathType]::Any,
        [switch]$IsValid
    )
    process {
        $values = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { $LiteralPath } else { $Path }
        foreach ($value in $values) {
            if (([string]$value).Replace('/', '\').Equals($global:SasValidatedE2EMappedInstaller, [StringComparison]::OrdinalIgnoreCase)) {
                [IO.File]::Exists($global:SasValidatedE2EFixtureInstaller)
                continue
            }
            $delegate = @{}
            if ($IsValid) { $delegate.IsValid = $true } else { $delegate.PathType = $PathType }
            if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { $delegate.LiteralPath = $value } else { $delegate.Path = $value }
            Microsoft.PowerShell.Management\Test-Path @delegate
        }
    }
}

function Get-FileHash {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')][string[]]$Path,
        [Parameter(Mandatory = $true, ParameterSetName = 'LiteralPath')][string[]]$LiteralPath,
        [string]$Algorithm = 'SHA256'
    )
    $values = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { $LiteralPath } else { $Path }
    foreach ($value in $values) {
        $actual = if (([string]$value).Replace('/', '\').Equals($global:SasValidatedE2EMappedInstaller, [StringComparison]::OrdinalIgnoreCase)) { $global:SasValidatedE2EFixtureInstaller } else { $value }
        Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $actual -Algorithm $Algorithm
    }
}

function Copy-Item {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$Destination,
        [object]$ToSession,
        [switch]$Force
    )
    $source = if ($LiteralPath.Replace('/', '\').Equals($global:SasValidatedE2EMappedInstaller, [StringComparison]::OrdinalIgnoreCase)) { $global:SasValidatedE2EFixtureInstaller } else { $LiteralPath }
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Microsoft.PowerShell.Management\Copy-Item -LiteralPath $source -Destination $Destination -Force
    $global:SasValidatedE2ELastStageRoot = $parent
}

function Start-Process {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$FilePath, [object[]]$ArgumentList = @(), [switch]$PassThru)
    $executionPath = $FilePath
    if ($global:SasValidatedE2ELastStageRoot -and
        [IO.Path]::GetFullPath($FilePath).StartsWith([IO.Path]::GetFullPath($global:SasValidatedE2ELastStageRoot) + '\', [StringComparison]::OrdinalIgnoreCase)) {
        if (-not (Microsoft.PowerShell.Management\Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "Staged fixture installer is missing: $FilePath" }
        $stagedHash = (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $sourceHash = (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $global:SasValidatedE2EFixtureInstaller -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($stagedHash -ne $sourceHash) { throw 'Staged fixture installer hash does not match the generated source executable.' }
        $global:SasValidatedE2EStagedCopyVerified = $true
        # Hosted Windows runners may refuse process creation from the simulated ProgramData tree.
        # The fixture adapter executes the identical hash-verified source binary after proving the staged copy.
        $executionPath = $global:SasValidatedE2EFixtureInstaller
    }
    $delegate = @{ FilePath = $executionPath }
    if ($ArgumentList.Count -gt 0) { $delegate.ArgumentList = $ArgumentList }
    if ($PassThru) { $delegate.PassThru = $true }
    Microsoft.PowerShell.Management\Start-Process @delegate
}

function New-PSSessionOption {
    [CmdletBinding()]
    param([int]$OpenTimeout, [int]$OperationTimeout)
    [pscustomobject]@{ OpenTimeout = $OpenTimeout; OperationTimeout = $OperationTimeout; FixtureTransport = $true }
}
function New-PSSession {
    [CmdletBinding()]
    param([string]$ComputerName, [object]$SessionOption)
    [pscustomobject]@{ ComputerName = $ComputerName; SessionOption = $SessionOption; FixtureTransport = $true }
}
function Invoke-Command {
    [CmdletBinding()]
    param([object]$Session, [scriptblock]$ScriptBlock, [object[]]$ArgumentList = @())
    $previous = $env:ProgramData
    $env:ProgramData = $global:SasValidatedE2EProgramData
    try { & $ScriptBlock @ArgumentList } finally { $env:ProgramData = $previous }
}
function Remove-PSSession {
    [CmdletBinding()]
    param([object]$Session)
    $global:SasValidatedE2ESessionCloseCount++
    if ($global:SasValidatedE2ESessionCloseCount -eq 1 -and $global:SasValidatedE2ELastStageRoot) {
        New-Item -ItemType Directory -Path $global:SasValidatedE2ELastStageRoot -Force | Out-Null
        $global:SasValidatedE2EInjectedTransient = Join-Path $global:SasValidatedE2ELastStageRoot 'post-install-transient.ps1'
        Set-Content -LiteralPath $global:SasValidatedE2EInjectedTransient -Value '# synthetic run-owned transient' -Encoding UTF8
    }
}

$deployment = & $orchestrator -RequestPath $requestPath -OutputRoot $operatorRoot -AllowTargetMutation -AllowFixtures -Confirm:$false
$runRoot = Split-Path -Parent ([string]$deployment.install_summary_path)
$finalizationPath = Join-Path $runRoot 'software_install_finalization.json'
$summary = Get-Content -LiteralPath $deployment.install_summary_path -Raw | ConvertFrom-Json
$finalization = Get-Content -LiteralPath $finalizationPath -Raw | ConvertFrom-Json
$stageRoot = Join-Path $programData ("SysAdminSuite\SoftwareInstall\{0}" -f $deployment.run_id)
$failures = @()
if (-not $deployment.deployment_complete -or $deployment.classification -ne 'DEPLOYMENT_COMPLETE_VALIDATED_AND_FINALIZED') { $failures += 'orchestrator did not report validated deployment completion' }
if (-not $deployment.installer_hash_verified) { $failures += 'installer SHA-256 was not verified' }
if ($summary.deployment_complete -ne $true -or $summary.completed_validated_finalized_count -ne 1) { $failures += 'install summary did not persist finalization completion' }
if ($finalization.completed_validated_finalized_count -ne 1 -or $finalization.teardown_failure_count -ne 0) { $failures += 'finalization artifact did not report one clean target' }
if (-not $global:SasValidatedE2EStagedCopyVerified) { $failures += 'fixture did not verify the CopyThenInstall staged executable hash' }
if (-not $global:SasValidatedE2EInjectedTransient) { $failures += 'fixture did not inject a post-install run-owned transient' }
if (Test-Path -LiteralPath $stageRoot) { $failures += "run-scoped SysAdminSuite staging remains: $stageRoot" }
if (Test-Path -LiteralPath $global:SasValidatedE2EInjectedTransient) { $failures += 'post-install transient survived finalization' }
foreach ($requiredPackageFile in @($dummyFile, $manifestFile, $installerLog)) {
    if (-not (Test-Path -LiteralPath $requiredPackageFile -PathType Leaf)) { $failures += "requested software evidence was removed: $requiredPackageFile" }
}
if ($finalization.results[0].requested_software_preserved_after_teardown -ne $true) { $failures += 'post-teardown package validation did not pass' }

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
$result = [ordered]@{
    schema_version = 'sas-validated-software-deployment-e2e/v1'
    status = $status
    proof_class = 'fixture-install-validate-finalize-preserve-e2e'
    fixture_transport_adapter = $true
    fixture_staged_execution_adapter = $true
    staged_copy_sha256_verified = [bool]$global:SasValidatedE2EStagedCopyVerified
    real_installer_executable_executed = $true
    real_production_installer_wrapper_executed = $true
    real_validated_deployment_orchestrator_executed = $true
    real_finalization_gate_executed = $true
    live_target_e2e = $false
    external_network_activity_performed = $false
    requested_software_preserved = ($failures.Count -eq 0)
    repo_owned_target_remnants = $(if (Test-Path -LiteralPath $stageRoot) { 1 } else { 0 })
    installer_sha256 = $installerHash
    install_summary_path = [string]$deployment.install_summary_path
    finalization_path = $finalizationPath
    request_path = $requestPath
    failures = @($failures)
}
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
$matrix = @(
    'SYSADMINSUITE VALIDATED SOFTWARE DEPLOYMENT E2E',
    "Status: $status",
    "Classification: $($deployment.classification)",
    "Installer SHA-256 verified: $($deployment.installer_hash_verified)",
    "Staged copy SHA-256 verified: $($result.staged_copy_sha256_verified)",
    "Requested software preserved: $($result.requested_software_preserved)",
    "Repo-owned target remnants: $($result.repo_owned_target_remnants)",
    "Finalization: $finalizationPath",
    'Live target proof: false'
)
if ($failures.Count -gt 0) {
    $matrix += ''
    $matrix += 'Failures:'
    $matrix += @($failures | ForEach-Object { "- $_" })
}
$matrix | Set-Content -LiteralPath $matrixPath -Encoding UTF8
$matrix | ForEach-Object { Write-Host $_ }
if ($failures.Count -gt 0) { exit 1 }
