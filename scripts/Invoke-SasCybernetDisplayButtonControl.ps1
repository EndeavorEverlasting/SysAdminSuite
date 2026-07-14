#Requires -Version 5.1
<#
.SYNOPSIS
Probe, apply, or restore MCCS 2.2 VCP 0xCA display-button control on authorized Cybernet workstations.

.DESCRIPTION
Uses the Windows Monitor Configuration API through the repo-owned SasDdcciMonitorControl.cs helper.

Probe is read-only. Apply sets VCP 0xCA to 0x0303 only when the target proves:
- MCCS 2.2 or later;
- readable VCP 0xCA;
- supported host OSD/menu-button and power-button control bytes.

0x0303 means:
- SL 0x03: OSD disabled and OSD/menu-button events disabled;
- SH 0x03: display power button disabled and power-button events disabled.

Apply records the original VCP 0xCA value in a restore manifest. Failed readback triggers an immediate
best-effort rollback to the original value. Restore consumes that generated manifest.

-WhatIf validates request shape and writes local planning evidence without contacting targets.
-FixtureMode exercises output contracts without network activity or target mutation.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string[]]$ComputerName = @(),
    [string]$TargetsCsv,

    [ValidateSet('Probe', 'Apply', 'Restore')]
    [string]$Operation = 'Probe',

    [ValidateRange(-1, 64)]
    [int]$MonitorIndex = -1,

    [string]$RestoreManifest,
    [string]$OutputRoot,

    [ValidateRange(1, 25)]
    [int]$MaxTargets = 25,

    [switch]$AllowTargetMutation,
    [switch]$FixtureMode
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasDisplayButtonTargets {
    [CmdletBinding()]
    param(
        [string[]]$DirectTargets,
        [string]$CsvPath,
        [int]$Limit,
        [string]$RepoRoot
    )

    $items = @()
    foreach ($target in @($DirectTargets)) {
        if (-not [string]::IsNullOrWhiteSpace($target)) {
            $items += $target.Trim()
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($CsvPath)) {
        Assert-SasApprovedInputPath `
            -Path $CsvPath `
            -RepoRoot $RepoRoot `
            -Role 'Cybernet display-button target CSV' `
            -AllowStaging

        foreach ($row in @(Import-Csv -LiteralPath $CsvPath)) {
            foreach ($column in @('ComputerName', 'HostName', 'Hostname', 'Target')) {
                if ($row.PSObject.Properties.Name -contains $column) {
                    $candidate = [string]$row.$column
                    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                        $items += $candidate.Trim()
                        break
                    }
                }
            }
        }
    }

    $seen = @{}
    $targets = @()
    foreach ($target in $items) {
        if ($target -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$') {
            throw "Invalid target name: $target"
        }
        $key = $target.ToUpperInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $targets += $target
        }
    }

    if ($targets.Count -eq 0) {
        throw 'No explicit targets were supplied. Use -ComputerName or -TargetsCsv.'
    }
    if ($targets.Count -gt $Limit) {
        throw "Target count $($targets.Count) exceeds MaxTargets $Limit. Split the run to keep display-button work bounded."
    }

    return @($targets)
}

function Write-SasDisplayButtonJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )

    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force -WhatIf:$false | Out-Null
    }
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8 -WhatIf:$false
}

function Write-SasDisplayButtonEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$Event
    )

    $Event['timestamp_utc'] = (Get-Date).ToUniversalTime().ToString('o')
    $Event | ConvertTo-Json -Depth 20 -Compress |
        Add-Content -LiteralPath $Path -Encoding UTF8 -WhatIf:$false
}

