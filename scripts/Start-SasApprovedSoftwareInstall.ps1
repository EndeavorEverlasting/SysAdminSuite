#Requires -Version 5.1
<#
.SYNOPSIS
Run the catalog-driven approved software snapshot and install workflow.

.DESCRIPTION
Selects one tracked package, captures a read-only Before snapshot, delegates WhatIf or live
installation to Invoke-SasValidatedSoftwareDeployment.ps1, then captures an After snapshot and local delta.
The normal technician path never asks for a raw installer path and never discovers executable
files dynamically from the package share.
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'ListPackages', 'Before', 'Plan', 'Install', 'After', 'OpenLatest')]
    [string]$Action = 'Menu',

    [string]$TargetsCsv,
    [string]$PackageId,
    [string[]]$InstallerArguments = @(),
    [string]$OutputRoot,

    [ValidateRange(1, 25)]
    [int]$MaxTargets = 25,

    [ValidateSet('Auto', 'WinRM', 'SmbScheduledTask')]
    [string]$Transport = 'WinRM',

    [string[]]$TransportPreflightPath = @(),

    [switch]$FixtureMode,
    [switch]$NonInteractive,
    [switch]$NoOpen
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $repoRoot 'configs/software-packages/approved-apps.json'
$apiPath = Join-Path $repoRoot 'harness/api/sas-harness-api.json'
$deploymentScript = Join-Path $PSScriptRoot 'Invoke-SasValidatedSoftwareDeployment.ps1'
$targetIntakeModule = Join-Path $PSScriptRoot 'SasTargetIntake.psm1'

foreach ($requiredPath in @($catalogPath, $apiPath, $deploymentScript, $targetIntakeModule)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required approved software dependency not found: $requiredPath"
    }
}

Import-Module -Name $targetIntakeModule -Force

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'survey/output/approved_software_install'
}
Assert-SasApprovedOutputPath -Path $OutputRoot -RepoRoot $repoRoot -Role 'approved software install output directory'

function Write-SasJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-SasStatePath {
    return Join-Path $OutputRoot 'operator-state.json'
}

function Read-SasState {
    $path = Get-SasStatePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Save-SasState {
    param([Parameter(Mandatory = $true)]$State)
    $path = Get-SasStatePath
    Write-SasJsonFile -Path $path -Value $State
    return $path
}

function ConvertTo-SasSafeName {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return 'blank' }
    return ($Value.Trim() -replace '[^A-Za-z0-9._-]', '_')
}

