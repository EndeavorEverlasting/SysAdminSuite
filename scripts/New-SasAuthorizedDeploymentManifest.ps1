#Requires -Version 5.1
<#
.SYNOPSIS
Builds a bounded authorized-deployment manifest from verified package evidence.

.DESCRIPTION
Reads one approved package from the canonical software share, computes its SHA-256, captures
Authenticode and version metadata, and writes a local deployment manifest plus package-intake
evidence. It never contacts target workstations or creates services, tasks, startup entries,
credentials, or target-side artifacts.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$ComputerName = @(),

    [Parameter(Mandatory = $false)]
    [string]$TargetsCsv,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PackageName,

    [Parameter(Mandatory = $false)]
    [string]$SoftwareShareRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InstallerRelativePath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$InstallerArguments,

    [Parameter(Mandatory = $false)]
    [ValidateSet('UncDirect')]
    [string]$InstallMode = 'UncDirect',

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Owner,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RequestReference,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ChangeReference,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TicketReference,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InstallerArgumentsReference,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 25)]
    [int]$MaxTargets = 25,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [switch]$RequireValidSignature,

    [Parameter(Mandatory = $false)]
    [switch]$FixtureMode,

    [Parameter(Mandatory = $false)]
    [string]$FixturePackagePath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$apiManifestPath = Join-Path $repoRoot 'harness/api/sas-harness-api.json'
$targetIntakeModule = Join-Path $PSScriptRoot 'SasTargetIntake.psm1'
Import-Module $targetIntakeModule -Force

if (-not (Test-Path -LiteralPath $apiManifestPath -PathType Leaf)) {
    throw "Harness API manifest not found: $apiManifestPath"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'survey/output/authorized_package_intake'
}
Assert-SasApprovedOutputPath -Path $OutputRoot -RepoRoot $repoRoot -Role 'authorized package intake output directory'

function Normalize-SasPackageRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $normalized = $Path.Trim().Replace('/', '\')
    if ($normalized -notmatch '^\\\\[^\\]+\\?$') {
        throw "SoftwareShareRoot must be a server-root UNC path such as \\server\. Received: $Path"
    }
    return "$($normalized.TrimEnd('\'))\"
}

function Get-SasApprovedPackageRoots {
    [CmdletBinding()]
    param()

    $api = Get-Content -LiteralPath $apiManifestPath -Raw | ConvertFrom-Json
    $roots = @($api.posture.approved_software_sources | ForEach-Object {
        Normalize-SasPackageRoot -Path ([string]$_)
    } | Sort-Object -Unique)
    if ($roots.Count -eq 0) {
        throw 'Harness API manifest does not declare approved_software_sources.'
    }
    return $roots
}