function Get-SasRestoreEntryMap {
    [CmdletBinding()]
    param(
        [string]$ManifestPath,
        [string]$RepoRoot
    )

    if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        throw 'Restore requires -RestoreManifest from a prior successful Apply run.'
    }

    Assert-SasApprovedInputPath `
        -Path $ManifestPath `
        -RepoRoot $RepoRoot `
        -Role 'Cybernet display-button restore manifest' `
        -AllowGenerated

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$manifest.schema_version -ne 'sas-cybernet-display-button-restore/v1') {
        throw "Unsupported restore manifest schema: $($manifest.schema_version)"
    }

    $map = @{}
    foreach ($entry in @($manifest.entries)) {
        $target = [string]$entry.computer_name
        if ([string]::IsNullOrWhiteSpace($target)) { continue }
        $map[$target.ToUpperInvariant()] = $entry
    }
    return $map
}

if ($FixtureMode -and $AllowTargetMutation) {
    throw 'FixtureMode is offline and cannot be combined with -AllowTargetMutation.'
}
if ($Operation -in @('Apply', 'Restore') -and -not $FixtureMode -and -not $WhatIfPreference -and -not $AllowTargetMutation) {
    throw "Refusing $Operation target mutation without -AllowTargetMutation. Use -WhatIf or -FixtureMode first."
}
if ($Operation -eq 'Restore' -and -not $FixtureMode -and [string]::IsNullOrWhiteSpace($RestoreManifest)) {
    throw 'Restore requires -RestoreManifest from a prior successful Apply run.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetIntakeModule = Join-Path $PSScriptRoot 'SasTargetIntake.psm1'
$ddcciSourcePath = Join-Path $PSScriptRoot 'SasDdcciMonitorControl.cs'
foreach ($requiredPath in @($targetIntakeModule, $ddcciSourcePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Missing required Cybernet display-button dependency: $requiredPath"
    }
}

Import-Module -Name $targetIntakeModule -Force
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'survey/output/cybernet_display_button_control'
}
Assert-SasApprovedOutputPath -Path $OutputRoot -RepoRoot $repoRoot -Role 'Cybernet display-button output root'

$targets = @(Get-SasDisplayButtonTargets `
    -DirectTargets $ComputerName `
    -CsvPath $TargetsCsv `
    -Limit $MaxTargets `
    -RepoRoot $repoRoot)

$restoreEntryMap = @{}
if ($Operation -eq 'Restore' -and -not $FixtureMode) {
    $restoreEntryMap = Get-SasRestoreEntryMap -ManifestPath $RestoreManifest -RepoRoot $repoRoot
    foreach ($target in $targets) {
        if (-not $restoreEntryMap.ContainsKey($target.ToUpperInvariant())) {
            throw "Restore manifest has no entry for target: $target"
        }
    }
}

$workflowId = 'cybernet-display-buttons-{0}-{1}' -f `
    (Get-Date -Format 'yyyyMMdd-HHmmss'), `
    ([guid]::NewGuid().ToString('N').Substring(0, 8))
$workflowRoot = Join-Path $OutputRoot $workflowId
$eventsPath = Join-Path $workflowRoot 'cybernet_display_button_events.jsonl'
$resultsPath = Join-Path $workflowRoot 'cybernet_display_button_results.csv'
$detailsPath = Join-Path $workflowRoot 'cybernet_display_button_details.json'
$summaryPath = Join-Path $workflowRoot 'cybernet_display_button_summary.json'
$restoreOutputPath = Join-Path $workflowRoot 'cybernet_display_button_restore_manifest.json'
$handoffPath = Join-Path $workflowRoot 'operator_handoff.txt'
New-Item -ItemType Directory -Path $workflowRoot -Force -WhatIf:$false | Out-Null

Write-SasDisplayButtonEvent -Path $eventsPath -Event @{
    event = 'workflow_started'
    workflow_id = $workflowId
    operation = $Operation
    target_count = $targets.Count
    targets = @($targets)
    monitor_index = $MonitorIndex
    fixture_mode = [bool]$FixtureMode
    what_if = [bool]$WhatIfPreference
    desired_vcp_ca = if ($Operation -eq 'Apply') { '0x0303' } else { '' }
    posture = 'explicit_targets_one_remote_session_per_target_no_payload_staging_read_before_write_verify_and_rollback'
}