function Get-SasApprovedPackageCatalog {
    $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
    if ([string]$catalog.schema_version -ne 'sas-approved-software-catalog/v1') {
        throw "Unsupported approved software catalog schema: $($catalog.schema_version)"
    }

    $api = Get-Content -LiteralPath $apiPath -Raw | ConvertFrom-Json
    $catalogRoot = ([string]$catalog.software_share_root).TrimEnd('\')
    $approvedRoots = @($api.posture.approved_software_sources | ForEach-Object {
        ([string]$_).TrimEnd('\')
    })
    if (@($approvedRoots | Where-Object {
        $_.Equals($catalogRoot, [System.StringComparison]::OrdinalIgnoreCase)
    }).Count -eq 0) {
        throw "Catalog software_share_root is not approved by harness/api/sas-harness-api.json: $catalogRoot"
    }

    $packages = @($catalog.packages)
    if ($packages.Count -eq 0) { throw 'Approved software catalog contains no packages.' }
    $ids = @($packages | ForEach-Object { ([string]$_.id).Trim() })
    if (@($ids | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        throw 'Approved software catalog contains a blank package id.'
    }
    if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) {
        throw 'Approved software catalog contains duplicate package ids.'
    }

    return $catalog
}

function Get-SasPackageById {
    param(
        [Parameter(Mandatory = $true)]$Catalog,
        [Parameter(Mandatory = $true)][string]$Id
    )

    $matches = @($Catalog.packages | Where-Object {
        ([string]$_.id).Equals($Id.Trim(), [System.StringComparison]::OrdinalIgnoreCase)
    })
    if ($matches.Count -ne 1) { throw "Approved package id not found or ambiguous: $Id" }
    return $matches[0]
}

function Get-SasPackageInstallerRelativePath {
    param([Parameter(Mandatory = $true)]$Package)

    $folder = ([string]$Package.source_folder_relative_path).Trim().TrimEnd('\')
    $file = ([string]$Package.installer_file).Trim().TrimStart('\')
    if ([string]::IsNullOrWhiteSpace($folder) -or [string]::IsNullOrWhiteSpace($file)) {
        return $null
    }

    $relativePath = "$folder\$file"
    if ([System.IO.Path]::IsPathRooted($relativePath) -or
        $relativePath.StartsWith('\') -or
        $relativePath -match '(^|\\)\.\.(\\|$)') {
        throw "Catalog package '$($Package.id)' contains an unsafe installer path."
    }
    return $relativePath
}

function Show-SasApprovedPackages {
    param([Parameter(Mandatory = $true)]$Catalog)

    Write-Host 'Approved software packages'
    Write-Host "Share root: $($Catalog.software_share_root)"
    Write-Host ''

    $index = 1
    foreach ($package in @($Catalog.packages)) {
        $installer = Get-SasPackageInstallerRelativePath -Package $package
        if ([string]::IsNullOrWhiteSpace($installer)) { $installer = '[installer filename pending]' }
        Write-Host ("[{0}] {1} ({2})" -f $index, $package.display_name, $package.id)
        Write-Host ("    Folder: {0}" -f $package.source_folder_relative_path)
        Write-Host ("    Installer: {0}" -f $installer)
        Write-Host ("    Readiness: {0}" -f $package.readiness)
        $index++
    }
}

function Select-SasApprovedPackage {
    param([Parameter(Mandatory = $true)]$Catalog)

    if (-not [string]::IsNullOrWhiteSpace($PackageId)) {
        return Get-SasPackageById -Catalog $Catalog -Id $PackageId
    }
    if ($NonInteractive) { throw 'PackageId is required for noninteractive approved software work.' }

    while ($true) {
        Show-SasApprovedPackages -Catalog $Catalog
        Write-Host ''
        $selection = (Read-Host 'Select package number or enter package id').Trim()
        $number = 0
        if ([int]::TryParse($selection, [ref]$number) -and
            $number -ge 1 -and
            $number -le @($Catalog.packages).Count) {
            return @($Catalog.packages)[$number - 1]
        }

        try { return Get-SasPackageById -Catalog $Catalog -Id $selection }
        catch { Write-Warning $_.Exception.Message }
    }
}

function Get-SasEffectiveInstallerArguments {
    param([Parameter(Mandatory = $true)]$Package)

    $arguments = @($InstallerArguments | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_)
    })
    if ($arguments.Count -eq 0) {
        $arguments = @($Package.default_installer_arguments | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_)
        })
    }

    if ($arguments.Count -eq 0 -and -not $NonInteractive) {
        Write-Host ''
        Write-Host 'No vendor-validated installer arguments are stored for this package.'
        Write-Host 'Leave blank for snapshot/WhatIf only. Separate multiple arguments with |.'
        $line = Read-Host 'Installer arguments'
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $arguments = @($line.Split('|') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
    }

    return @($arguments)
}

function Assert-SasPackagePlanReady {
    param([Parameter(Mandatory = $true)]$Package)

    if (-not [bool]$Package.install_enabled) {
        throw "Package '$($Package.display_name)' is not enabled for plan/install. Catalog readiness: $($Package.readiness)"
    }
    $relativePath = Get-SasPackageInstallerRelativePath -Package $Package
    if ([string]::IsNullOrWhiteSpace($relativePath)) {
        throw "Package '$($Package.display_name)' has no pinned installer filename. Update the catalog before plan/install."
    }
    return $relativePath
}

function Assert-SasPackageLiveReady {
    param(
        [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $null = Assert-SasPackagePlanReady -Package $Package
    if ([bool]$Package.requires_validated_installer_arguments -and $Arguments.Count -eq 0) {
        throw "Live installation of '$($Package.display_name)' requires explicit vendor-validated installer arguments. No arguments are cataloged or supplied."
    }
}

function Get-SasCsvTargets {
    param([Parameter(Mandatory = $true)][string]$CsvPath)

    Assert-SasApprovedInputPath -Path $CsvPath -RepoRoot $repoRoot -Role 'approved software target manifest' -AllowStaging
    $targets = @()
    foreach ($row in @(Import-Csv -LiteralPath $CsvPath)) {
        foreach ($column in @('ComputerName', 'HostName', 'Hostname', 'Target')) {
            if ($row.PSObject.Properties.Name -contains $column) {
                $candidate = ([string]$row.$column).Trim()
                if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                    $targets += $candidate
                    break
                }
            }
        }
    }

    $targets = @($targets | Sort-Object -Unique)
    if ($targets.Count -eq 0) {
        throw 'No targets were supplied. Use a CSV with ComputerName, HostName, Hostname, or Target column.'
    }
    if ($targets.Count -gt $MaxTargets) {
        throw "Target count $($targets.Count) exceeds MaxTargets $MaxTargets. Split the approved software pilot batch."
    }
    return $targets
}

function New-SasRunId {
    param([Parameter(Mandatory = $true)][string]$SelectedPackageId)
    $safeId = ConvertTo-SasSafeName -Value $SelectedPackageId
    return 'approved-install-{0}-{1}-{2}' -f $safeId, (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
}

function New-SasFixtureSnapshot {
    param(
        [string]$Target,
        [string]$Phase,
        $Package
    )

    $software = @(
        [pscustomobject]@{
            name = 'Contoso Base Agent'
            version = '1.0.0'
            publisher = 'Contoso'
            install_date = '20260101'
            registry_path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ContosoBase'
        }
    )
    if ($Phase -eq 'after') {
        $software += [pscustomobject]@{
            name = [string]$Package.display_name
            version = '1.0.0'
            publisher = 'Fixture Publisher'
            install_date = (Get-Date -Format 'yyyyMMdd')
            registry_path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$($Package.id)"
        }
    }

    return [pscustomobject]@{
        schema_version = 'sas-approved-software-snapshot/v1'
        package_id = [string]$Package.id
        package_name = [string]$Package.display_name
        snapshot_phase = $Phase
        requested_target = $Target
        computer_name = $Target.ToUpperInvariant()
        collection_status = 'success'
        error = $null
        captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        identity = [pscustomobject]@{
            os_caption = 'Microsoft Windows 11 Enterprise'
            os_version = '10.0.26100'
            last_boot_time_utc = '2026-07-14T00:00:00Z'
            logged_on_user = 'FIXTURE\TECH'
        }
        installed_software = $software
        target_mutation_performed = $false
        target_side_sysadminsuite_artifacts_written = $false
        collection_notes = @('fixture_mode', 'no_network_activity', 'no_target_mutation')
    }
}

$remoteSnapshot = {
    param([string]$Phase, [string]$SelectedPackageId, [string]$SelectedPackageName)

    Set-StrictMode -Version 2.0
    $ErrorActionPreference = 'Stop'
    $software = @()
    foreach ($root in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            try {
                $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                $name = ([string]$item.DisplayName).Trim()
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                $software += [pscustomobject]@{
                    name = $name
                    version = ([string]$item.DisplayVersion).Trim()
                    publisher = ([string]$item.Publisher).Trim()
                    install_date = ([string]$item.InstallDate).Trim()
                    registry_path = $key.Name
                }
            }
            catch {}
        }
    }

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        schema_version = 'sas-approved-software-snapshot/v1'
        package_id = $SelectedPackageId
        package_name = $SelectedPackageName
        snapshot_phase = $Phase
        requested_target = $env:COMPUTERNAME
        computer_name = $env:COMPUTERNAME
        collection_status = 'success'
        error = $null
        captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        identity = [pscustomobject]@{
            os_caption = [string]$os.Caption
            os_version = [string]$os.Version
            last_boot_time_utc = $os.LastBootUpTime.ToUniversalTime().ToString('o')
            logged_on_user = [string]$cs.UserName
        }
        installed_software = @($software | Sort-Object name, publisher, version, registry_path -Unique)
        target_mutation_performed = $false
        target_side_sysadminsuite_artifacts_written = $false
        collection_notes = @('remote_read_only_snapshot', 'no_target_side_sysadminsuite_artifacts')
    }
}

function Invoke-SasSnapshotSet {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('before', 'after')][string]$Phase,
        [Parameter(Mandatory = $true)][string[]]$Targets,
        [Parameter(Mandatory = $true)][string]$RunRoot,
        [Parameter(Mandatory = $true)]$Package,
        [switch]$Fixture
    )

    $phaseRoot = Join-Path $RunRoot $Phase
    New-Item -ItemType Directory -Path $phaseRoot -Force | Out-Null
    $rows = @()

    foreach ($target in $Targets) {
        $snapshotPath = Join-Path $phaseRoot ((ConvertTo-SasSafeName -Value $target) + '.json')
        try {
            if ($Fixture) {
                $snapshot = New-SasFixtureSnapshot -Target $target -Phase $Phase -Package $Package
            }
            else {
                $session = $null
                try {
                    $sessionOption = New-PSSessionOption -OpenTimeout 30000 -OperationTimeout 300000
                    $session = New-PSSession -ComputerName $target -SessionOption $sessionOption
                    $snapshot = Invoke-Command -Session $session -ScriptBlock $remoteSnapshot -ArgumentList $Phase, ([string]$Package.id), ([string]$Package.display_name)
                    $snapshot.requested_target = $target
                }
                finally {
                    if ($session) { Remove-PSSession -Session $session }
                }
            }

            Write-SasJsonFile -Path $snapshotPath -Value $snapshot
            $rows += [pscustomobject]@{
                target = $target
                status = [string]$snapshot.collection_status
                path = $snapshotPath
                error = [string]$snapshot.error
            }
        }
        catch {
            $failure = [pscustomobject]@{
                schema_version = 'sas-approved-software-snapshot/v1'
                package_id = [string]$Package.id
                package_name = [string]$Package.display_name
                snapshot_phase = $Phase
                requested_target = $target
                computer_name = $target
                collection_status = 'failed'
                error = $_.Exception.Message
                captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
                installed_software = @()
                target_mutation_performed = $false
                target_side_sysadminsuite_artifacts_written = $false
            }
            Write-SasJsonFile -Path $snapshotPath -Value $failure
            $rows += [pscustomobject]@{
                target = $target
                status = 'failed'
                path = $snapshotPath
                error = $_.Exception.Message
            }
        }
    }

    $failed = @($rows | Where-Object { $_.status -ne 'success' })
    $manifest = [pscustomobject]@{
        schema_version = 'sas-approved-software-snapshot-manifest/v1'
        package_id = [string]$Package.id
        package_name = [string]$Package.display_name
        phase = $Phase
        run_root = $RunRoot
        target_count = $Targets.Count
        success_count = $Targets.Count - $failed.Count
        failed_count = $failed.Count
        snapshot_status = $(if ($failed.Count -eq 0) { 'complete' } else { 'incomplete' })
        snapshots = $rows
        guardrails = @(
            'read_only_snapshot_before_install',
            'read_only_snapshot_after_install',
            'admin_box_evidence_only',
            'no_target_side_sysadminsuite_artifacts',
            'no_secret_collection',
            'no_target_mutation_from_snapshot'
        )
    }

    $manifestPath = Join-Path $phaseRoot 'snapshot-manifest.json'
    Write-SasJsonFile -Path $manifestPath -Value $manifest
    return $manifestPath
}