function Resolve-SasPackagePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string[]]$ApprovedRoots
    )

    $normalizedRoot = Normalize-SasPackageRoot -Path $Root
    $approved = @($ApprovedRoots | Where-Object {
        $normalizedRoot.Equals((Normalize-SasPackageRoot -Path $_), [System.StringComparison]::OrdinalIgnoreCase)
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

function Get-SasPackageTargets {
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
        Assert-SasApprovedInputPath -Path $CsvPath -RepoRoot $repoRoot -Role 'authorized deployment target CSV'
        foreach ($row in @(Import-Csv -LiteralPath $CsvPath)) {
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
            if ($value) { $targets.Add($value) }
        }
    }

    $deduped = @($targets | Sort-Object -Unique)
    if ($deduped.Count -eq 0) {
        throw 'No targets were supplied. Use -ComputerName or an approved -TargetsCsv.'
    }
    if ($deduped.Count -gt $Limit) {
        throw "Unique target count $($deduped.Count) exceeds MaxTargets $Limit. Split the manifest."
    }
    foreach ($target in $deduped) {
        if ($target -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$') {
            throw "Invalid target hostname: $target"
        }
    }
    return $deduped
}

foreach ($argument in $InstallerArguments) {
    if ([string]::IsNullOrWhiteSpace($argument)) {
        throw 'InstallerArguments must contain only nonblank strings.'
    }
}

$approvedRoots = @(Get-SasApprovedPackageRoots)
if ([string]::IsNullOrWhiteSpace($SoftwareShareRoot)) {
    $SoftwareShareRoot = $approvedRoots[0]
}
$normalizedRoot = Normalize-SasPackageRoot -Path $SoftwareShareRoot
$sourcePath = Resolve-SasPackagePath -Root $normalizedRoot -RelativePath $InstallerRelativePath -ApprovedRoots $approvedRoots
$targets = @(Get-SasPackageTargets -DirectTargets $ComputerName -CsvPath $TargetsCsv -Limit $MaxTargets)

if ($FixtureMode) {
    if ([string]::IsNullOrWhiteSpace($FixturePackagePath)) {
        $FixturePackagePath = Join-Path $repoRoot 'Tests/fixtures/deployment/authorized-package-intake.fixture.txt'
    }
    if (-not (Test-Path -LiteralPath $FixturePackagePath -PathType Leaf)) {
        throw "Fixture package not found: $FixturePackagePath"
    }
    $packageReadPath = (Resolve-Path -LiteralPath $FixturePackagePath).Path
    $sourceKind = 'synthetic_fixture'
    $networkActivityPerformed = $false
}
else {
    $packageReadPath = $sourcePath
    $sourceKind = 'approved_unc_package'
    $networkActivityPerformed = $true
}

$plan = [ordered]@{
    schema_version = 'sas-authorized-package-intake-plan/v1'
    package_name = $PackageName
    source_path = $sourcePath
    source_kind = $sourceKind
    install_mode = $InstallMode
    target_count = $targets.Count
    targets = $targets
    output_root = $OutputRoot
    package_share_contact_planned = (-not $FixtureMode)
    target_contact_planned = $false
    target_mutation_planned = $false
    service_created = $false
    scheduled_task_created = $false
    public_startup_folder_used = $false
}

if ($WhatIfPreference) {
    $plan.status = 'planned_whatif'
    $plan.package_share_contact_performed = $false
    $plan.files_written = $false
    Write-Output ([pscustomobject]$plan)
    return
}

if (-not (Test-Path -LiteralPath $packageReadPath -PathType Leaf)) {
    throw "Package not found: $packageReadPath"
}

$hash = (Get-FileHash -LiteralPath $packageReadPath -Algorithm SHA256).Hash.ToLowerInvariant()
$item = Get-Item -LiteralPath $packageReadPath
$signatureStatus = 'NotCheckedFixture'
$signerSubject = $null
$signerThumbprint = $null
if (-not $FixtureMode) {
    $signature = Get-AuthenticodeSignature -FilePath $packageReadPath
    $signatureStatus = [string]$signature.Status
    if ($signature.SignerCertificate) {
        $signerSubject = [string]$signature.SignerCertificate.Subject
        $signerThumbprint = [string]$signature.SignerCertificate.Thumbprint
    }
}
if ($RequireValidSignature -and $signatureStatus -ne 'Valid') {
    throw "Package signature is not Valid. Status: $signatureStatus"
}

$runId = 'authorized-package-intake-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runRoot = Join-Path $OutputRoot $runId
$manifestPath = Join-Path $runRoot 'authorized-deployment-manifest.json'
$summaryPath = Join-Path $runRoot 'package-intake-summary.json'
$handoffPath = Join-Path $runRoot 'operator_handoff.txt'

if (-not $PSCmdlet.ShouldProcess($runRoot, 'Write verified package intake manifest and local evidence')) {
    $plan.status = 'skipped_by_shouldprocess'
    $plan.package_share_contact_performed = $networkActivityPerformed
    $plan.files_written = $false
    Write-Output ([pscustomobject]$plan)
    return
}

New-Item -ItemType Directory -Path $runRoot -Force -WhatIf:$false | Out-Null
$manifestRows = New-Object System.Collections.Generic.List[object]
foreach ($target in $targets) {
    $manifestRows.Add([pscustomobject][ordered]@{
        TargetHostname = $target
        PackageName = $PackageName
        SoftwareShareRoot = $normalizedRoot
        InstallerRelativePath = $InstallerRelativePath.Trim().Replace('/', '\')
        ExpectedSha256 = $hash
        InstallerArguments = @($InstallerArguments)
        InstallMode = $InstallMode
        Owner = $Owner
        RequestReference = $RequestReference
        ChangeReference = $ChangeReference
        TicketReference = $TicketReference
    })
}

ConvertTo-Json -InputObject @($manifestRows.ToArray()) -Depth 8 |
    Set-Content -LiteralPath $manifestPath -Encoding UTF8 -WhatIf:$false

$summary = [ordered]@{
    schema_version = 'sas-authorized-package-intake-summary/v1'
    run_id = $runId
    status = 'manifest_ready_for_review'
    package_name = $PackageName
    source_path = $sourcePath
    source_kind = $sourceKind
    file_name = $item.Name
    file_size_bytes = $item.Length
    sha256 = $hash
    signature_status = $signatureStatus
    signer_subject = $signerSubject
    signer_thumbprint = $signerThumbprint
    product_name = [string]$item.VersionInfo.ProductName
    product_version = [string]$item.VersionInfo.ProductVersion
    file_version = [string]$item.VersionInfo.FileVersion
    installer_arguments = @($InstallerArguments)
    installer_arguments_reference = $InstallerArgumentsReference
    install_mode = $InstallMode
    target_count = $targets.Count
    targets = $targets
    request_reference = $RequestReference
    change_reference = $ChangeReference
    ticket_reference = $TicketReference
    owner = $Owner
    require_valid_signature = [bool]$RequireValidSignature
    package_share_contact_performed = $networkActivityPerformed
    target_contact_performed = $false
    target_mutation_performed = $false
    interactive_logon_required = $false
    service_created = $false
    scheduled_task_created = $false
    public_startup_folder_used = $false
    default_password_value_collected = $false
    manifest_path = $manifestPath
    handoff_path = $handoffPath
    guardrails = @(
        'approved_software_source_only',
        'sha256_computed_before_manifest_release',
        'signature_status_recorded',
        'explicit_vendor_argument_reference_required',
        'maximum_25_unique_targets',
        'no_target_contact_or_mutation',
        'no_interactive_logon_dependency',
        'no_service_task_startup_or_run_key',
        'no_credential_collection',
        'local_gitignored_evidence_only'
    )
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8 -WhatIf:$false

@(
    'SysAdminSuite authorized package intake handoff',
    "Run ID: $runId",
    "Package: $PackageName",
    "SHA-256: $hash",
    "Signature status: $signatureStatus",
    "Installer-argument reference: $InstallerArgumentsReference",
    "Targets: $($targets.Count)",
    "Manifest: $manifestPath",
    "Summary: $summaryPath",
    '',
    'Review the hash, signature status, silent arguments, references, and target list before any deployment run.',
    'This intake did not contact or mutate any target workstation.'
) | Set-Content -LiteralPath $handoffPath -Encoding UTF8 -WhatIf:$false

Write-Output ([pscustomobject]$summary)