if ($WhatIfPreference) {
    $summary = [ordered]@{
        schema_version = 'sas-cybernet-display-button-summary/v1'
        workflow_id = $workflowId
        status = 'PLANNED_WHATIF'
        operation = $Operation
        generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        target_count = $targets.Count
        targets = @($targets)
        monitor_index = $MonitorIndex
        desired_vcp_ca = if ($Operation -eq 'Apply') { '0x0303' } else { '' }
        network_activity_performed = $false
        target_mutation_attempted = $false
        target_mutation_performed = $false
        results_path = $resultsPath
        details_path = $detailsPath
        restore_manifest_path = if ($Operation -eq 'Apply') { $restoreOutputPath } else { '' }
        events_path = $eventsPath
    }
    Write-SasDisplayButtonJson -Path $summaryPath -Value $summary
    @(
        "Cybernet display-button plan: $workflowId",
        "Operation: $Operation",
        "Targets: $($targets.Count)",
        'No target contact or mutation occurred.',
        'Apply will require confirmed MCCS 2.2 VCP 0xCA host control and per-target confirmation.',
        "Summary: $summaryPath"
    ) | Set-Content -LiteralPath $handoffPath -Encoding UTF8 -WhatIf:$false
    Write-Output ([pscustomobject]$summary)
    return
}

$ddcciSource = Get-Content -LiteralPath $ddcciSourcePath -Raw -Encoding UTF8
$summaryRows = @()
$details = @()
$restoreEntries = @()

