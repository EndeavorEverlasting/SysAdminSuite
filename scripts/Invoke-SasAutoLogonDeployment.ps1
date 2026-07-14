#Requires -Version 5.1
<#
.SYNOPSIS
Run the bounded SysAdminSuite auto-logon deployment workflow.

.DESCRIPTION
Composes the read-only auto-logon state-delta collector with the existing authorized
software-install operator lane:

  request validation -> baseline snapshot -> eligibility reduction -> approved install
  -> after snapshot -> combined local report

The default installer is:
  \\nt2kwb972sms01\packages\AutoLogonSetup\NW_AutoLogon_Setup_x64.exe

The workflow does not create Startup-folder commands, Run keys, scheduled tasks, services,
or other persistence. CopyThenInstall uses the existing run-specific ProgramData staging
boundary and removes SysAdminSuite-owned staging after the installer exits. Installer-owned
changes and normal Windows/endpoint audit evidence are not removed.

-WhatIf is request-only and does not contact the share or target. -FixtureMode provides an
offline end-to-end contract run with synthetic before/after state and a planned install.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string[]]$ComputerName = @(),
    [string]$TargetsCsv,

    [string]$PackageName = 'NW AutoLogon Setup x64',
    [string]$SoftwareShareRoot = '\\nt2kwb972sms01\',
    [string]$InstallerRelativePath = 'packages\AutoLogonSetup\NW_AutoLogon_Setup_x64.exe',
    [string[]]$InstallerArguments = @(),

    [ValidateSet('UncDirect', 'CopyThenInstall')]
    [string]$InstallMode = 'CopyThenInstall',

    [string]$TechnicianLabel,
    [string]$OutputRoot,

    [ValidateRange(1, 25)]
    [int]$MaxTargets = 25,

    [switch]$AllowTargetMutation,
    [switch]$FixtureMode
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasAutoLogonTargets {
    [CmdletBinding()]
    param(
        [string[]]$DirectTargets,
        [string]$CsvPath,
        [int]$Limit
    )

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($target in @($DirectTargets)) {
        if (-not [string]::IsNullOrWhiteSpace($target)) {
            $items.Add($target.Trim())
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($CsvPath)) {
        if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
            throw "TargetsCsv not found: $CsvPath"
        }

        foreach ($row in @(Import-Csv -LiteralPath $CsvPath)) {
            $value = $null
            foreach ($column in @('ComputerName', 'HostName', 'Hostname', 'Target')) {
                if ($row.PSObject.Properties.Name -contains $column) {
                    $candidate = [string]$row.$column
                    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                        $value = $candidate.Trim()
                        break
                    }
                }
            }
            if ($value) {
                $items.Add($value)
            }
        }
    }

    $targets = @($items | Sort-Object -Unique)
    if ($targets.Count -eq 0) {
        throw 'No explicit targets were supplied. Use -ComputerName or -TargetsCsv.'
    }
    if ($targets.Count -gt $Limit) {
        throw "Target count $($targets.Count) exceeds MaxTargets $Limit. Split the run to keep deployment bounded."
    }

    return $targets
}

function Write-SasWorkflowJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force -WhatIf:$false | Out-Null
    }
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8 -WhatIf:$false
}

function Write-SasWorkflowEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [hashtable]$Event
    )

    $Event['timestamp_utc'] = (Get-Date).ToUniversalTime().ToString('o')
    $Event | ConvertTo-Json -Depth 12 -Compress |
        Add-Content -LiteralPath $Path -Encoding UTF8 -WhatIf:$false
}