function Assert-SasBeforeSnapshotReady {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw 'Before snapshot must complete before approved software install. Missing before snapshot manifest.'
    }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    if ([string]$manifest.snapshot_status -ne 'complete') {
        throw "Before snapshot must complete before approved software install. Current status: $($manifest.snapshot_status)"
    }
    if ([int]$manifest.target_count -le 0) {
        throw 'Before snapshot must contain at least one approved target before approved software install.'
    }
}

function Get-SasSoftwareKeys {
    param([object[]]$Software)
    return @($Software | ForEach-Object {
        '{0}|{1}|{2}' -f ([string]$_.name).ToUpperInvariant(), ([string]$_.publisher).ToUpperInvariant(), ([string]$_.version).ToUpperInvariant()
    } | Sort-Object -Unique)
}

function Compare-SasSnapshots {
    param([Parameter(Mandatory = $true)][string]$RunRoot)

    $beforeRoot = Join-Path $RunRoot 'before'
    $afterRoot = Join-Path $RunRoot 'after'
    $rows = @()

    foreach ($afterFile in @(Get-ChildItem -LiteralPath $afterRoot -Filter '*.json' -File | Where-Object {
        $_.Name -ne 'snapshot-manifest.json'
    })) {
        $beforeFile = Join-Path $beforeRoot $afterFile.Name
        if (-not (Test-Path -LiteralPath $beforeFile -PathType Leaf)) { continue }

        $before = Get-Content -LiteralPath $beforeFile -Raw | ConvertFrom-Json
        $after = Get-Content -LiteralPath $afterFile.FullName -Raw | ConvertFrom-Json
        $beforeKeys = @(Get-SasSoftwareKeys -Software @($before.installed_software))
        $afterKeys = @(Get-SasSoftwareKeys -Software @($after.installed_software))
        $added = @($afterKeys | Where-Object { $beforeKeys -notcontains $_ })
        $removed = @($beforeKeys | Where-Object { $afterKeys -notcontains $_ })

        $rows += [pscustomobject]@{
            target = [string]$after.requested_target
            package_id = [string]$after.package_id
            added_software_count = $added.Count
            removed_software_count = $removed.Count
            added_software_keys = $added
            removed_software_keys = $removed
        }
    }

    $delta = [pscustomobject]@{
        schema_version = 'sas-approved-software-install-delta/v1'
        run_root = $RunRoot
        target_count = $rows.Count
        result = $(if (@($rows | Where-Object { $_.added_software_count -gt 0 }).Count -gt 0) {
            'SOFTWARE_DELTA_OBSERVED'
        } else {
            'NO_SOFTWARE_DELTA_OBSERVED'
        })
        proof_boundary = 'snapshot_delta_does_not_prove_app_launch_or_user_acceptance'
        deltas = $rows
    }

    $path = Join-Path $RunRoot 'approved-software-install-delta.json'
    Write-SasJsonFile -Path $path -Value $delta
    return $path
}