if ($FixtureMode) {
    foreach ($target in $targets) {
        if ($Operation -eq 'Probe') {
            $probe = [pscustomobject][ordered]@{
                MonitorIndex = if ($MonitorIndex -ge 0) { $MonitorIndex } else { 0 }
                Description = 'Synthetic Cybernet integrated display'
                CapabilitiesRead = $true
                VcpVersionRead = $true
                MccsMajor = 2
                MccsMinor = 2
                MccsVersion = '2.2'
                VcpCaAdvertised = $true
                VcpCaRead = $true
                VcpCaCurrentValue = 0x0202
                VcpCaCurrentHex = '0x0202'
                OsdButtonControlByte = 2
                PowerButtonControlByte = 2
                HostOsdButtonControlSupported = $true
                HostPowerButtonControlSupported = $true
                EligibleForButtonLock = $true
                Classification = 'VCP_CA_V22_BUTTON_LOCK_READY'
                Error = ''
            }
            $details += [pscustomobject]@{ computer_name = $target; operation = $Operation; result = @($probe) }
            $summaryRows += [pscustomobject][ordered]@{
                computer_name = $target
                operation = $Operation
                status = 'PROBE_COMPLETE'
                eligible_monitor_count = 1
                selected_monitor_index = ''
                original_vcp_ca = '0x0202'
                final_vcp_ca = '0x0202'
                verification_passed = $true
                rollback_attempted = $false
                rollback_verified = $false
                network_activity_performed = $false
                target_mutation_attempted = $false
                target_mutation_performed = $false
                error = ''
            }
        }
        elseif ($Operation -eq 'Apply') {
            $selectedIndex = if ($MonitorIndex -ge 0) { $MonitorIndex } else { 0 }
            $mutation = [pscustomobject][ordered]@{
                MonitorIndex = $selectedIndex
                Description = 'Synthetic Cybernet integrated display'
                Operation = 'Apply'
                Status = 'APPLIED_VERIFIED'
                MccsVersion = '2.2'
                OriginalValue = 0x0202
                OriginalHex = '0x0202'
                DesiredValue = 0x0303
                DesiredHex = '0x0303'
                FinalValue = 0x0303
                FinalHex = '0x0303'
                MutationAttempted = $true
                MutationPerformed = $true
                VerificationPassed = $true
                RollbackAttempted = $false
                RollbackVerified = $false
                Error = ''
            }
            $details += [pscustomobject]@{ computer_name = $target; operation = $Operation; result = $mutation }
            $summaryRows += [pscustomobject][ordered]@{
                computer_name = $target
                operation = $Operation
                status = 'APPLIED_VERIFIED'
                eligible_monitor_count = 1
                selected_monitor_index = $selectedIndex
                original_vcp_ca = '0x0202'
                final_vcp_ca = '0x0303'
                verification_passed = $true
                rollback_attempted = $false
                rollback_verified = $false
                network_activity_performed = $false
                target_mutation_attempted = $false
                target_mutation_performed = $false
                error = ''
            }
            $restoreEntries += [pscustomobject][ordered]@{
                computer_name = $target
                monitor_index = $selectedIndex
                physical_monitor_description = 'Synthetic Cybernet integrated display'
                original_vcp_ca_value = 0x0202
                original_vcp_ca_hex = '0x0202'
                applied_vcp_ca_value = 0x0303
                applied_vcp_ca_hex = '0x0303'
            }
        }
        else {
            $selectedIndex = if ($MonitorIndex -ge 0) { $MonitorIndex } else { 0 }
            $mutation = [pscustomobject][ordered]@{
                MonitorIndex = $selectedIndex
                Description = 'Synthetic Cybernet integrated display'
                Operation = 'Restore'
                Status = 'RESTORED_VERIFIED'
                MccsVersion = '2.2'
                OriginalValue = 0x0303
                OriginalHex = '0x0303'
                DesiredValue = 0x0202
                DesiredHex = '0x0202'
                FinalValue = 0x0202
                FinalHex = '0x0202'
                MutationAttempted = $true
                MutationPerformed = $true
                VerificationPassed = $true
                RollbackAttempted = $false
                RollbackVerified = $false
                Error = ''
            }
            $details += [pscustomobject]@{ computer_name = $target; operation = $Operation; result = $mutation }
            $summaryRows += [pscustomobject][ordered]@{
                computer_name = $target
                operation = $Operation
                status = 'RESTORED_VERIFIED'
                eligible_monitor_count = 1
                selected_monitor_index = $selectedIndex
                original_vcp_ca = '0x0303'
                final_vcp_ca = '0x0202'
                verification_passed = $true
                rollback_attempted = $false
                rollback_verified = $false
                network_activity_performed = $false
                target_mutation_attempted = $false
                target_mutation_performed = $false
                error = ''
            }
        }
    }
}
else {
    $remoteScript = {
        param(
            [string]$CSharpSource,
            [string]$RequestedOperation,
            [int]$RequestedMonitorIndex,
            [uint32]$RestoreValue
        )

        Set-StrictMode -Version 2.0
        $ErrorActionPreference = 'Stop'
        if (-not ('SysAdminSuite.DisplayControl.MonitorController' -as [type])) {
            Add-Type -TypeDefinition $CSharpSource -Language CSharp -ErrorAction Stop
        }

        $result = if ($RequestedOperation -eq 'Probe') {
            [SysAdminSuite.DisplayControl.MonitorController]::ProbeAll()
        }
        elseif ($RequestedOperation -eq 'Apply') {
            [SysAdminSuite.DisplayControl.MonitorController]::ApplyButtonLock($RequestedMonitorIndex)
        }
        else {
            [SysAdminSuite.DisplayControl.MonitorController]::RestoreButtonLock($RequestedMonitorIndex, $RestoreValue)
        }

        return ($result | ConvertTo-Json -Depth 30 -Compress)
    }

    foreach ($target in $targets) {
        $targetRestoreValue = [uint32]0
        $targetMonitorIndex = $MonitorIndex
        if ($Operation -eq 'Restore') {
            $entry = $restoreEntryMap[$target.ToUpperInvariant()]
            $targetRestoreValue = [uint32]$entry.original_vcp_ca_value
            if ($MonitorIndex -lt 0) {
                $targetMonitorIndex = [int]$entry.monitor_index
            }
        }

        if ($Operation -in @('Apply', 'Restore')) {
            $actionText = if ($Operation -eq 'Apply') {
                'Apply and verify MCCS 2.2 VCP 0xCA value 0x0303, preserving original value for restore'
            }
            else {
                "Restore and verify MCCS 2.2 VCP 0xCA value 0x$($targetRestoreValue.ToString('X4'))"
            }
            if (-not $PSCmdlet.ShouldProcess($target, $actionText)) {
                $summaryRows += [pscustomobject][ordered]@{
                    computer_name = $target
                    operation = $Operation
                    status = 'SKIPPED_OPERATOR_DECLINED'
                    eligible_monitor_count = 0
                    selected_monitor_index = if ($targetMonitorIndex -ge 0) { $targetMonitorIndex } else { '' }
                    original_vcp_ca = ''
                    final_vcp_ca = ''
                    verification_passed = $false
                    rollback_attempted = $false
                    rollback_verified = $false
                    network_activity_performed = $false
                    target_mutation_attempted = $false
                    target_mutation_performed = $false
                    error = 'Operator declined ShouldProcess confirmation.'
                }
                continue
            }
        }

        Write-SasDisplayButtonEvent -Path $eventsPath -Event @{
            event = 'target_operation_started'
            workflow_id = $workflowId
            computer_name = $target
            operation = $Operation
            monitor_index = $targetMonitorIndex
        }

        try {
            $json = Invoke-Command `
                -ComputerName $target `
                -ScriptBlock $remoteScript `
                -ArgumentList $ddcciSource, $Operation, $targetMonitorIndex, $targetRestoreValue `
                -ErrorAction Stop
            $remoteResult = $json | ConvertFrom-Json

            if ($Operation -eq 'Probe') {
                $probeResults = @($remoteResult)
                $eligibleCount = @($probeResults | Where-Object { $_.EligibleForButtonLock }).Count
                $probeErrors = @($probeResults | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Error) })
                $details += [pscustomobject]@{
                    computer_name = $target
                    operation = $Operation
                    result = $probeResults
                }
                $summaryRows += [pscustomobject][ordered]@{
                    computer_name = $target
                    operation = $Operation
                    status = 'PROBE_COMPLETE'
                    eligible_monitor_count = $eligibleCount
                    selected_monitor_index = ''
                    original_vcp_ca = (@($probeResults | Where-Object { $_.VcpCaRead } | Select-Object -ExpandProperty VcpCaCurrentHex) -join ';')
                    final_vcp_ca = (@($probeResults | Where-Object { $_.VcpCaRead } | Select-Object -ExpandProperty VcpCaCurrentHex) -join ';')
                    verification_passed = ($probeErrors.Count -eq 0)
                    rollback_attempted = $false
                    rollback_verified = $false
                    network_activity_performed = $true
                    target_mutation_attempted = $false
                    target_mutation_performed = $false
                    error = (@($probeErrors | Select-Object -ExpandProperty Error) -join '; ')
                }
                Write-SasDisplayButtonEvent -Path $eventsPath -Event @{
                    event = 'target_probe_completed'
                    workflow_id = $workflowId
                    computer_name = $target
                    eligible_monitor_count = $eligibleCount
                }
            }
            else {
                $mutation = $remoteResult
                $details += [pscustomobject]@{
                    computer_name = $target
                    operation = $Operation
                    result = $mutation
                }
                $summaryRows += [pscustomobject][ordered]@{
                    computer_name = $target
                    operation = $Operation
                    status = [string]$mutation.Status
                    eligible_monitor_count = if ([string]$mutation.Status -like '*REFUSED*') { 0 } else { 1 }
                    selected_monitor_index = [int]$mutation.MonitorIndex
                    original_vcp_ca = [string]$mutation.OriginalHex
                    final_vcp_ca = [string]$mutation.FinalHex
                    verification_passed = [bool]$mutation.VerificationPassed
                    rollback_attempted = [bool]$mutation.RollbackAttempted
                    rollback_verified = [bool]$mutation.RollbackVerified
                    network_activity_performed = $true
                    target_mutation_attempted = [bool]$mutation.MutationAttempted
                    target_mutation_performed = [bool]$mutation.MutationPerformed
                    error = [string]$mutation.Error
                }

                if ($Operation -eq 'Apply' -and [string]$mutation.Status -in @('APPLIED_VERIFIED', 'ALREADY_LOCKED_VERIFIED')) {
                    $restoreEntries += [pscustomobject][ordered]@{
                        computer_name = $target
                        monitor_index = [int]$mutation.MonitorIndex
                        physical_monitor_description = [string]$mutation.Description
                        original_vcp_ca_value = [uint32]$mutation.OriginalValue
                        original_vcp_ca_hex = [string]$mutation.OriginalHex
                        applied_vcp_ca_value = [uint32]$mutation.FinalValue
                        applied_vcp_ca_hex = [string]$mutation.FinalHex
                    }
                }

                Write-SasDisplayButtonEvent -Path $eventsPath -Event @{
                    event = 'target_mutation_completed'
                    workflow_id = $workflowId
                    computer_name = $target
                    operation = $Operation
                    status = [string]$mutation.Status
                    verification_passed = [bool]$mutation.VerificationPassed
                    rollback_attempted = [bool]$mutation.RollbackAttempted
                    rollback_verified = [bool]$mutation.RollbackVerified
                }
            }
        }
        catch {
            $summaryRows += [pscustomobject][ordered]@{
                computer_name = $target
                operation = $Operation
                status = 'FAILED_REMOTE_EXECUTION'
                eligible_monitor_count = 0
                selected_monitor_index = if ($targetMonitorIndex -ge 0) { $targetMonitorIndex } else { '' }
                original_vcp_ca = ''
                final_vcp_ca = ''
                verification_passed = $false
                rollback_attempted = $false
                rollback_verified = $false
                network_activity_performed = $true
                target_mutation_attempted = ($Operation -in @('Apply', 'Restore'))
                target_mutation_performed = $false
                error = $_.Exception.Message
            }
            Write-SasDisplayButtonEvent -Path $eventsPath -Event @{
                event = 'target_operation_failed'
                workflow_id = $workflowId
                computer_name = $target
                operation = $Operation
                error = $_.Exception.Message
            }
        }
    }
}

