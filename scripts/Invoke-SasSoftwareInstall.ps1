#Requires -Version 5.1
<#
.SYNOPSIS
Installs approved software on authorized target computers from an approved read-only software share.

.DESCRIPTION
Invoke-SasSoftwareInstall is the SysAdminSuite operator-execute wrapper for admin-box software installs.
It prefers direct UNC execution so SysAdminSuite does not stage payloads on the target. When staging is explicitly
requested, it copies the installer to ProgramData\SysAdminSuite\SoftwareInstall\<run_id> and removes that staging
folder in a cleanup block after the installer exits.

This script does not suppress Windows logs, clear evidence, collect credentials, create persistence, or bypass
monitoring. Local JSON evidence is written on the admin box.
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
    [string]$SoftwareShareRoot = '\\nt2kwb972sms01\',

    [Parameter(Mandatory = $false)]
    [string[]]$InstallerArguments = @('/quiet', '/norestart'),

    [Parameter(Mandatory = $false)]
    [ValidateSet('UncDirect', 'CopyThenInstall')]
    [string]$InstallMode = 'UncDirect',

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot = (Join-Path -Path (Get-Location) -ChildPath 'survey/output/software_install'),

    [Parameter(Mandatory = $false)]
    [int]$MaxTargets = 25,

    [Parameter(Mandatory = $false)]
    [switch]$AllowTargetMutation
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Normalize-SasUncRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not $Path.StartsWith('\\')) {
        throw "SoftwareShareRoot must be a UNC path. Received: $Path"
    }

    $trimmed = $Path.TrimEnd('\')
    return "$trimmed\"
}

function Resolve-SasApprovedInstallerPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw 'InstallerRelativePath must be relative to the approved software share root.'
    }

    if ($RelativePath -match '(^|[\\/])\.\.([\\/]|$)') {
        throw 'InstallerRelativePath cannot contain parent-directory traversal.'
    }

    $normalizedRoot = Normalize-SasUncRoot -Path $Root
    $child = $RelativePath.TrimStart('\', '/')
    $candidate = Join-Path -Path $normalizedRoot -ChildPath $child

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

    $deduped = $targets | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique
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
    $Event | ConvertTo-Json -Depth 10 -Compress | Add-Content -LiteralPath $EventPath -Encoding UTF8
}

if (-not $AllowTargetMutation -and -not $WhatIfPreference) {
    throw 'Refusing target mutation without -AllowTargetMutation. Use -WhatIf for dry-run planning.'
}

$runId = 'software-install-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
$runRoot = Join-Path -Path $OutputRoot -ChildPath $runId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

$eventPath = Join-Path -Path $runRoot -ChildPath 'software_install_events.jsonl'
$summaryPath = Join-Path -Path $runRoot -ChildPath 'software_install_summary.json'
$handoffPath = Join-Path -Path $runRoot -ChildPath 'operator_handoff.txt'
$installerPath = Resolve-SasApprovedInstallerPath -Root $SoftwareShareRoot -RelativePath $InstallerRelativePath
if ([string]::IsNullOrWhiteSpace($PackageName)) {
    $PackageName = Split-Path -Path $installerPath -Leaf
}

if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw "Installer was not found under the approved software source: $installerPath"
}

$targets = Get-SasInstallTargets -DirectTargets $ComputerName -CsvPath $TargetsCsv -Limit $MaxTargets

Write-SasInstallEvent -EventPath $eventPath -Event @{
    event = 'run_started'
    run_id = $runId
    package_name = $PackageName
    installer_path = $installerPath
    install_mode = $InstallMode
    target_count = $targets.Count
    output_root = $runRoot
    posture = 'authorized_operator_execute_no_log_suppression_no_credential_collection_cleanup_staging_only'
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
        status = 'started'
        error = $null
    }

    try {
        if (-not (Test-Path -LiteralPath $InstallerSource -PathType Leaf)) {
            throw "Installer source not found on target context: $InstallerSource"
        }

        $process = Start-Process -FilePath $InstallerSource -ArgumentList $Arguments -Wait -PassThru
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
            $result.cleanup_attempted = $true
            try {
                if (Test-Path -LiteralPath $stageRoot) {
                    Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction Stop
                }
                $result.cleanup_succeeded = -not (Test-Path -LiteralPath $stageRoot)
            }
            catch {
                $result.cleanup_succeeded = $false
                if ([string]::IsNullOrWhiteSpace([string]$result.error)) {
                    $result.error = $_.Exception.Message
                }
                else {
                    $result.error = "$($result.error); cleanup failed: $($_.Exception.Message)"
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
    try {
        $session = New-PSSession -ComputerName $target
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
            error = $row.error
        }
    }
    catch {
        $row = [pscustomobject]@{
            computer_name = $target
            package_name = $PackageName
            install_mode = $InstallMode
            status = 'failed_before_remote_result'
            exit_code = $null
            cleanup_attempted = ($InstallMode -eq 'CopyThenInstall')
            cleanup_succeeded = $false
            error = $_.Exception.Message
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
    event_path = $eventPath
    operator_handoff_path = $handoffPath
    results = @($results)
    guardrails = @(
        'approved_admin_context_only',
        'approved_read_only_software_share_only',
        'no_credential_collection',
        'no_monitoring_bypass_or_log_suppression',
        'no_unapproved_background_services',
        'temporary_staging_cleanup_status_reported'
    )
}

$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
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
    "Events: $eventPath",
    "Summary: $summaryPath",
    '',
    'Review failures and cleanup failures before reporting completion to the client.'
)
$handoffLines | Set-Content -LiteralPath $handoffPath -Encoding UTF8
Write-SasInstallEvent -EventPath $eventPath -Event @{
    event = 'run_completed'
    run_id = $runId
    summary_path = $summaryPath
    completed_count = $summary.completed_count
    planned_count = $summary.planned_count
    failed_count = $summary.failed_count
    cleanup_failure_count = $summary.cleanup_failure_count
}

Write-Output $summary
