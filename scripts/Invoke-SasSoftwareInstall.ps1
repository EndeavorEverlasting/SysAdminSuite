#Requires -Version 5.1
<#
.SYNOPSIS
Installs approved software on authorized target computers from an approved read-only software share.

.DESCRIPTION
Invoke-SasSoftwareInstall is the SysAdminSuite operator-execute wrapper for admin-box software installs.
It prefers direct UNC execution so SysAdminSuite does not stage payloads on the target. When staging is explicitly
requested, it copies the installer to ProgramData\SysAdminSuite\SoftwareInstall\<run_id> and removes that staging
folder in cleanup. Empty SysAdminSuite parent folders are pruned when no sibling run artifacts remain.

This script does not suppress Windows logs, clear evidence, collect credentials, create persistence, or bypass
monitoring. It writes SysAdminSuite run evidence only on the admin box and cleans SysAdminSuite-owned target staging.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$ComputerName = @(),

    [Parameter(Mandatory = $false)]
    [string]$TargetsCsv,

    [Parameter(Mandatory = $false)]
    [string]$PackageName,

    [Parameter(Mandatory = $true)]
    [string]$InstallerRelativePath,

    [Parameter(Mandatory = $false)]
    [string]$SoftwareShareRoot,

    [Parameter(Mandatory = $false)]
    [string[]]$InstallerArguments = @('/quiet', '/norestart'),

    [Parameter(Mandatory = $false)]
    [ValidateSet('UncDirect', 'CopyThenInstall')]
    [string]$InstallMode = 'UncDirect',

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 25)]
    [int]$MaxTargets = 25,

    [Parameter(Mandatory = $false)]
    [switch]$AllowTargetMutation,

    [Parameter(Mandatory = $false)]
    [switch]$AllowFixtures
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Normalize-SasUncRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $normalized = $Path.Trim().Replace('/', '\')
    if ($normalized -notmatch '^\\\\[^\\]+\\?$') {
        throw "SoftwareShareRoot must be a UNC path. Received: $Path"
    }

    $trimmed = $normalized.TrimEnd('\')
    return "$trimmed\"
}

function Get-SasApprovedSoftwareShareRoots {
    [CmdletBinding()]
    param()

    $manifestPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'harness/api/sas-harness-api.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Harness API manifest not found: $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $roots = @($manifest.posture.approved_software_sources | ForEach-Object {
        Normalize-SasUncRoot -Path ([string]$_)
    } | Sort-Object -Unique)
    if ($roots.Count -eq 0) {
        throw 'Harness API manifest does not declare any approved software source roots.'
    }

    return $roots
}

function Resolve-SasApprovedInstallerPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string[]]$ApprovedRoots
    )

    $normalizedRoot = Normalize-SasUncRoot -Path $Root
    $rootApproved = @($ApprovedRoots | Where-Object {
        $normalizedRoot.Equals((Normalize-SasUncRoot -Path $_), [System.StringComparison]::OrdinalIgnoreCase)
    }).Count -gt 0
    if (-not $rootApproved) {
        throw "SoftwareShareRoot is not an approved software source: $normalizedRoot"
    }

    $normalizedRelativePath = $RelativePath.Trim().Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($normalizedRelativePath) -or
        [System.IO.Path]::IsPathRooted($normalizedRelativePath) -or
        $normalizedRelativePath.StartsWith('\')) {
        throw 'InstallerRelativePath must be relative to the approved software share root.'
    }

    if ($normalizedRelativePath -match '(^|\\)\.\.(\\|$)') {
        throw 'InstallerRelativePath cannot contain parent-directory traversal.'
    }

    $candidate = "$normalizedRoot$normalizedRelativePath"

    if (-not $candidate.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Resolved installer path escaped the approved software share root.'
    }

    return $candidate
}

