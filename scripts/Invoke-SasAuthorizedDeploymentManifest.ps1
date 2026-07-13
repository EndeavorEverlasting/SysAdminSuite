#Requires -Version 5.1
<#
.SYNOPSIS
Runs a bounded authorized-deployment manifest through Invoke-SasSoftwareInstall.ps1.

.DESCRIPTION
The adapter validates a JSON manifest, approved share roots, SHA-256, and request references before
delegating to the canonical installer. It does not depend on an interactive desktop logon or Public
Startup, and it creates no service, task, Run key, startup entry, or other persistence.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [string]$OutputRoot,
    [string]$SingleHost,
    [ValidateRange(1, 25)][int]$MaxTargets = 25,
    [ValidateRange(1, 100)][int]$MaxRows = 100,
    [switch]$AllowTargetMutation
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not $AllowTargetMutation -and -not $WhatIfPreference) {
    throw 'Refusing target mutation without -AllowTargetMutation. Use -WhatIf for request-only validation.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$softwareInstallScript = Join-Path $PSScriptRoot 'Invoke-SasSoftwareInstall.ps1'
$apiManifestPath = Join-Path $repoRoot 'harness/api/sas-harness-api.json'
Import-Module (Join-Path $PSScriptRoot 'SasTargetIntake.psm1') -Force

foreach ($requiredPath in @($softwareInstallScript, $apiManifestPath, $ManifestPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required deployment file not found: $requiredPath"
    }
}
if ([System.IO.Path]::GetExtension($ManifestPath) -ne '.json') {
    throw 'Authorized deployment manifests must be JSON so InstallerArguments remains an explicit string array.'
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'survey/output/authorized_app_deployment'
}
Assert-SasApprovedOutputPath -Path $OutputRoot -RepoRoot $repoRoot -Role 'authorized deployment manifest output directory'

function Normalize-SasManifestUncRoot {
    param([Parameter(Mandatory = $true)][string]$Path)
    $normalized = $Path.Trim().Replace('/', '\')
    if ($normalized -notmatch '^\\\\[^\\]+\\?$') {
        throw "SoftwareShareRoot must be a server-root UNC path such as \\server\. Received: $Path"
    }
    return "$($normalized.TrimEnd('\'))\"
}

function Get-SasManifestApprovedRoots {
    $api = Get-Content -LiteralPath $apiManifestPath -Raw | ConvertFrom-Json
    $roots = @($api.posture.approved_software_sources | ForEach-Object {
        Normalize-SasManifestUncRoot ([string]$_)
    } | Sort-Object -Unique)
    if ($roots.Count -eq 0) {
        throw 'Harness API manifest does not declare approved_software_sources.'
    }
    return $roots
}

function Resolve-SasManifestInstallerPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string[]]$ApprovedRoots
    )
    $normalizedRoot = Normalize-SasManifestUncRoot $Root
    $approved = @($ApprovedRoots | Where-Object {
        $normalizedRoot.Equals((Normalize-SasManifestUncRoot $_), [System.StringComparison]::OrdinalIgnoreCase)
    }).Count -gt 0
    if (-not $approved) {
        throw "SoftwareShareRoot is not an approved software source: $normalizedRoot"
    }

    $relative = $RelativePath.Trim().Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($relative) -or
        [System.IO.Path]::IsPathRooted($relative) -or
        $relative.StartsWith('\')) {
        throw 'InstallerRelativePath must be relative to the approved software source.'
    }
    if ($relative -match '(^|\\)\.\.(\\|$)') {
        throw 'InstallerRelativePath cannot contain parent-directory traversal.'
    }
    return "$normalizedRoot$relative"
}

function Get-SasManifestText {
    param([object]$Row, [string]$Name, [int]$RowNumber)
    if (-not ($Row.PSObject.Properties.Name -contains $Name) -or
        [string]::IsNullOrWhiteSpace([string]$Row.$Name)) {
        throw "Manifest row $RowNumber has a missing or blank '$Name'."
    }
    return ([string]$Row.$Name).Trim()
}