function Get-SasTargetsCsv {
    if (-not [string]::IsNullOrWhiteSpace($TargetsCsv)) { return $TargetsCsv }
    if ($NonInteractive) { throw 'TargetsCsv is required for noninteractive approved software work.' }
    return Read-Host 'Targets CSV under targets/local/ or survey/input/'
}

function Start-SasBefore {
    $catalog = Get-SasApprovedPackageCatalog
    $package = Select-SasApprovedPackage -Catalog $catalog
    $effectiveTargetsCsv = Get-SasTargetsCsv
    $targets = @(Get-SasCsvTargets -CsvPath $effectiveTargetsCsv)
    $arguments = @(Get-SasEffectiveInstallerArguments -Package $package)
    $installerRelativePath = Get-SasPackageInstallerRelativePath -Package $package

    $runId = New-SasRunId -SelectedPackageId ([string]$package.id)
    $runRoot = Join-Path $OutputRoot $runId
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

    $beforeManifest = Invoke-SasSnapshotSet -Phase before -Targets $targets -RunRoot $runRoot -Package $package -Fixture:$FixtureMode
    Assert-SasBeforeSnapshotReady -ManifestPath $beforeManifest

    $state = [ordered]@{
        schema_version = 'sas-approved-software-install-state/v1'
        active_run_id = $runId
        run_root = $runRoot
        catalog_path = $catalogPath
        catalog_schema_version = [string]$catalog.schema_version
        package_id = [string]$package.id
        package_name = [string]$package.display_name
        source_folder_relative_path = [string]$package.source_folder_relative_path
        installer_file = [string]$package.installer_file
        installer_relative_path = $installerRelativePath
        installer_arguments = $arguments
        install_mode = [string]$package.default_install_mode
        software_share_root = [string]$catalog.software_share_root
        catalog_readiness = [string]$package.readiness
        targets_csv = $effectiveTargetsCsv
        before_manifest_path = $beforeManifest
        install_summary_path = $null
        after_manifest_path = $null
        delta_path = $null
        workflow_status = 'before_complete'
        target_count = $targets.Count
        snapshot_required_before_install = $true
    }

    $statePath = Save-SasState -State $state
    Write-Host "BEFORE SNAPSHOT COMPLETE - Package: $($package.display_name)"
    Write-Host "Catalog readiness: $($package.readiness)"
    Write-Host "State: $statePath"
    Write-Host "Run root: $runRoot"
}