function Get-SasBaselineEligibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BeforeDirectory
    )

    $rows = foreach ($file in @(Get-ChildItem -LiteralPath $BeforeDirectory -Filter '*.json' -File -ErrorAction Stop)) {
        try {
            $snapshot = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            $target = [string]$snapshot.requested_target
            $collectionStatus = [string]$snapshot.collection_status
            $autoLogonStatus = if ($snapshot.autologon) { [string]$snapshot.autologon.status } else { 'unknown' }

            $decision = if ($collectionStatus -ne 'success') {
                'SKIP_BASELINE_COLLECTION_FAILED'
            }
            elseif ($autoLogonStatus -eq 'autologon_ready') {
                'SKIP_ALREADY_CONFIGURED'
            }
            else {
                'ELIGIBLE_FOR_INSTALL'
            }

            [pscustomobject]@{
                computer_name = $target
                collection_status = $collectionStatus
                autologon_status = $autoLogonStatus
                eligibility_decision = $decision
                baseline_path = $file.FullName
                error = [string]$snapshot.error
            }
        }
        catch {
            [pscustomobject]@{
                computer_name = $file.BaseName
                collection_status = 'failed'
                autologon_status = 'unknown'
                eligibility_decision = 'SKIP_BASELINE_COLLECTION_FAILED'
                baseline_path = $file.FullName
                error = $_.Exception.Message
            }
        }
    }

    return @($rows)
}

if ($FixtureMode -and $AllowTargetMutation) {
    throw 'FixtureMode is offline and cannot be combined with -AllowTargetMutation.'
}
if (-not $FixtureMode -and -not $WhatIfPreference -and -not $AllowTargetMutation) {
    throw 'Refusing target mutation without -AllowTargetMutation. Use -WhatIf for request validation or -FixtureMode for offline end-to-end proof.'
}
if (-not $FixtureMode -and -not $WhatIfPreference -and @($InstallerArguments).Count -eq 0) {
    throw 'Live execution requires explicit vendor-validated -InstallerArguments. Do not assume an EXE silent-install syntax.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetIntakeModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasTargetIntake.psm1'
$stateDeltaScript = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-SasAutoLogonStateDelta.ps1'
$softwareInstallScript = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-SasSoftwareInstall.ps1'

foreach ($requiredPath in @($targetIntakeModule, $stateDeltaScript, $softwareInstallScript)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Missing required SysAdminSuite workflow dependency: $requiredPath"
    }
}

Import-Module -Name $targetIntakeModule -Force
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path -Path $repoRoot -ChildPath 'survey/output/autologon_deployment'
}
Assert-SasApprovedOutputPath -Path $OutputRoot -RepoRoot $repoRoot -Role 'auto-logon deployment output root'

$targets = @(Get-SasAutoLogonTargets -DirectTargets $ComputerName -CsvPath $TargetsCsv -Limit $MaxTargets)
$workflowId = 'autologon-deploy-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$workflowRoot = Join-Path -Path $OutputRoot -ChildPath $workflowId
$stateOutputRoot = Join-Path -Path $workflowRoot -ChildPath 'state'
$installOutputRoot = Join-Path -Path $workflowRoot -ChildPath 'install'
$eventsPath = Join-Path -Path $workflowRoot -ChildPath 'autologon_deployment_events.jsonl'
$summaryPath = Join-Path -Path $workflowRoot -ChildPath 'autologon_deployment_summary.json'
$handoffPath = Join-Path -Path $workflowRoot -ChildPath 'operator_handoff.txt'

New-Item -ItemType Directory -Path $workflowRoot -Force -WhatIf:$false | Out-Null

Write-SasWorkflowEvent -Path $eventsPath -Event @{
    event = 'workflow_started'
    workflow_id = $workflowId
    target_count = $targets.Count
    package_name = $PackageName
    installer_relative_path = $InstallerRelativePath
    install_mode = $InstallMode
    fixture_mode = [bool]$FixtureMode
    what_if = [bool]$WhatIfPreference
    posture = 'request_validate_baseline_reduce_install_validate_local_evidence_no_startup_persistence'
}

