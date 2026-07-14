#Requires -Version 5.1
<#
.SYNOPSIS
Apply the known-good Windows physical power-button hardening to authorized Cybernet workstations.

.DESCRIPTION
This deployment/repair lane changes only the Windows physical power-button action for every parsed power scheme.
It sets AC and DC action index 0 (Do nothing) for the canonical power-button action GUID, verifies the result,
and writes local run evidence under survey/output.

The physical display/menu button is not claimed as fixed. Current repository evidence shows no proven Windows
policy, registry, or event contract for that hardware/OSD button. The result therefore reports
NOT_APPLIED_UNPROVEN and directs the operator to the local DisplayMenuButtonProbe workflow.

-WhatIf validates target intake and writes a local plan without opening a remote session.
-FixtureMode writes synthetic evidence without contacting targets.
Live execution requires -AllowTargetMutation and an approved ShouldProcess confirmation.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string[]]$ComputerName = @(),
    [string]$TargetsCsv,
    [string]$OutputRoot,
    [ValidateRange(1, 25)]
    [int]$MaxTargets = 25,
    [switch]$AllowTargetMutation,
    [switch]$FixtureMode
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasCybernetPowerTargets {
    [CmdletBinding()]
    param(
        [string[]]$DirectTargets,
        [string]$CsvPath,
        [int]$Limit,
        [string]$RepoRoot
    )

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($target in @($DirectTargets)) {
        if (-not [string]::IsNullOrWhiteSpace($target)) {
            $items.Add($target.Trim())
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($CsvPath)) {
        Assert-SasApprovedInputPath -Path $CsvPath -RepoRoot $RepoRoot -Role 'Cybernet power-hardening target CSV' -AllowStaging
        foreach ($row in @(Import-Csv -LiteralPath $CsvPath)) {
            $value = $null
            foreach ($column in @('ComputerName', 'HostName', 'Hostname', 'Target')) {
                if ($row.PSObject.Properties.Name -ccontains $column) {
                    $candidate = [string]$row.$column
                    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                        $value = $candidate.Trim()
                        break
                    }
                }
            }
            if ($value) { $items.Add($value) }
        }
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($target in $items) {
        if ($target -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$') {
            throw "Invalid target name: $target"
        }
        if ($seen.Add($target)) { $targets.Add($target) }
    }

    if ($targets.Count -eq 0) {
        throw 'No explicit targets were supplied. Use -ComputerName or -TargetsCsv.'
    }
    if ($targets.Count -gt $Limit) {
        throw "Target count $($targets.Count) exceeds MaxTargets $Limit. Split the run to keep repair bounded."
    }

    return @($targets)
}

function Write-SasCybernetJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )

    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force -WhatIf:$false | Out-Null
    }
    $Value | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $Path -Encoding UTF8 -WhatIf:$false
}

function Write-SasCybernetEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$Event
    )

    $Event['timestamp_utc'] = (Get-Date).ToUniversalTime().ToString('o')
    $Event | ConvertTo-Json -Depth 16 -Compress |
        Add-Content -LiteralPath $Path -Encoding UTF8 -WhatIf:$false
}

if ($FixtureMode -and $AllowTargetMutation) {
    throw 'FixtureMode is offline and cannot be combined with -AllowTargetMutation.'
}
if (-not $FixtureMode -and -not $WhatIfPreference -and -not $AllowTargetMutation) {
    throw 'Refusing target mutation without -AllowTargetMutation. Use -WhatIf for request-only planning or -FixtureMode for offline proof.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetIntakeModule = Join-Path $PSScriptRoot 'SasTargetIntake.psm1'
if (-not (Test-Path -LiteralPath $targetIntakeModule -PathType Leaf)) {
    throw "Missing target-intake module: $targetIntakeModule"
}
Import-Module -Name $targetIntakeModule -Force

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'survey/output/cybernet_power_hardening'
}
Assert-SasApprovedOutputPath -Path $OutputRoot -RepoRoot $repoRoot -Role 'Cybernet power-hardening output root'

