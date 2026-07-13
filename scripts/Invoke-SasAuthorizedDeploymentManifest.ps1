#Requires -Version 5.1
<#
.SYNOPSIS
Runs an authorized application-deployment manifest through the canonical SysAdminSuite software-install engine.

.DESCRIPTION
This is the recovered PR #150 manifest layer. It validates a bounded JSON manifest, verifies approved
software-source roots, optionally verifies SHA-256 before mutation, and delegates every install to
Invoke-SasSoftwareInstall.ps1.

The delegated install runs through PowerShell remoting and therefore does not depend on an interactive
desktop logon or the Public Startup folder. This wrapper does not create a service, scheduled task,
Run key, startup-folder entry, or any other persistence.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [string]$SingleHost,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 25)]
    [int]$MaxTargets = 25,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$MaxRows = 100,

    [Parameter(Mandatory = $false)]
    [switch]$AllowTargetMutation
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not $AllowTargetMutation -and -not $WhatIfPreference) {
    throw 'Refusing target mutation without -AllowTargetMutation. Use -WhatIf for request-only validation.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetIntakeModule = Join-Path -Path $PSScriptRoot -ChildPath 'SasTargetIntake.psm1'
$softwareInstallScript = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-SasSoftwareInstall.ps1'
$apiManifestPath = Join-Path -Path $repoRoot -ChildPath 'harness/api/sas-harness-api.json'

Import-Module -Name $targetIntakeModule -Force

if (-not (Test-Path -LiteralPath $softwareInstallScript -PathType Leaf)) {
    throw "Canonical software-install engine not found: $softwareInstallScript"
}
if (-not (Test-Path -LiteralPath $apiManifestPath -PathType Leaf)) {
    throw "Harness API manifest not found: $apiManifestPath"
}
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Deployment manifest not found: $ManifestPath"
}
if ([System.IO.Path]::GetExtension($ManifestPath) -ne '.json') {
    throw 'Authorized deployment manifests must be JSON so installer arguments remain an explicit string array.'
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path -Path $repoRoot -ChildPath 'survey/output/authorized_app_deployment'
}
Assert-SasApprovedOutputPath -Path $OutputRoot -RepoRoot $repoRoot -Role 'authorized deployment manifest output directory'

function Normalize-SasManifestUncRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $normalized = $Path.Trim().Replace('/', '\')
    if ($normalized -notmatch '^\\\\[^\\]+\\?$') {
        throw "SoftwareShareRoot must be a server-root UNC path such as \\server\. Received: $Path"
    }

    return "$($normalized.TrimEnd('\'))\"
}

function Get-SasManifestApprovedRoots {
    [CmdletBinding()]
    param()

    $api = Get-Content -LiteralPath $apiManifestPath -Raw | ConvertFrom-Json
    $roots = @($api.posture.approved_software_sources | ForEach-Object {
        Normalize-SasManifestUncRoot -Path ([string]$_)
    } | Sort-Object -Unique)

    if ($roots.Count -eq 0) {
        throw 'Harness API manifest does not declare any approved software source roots.'
    }

    return $roots
}

function Resolve-SasManifestInstallerPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string[]]$ApprovedRoots
    )

    $normalizedRoot = Normalize-SasManifestUncRoot -Path $Root
    $approved = @($ApprovedRoots | Where-Object {
        $normalizedRoot.Equals((Normalize-SasManifestUncRoot -Path $_), [System.StringComparison]::OrdinalIgnoreCase)
    }).Count -gt 0

    if (-not $approved) {
        throw "SoftwareShareRoot is not an approved software source: $normalizedRoot"
    }

    $normalizedRelative = $RelativePath.Trim().Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($normalizedRelative) -or
        [System.IO.Path]::IsPathRooted($normalizedRelative) -or
        $normalizedRelative.StartsWith('\')) {
        throw 'InstallerRelativePath must be relative to the approved software source root.'
    }
    if ($normalizedRelative -match '(^|\\)\.\.(\\|$)') {
        throw 'InstallerRelativePath cannot contain parent-directory traversal.'
    }

    return "$normalizedRoot$normalizedRelative"
}

function Get-SasRequiredManifestText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Row,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [int]$RowNumber
    )

    if (-not ($Row.PSObject.Properties.Name -contains $Name)) {
        throw "Manifest row $RowNumber is missing required field '$Name'."
    }

    $value = [string]$Row.$Name
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Manifest row $RowNumber has a blank required field '$Name'."
    }

    return $value.Trim()
}