# Validate the approved source root and relative installer path before any baseline
# collection can contact a workstation. Invoke-SasSoftwareInstall -WhatIf performs
# request-only validation and writes local planning evidence without probing the share,
# opening a remote session, copying a payload, or starting the installer.
$requestPreflight = & $softwareInstallScript `
    -ComputerName $targets `
    -PackageName $PackageName `
    -SoftwareShareRoot $SoftwareShareRoot `
    -InstallerRelativePath $InstallerRelativePath `
    -InstallerArguments $InstallerArguments `
    -InstallMode $InstallMode `
    -OutputRoot $installOutputRoot `
    -MaxTargets $MaxTargets `
    -WhatIf

Write-SasWorkflowEvent -Path $eventsPath -Event @{
    event = 'request_preflight_completed'
    workflow_id = $workflowId
    planned_count = [int]$requestPreflight.planned_count
    target_reads_performed = $false
    target_mutation_performed = $false
}

if ($WhatIfPreference -and -not $FixtureMode) {
    $summary = [ordered]@{
        schema_version = 'sas-autologon-deployment-summary/v1'
        workflow_id = $workflowId
        status = 'PLANNED_WHATIF'
        generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        target_count = $targets.Count
        targets = $targets
        fixture_mode = $false
        what_if = $true
        target_reads_performed = $false
        target_mutation_performed = $false
        startup_persistence_created = $false
        package_name = $PackageName
        software_share_root = $SoftwareShareRoot
        installer_relative_path = $InstallerRelativePath
        install_mode = $InstallMode
        request_preflight = $requestPreflight
        install_plan = $requestPreflight
        next_gate = 'Run -FixtureMode for offline end-to-end proof, then a two-target approved pilot with explicit vendor-validated InstallerArguments and -AllowTargetMutation.'
    }
    Write-SasWorkflowJson -Path $summaryPath -Value $summary
    @(
        'SysAdminSuite auto-logon deployment workflow',
        "Workflow ID: $workflowId",
        'Status: PLANNED_WHATIF',
        "Targets: $($targets.Count)",
        "Installer: $SoftwareShareRoot$InstallerRelativePath",
        "Summary: $summaryPath",
        '',
        'No share read, target read, remote session, copy, or installer execution occurred.',
        'No Startup-folder command or other persistence was created.'
    ) | Set-Content -LiteralPath $handoffPath -Encoding UTF8 -WhatIf:$false

    Write-SasWorkflowEvent -Path $eventsPath -Event @{
        event = 'workflow_completed'
        workflow_id = $workflowId
        status = 'PLANNED_WHATIF'
        summary_path = $summaryPath
    }

    [pscustomobject]@{
        workflow_id = $workflowId
        status = 'PLANNED_WHATIF'
        output_root = $workflowRoot
        summary_json = $summaryPath
        handoff = $handoffPath
    }
    return
}

$stateRunId = 'autologon-delta-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$beforeParams = @{
    Mode = 'Before'
    ComputerName = $targets
    RunId = $stateRunId
    OutputRoot = $stateOutputRoot
    TechnicianLabel = $TechnicianLabel
    MaxTargets = $MaxTargets
}
if ($FixtureMode) {
    $beforeParams['FixtureMode'] = $true
}

$before = & $stateDeltaScript @beforeParams
$beforeDirectory = Join-Path -Path $before.output_root -ChildPath 'before'
$eligibility = @(Get-SasBaselineEligibility -BeforeDirectory $beforeDirectory)
$eligibleTargets = @($eligibility |
    Where-Object { $_.eligibility_decision -eq 'ELIGIBLE_FOR_INSTALL' } |
    ForEach-Object { $_.computer_name })
$baselineFailureTargets = @($eligibility |
    Where-Object { $_.eligibility_decision -eq 'SKIP_BASELINE_COLLECTION_FAILED' } |
    ForEach-Object { $_.computer_name })
$alreadyConfiguredTargets = @($eligibility |
    Where-Object { $_.eligibility_decision -eq 'SKIP_ALREADY_CONFIGURED' } |
    ForEach-Object { $_.computer_name })

Write-SasWorkflowEvent -Path $eventsPath -Event @{
    event = 'baseline_reduced'
    workflow_id = $workflowId
    eligible_count = $eligibleTargets.Count
    already_configured_count = $alreadyConfiguredTargets.Count
    baseline_failure_count = $baselineFailureTargets.Count
}

$installSummary = $null
if ($eligibleTargets.Count -gt 0) {
    $installParams = @{
        ComputerName = $eligibleTargets
        PackageName = $PackageName
        SoftwareShareRoot = $SoftwareShareRoot
        InstallerRelativePath = $InstallerRelativePath
        InstallerArguments = $(if (@($InstallerArguments).Count -gt 0) { $InstallerArguments } else { @('/quiet', '/norestart') })
        InstallMode = $InstallMode
        OutputRoot = $installOutputRoot
        MaxTargets = $MaxTargets
    }

    if ($FixtureMode) {
        $installSummary = & $softwareInstallScript @installParams -WhatIf
    }
    elseif ($PSCmdlet.ShouldProcess(
        ($eligibleTargets -join ', '),
        "Install '$PackageName' after successful baseline capture"
    )) {
        $installSummary = & $softwareInstallScript @installParams -AllowTargetMutation -Confirm:$false
    }
}
else {
    $installSummary = [pscustomobject]@{
        schema_version = 'sas-software-install-summary/v1'
        run_id = $null
        package_name = $PackageName
        target_count = 0
        completed_count = 0
        planned_count = 0
        failed_count = 0
        cleanup_failure_count = 0
        repo_artifact_remaining_count = 0
        results = @()
        disposition = 'no_eligible_targets'
    }
}

$afterParams = @{
    Mode = 'After'
    ComputerName = $targets
    RunId = $stateRunId
    OutputRoot = $stateOutputRoot
    TechnicianLabel = $TechnicianLabel
    MaxTargets = $MaxTargets
}
if ($FixtureMode) {
    $afterParams['FixtureMode'] = $true
}
$after = & $stateDeltaScript @afterParams
$afterSummary = Get-Content -LiteralPath $after.summary_json -Raw | ConvertFrom-Json

$installFailedCount = [int]$installSummary.failed_count
$cleanupFailureCount = [int]$installSummary.cleanup_failure_count
$repoRemnantCount = [int]$installSummary.repo_artifact_remaining_count
$reviewCount = [int]$afterSummary.partial_change_review_count +
    [int]$afterSummary.regression_review_count +
    [int]$afterSummary.inconclusive_count +
    $baselineFailureTargets.Count +
    $installFailedCount +
    $cleanupFailureCount +
    $repoRemnantCount

$status = if ($FixtureMode) {
    if (
        [int]$installSummary.planned_count -eq $eligibleTargets.Count -and
        [int]$afterSummary.confirmed_state_transition_count -eq $eligibleTargets.Count -and
        $reviewCount -eq 0
    ) {
        'FIXTURE_PASS'
    }
    else {
        'FIXTURE_FAIL'
    }
}
elseif ($reviewCount -eq 0) {
    'COMPLETED'
}
else {
    'COMPLETED_WITH_REVIEW'
}

$summary = [ordered]@{
    schema_version = 'sas-autologon-deployment-summary/v1'
    workflow_id = $workflowId
    state_run_id = $stateRunId
    status = $status
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    technician_label = $TechnicianLabel
    package_name = $PackageName
    software_share_root = $SoftwareShareRoot
    installer_relative_path = $InstallerRelativePath
    installer_arguments_supplied = (@($InstallerArguments).Count -gt 0)
    install_mode = $InstallMode
    target_count = $targets.Count
    targets = $targets
    fixture_mode = [bool]$FixtureMode
    what_if = [bool]$WhatIfPreference
    request_preflight = $requestPreflight
    baseline_success_count = @($eligibility | Where-Object { $_.collection_status -eq 'success' }).Count
    baseline_failure_count = $baselineFailureTargets.Count
    baseline_failure_targets = $baselineFailureTargets
    already_configured_count = $alreadyConfiguredTargets.Count
    already_configured_targets = $alreadyConfiguredTargets
    eligible_install_count = $eligibleTargets.Count
    eligible_install_targets = $eligibleTargets
    install_completed_count = [int]$installSummary.completed_count
    install_planned_count = [int]$installSummary.planned_count
    install_failed_count = $installFailedCount
    cleanup_failure_count = $cleanupFailureCount
    repo_artifact_remaining_count = $repoRemnantCount
    confirmed_state_transition_count = [int]$afterSummary.confirmed_state_transition_count
    no_material_change_count = [int]$afterSummary.no_material_change_count
    partial_change_review_count = [int]$afterSummary.partial_change_review_count
    regression_review_count = [int]$afterSummary.regression_review_count
    inconclusive_count = [int]$afterSummary.inconclusive_count
    target_mutation_authorized = (-not $FixtureMode)
    install_attempted = (-not $FixtureMode -and $eligibleTargets.Count -gt 0 -and [int]$installSummary.planned_count -eq 0)
    startup_persistence_created = $false
    default_password_value_collected = $false
    eligibility = $eligibility
    before_summary_json = $before.summary_json
    install_summary = $installSummary
    after_summary_json = $after.summary_json
    events_jsonl = $eventsPath
    guardrails = @(
        'explicit_targets_only',
        'maximum_25_targets_per_run',
        'approved_source_and_relative_path_validated_before_target_reads',
        'baseline_required_before_install',
        'baseline_collection_failures_are_not_installed',
        'already_configured_targets_are_not_reinstalled',
        'approved_read_only_software_share_only',
        'explicit_vendor_validated_installer_arguments_required_for_live_execution',
        'no_startup_folder_cmd_or_other_persistence',
        'no_credential_collection',
        'no_monitoring_bypass_or_log_suppression',
        'sysadminsuite_owned_target_staging_cleanup_reported',
        'local_gitignored_evidence_only',
        'real_reboot_and_observed_autologon_still_required_for_runtime_proof'
    )
}
Write-SasWorkflowJson -Path $summaryPath -Value $summary

@(
    'SysAdminSuite auto-logon deployment workflow',
    "Workflow ID: $workflowId",
    "State run ID: $stateRunId",
    "Status: $status",
    "Targets requested: $($targets.Count)",
    "Request preflight planned: $([int]$requestPreflight.planned_count)",
    "Eligible for install: $($eligibleTargets.Count)",
    "Already configured before: $($alreadyConfiguredTargets.Count)",
    "Baseline collection failures skipped: $($baselineFailureTargets.Count)",
    "Install completed: $($summary.install_completed_count)",
    "Install planned: $($summary.install_planned_count)",
    "Install failed: $($summary.install_failed_count)",
    "Confirmed state transitions: $($summary.confirmed_state_transition_count)",
    "Cleanup failures: $cleanupFailureCount",
    "Repo-owned target remnants: $repoRemnantCount",
    "Summary: $summaryPath",
    "Events: $eventsPath",
    '',
    'No Startup-folder CMD, Run key, scheduled task, service, or hidden persistence was created.',
    'Review failures and state-delta decisions before expanding beyond the pilot.',
    'A real reboot and observed auto-logon are still required before declaring runtime success.'
) | Set-Content -LiteralPath $handoffPath -Encoding UTF8 -WhatIf:$false

Write-SasWorkflowEvent -Path $eventsPath -Event @{
    event = 'workflow_completed'
    workflow_id = $workflowId
    status = $status
    summary_path = $summaryPath
    eligible_install_count = $eligibleTargets.Count
    install_completed_count = [int]$installSummary.completed_count
    install_failed_count = $installFailedCount
    confirmed_state_transition_count = [int]$afterSummary.confirmed_state_transition_count
    cleanup_failure_count = $cleanupFailureCount
    repo_artifact_remaining_count = $repoRemnantCount
}

[pscustomobject]@{
    workflow_id = $workflowId
    state_run_id = $stateRunId
    status = $status
    target_count = $targets.Count
    eligible_install_count = $eligibleTargets.Count
    output_root = $workflowRoot
    summary_json = $summaryPath
    events_jsonl = $eventsPath
    handoff = $handoffPath
}