$targets = @(Get-SasCybernetPowerTargets -DirectTargets $ComputerName -CsvPath $TargetsCsv -Limit $MaxTargets -RepoRoot $repoRoot)
$workflowId = 'cybernet-power-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$workflowRoot = Join-Path $OutputRoot $workflowId
$eventsPath = Join-Path $workflowRoot 'cybernet_power_hardening_events.jsonl'
$resultsPath = Join-Path $workflowRoot 'cybernet_power_hardening_results.csv'
$summaryPath = Join-Path $workflowRoot 'cybernet_power_hardening_summary.json'
$handoffPath = Join-Path $workflowRoot 'operator_handoff.txt'

New-Item -ItemType Directory -Path $workflowRoot -Force -WhatIf:$false | Out-Null

Write-SasCybernetEvent -Path $eventsPath -Event @{
    event = 'workflow_started'
    workflow_id = $workflowId
    target_count = $targets.Count
    targets = @($targets)
    what_if = [bool]$WhatIfPreference
    fixture_mode = [bool]$FixtureMode
    physical_power_button_action = 'DO_NOTHING'
    display_menu_button_status = 'NOT_APPLIED_UNPROVEN'
    posture = 'authorized_repair_one_remote_session_per_target_no_staging_local_evidence_only'
}

if ($WhatIfPreference) {
    $summary = [ordered]@{
        schema_version = 'sas-cybernet-power-hardening-summary/v1'
        workflow_id = $workflowId
        status = 'PLANNED_WHATIF'
        generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        target_count = $targets.Count
        targets = @($targets)
        physical_power_button_action = 'PLANNED_DO_NOTHING'
        display_menu_button_status = 'NOT_APPLIED_UNPROVEN'
        display_menu_button_reason = 'No proven Windows policy, registry, firmware, or OSD control contract exists in the repository.'
        network_activity_performed = $false
        target_mutation_performed = $false
        results_path = $resultsPath
        events_path = $eventsPath
    }
    Write-SasCybernetJson -Path $summaryPath -Value $summary
    @(
        "Cybernet power hardening plan: $workflowId",
        "Targets: $($targets.Count)",
        'Physical Windows power button: planned Do nothing for AC and DC on every parsed power scheme.',
        'Physical display/menu button: NOT APPLIED; control path remains unproven.',
        'Next: run one authorized pilot with -AllowTargetMutation and confirmation enabled.'
    ) | Set-Content -LiteralPath $handoffPath -Encoding UTF8 -WhatIf:$false
    Write-Output ([pscustomobject]$summary)
    return
}

$results = New-Object System.Collections.Generic.List[object]