$summaryRows | Export-Csv -LiteralPath $resultsPath -NoTypeInformation -Encoding UTF8 -WhatIf:$false
Write-SasDisplayButtonJson -Path $detailsPath -Value @($details)

if ($Operation -eq 'Apply') {
    $restoreDocument = [ordered]@{
        schema_version = 'sas-cybernet-display-button-restore/v1'
        workflow_id = $workflowId
        generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        source_operation = 'Apply'
        applied_vcp_ca_value = 0x0303
        applied_vcp_ca_hex = '0x0303'
        entries = @($restoreEntries)
    }
    Write-SasDisplayButtonJson -Path $restoreOutputPath -Value $restoreDocument
}

$successStatuses = if ($Operation -eq 'Probe') {
    @('PROBE_COMPLETE')
}
elseif ($Operation -eq 'Apply') {
    @('APPLIED_VERIFIED', 'ALREADY_LOCKED_VERIFIED')
}
else {
    @('RESTORED_VERIFIED', 'ALREADY_RESTORED_VERIFIED')
}

$successCount = @($summaryRows | Where-Object { $_.status -in $successStatuses }).Count
$failureCount = @($summaryRows | Where-Object { $_.status -like 'FAILED*' -or $_.status -like 'SET_FAILED*' -or $_.status -like 'VERIFY_FAILED*' }).Count
$refusedCount = @($summaryRows | Where-Object { $_.status -like 'REFUSED*' }).Count
$skippedCount = @($summaryRows | Where-Object { $_.status -like 'SKIPPED*' }).Count
$eligibleTargetCount = @($summaryRows | Where-Object { [int]$_.eligible_monitor_count -gt 0 }).Count
$networkActivity = @($summaryRows | Where-Object { $_.network_activity_performed }).Count -gt 0
$mutationAttempted = @($summaryRows | Where-Object { $_.target_mutation_attempted }).Count -gt 0
$mutationPerformed = @($summaryRows | Where-Object { $_.target_mutation_performed }).Count -gt 0