function ConvertTo-SasManifestArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [int]$RowNumber
    )

    if ($Value -is [string]) {
        throw "Manifest row $RowNumber field 'InstallerArguments' must be a JSON string array, not one command-line string."
    }

    $arguments = @($Value | ForEach-Object { [string]$_ })
    if ($arguments.Count -eq 0 -or @($arguments | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        throw "Manifest row $RowNumber field 'InstallerArguments' must contain one or more nonblank strings."
    }

    return $arguments
}

$rawRows = @(Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json)
if ($rawRows.Count -eq 0) {
    throw 'Deployment manifest contains no rows.'
}
if ($rawRows.Count -gt $MaxRows) {
    throw "Manifest row count $($rawRows.Count) exceeds MaxRows $MaxRows."
}

$approvedRoots = @(Get-SasManifestApprovedRoots)
$validatedRows = New-Object System.Collections.Generic.List[object]
$rowNumber = 0

foreach ($row in $rawRows) {
    $rowNumber++

    $targetHostname = Get-SasRequiredManifestText -Row $row -Name 'TargetHostname' -RowNumber $rowNumber
    if ($targetHostname -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$') {
        throw "Manifest row $rowNumber has an invalid TargetHostname."
    }
    if (-not [string]::IsNullOrWhiteSpace($SingleHost) -and $targetHostname -ine $SingleHost.Trim()) {
        continue
    }

    $packageName = Get-SasRequiredManifestText -Row $row -Name 'PackageName' -RowNumber $rowNumber
    $softwareShareRoot = Get-SasRequiredManifestText -Row $row -Name 'SoftwareShareRoot' -RowNumber $rowNumber
    $installerRelativePath = Get-SasRequiredManifestText -Row $row -Name 'InstallerRelativePath' -RowNumber $rowNumber
    $expectedSha256 = Get-SasRequiredManifestText -Row $row -Name 'ExpectedSha256' -RowNumber $rowNumber
    $owner = Get-SasRequiredManifestText -Row $row -Name 'Owner' -RowNumber $rowNumber
    $requestReference = Get-SasRequiredManifestText -Row $row -Name 'RequestReference' -RowNumber $rowNumber
    $changeReference = Get-SasRequiredManifestText -Row $row -Name 'ChangeReference' -RowNumber $rowNumber
    $ticketReference = Get-SasRequiredManifestText -Row $row -Name 'TicketReference' -RowNumber $rowNumber
    $installMode = Get-SasRequiredManifestText -Row $row -Name 'InstallMode' -RowNumber $rowNumber

    if ($expectedSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
        throw "Manifest row $rowNumber field 'ExpectedSha256' must be a 64-character hexadecimal SHA-256."
    }
    if ($installMode -notin @('UncDirect', 'CopyThenInstall')) {
        throw "Manifest row $rowNumber field 'InstallMode' must be UncDirect or CopyThenInstall."
    }
    if (-not ($row.PSObject.Properties.Name -contains 'InstallerArguments')) {
        throw "Manifest row $rowNumber is missing required field 'InstallerArguments'."
    }

    $arguments = @(ConvertTo-SasManifestArguments -Value $row.InstallerArguments -RowNumber $rowNumber)
    $sourcePath = Resolve-SasManifestInstallerPath `
        -Root $softwareShareRoot `
        -RelativePath $installerRelativePath `
        -ApprovedRoots $approvedRoots

    $validatedRows.Add([pscustomobject]@{
        manifest_row = $rowNumber
        target_hostname = $targetHostname
        package_name = $packageName
        software_share_root = (Normalize-SasManifestUncRoot -Path $softwareShareRoot)
        installer_relative_path = $installerRelativePath
        source_path = $sourcePath
        expected_sha256 = $expectedSha256.ToLowerInvariant()
        installer_arguments = $arguments
        install_mode = $installMode
        owner = $owner
        request_reference = $requestReference
        change_reference = $changeReference
        ticket_reference = $ticketReference
    })
}

if ($validatedRows.Count -eq 0) {
    throw 'No manifest rows remain after applying SingleHost.'
}

$targets = @($validatedRows | ForEach-Object { $_.target_hostname } | Sort-Object -Unique)
if ($targets.Count -gt $MaxTargets) {
    throw "Unique target count $($targets.Count) exceeds MaxTargets $MaxTargets. Split the manifest."
}

$runId = 'authorized-deployment-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runRoot = Join-Path -Path $OutputRoot -ChildPath $runId
$childOutputRoot = Join-Path -Path $runRoot -ChildPath 'software_install'
New-Item -ItemType Directory -Path $runRoot -Force -WhatIf:$false | Out-Null

$results = New-Object System.Collections.Generic.List[object]

foreach ($row in $validatedRows) {
    $result = [ordered]@{
        manifest_row = $row.manifest_row
        target_hostname = $row.target_hostname
        package_name = $row.package_name
        owner = $row.owner
        request_reference = $row.request_reference
        change_reference = $row.change_reference
        ticket_reference = $row.ticket_reference
        install_mode = $row.install_mode
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

            $actualHash = (Get-FileHash -LiteralPath $row.source_path -Algorithm SHA256).Hash.ToLowerInvariant()
            $result.actual_sha256 = $actualHash
            $result.hash_status = $(if ($actualHash -eq $row.expected_sha256) { 'match' } else { 'mismatch' })
            if ($result.hash_status -ne 'match') {
                throw "HASH_MISMATCH expected $($row.expected_sha256) actual $actualHash"
            }
        }

        $invokeParameters = @{
            ComputerName = @($row.target_hostname)
            PackageName = $row.package_name
            InstallerRelativePath = $row.installer_relative_path
            SoftwareShareRoot = $row.software_share_root
            InstallerArguments = @($row.installer_arguments)
            InstallMode = $row.install_mode
            OutputRoot = $childOutputRoot
            MaxTargets = 1
        }

        if ($WhatIfPreference) {
            $childSummary = & $softwareInstallScript @invokeParameters -WhatIf
        }
        elseif ($PSCmdlet.ShouldProcess(
            $row.target_hostname,
            "Install '$($row.package_name)' from approved source after SHA-256 verification"
        )) {
            $result.mutation_attempted = $true
            $childSummary = & $softwareInstallScript @invokeParameters -AllowTargetMutation -Confirm:$false
        }
        else {
            $result.status = 'skipped_by_shouldprocess'
            $results.Add([pscustomobject]$result)
            continue
        }

        $result.child_run_id = $childSummary.run_id
        $result.child_summary_path = Join-Path -Path $childOutputRoot -ChildPath "$($childSummary.run_id)\software_install_summary.json"
        $result.status = $(if ($WhatIfPreference) { 'planned_whatif' } elseif ($childSummary.failed_count -eq 0) { 'completed' } else { 'child_reported_failure' })
    }
    catch {
        $result.status = 'failed'
        $result.error = $_.Exception.Message
    }

    $results.Add([pscustomobject]$result)
}

$summaryPath = Join-Path -Path $runRoot -ChildPath 'authorized_deployment_summary.json'
$handoffPath = Join-Path -Path $runRoot -ChildPath 'operator_handoff.txt'
$summary = [ordered]@{
    schema_version = 'sas-authorized-deployment-manifest-summary/v1'
    run_id = $runId
    manifest_path = $ManifestPath
    target_count = $targets.Count
    row_count = $validatedRows.Count
    completed_count = @($results | Where-Object { $_.status -eq 'completed' }).Count
    planned_count = @($results | Where-Object { $_.status -eq 'planned_whatif' }).Count
    failed_count = @($results | Where-Object { $_.status -in @('failed', 'child_reported_failure') }).Count
    interactive_logon_required = $false
    public_startup_folder_used = $false
    service_created = $false
    scheduled_task_created = $false
    target_mutation_authorized = [bool]$AllowTargetMutation
    target_mutation_performed = (@($results | Where-Object { $_.mutation_attempted }).Count -gt 0)
    default_password_value_collected = $false
    results = $results.ToArray()
    guardrails = @(
        'canonical_software_install_engine_only',
        'approved_software_source_only',
        'sha256_verified_before_target_mutation',
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
    "Manifest: $ManifestPath",
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
    'Review every child software-install summary and cleanup result before expanding the batch.'
) | Set-Content -LiteralPath $handoffPath -Encoding UTF8 -WhatIf:$false

Write-Output $summary