if ($FixtureMode) {
    foreach ($target in $targets) {
        $results.Add([pscustomobject][ordered]@{
            computer_name = $target
            status = 'FIXTURE_PASS'
            scheme_count = 2
            verified_scheme_count = 2
            physical_power_button_action = 'DO_NOTHING'
            display_menu_button_status = 'NOT_APPLIED_UNPROVEN'
            network_activity_performed = $false
            target_mutation_performed = $false
            error = ''
        })
    }
}
else {
    $remoteScript = {
        param([string]$WorkflowId)

        Set-StrictMode -Version 2.0
        $ErrorActionPreference = 'Stop'
        $powerCfg = Join-Path $env:WINDIR 'System32\powercfg.exe'
        $powerButtonAction = '7648efa3-dd9c-4e3e-b566-50f929386280'

        function Invoke-RemotePowerCfg {
            param([string[]]$Arguments)
            $output = & $powerCfg @Arguments 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                throw "powercfg $($Arguments -join ' ') exited $exitCode :: $output"
            }
            return $output
        }

        function Get-ButtonIndexes {
            param([string]$SchemeGuid)
            $text = Invoke-RemotePowerCfg -Arguments @('/query', $SchemeGuid, 'SUB_BUTTONS', $powerButtonAction)
            $ac = $null
            $dc = $null
            if ($text -match 'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)') { $ac = [Convert]::ToInt32($Matches[1], 16) }
            if ($text -match 'Current DC Power Setting Index:\s*0x([0-9a-fA-F]+)') { $dc = [Convert]::ToInt32($Matches[1], 16) }
            return [pscustomobject]@{ ac = $ac; dc = $dc; raw = $text }
        }

        $list = Invoke-RemotePowerCfg -Arguments @('/list')
        $schemes = New-Object System.Collections.Generic.List[object]
        foreach ($line in ($list -split "`r?`n")) {
            if ($line -match 'Power Scheme GUID:\s*([a-fA-F0-9-]{36})\s+\(([^)]*)\)\s*(\*)?') {
                $schemes.Add([pscustomobject]@{
                    guid = $Matches[1]
                    name = $Matches[2]
                    active = ($Matches[3] -eq '*')
                })
            }
        }
        if ($schemes.Count -eq 0) { throw 'No power schemes parsed from powercfg /list.' }

        $settings = New-Object System.Collections.Generic.List[object]
        $errors = New-Object System.Collections.Generic.List[string]
        $activeGuid = $null

        foreach ($scheme in $schemes) {
            if ($scheme.active) { $activeGuid = $scheme.guid }
            try {
                $before = Get-ButtonIndexes -SchemeGuid $scheme.guid
                Invoke-RemotePowerCfg -Arguments @('/setacvalueindex', $scheme.guid, 'SUB_BUTTONS', $powerButtonAction, '0') | Out-Null
                Invoke-RemotePowerCfg -Arguments @('/setdcvalueindex', $scheme.guid, 'SUB_BUTTONS', $powerButtonAction, '0') | Out-Null
                $after = Get-ButtonIndexes -SchemeGuid $scheme.guid
                $verified = ($after.ac -eq 0 -and $after.dc -eq 0)
                if (-not $verified) { $errors.Add("Verification failed for scheme $($scheme.guid)") }
                $settings.Add([pscustomobject][ordered]@{
                    scheme_guid = $scheme.guid
                    scheme_name = $scheme.name
                    before_ac = $before.ac
                    before_dc = $before.dc
                    after_ac = $after.ac
                    after_dc = $after.dc
                    verified = [bool]$verified
                })
            }
            catch {
                $errors.Add("$($scheme.guid) :: $($_.Exception.Message)")
            }
        }

        if ($activeGuid) {
            try { Invoke-RemotePowerCfg -Arguments @('/setactive', $activeGuid) | Out-Null }
            catch { $errors.Add("setactive $activeGuid :: $($_.Exception.Message)") }
        }

        $verifiedCount = @($settings | Where-Object { $_.verified }).Count
        $status = if ($errors.Count -eq 0 -and $verifiedCount -eq $schemes.Count) { 'APPLIED_VERIFIED' }
            elseif ($verifiedCount -gt 0) { 'PARTIAL' }
            else { 'FAILED' }

        [pscustomobject][ordered]@{
            workflow_id = $WorkflowId
            computer_name = $env:COMPUTERNAME
            status = $status
            scheme_count = $schemes.Count
            verified_scheme_count = $verifiedCount
            physical_power_button_action = 'DO_NOTHING'
            display_menu_button_status = 'NOT_APPLIED_UNPROVEN'
            display_menu_button_reason = 'Physical display/menu button may be firmware-only or display-OSD controlled; no Windows mutation attempted.'
            settings = @($settings)
            network_activity_performed = $true
            target_mutation_performed = $true
            errors = @($errors)
        }
    }

    foreach ($target in $targets) {
        if (-not $PSCmdlet.ShouldProcess($target, 'Apply and verify Cybernet Windows physical power-button action = Do nothing')) {
            $results.Add([pscustomobject][ordered]@{
                computer_name = $target
                status = 'SKIPPED_OPERATOR_DECLINED'
                scheme_count = 0
                verified_scheme_count = 0
                physical_power_button_action = 'NOT_APPLIED'
                display_menu_button_status = 'NOT_APPLIED_UNPROVEN'
                network_activity_performed = $false
                target_mutation_performed = $false
                error = 'Operator declined ShouldProcess confirmation.'
            })
            continue
        }

        Write-SasCybernetEvent -Path $eventsPath -Event @{
            event = 'target_mutation_started'
            workflow_id = $workflowId
            computer_name = $target
        }

        try {
            $remote = Invoke-Command -ComputerName $target -ScriptBlock $remoteScript -ArgumentList $workflowId -ErrorAction Stop
            $errorText = @($remote.errors) -join '; '
            $results.Add([pscustomobject][ordered]@{
                computer_name = $target
                status = [string]$remote.status
                scheme_count = [int]$remote.scheme_count
                verified_scheme_count = [int]$remote.verified_scheme_count
                physical_power_button_action = [string]$remote.physical_power_button_action
                display_menu_button_status = [string]$remote.display_menu_button_status
                network_activity_performed = [bool]$remote.network_activity_performed
                target_mutation_performed = [bool]$remote.target_mutation_performed
                error = $errorText
            })
            Write-SasCybernetEvent -Path $eventsPath -Event @{
                event = 'target_mutation_completed'
                workflow_id = $workflowId
                computer_name = $target
                status = [string]$remote.status
                verified_scheme_count = [int]$remote.verified_scheme_count
                display_menu_button_status = [string]$remote.display_menu_button_status
            }
        }
        catch {
            $results.Add([pscustomobject][ordered]@{
                computer_name = $target
                status = 'FAILED_REMOTE_EXECUTION'
                scheme_count = 0
                verified_scheme_count = 0
                physical_power_button_action = 'UNKNOWN'
                display_menu_button_status = 'NOT_APPLIED_UNPROVEN'
                network_activity_performed = $true
                target_mutation_performed = $false
                error = $_.Exception.Message
            })
            Write-SasCybernetEvent -Path $eventsPath -Event @{
                event = 'target_mutation_failed'
                workflow_id = $workflowId
                computer_name = $target
                error = $_.Exception.Message
            }
        }
    }
}