$summaryStatus = if ($successCount -eq $targets.Count -and $failureCount -eq 0 -and $refusedCount -eq 0 -and $skippedCount -eq 0) {
    'PASS'
}
elseif ($successCount -gt 0) {
    'PARTIAL'
}
else {
    'FAIL'
}

$summary = [ordered]@{
    schema_version = 'sas-cybernet-display-button-summary/v1'
    workflow_id = $workflowId
    status = $summaryStatus
    operation = $Operation
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    target_count = $targets.Count
    success_count = $successCount
    failure_count = $failureCount
    refused_count = $refusedCount
    skipped_count = $skippedCount
    eligible_target_count = $eligibleTargetCount
    desired_vcp_ca_value = if ($Operation -eq 'Apply') { 0x0303 } else { $null }
    desired_vcp_ca_hex = if ($Operation -eq 'Apply') { '0x0303' } else { '' }
    network_activity_performed = [bool]$networkActivity
    target_mutation_attempted = [bool]$mutationAttempted
    target_mutation_performed = [bool]$mutationPerformed
    fixture_mode = [bool]$FixtureMode
    results_path = $resultsPath
    details_path = $detailsPath
    restore_manifest_path = if ($Operation -eq 'Apply') { $restoreOutputPath } else { '' }
    events_path = $eventsPath
}
Write-SasDisplayButtonJson -Path $summaryPath -Value $summary