function Get-SasInstallTargets {
    [CmdletBinding()]
    param(
        [string[]]$DirectTargets,
        [string]$CsvPath,
        [int]$Limit
    )

    $targets = New-Object System.Collections.Generic.List[string]

    foreach ($target in $DirectTargets) {
        if (-not [string]::IsNullOrWhiteSpace($target)) {
            $targets.Add($target.Trim())
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($CsvPath)) {
        if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
            throw "TargetsCsv not found: $CsvPath"
        }

        $rows = Import-Csv -LiteralPath $CsvPath
        foreach ($row in $rows) {
            $value = $null
            foreach ($column in @('ComputerName', 'Hostname', 'Target')) {
                if ($row.PSObject.Properties.Name -contains $column) {
                    $candidate = [string]$row.$column
                    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                        $value = $candidate.Trim()
                        break
                    }
                }
            }
            if ($value) {
                $targets.Add($value)
            }
        }
    }

    $deduped = @($targets | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($deduped.Count -eq 0) {
        throw 'No targets were supplied. Use -ComputerName or -TargetsCsv with ComputerName, Hostname, or Target column.'
    }

    if ($deduped.Count -gt $Limit) {
        throw "Target count $($deduped.Count) exceeds MaxTargets $Limit. Split the run to keep noise bounded."
    }

    return @($deduped)
}

function Write-SasInstallEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EventPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Event
    )

    $Event['timestamp_utc'] = (Get-Date).ToUniversalTime().ToString('o')
    $Event | ConvertTo-Json -Depth 10 -Compress | Add-Content -LiteralPath $EventPath -Encoding UTF8 -WhatIf:$false
}

if (-not $AllowTargetMutation -and -not $WhatIfPreference) {
    throw 'Refusing target mutation without -AllowTargetMutation. Use -WhatIf for dry-run planning.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetIntakeModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasTargetIntake.psm1'
Import-Module -Name $targetIntakeModule -Force
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path -Path $repoRoot -ChildPath 'survey/output/software_install'
}
Assert-SasApprovedOutputPath -Path $OutputRoot -RepoRoot $repoRoot -Role 'software install output directory'

$runId = 'software-install-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runRoot = Join-Path -Path $OutputRoot -ChildPath $runId
New-Item -ItemType Directory -Path $runRoot -Force -WhatIf:$false | Out-Null

$eventPath = Join-Path -Path $runRoot -ChildPath 'software_install_events.jsonl'
$summaryPath = Join-Path -Path $runRoot -ChildPath 'software_install_summary.json'
$handoffPath = Join-Path -Path $runRoot -ChildPath 'operator_handoff.txt'
$approvedSoftwareShareRoots = @(Get-SasApprovedSoftwareShareRoots)
if ($AllowFixtures -and -not $WhatIfPreference) {
    throw '-AllowFixtures is restricted to non-mutating -WhatIf planning.'
}
if ($AllowFixtures -and $WhatIfPreference) {
    $approvedSoftwareShareRoots += Normalize-SasUncRoot -Path '\\fixture.invalid\'
}
if ([string]::IsNullOrWhiteSpace($SoftwareShareRoot)) {
    $SoftwareShareRoot = $approvedSoftwareShareRoots[0]
}
$installerPath = Resolve-SasApprovedInstallerPath -Root $SoftwareShareRoot -RelativePath $InstallerRelativePath -ApprovedRoots $approvedSoftwareShareRoots
if ([string]::IsNullOrWhiteSpace($PackageName)) {
    $PackageName = Split-Path -Path $installerPath -Leaf
}

if (-not $WhatIfPreference -and -not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw "Installer was not found under the approved software source: $installerPath"
}

$targets = @(Get-SasInstallTargets -DirectTargets $ComputerName -CsvPath $TargetsCsv -Limit $MaxTargets)