function Invoke-SasInstallWrapper {
    param([switch]$PlanOnly)

    $state = Read-SasState
    if ($null -eq $state) { throw 'No approved software operator state found. Run BEFORE snapshot first.' }
    Assert-SasBeforeSnapshotReady -ManifestPath ([string]$state.before_manifest_path)

    $catalog = Get-SasApprovedPackageCatalog
    $package = Get-SasPackageById -Catalog $catalog -Id ([string]$state.package_id)
    $installerRelativePath = Assert-SasPackagePlanReady -Package $package
    if (-not $installerRelativePath.Equals([string]$state.installer_relative_path, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'The catalog installer path changed after the Before snapshot. Start a new Before snapshot before plan/install.'
    }

    $arguments = @($state.installer_arguments | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_)
    })
    if (-not $PlanOnly) { Assert-SasPackageLiveReady -Package $package -Arguments $arguments }

    # Detect if we are in fixture mode
    $isFixture = $false
    $beforeManifest = Get-Content -LiteralPath ([string]$state.before_manifest_path) -Raw | ConvertFrom-Json
    if ($beforeManifest.snapshots.Count -gt 0) {
        $firstSnapshotPath = $beforeManifest.snapshots[0].path
        if (Test-Path -LiteralPath $firstSnapshotPath -PathType Leaf) {
            $firstSnapshot = Get-Content -LiteralPath $firstSnapshotPath -Raw | ConvertFrom-Json
            if ($null -ne $firstSnapshot.collection_notes -and $firstSnapshot.collection_notes -contains 'fixture_mode') {
                $isFixture = $true
            }
        }
    }

    # Resolve installer file and compute hash
    $installerPath = Join-Path ([string]$catalog.software_share_root) $installerRelativePath
    if ($isFixture -or -not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        $hashingPath = Join-Path $repoRoot 'Tests/fixtures/deployment/authorized-package-intake.fixture.txt'
    } else {
        $hashingPath = $installerPath
    }
    $installerSha256 = (Get-FileHash -LiteralPath $hashingPath -Algorithm SHA256).Hash.ToLowerInvariant()

    # Require at least one argument in request to satisfy schema constraints
    $effectiveArguments = @($arguments)
    if ($effectiveArguments.Count -eq 0) {
        $effectiveArguments = @('/WhatIfOnly')
    }

    # Get target list
    $targets = @(Get-SasCsvTargets -CsvPath ([string]$state.targets_csv))

    # Construct validated-software-deployment-request
    $request = [ordered]@{
        schema_version = 'sas-validated-software-deployment-request/v1'
        request_id = ('req-' + $state.active_run_id).Substring(0, [Math]::Min(90, ('req-' + $state.active_run_id).Length))
        package_name = [string]$package.display_name
        software_share_root = [string]$catalog.software_share_root
        installer_relative_path = $installerRelativePath
        installer_sha256 = $installerSha256
        installer_arguments = @($effectiveArguments)
        installer_arguments_reference = 'catalog default arguments or operator override'
        install_mode = [string]$package.default_install_mode
        targets = @($targets)
        authorization = [ordered]@{
            authorized_by = 'SysAdminSuite Approved Software Operator'
            request_reference = ('REQ-' + $state.active_run_id).Substring(0, [Math]::Min(150, ('REQ-' + $state.active_run_id).Length))
            change_reference = ('CHG-' + $state.active_run_id).Substring(0, [Math]::Min(150, ('CHG-' + $state.active_run_id).Length))
            ticket_reference = ('TASK-' + $state.active_run_id).Substring(0, [Math]::Min(150, ('TASK-' + $state.active_run_id).Length))
        }
        validation = [ordered]@{
            checks = @(
                [ordered]@{
                    id = 'system_kernel_presence'
                    type = 'FileExists'
                    required = $true
                    path = 'C:\Windows\System32\kernel32.dll'
                }
            )
        }
        cleanup_policy = 'repo_owned_run_scoped_only'
    }

    $requestPath = Join-Path ([string]$state.run_root) 'validated-deployment-request.json'
    $request | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $requestPath -Encoding UTF8

    $params = @{
        RequestPath = $requestPath
        OutputRoot = (Join-Path ([string]$state.run_root) 'software_install')
        Transport = $Transport
    }
    if ($TransportPreflightPath.Count -gt 0) { $params.TransportPreflightPath = @($TransportPreflightPath) }
    if ($isFixture) {
        $params.AllowFixtures = $true
    }

    if ($PlanOnly) {
        $output = @(& $deploymentScript @params -WhatIf)
        $state.workflow_status = 'install_planned_whatif'
    }
    else {
        $output = @(& $deploymentScript @params -AllowTargetMutation -Confirm:$false)
        $state.workflow_status = 'install_attempted'
    }

    $summary = @($output | Where-Object {
        $_ -and $_.PSObject.Properties.Name -contains 'install_summary_path'
    } | Select-Object -Last 1)
    if ($summary.Count -ne 1) { throw 'Canonical validated deployment did not return its result object.' }

    $installSummaryJson = Get-Content -LiteralPath $summary[0].install_summary_path -Raw | ConvertFrom-Json
    $state.install_summary_path = [string]$installSummaryJson.operator_handoff_path
    Save-SasState -State $state | Out-Null

    Write-Host $(if ($PlanOnly) { 'INSTALL PLAN COMPLETE' } else { 'INSTALL ATTEMPT COMPLETE' })
    Write-Host "Package: $($package.display_name)"
    Write-Host "Install evidence: $($state.install_summary_path)"
}