@($results) | Export-Csv -LiteralPath $resultsPath -NoTypeInformation -Encoding UTF8 -WhatIf:$false

$appliedCount = @($results | Where-Object { $_.status -in @('APPLIED_VERIFIED', 'FIXTURE_PASS') }).Count
$partialCount = @($results | Where-Object { $_.status -eq 'PARTIAL' }).Count
$failedCount = @($results | Where-Object { $_.status -like 'FAILED*' }).Count
$skippedCount = @($results | Where-Object { $_.status -like 'SKIPPED*' }).Count
$summaryStatus = if ($failedCount -eq 0 -and $partialCount -eq 0 -and $skippedCount -eq 0 -and $appliedCount -eq $targets.Count) { 'PASS' }
    elseif ($appliedCount -gt 0) { 'PARTIAL' }
    else { 'FAIL' }

$summary = [ordered]@{
    schema_version = 'sas-cybernet-power-hardening-summary/v1'
    workflow_id = $workflowId
    status = $summaryStatus
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    target_count = $targets.Count
    applied_verified_count = $appliedCount
    partial_count = $partialCount
    failed_count = $failedCount
    skipped_count = $skippedCount
    fixture_mode = [bool]$FixtureMode
    physical_power_button_action = 'DO_NOTHING'
    display_menu_button_status = 'NOT_APPLIED_UNPROVEN'
    display_menu_button_reason = 'No proven Windows-controllable contract exists. Use the local DisplayMenuButtonProbe before designing a firmware or OSD-specific fix.'
    network_activity_performed = [bool](-not $FixtureMode)
    target_mutation_performed = [bool](-not $FixtureMode -and $appliedCount -gt 0)
    results_path = $resultsPath
    events_path = $eventsPath
}
Write-SasCybernetJson -Path $summaryPath -Value $summary

@(
    "Cybernet power hardening result: $workflowId",
    "Status: $summaryStatus",
    "Targets: $($targets.Count)",
    "Applied and verified: $appliedCount",
    "Partial: $partialCount",
    "Failed: $failedCount",
    "Skipped: $skippedCount",
    'Physical Windows power button: configured to Do nothing for AC and DC on every verified power scheme.',
    'Physical display/menu button: NOT APPLIED / UNPROVEN. Do not claim this button is disabled.',
    'Run QRTasks\Test-DisplayMenuButtonEvent.ps1 locally on one representative Cybernet before any firmware or OSD-specific sprint.',
    "Summary: $summaryPath",
    "Results: $resultsPath",
    "Events: $eventsPath"
) | Set-Content -LiteralPath $handoffPath -Encoding UTF8 -WhatIf:$false

Write-SasCybernetEvent -Path $eventsPath -Event @{
    event = 'workflow_completed'
    workflow_id = $workflowId
    status = $summaryStatus
    applied_verified_count = $appliedCount
    partial_count = $partialCount
    failed_count = $failedCount
    skipped_count = $skippedCount
    display_menu_button_status = 'NOT_APPLIED_UNPROVEN'
}

Write-Host "Cybernet power hardening status: $summaryStatus"
Write-Host "Summary: $summaryPath"
Write-Output ([pscustomobject]$summary)

if ($summaryStatus -eq 'FAIL') { exit 1 }
if ($summaryStatus -eq 'PARTIAL') { exit 2 }
exit 0