@(
    "Cybernet display-button control result: $workflowId",
    "Operation: $Operation",
    "Status: $summaryStatus",
    "Targets: $($targets.Count)",
    "Successful: $successCount",
    "Failed: $failureCount",
    "Refused as ineligible: $refusedCount",
    "Skipped: $skippedCount",
    "Eligible targets: $eligibleTargetCount",
    $(if ($Operation -eq 'Apply') { 'Applied value: 0x0303 only after confirmed MCCS 2.2 VCP 0xCA host control.' } else { '' }),
    $(if ($Operation -eq 'Apply') { "Restore manifest: $restoreOutputPath" } else { '' }),
    'A green fixture or CI run does not prove a Cybernet monitor implements this control. Require one authorized hardware pilot.',
    "Summary: $summaryPath",
    "Results: $resultsPath",
    "Details: $detailsPath",
    "Events: $eventsPath"
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Set-Content -LiteralPath $handoffPath -Encoding UTF8 -WhatIf:$false

Write-SasDisplayButtonEvent -Path $eventsPath -Event @{
    event = 'workflow_completed'
    workflow_id = $workflowId
    operation = $Operation
    status = $summaryStatus
    success_count = $successCount
    failure_count = $failureCount
    refused_count = $refusedCount
    skipped_count = $skippedCount
    target_mutation_attempted = [bool]$mutationAttempted
    target_mutation_performed = [bool]$mutationPerformed
}

Write-Host "Cybernet display-button control status: $summaryStatus"
Write-Host "Summary: $summaryPath"
Write-Output ([pscustomobject]$summary)

if ($summaryStatus -eq 'FAIL') { exit 1 }
if ($summaryStatus -eq 'PARTIAL') { exit 2 }
exit 0