function Get-SasManifestArguments {
    param([object]$Value, [int]$RowNumber)
    if ($Value -is [string]) {
        throw "Manifest row $RowNumber InstallerArguments must be a JSON string array, not one command-line string."
    }
    $values = @($Value | ForEach-Object { [string]$_ })
    if ($values.Count -eq 0 -or @($values | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        throw "Manifest row $RowNumber InstallerArguments must contain nonblank strings."
    }
    return $values
}

$rawRows = @(Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json)
if ($rawRows.Count -eq 0) { throw 'Deployment manifest contains no rows.' }
if ($rawRows.Count -gt $MaxRows) {
    throw "Manifest row count $($rawRows.Count) exceeds MaxRows $MaxRows."
}

$approvedRoots = @(Get-SasManifestApprovedRoots)
$rows = New-Object System.Collections.Generic.List[object]
$index = 0

foreach ($raw in $rawRows) {
    $index++
    $target = Get-SasManifestText $raw 'TargetHostname' $index
    if ($target -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$') {
        throw "Manifest row $index has an invalid TargetHostname."
    }
    if ($SingleHost -and $target -ine $SingleHost.Trim()) { continue }

    $mode = Get-SasManifestText $raw 'InstallMode' $index
    if ($mode -ne 'UncDirect') {
        throw "Manifest row $index requests CopyThenInstall, but the canonical engine does not yet prove staged-file SHA-256 verification before execution. Use UncDirect or land verified staging first."
    }

    $sha256 = Get-SasManifestText $raw 'ExpectedSha256' $index
    if ($sha256 -notmatch '^[A-Fa-f0-9]{64}$') {
        throw "Manifest row $index ExpectedSha256 must be 64 hexadecimal characters."
    }
    if (-not ($raw.PSObject.Properties.Name -contains 'InstallerArguments')) {
        throw "Manifest row $index is missing InstallerArguments."
    }

    $root = Get-SasManifestText $raw 'SoftwareShareRoot' $index
    $relative = Get-SasManifestText $raw 'InstallerRelativePath' $index
    $rows.Add([pscustomobject]@{
        manifest_row = $index
        target_hostname = $target
        package_name = Get-SasManifestText $raw 'PackageName' $index
        software_share_root = Normalize-SasManifestUncRoot $root
        installer_relative_path = $relative
        source_path = Resolve-SasManifestInstallerPath $root $relative $approvedRoots
        expected_sha256 = $sha256.ToLowerInvariant()
        installer_arguments = @(Get-SasManifestArguments $raw.InstallerArguments $index)
        install_mode = $mode
        owner = Get-SasManifestText $raw 'Owner' $index
        request_reference = Get-SasManifestText $raw 'RequestReference' $index
        change_reference = Get-SasManifestText $raw 'ChangeReference' $index
        ticket_reference = Get-SasManifestText $raw 'TicketReference' $index
    })
}

if ($rows.Count -eq 0) { throw 'No manifest rows remain after applying SingleHost.' }
$targets = @($rows | ForEach-Object target_hostname | Sort-Object -Unique)
if ($targets.Count -gt $MaxTargets) {
    throw "Unique target count $($targets.Count) exceeds MaxTargets $MaxTargets. Split the manifest."
}

$runId = 'authorized-deployment-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runRoot = Join-Path $OutputRoot $runId
$childOutputRoot = Join-Path $runRoot 'software_install'
New-Item -ItemType Directory -Path $runRoot -Force -WhatIf:$false | Out-Null
$results = New-Object System.Collections.Generic.List[object]

foreach ($row in $rows) {
    $record = [ordered]@{
        manifest_row = $row.manifest_row
        target_hostname = $row.target_hostname
        package_name = $row.package_name
        owner = $row.owner
        request_reference = $row.request_reference
        change_reference = $row.change_reference
        ticket_reference = $row.ticket_reference
        expected_sha256 = $row.expected_sha256
        actual_sha256 = $null
        hash_status = $(if ($WhatIfPreference) { 'not_checked_whatif' } else { 'pending' })
        status = 'pending'
        mutation_attempted = $false
        child_run_id = $null
        child_summary_path = $null
        error = $null
    }

    try {
        if (-not $WhatIfPreference) {
            if (-not (Test-Path -LiteralPath $row.source_path -PathType Leaf)) {
                throw "Installer not found under approved software source: $($row.source_path)"
            }
            $record.actual_sha256 = (Get-FileHash -LiteralPath $row.source_path -Algorithm SHA256).Hash.ToLowerInvariant()
            $record.hash_status = $(if ($record.actual_sha256 -eq $row.expected_sha256) { 'match' } else { 'mismatch' })
            if ($record.hash_status -ne 'match') {
                throw "HASH_MISMATCH expected $($row.expected_sha256) actual $($record.actual_sha256)"
            }
        }

        $invokeParameters = @{
            ComputerName = @($row.target_hostname)
            PackageName = $row.package_name
            InstallerRelativePath = $row.installer_relative_path
            SoftwareShareRoot = $row.software_share_root
            InstallerArguments = @($row.installer_arguments)
            InstallMode = 'UncDirect'
            OutputRoot = $childOutputRoot
            MaxTargets = 1
        }

        if ($WhatIfPreference) {
            $child = & $softwareInstallScript @invokeParameters -WhatIf
        }
        elseif ($PSCmdlet.ShouldProcess($row.target_hostname, "Install '$($row.package_name)' after SHA-256 verification")) {
            $record.mutation_attempted = $true
            $child = & $softwareInstallScript @invokeParameters -AllowTargetMutation -Confirm:$false
        }
        else {
            $record.status = 'skipped_by_shouldprocess'
            $results.Add([pscustomobject]$record)
            continue
        }

        $record.child_run_id = $child.run_id
        $record.child_summary_path = Join-Path $childOutputRoot "$($child.run_id)\software_install_summary.json"
        $record.status = $(if ($WhatIfPreference) { 'planned_whatif' } elseif ($child.failed_count -eq 0) { 'completed' } else { 'child_reported_failure' })
    }
    catch {
        $record.status = 'failed'
        $record.error = $_.Exception.Message
    }
    $results.Add([pscustomobject]$record)
}

$summaryPath = Join-Path $runRoot 'authorized_deployment_summary.json'
$handoffPath = Join-Path $runRoot 'operator_handoff.txt'
$summary = [ordered]@{
    schema_version = 'sas-authorized-deployment-manifest-summary/v1'
    run_id = $runId
    manifest_path = $ManifestPath
    target_count = $targets.Count
    row_count = $rows.Count
    completed_count = @($results | Where-Object status -eq 'completed').Count
    planned_count = @($results | Where-Object status -eq 'planned_whatif').Count
    failed_count = @($results | Where-Object status -in @('failed', 'child_reported_failure')).Count
    interactive_logon_required = $false
    public_startup_folder_used = $false
    service_created = $false
    scheduled_task_created = $false
    target_mutation_authorized = [bool]$AllowTargetMutation
    target_mutation_performed = (@($results | Where-Object mutation_attempted).Count -gt 0)
    default_password_value_collected = $false
    results = $results.ToArray()
    guardrails = @(
        'canonical_software_install_engine_only',
        'approved_software_source_only',
        'sha256_verified_before_target_mutation',
        'unc_direct_only_until_remote_staged_hash_verification',
        'maximum_25_unique_targets',
        'no_interactive_logon_dependency',
        'no_service_or_scheduled_task_persistence',
        'no_startup_folder_or_run_key',
        'no_credential_collection',
        'no_monitoring_bypass_or_log_suppression',
        'local_gitignored_evidence_only'
    )
}

$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding UTF8 -WhatIf:$false
@(
    'SysAdminSuite authorized deployment manifest handoff',
    "Run ID: $runId",
    "Targets: $($summary.target_count)",
    "Rows: $($summary.row_count)",
    "Completed: $($summary.completed_count)",
    "Planned/WhatIf: $($summary.planned_count)",
    "Failed or unresolved: $($summary.failed_count)",
    "Interactive logon required: $($summary.interactive_logon_required)",
    "Service created: $($summary.service_created)",
    "Scheduled task created: $($summary.scheduled_task_created)",
    "Summary: $summaryPath",
    '',
    'Review every child software-install summary before expanding the batch.'
) | Set-Content -LiteralPath $handoffPath -Encoding UTF8 -WhatIf:$false

Write-Output $summary