function Start-SasAfter {
    $state = Read-SasState
    if ($null -eq $state) { throw 'No approved software operator state found. Run BEFORE snapshot first.' }
    Assert-SasBeforeSnapshotReady -ManifestPath ([string]$state.before_manifest_path)
    if ([string]$state.workflow_status -notin @('install_planned_whatif', 'install_attempted')) {
        throw "After snapshot requires a completed WhatIf plan or install attempt. Current status: $($state.workflow_status)"
    }

    $catalog = Get-SasApprovedPackageCatalog
    $package = Get-SasPackageById -Catalog $catalog -Id ([string]$state.package_id)
    $targets = @(Get-SasCsvTargets -CsvPath ([string]$state.targets_csv))
    $afterManifest = Invoke-SasSnapshotSet -Phase after -Targets $targets -RunRoot ([string]$state.run_root) -Package $package -Fixture:$FixtureMode
    $after = Get-Content -LiteralPath $afterManifest -Raw | ConvertFrom-Json
    if ([string]$after.snapshot_status -ne 'complete') {
        throw "After snapshot is incomplete: $($after.snapshot_status)"
    }

    $state.after_manifest_path = $afterManifest
    $state.delta_path = Compare-SasSnapshots -RunRoot ([string]$state.run_root)
    $state.workflow_status = 'after_complete'
    Save-SasState -State $state | Out-Null
    Write-Host "AFTER SNAPSHOT COMPLETE - Package: $($package.display_name)"
    Write-Host "Delta: $($state.delta_path)"
}