Write-SasInstallEvent -EventPath $eventPath -Event @{
    event = 'run_started'
    run_id = $runId
    package_name = $PackageName
    installer_path = $installerPath
    install_mode = $InstallMode
    target_count = $targets.Count
    output_root = $runRoot
    posture = 'authorized_operator_execute_no_log_suppression_no_credential_collection_cleanup_repo_owned_target_staging_only'
}

$remoteRepoCleanup = {
    param([string]$RunId)

    $ErrorActionPreference = 'Stop'
    $stageRoot = Join-Path -Path $env:ProgramData -ChildPath ("SysAdminSuite\SoftwareInstall\{0}" -f $RunId)
    $softwareInstallRoot = Join-Path -Path $env:ProgramData -ChildPath 'SysAdminSuite\SoftwareInstall'
    $suiteRoot = Join-Path -Path $env:ProgramData -ChildPath 'SysAdminSuite'
    $removedPaths = @()
    $prunedParentDirs = @()
    $errorMessage = $null

    $expectedBase = [System.IO.Path]::GetFullPath((Join-Path -Path $env:ProgramData -ChildPath 'SysAdminSuite\SoftwareInstall'))
    $expectedStageRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $expectedBase -ChildPath $RunId))
    if ($RunId -notmatch '^software-install-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$' -or
        -not $stageRoot.Equals($expectedStageRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing cleanup because the run-specific staging path failed validation.'
    }

    try {
        if (Test-Path -LiteralPath $stageRoot) {
            Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction Stop
            $removedPaths += $stageRoot
        }

        foreach ($parentPath in @($softwareInstallRoot, $suiteRoot)) {
            if (Test-Path -LiteralPath $parentPath) {
                $children = @(Get-ChildItem -LiteralPath $parentPath -Force -ErrorAction Stop)
                if ($children.Count -eq 0) {
                    Remove-Item -LiteralPath $parentPath -Force -ErrorAction Stop
                    $prunedParentDirs += $parentPath
                }
            }
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
    }

    $repoArtifactRemaining = Test-Path -LiteralPath $stageRoot

    return [pscustomobject]@{
        cleanup_attempted = $true
        cleanup_succeeded = (-not $repoArtifactRemaining -and [string]::IsNullOrWhiteSpace($errorMessage))
        repo_owned_stage_root = $stageRoot
        repo_artifact_remaining = $repoArtifactRemaining
        removed_paths = @($removedPaths)
        pruned_empty_parent_dirs = @($prunedParentDirs)
        error = $errorMessage
    }
}

$remoteInstall = {
    param(
        [string]$PackageName,
        [string]$InstallerSource,
        [string[]]$Arguments,
        [string]$InstallMode,
        [string]$RunId
    )

    $ErrorActionPreference = 'Stop'

    function Remove-SasRepoOwnedInstallArtifacts {
        param([string]$CleanupRunId)

        $stageRoot = Join-Path -Path $env:ProgramData -ChildPath ("SysAdminSuite\SoftwareInstall\{0}" -f $CleanupRunId)
        $softwareInstallRoot = Join-Path -Path $env:ProgramData -ChildPath 'SysAdminSuite\SoftwareInstall'
        $suiteRoot = Join-Path -Path $env:ProgramData -ChildPath 'SysAdminSuite'
        $removedPaths = @()
        $prunedParentDirs = @()
        $errorMessage = $null

        $expectedBase = [System.IO.Path]::GetFullPath((Join-Path -Path $env:ProgramData -ChildPath 'SysAdminSuite\SoftwareInstall'))
        $expectedStageRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $expectedBase -ChildPath $CleanupRunId))
        if ($CleanupRunId -notmatch '^software-install-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$' -or
            -not $stageRoot.Equals($expectedStageRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing cleanup because the run-specific staging path failed validation.'
        }

        try {
            if (Test-Path -LiteralPath $stageRoot) {
                Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction Stop
                $removedPaths += $stageRoot
            }

            foreach ($parentPath in @($softwareInstallRoot, $suiteRoot)) {
                if (Test-Path -LiteralPath $parentPath) {
                    $children = @(Get-ChildItem -LiteralPath $parentPath -Force -ErrorAction Stop)
                    if ($children.Count -eq 0) {
                        Remove-Item -LiteralPath $parentPath -Force -ErrorAction Stop
                        $prunedParentDirs += $parentPath
                    }
                }
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
        }

        $repoArtifactRemaining = Test-Path -LiteralPath $stageRoot
        return [pscustomobject]@{
            cleanup_attempted = $true
            cleanup_succeeded = (-not $repoArtifactRemaining -and [string]::IsNullOrWhiteSpace($errorMessage))
            repo_owned_stage_root = $stageRoot
            repo_artifact_remaining = $repoArtifactRemaining
            removed_paths = @($removedPaths)
            pruned_empty_parent_dirs = @($prunedParentDirs)
            error = $errorMessage
        }
    }

    $stageRoot = Join-Path -Path $env:ProgramData -ChildPath ("SysAdminSuite\SoftwareInstall\{0}" -f $RunId)
    $result = [ordered]@{
        package_name = $PackageName
        installer_source = $InstallerSource
        install_mode = $InstallMode
        exit_code = $null
        staged = ($InstallMode -eq 'CopyThenInstall')
        stage_root = $(if ($InstallMode -eq 'CopyThenInstall') { $stageRoot } else { $null })
        cleanup_attempted = $false
        cleanup_succeeded = $null
        repo_artifact_remaining = $null
        pruned_empty_parent_dirs = @()
        status = 'started'
        error = $null
    }

    try {
        if (-not (Test-Path -LiteralPath $InstallerSource -PathType Leaf)) {
            throw "Installer source not found on target context: $InstallerSource"
        }

        $installerTimeoutMilliseconds = 1800000
        $process = Start-Process -FilePath $InstallerSource -ArgumentList $Arguments -PassThru
        if (-not $process.WaitForExit($installerTimeoutMilliseconds)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw "Installer timed out after $($installerTimeoutMilliseconds / 1000) seconds."
        }
        $result.exit_code = $process.ExitCode
        if ($process.ExitCode -eq 0) {
            $result.status = 'completed'
        }
        else {
            $result.status = 'installer_exit_nonzero'
        }
    }
    catch {
        $result.status = 'failed'
        $result.error = $_.Exception.Message
    }
    finally {
        if ($InstallMode -eq 'CopyThenInstall') {
            $cleanup = Remove-SasRepoOwnedInstallArtifacts -CleanupRunId $RunId
            $result.cleanup_attempted = $cleanup.cleanup_attempted
            $result.cleanup_succeeded = $cleanup.cleanup_succeeded
            $result.repo_artifact_remaining = $cleanup.repo_artifact_remaining
            $result.pruned_empty_parent_dirs = $cleanup.pruned_empty_parent_dirs
            if (-not [string]::IsNullOrWhiteSpace([string]$cleanup.error)) {
                if ([string]::IsNullOrWhiteSpace([string]$result.error)) {
                    $result.error = $cleanup.error
                }
                else {
                    $result.error = "$($result.error); cleanup failed: $($cleanup.error)"
                }
            }
        }
    }

    return [pscustomobject]$result
}

$results = New-Object System.Collections.Generic.List[object]

foreach ($target in $targets) {
    Write-SasInstallEvent -EventPath $eventPath -Event @{
        event = 'target_started'
        run_id = $runId
        computer_name = $target
        package_name = $PackageName
        install_mode = $InstallMode
    }

    if (-not $PSCmdlet.ShouldProcess($target, "Install package '$PackageName' from approved software source using $InstallMode")) {
        $planned = [pscustomobject]@{
            computer_name = $target
            package_name = $PackageName
            install_mode = $InstallMode
            status = 'planned_whatif'
            exit_code = $null
            cleanup_attempted = $false
            cleanup_succeeded = $null
            repo_artifact_remaining = $null
            pruned_empty_parent_dirs = @()
            error = $null
        }
        $results.Add($planned)
        Write-SasInstallEvent -EventPath $eventPath -Event @{
            event = 'target_planned_whatif'
            run_id = $runId
            computer_name = $target
            package_name = $PackageName
            install_mode = $InstallMode
        }
        continue
    }

    $session = $null
    $stageRoot = $null
    try {
        $sessionOption = New-PSSessionOption -OpenTimeout 30000 -OperationTimeout 3600000
        $session = New-PSSession -ComputerName $target -SessionOption $sessionOption
        $remoteInstallerPath = $installerPath

        if ($InstallMode -eq 'CopyThenInstall') {
            $stageRoot = Invoke-Command -Session $session -ScriptBlock {
                param([string]$RunId)
                $path = Join-Path -Path $env:ProgramData -ChildPath ("SysAdminSuite\SoftwareInstall\{0}" -f $RunId)
                New-Item -ItemType Directory -Path $path -Force | Out-Null
                return $path
            } -ArgumentList $runId

            $remoteInstallerPath = Join-Path -Path $stageRoot -ChildPath (Split-Path -Path $installerPath -Leaf)
            Copy-Item -LiteralPath $installerPath -Destination $remoteInstallerPath -ToSession $session -Force
        }

        $remoteResult = Invoke-Command -Session $session -ScriptBlock $remoteInstall -ArgumentList $PackageName, $remoteInstallerPath, $InstallerArguments, $InstallMode, $runId
        $row = [pscustomobject]@{
            computer_name = $target
            package_name = $PackageName
            install_mode = $InstallMode
            status = $remoteResult.status
            exit_code = $remoteResult.exit_code
            cleanup_attempted = $remoteResult.cleanup_attempted
            cleanup_succeeded = $remoteResult.cleanup_succeeded
            repo_artifact_remaining = $remoteResult.repo_artifact_remaining
            pruned_empty_parent_dirs = $remoteResult.pruned_empty_parent_dirs
            error = $remoteResult.error
        }
        $results.Add($row)

        Write-SasInstallEvent -EventPath $eventPath -Event @{
            event = 'target_completed'
            run_id = $runId
            computer_name = $target
            package_name = $PackageName
            install_mode = $InstallMode
            status = $row.status
            exit_code = $row.exit_code
            cleanup_attempted = $row.cleanup_attempted
            cleanup_succeeded = $row.cleanup_succeeded
            repo_artifact_remaining = $row.repo_artifact_remaining
            pruned_empty_parent_dirs = $row.pruned_empty_parent_dirs
            error = $row.error
        }
    }
    catch {
        $failureMessage = $_.Exception.Message
        $outerCleanup = $null
        if ($InstallMode -eq 'CopyThenInstall' -and $session) {
            try {
                $outerCleanup = Invoke-Command -Session $session -ScriptBlock $remoteRepoCleanup -ArgumentList $runId
            }
            catch {
                $outerCleanup = [pscustomobject]@{
                    cleanup_attempted = $true
                    cleanup_succeeded = $false
                    repo_owned_stage_root = $stageRoot
                    repo_artifact_remaining = $true
                    removed_paths = @()
                    pruned_empty_parent_dirs = @()
                    error = $_.Exception.Message
                }
            }
        }

        if ($outerCleanup -and -not [string]::IsNullOrWhiteSpace([string]$outerCleanup.error)) {
            $failureMessage = "$failureMessage; cleanup failed: $($outerCleanup.error)"
        }

        $row = [pscustomobject]@{
            computer_name = $target
            package_name = $PackageName
            install_mode = $InstallMode
            status = 'failed_before_remote_result'
            exit_code = $null
            cleanup_attempted = $(if ($outerCleanup) { $outerCleanup.cleanup_attempted } else { $false })
            cleanup_succeeded = $(if ($outerCleanup) { $outerCleanup.cleanup_succeeded } else { $null })
            repo_artifact_remaining = $(if ($outerCleanup) { $outerCleanup.repo_artifact_remaining } else { $null })
            pruned_empty_parent_dirs = $(if ($outerCleanup) { $outerCleanup.pruned_empty_parent_dirs } else { @() })
            error = $failureMessage
        }
        $results.Add($row)
        Write-SasInstallEvent -EventPath $eventPath -Event @{
            event = 'target_failed'
            run_id = $runId
            computer_name = $target
            package_name = $PackageName
            install_mode = $InstallMode
            status = $row.status
            cleanup_attempted = $row.cleanup_attempted
            cleanup_succeeded = $row.cleanup_succeeded
            repo_artifact_remaining = $row.repo_artifact_remaining
            pruned_empty_parent_dirs = $row.pruned_empty_parent_dirs
            error = $row.error
        }
    }
    finally {
        if ($session) {
            Remove-PSSession -Session $session
        }
    }
}

$summary = [ordered]@{
    schema_version = 'sas-software-install-summary/v1'
    run_id = $runId
    package_name = $PackageName
    installer_path = $installerPath
    install_mode = $InstallMode
    target_count = $targets.Count
    completed_count = @($results | Where-Object { $_.status -eq 'completed' }).Count
    planned_count = @($results | Where-Object { $_.status -eq 'planned_whatif' }).Count
    failed_count = @($results | Where-Object { $_.status -notin @('completed', 'planned_whatif') }).Count
    cleanup_failure_count = @($results | Where-Object { $_.cleanup_attempted -and $_.cleanup_succeeded -eq $false }).Count
    repo_artifact_remaining_count = @($results | Where-Object { $_.repo_artifact_remaining -eq $true }).Count
    target_repo_artifact_policy = 'No SysAdminSuite-owned target logs, reports, manifests, transcripts, scripts, evidence, or staging should remain after cleanup. Installer-owned changes are outside this cleanup boundary.'
    event_path = $eventPath
    operator_handoff_path = $handoffPath
    results = @($results | ForEach-Object { $_ })
    guardrails = @(
        'approved_admin_context_only',
        'approved_read_only_software_share_only',
        'no_credential_collection',
        'no_monitoring_bypass_or_log_suppression',
        'no_unapproved_background_services',
        'no_repo_owned_target_logs_reports_manifests_or_transcripts',
        'run_specific_staging_cleanup_attempted_on_all_failure_paths',
        'prune_empty_sysadminsuite_target_directories',
        'temporary_staging_cleanup_status_reported'
    )
}

$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8 -WhatIf:$false
$handoffLines = @(
    'SysAdminSuite software install handoff',
    "Run ID: $runId",
    "Package: $PackageName",
    "Install mode: $InstallMode",
    "Targets: $($targets.Count)",
    "Completed: $($summary.completed_count)",
    "Planned/WhatIf: $($summary.planned_count)",
    "Failed or unresolved: $($summary.failed_count)",
    "Cleanup failures: $($summary.cleanup_failure_count)",
    "Repo-owned target remnants remaining: $($summary.repo_artifact_remaining_count)",
    "Events: $eventPath",
    "Summary: $summaryPath",
    '',
    'Review failures, cleanup failures, and repo-owned target remnant status before reporting completion to the client.'
)
$handoffLines | Set-Content -LiteralPath $handoffPath -Encoding UTF8 -WhatIf:$false
Write-SasInstallEvent -EventPath $eventPath -Event @{
    event = 'run_completed'
    run_id = $runId
    summary_path = $summaryPath
    completed_count = $summary.completed_count
    planned_count = $summary.planned_count
    failed_count = $summary.failed_count
    cleanup_failure_count = $summary.cleanup_failure_count
    repo_artifact_remaining_count = $summary.repo_artifact_remaining_count
}

Write-Output $summary