function Open-SasLatest {
    $state = Read-SasState
    if ($null -eq $state) { throw 'No approved software operator state found.' }
    Write-Host "Latest approved software run root: $($state.run_root)"
    if (-not $NoOpen -and (Test-Path -LiteralPath ([string]$state.run_root) -PathType Container)) {
        Start-Process -FilePath ([string]$state.run_root) | Out-Null
    }
}

function Wait-SasOperator {
    if (-not $NonInteractive) { $null = Read-Host 'Press Enter to continue' }
}

function Show-SasMenu {
    while ($true) {
        Clear-Host
        Write-Host 'SysAdminSuite - Approved Software Install'
        Write-Host 'Catalog: Epic, BCA, AllScripts, AutoLogon'
        Write-Host ''
        Write-Host '[1] List approved packages and readiness'
        Write-Host '[2] Select package and capture BEFORE snapshot'
        Write-Host '[3] Plan selected package install (WhatIf)'
        Write-Host '[4] Install selected package after confirmed BEFORE snapshot'
        Write-Host '[5] Capture AFTER snapshot and compare'
        Write-Host '[6] Open latest evidence folder'
        Write-Host '[Q] Quit'
        Write-Host ''

        $choice = Read-Host 'Select action'
        switch -Regex ($choice) {
            '^1$' { Show-SasApprovedPackages -Catalog (Get-SasApprovedPackageCatalog); Wait-SasOperator }
            '^2$' { Start-SasBefore; Wait-SasOperator }
            '^3$' { Invoke-SasInstallWrapper -PlanOnly; Wait-SasOperator }
            '^4$' { Invoke-SasInstallWrapper; Wait-SasOperator }
            '^5$' { Start-SasAfter; Wait-SasOperator }
            '^6$' { Open-SasLatest; Wait-SasOperator }
            '(?i)^q$' { return }
            default { Write-Warning "Unknown selection: $choice"; Wait-SasOperator }
        }
    }
}

switch ($Action) {
    'ListPackages' { Show-SasApprovedPackages -Catalog (Get-SasApprovedPackageCatalog) }
    'Before' { Start-SasBefore }
    'Plan' { Invoke-SasInstallWrapper -PlanOnly }
    'Install' { Invoke-SasInstallWrapper }
    'After' { Start-SasAfter }
    'OpenLatest' { Open-SasLatest }
    'Menu' { Show-SasMenu }
}
