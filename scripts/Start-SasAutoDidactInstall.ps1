#Requires -Version 5.1
<#
.SYNOPSIS
Technician-facing approved software install capsule with required before/after snapshots.

.DESCRIPTION
This wrapper selects an approved package from the tracked software catalog, enforces a read-only
BEFORE software snapshot before target mutation, delegates installation to
Invoke-SasSoftwareInstall.ps1, then captures an AFTER snapshot and local delta.

Evidence is written only on the admin workstation under survey/output/approved_software_install.
The wrapper does not discover installer files from a share, store credentials, suppress logs,
clear events, or create target persistence.
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

    [switch]$FixtureMode,
    [switch]$NonInteractive,
    [switch]$NoOpen
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module -Name (Join-Path $PSScriptRoot 'SasTargetIntake.psm1') -Force

$installScript = Join-Path $PSScriptRoot 'Invoke-SasSoftwareInstall.ps1'
$catalogPath = Join-Path $repoRoot 'configs/software-packages/approved-apps.json'
$apiPath = Join-Path $repoRoot 'harness/api/sas-harness-api.json'

foreach ($requiredPath in @($installScript, $catalogPath, $apiPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required approved-software dependency not found: $requiredPath"
    }
}

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
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-SasStatePath {
    param([string]$Root)
    Join-Path $Root 'operator-state.json'
}

function Read-SasState {
    param([string]$Root)
    $statePath = Get-SasStatePath -Root $Root
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
}

function Save-SasState {
    param([string]$Root, [Parameter(Mandatory = $true)]$State)
    $path = Get-SasStatePath -Root $Root
    Write-SasJsonFile -Path $path -Value $State
    $path
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
    $approved = @($api.posture.approved_software_sources | Where-Object {
        ([string]$_).TrimEnd('\').Equals($catalogRoot, [System.StringComparison]::OrdinalIgnoreCase)
    })
    if ($approved.Count -eq 0) {
        throw "Catalog software_share_root is not approved by harness/api/sas-harness-api.json: $catalogRoot"
    }

    $packages = @($catalog.packages)
    if ($packages.Count -eq 0) { throw 'Approved software catalog contains no packages.' }

    $ids = @($packages | ForEach-Object { ([string]$_.id).Trim() })
    if (@($ids | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        throw 'Approved software catalog contains a package with a blank id.'
    }
    if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) {
        throw 'Approved software catalog contains duplicate package ids.'
    }

    return $catalog
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

function Get-SasPackageById {
    param(
        [Parameter(Mandatory = $true)]$Catalog,
        [Parameter(Mandatory = $true)][string]$Id
    )

    $matches = @($Catalog.packages | Where-Object {
        ([string]$_.id).Equals($Id.Trim(), [System.StringComparison]::OrdinalIgnoreCase)
    })
    if ($matches.Count -ne 1) {
        throw "Approved package id not found or ambiguous: $Id"
    }
    return $matches[0]
}

function Show-SasApprovedPackages {
    param([Parameter(Mandatory = $true)]$Catalog)

    Write-Host 'Approved software packages'
    Write-Host "Share root: $($Catalog.software_share_root)"
    Write-Host ''

    $index = 1
    foreach ($package in @($Catalog.packages)) {
        $installer = Get-SasPackageInstallerRelativePath -Package $package
        $installerText = if ($installer) { $installer } else { '[installer filename pending]' }
        Write-Host ("[{0}] {1} ({2})" -f $index, $package.display_name, $package.id)
        Write-Host ("    Folder: {0}" -f $package.source_folder_relative_path)
        Write-Host ("    Installer: {0}" -f $installerText)
        Write-Host ("    Readiness: {0}" -f $package.readiness)
        $index++
    }
}

function Select-SasApprovedPackage {
    param([Parameter(Mandatory = $true)]$Catalog)

    if (-not [string]::IsNullOrWhiteSpace($PackageId)) {
        return Get-SasPackageById -Catalog $Catalog -Id $PackageId
    }
    if ($NonInteractive) {
        throw 'PackageId is required for noninteractive approved software work.'
    }

    while ($true) {
        Show-SasApprovedPackages -Catalog $Catalog
        Write-Host ''
        $selection = (Read-Host 'Select package number or enter package id').Trim()
        $number = 0
        if ([int]::TryParse($selection, [ref]$number) -and $number -ge 1 -and $number -le @($Catalog.packages).Count) {
            return @($Catalog.packages)[$number - 1]
        }
        try {
            return Get-SasPackageById -Catalog $Catalog -Id $selection
        }
        catch {
            Write-Warning $_.Exception.Message
        }
    }
}

function Get-SasEffectiveInstallerArguments {
    param([Parameter(Mandatory = $true)]$Package)

    $arguments = @($InstallerArguments | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($arguments.Count -eq 0) {
        $arguments = @($Package.default_installer_arguments | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }

    if ($arguments.Count -eq 0 -and -not $NonInteractive) {
        Write-Host ''
        Write-Host 'No vendor-validated installer arguments are stored for this package.'
        Write-Host 'Leave blank for snapshot/WhatIf work only. Separate multiple arguments with |.'
        $argumentLine = Read-Host 'Installer arguments'
        if (-not [string]::IsNullOrWhiteSpace($argumentLine)) {
            $arguments = @($argumentLine.Split('|') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
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
    if ([bool]$Package.requires_validated_installer_arguments -and @($Arguments).Count -eq 0) {
        throw "Live installation of '$($Package.display_name)' requires explicit vendor-validated installer arguments. No arguments are cataloged or supplied."
    }
}

function Get-SasCsvTargets {
    param([Parameter(Mandatory = $true)][string]$CsvPath, [int]$Limit)

    Assert-SasApprovedInputPath -Path $CsvPath -RepoRoot $repoRoot -Role 'approved software target manifest' -AllowStaging
    $items = New-Object System.Collections.Generic.List[string]
    foreach ($row in @(Import-Csv -LiteralPath $CsvPath)) {
        foreach ($column in @('ComputerName', 'HostName', 'Hostname', 'Target')) {
            if ($row.PSObject.Properties.Name -contains $column -and
                -not [string]::IsNullOrWhiteSpace([string]$row.$column)) {
                $items.Add(([string]$row.$column).Trim())
                break
            }
        }
    }

    $targets = @($items | Sort-Object -Unique)
    if ($targets.Count -eq 0) {
        throw 'No targets were supplied. Use a CSV with ComputerName, HostName, Hostname, or Target column.'
    }
    if ($targets.Count -gt $Limit) {
        throw "Target count $($targets.Count) exceeds MaxTargets $Limit. Split the approved software pilot batch."
    }
    return @($targets)
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
        [string]$SelectedPackageId,
        [string]$SelectedPackageName
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
            name = $SelectedPackageName
            version = '1.0.0'
            publisher = 'Fixture Publisher'
            install_date = (Get-Date -Format 'yyyyMMdd')
            registry_path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$SelectedPackageId"
        }
    }

    return [pscustomobject]@{
        schema_version = 'sas-approved-software-snapshot/v1'
        package_id = $SelectedPackageId
        package_name = $SelectedPackageName
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
        installed_software = @($software)
        target_mutation_performed = $false
        target_side_sysadminsuite_artifacts_written = $false
        collection_notes = @('fixture_mode', 'no_network_activity', 'no_target_mutation')
    }
}

$softwareSnapshotBlock = {
    param([string]$Phase, [string]$SelectedPackageId, [string]$SelectedPackageName)

    Set-StrictMode -Version 2.0
    $ErrorActionPreference = 'Stop'

    function Get-InstalledSoftwareSafe {
        $roots = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )
        $rows = foreach ($root in $roots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                try {
                    $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                    $name = ([string]$item.DisplayName).Trim()
                    if ([string]::IsNullOrWhiteSpace($name)) { continue }
                    [pscustomobject]@{
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
        return @($rows | Sort-Object -Property name, publisher, version, registry_path -Unique)
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
        installed_software = @(Get-InstalledSoftwareSafe)
        target_mutation_performed = $false
        target_side_sysadminsuite_artifacts_written = $false
        collection_notes = @('remote_read_only_snapshot', 'no_target_side_sysadminsuite_artifacts')
    }
}

function Invoke-SasSnapshotSet {
    param(
        [Parameter(Mandatory = $true)][string]$Phase,
        [Parameter(Mandatory = $true)][string[]]$Targets,
        [Parameter(Mandatory = $true)][string]$RunRoot,
        [Parameter(Mandatory = $true)]$Package,
        [switch]$Fixture
    )

    $phaseRoot = Join-Path $RunRoot $Phase
    New-Item -ItemType Directory -Path $phaseRoot -Force | Out-Null
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($target in $Targets) {
        $snapshotPath = Join-Path $phaseRoot ((ConvertTo-SasSafeName -Value $target) + '.json')
        try {
            if ($Fixture) {
                $snapshot = New-SasFixtureSnapshot -Target $target -Phase $Phase -SelectedPackageId ([string]$Package.id) -SelectedPackageName ([string]$Package.display_name)
            }
            else {
                $session = $null
                $sessionOption = New-PSSessionOption -OpenTimeout 30000 -OperationTimeout 300000
                $session = New-PSSession -ComputerName $target -SessionOption $sessionOption
                try {
                    $snapshot = Invoke-Command -Session $session -ScriptBlock $softwareSnapshotBlock -ArgumentList $Phase, ([string]$Package.id), ([string]$Package.display_name)
                    $snapshot.requested_target = $target
                }
                finally {
                    if ($session) { Remove-PSSession -Session $session }
                }
            }

            Write-SasJsonFile -Path $snapshotPath -Value $snapshot
            $rows.Add([pscustomobject]@{
                target = $target
                status = $snapshot.collection_status
                path = $snapshotPath
                error = $snapshot.error
            })
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
            $rows.Add([pscustomobject]@{
                target = $target
                status = 'failed'
                path = $snapshotPath
                error = $_.Exception.Message
            })
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
        snapshots = @($rows)
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
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($afterFile in @(Get-ChildItem -LiteralPath $afterRoot -Filter '*.json' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'snapshot-manifest.json' })) {
        $beforeFile = Join-Path $beforeRoot $afterFile.Name
        if (-not (Test-Path -LiteralPath $beforeFile -PathType Leaf)) { continue }

        $before = Get-Content -LiteralPath $beforeFile -Raw | ConvertFrom-Json
        $after = Get-Content -LiteralPath $afterFile.FullName -Raw | ConvertFrom-Json
        $beforeKeys = @(Get-SasSoftwareKeys -Software @($before.installed_software))
        $afterKeys = @(Get-SasSoftwareKeys -Software @($after.installed_software))
        $added = @($afterKeys | Where-Object { $beforeKeys -notcontains $_ })
        $removed = @($beforeKeys | Where-Object { $afterKeys -notcontains $_ })

        $rows.Add([pscustomobject]@{
            target = [string]$after.requested_target
            package_id = [string]$after.package_id
            added_software_count = $added.Count
            removed_software_count = $removed.Count
            added_software_keys = @($added)
            removed_software_keys = @($removed)
        })
    }

    $delta = [pscustomobject]@{
        schema_version = 'sas-approved-software-install-delta/v1'
        run_root = $RunRoot
        target_count = $rows.Count
        result = $(if (@($rows | Where-Object { $_.added_software_count -gt 0 }).Count -gt 0) { 'SOFTWARE_DELTA_OBSERVED' } else { 'NO_SOFTWARE_DELTA_OBSERVED' })
        proof_boundary = 'snapshot_delta_does_not_prove_app_launch_or_user_acceptance'
        deltas = @($rows)
    }
    $deltaPath = Join-Path $RunRoot 'approved-software-install-delta.json'
    Write-SasJsonFile -Path $deltaPath -Value $delta
    return $deltaPath
}

function Get-SasRequiredTargetsCsv {
    if (-not [string]::IsNullOrWhiteSpace($TargetsCsv)) { return $TargetsCsv }
    if ($NonInteractive) { throw 'TargetsCsv is required for noninteractive approved software work.' }
    return Read-Host 'Targets CSV under targets/local/ or survey/input/'
}

function Start-SasBefore {
    $catalog = Get-SasApprovedPackageCatalog
    $package = Select-SasApprovedPackage -Catalog $catalog
    $effectiveTargetsCsv = Get-SasRequiredTargetsCsv
    $targets = @(Get-SasCsvTargets -CsvPath $effectiveTargetsCsv -Limit $MaxTargets)
    $arguments = @(Get-SasEffectiveInstallerArguments -Package $package)
    $installerRelativePath = Get-SasPackageInstallerRelativePath -Package $package

    $runId = New-SasRunId -SelectedPackageId ([string]$package.id)
    $runRoot = Join-Path $OutputRoot $runId
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

    $beforeManifest = Invoke-SasSnapshotSet -Phase 'before' -Targets $targets -RunRoot $runRoot -Package $package -Fixture:$FixtureMode
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
        installer_arguments = @($arguments)
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

    $statePath = Save-SasState -Root $OutputRoot -State $state
    Write-Host "BEFORE SNAPSHOT COMPLETE - Package: $($package.display_name)"
    Write-Host "Catalog readiness: $($package.readiness)"
    Write-Host "State: $statePath"
    Write-Host "Run root: $runRoot"
}

function Invoke-SasInstallWrapper {
    param([switch]$PlanOnly)

    $state = Read-SasState -Root $OutputRoot
    if ($null -eq $state) { throw 'No approved software operator state found. Run BEFORE snapshot first.' }
    Assert-SasBeforeSnapshotReady -ManifestPath ([string]$state.before_manifest_path)

    $catalog = Get-SasApprovedPackageCatalog
    $package = Get-SasPackageById -Catalog $catalog -Id ([string]$state.package_id)
    $installerRelativePath = Assert-SasPackagePlanReady -Package $package

    if (-not $installerRelativePath.Equals([string]$state.installer_relative_path, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'The catalog installer path changed after the Before snapshot. Start a new Before snapshot before plan/install.'
    }

    $arguments = @($state.installer_arguments)
    if (-not $PlanOnly) {
        Assert-SasPackageLiveReady -Package $package -Arguments $arguments
    }

    $params = @{
        TargetsCsv = [string]$state.targets_csv
        PackageName = [string]$package.display_name
        InstallerRelativePath = $installerRelativePath
        InstallerArguments = @($arguments)
        InstallMode = [string]$package.default_install_mode
        SoftwareShareRoot = [string]$catalog.software_share_root
        OutputRoot = (Join-Path ([string]$state.run_root) 'software_install')
        MaxTargets = $MaxTargets
    }

    if ($PlanOnly) {
        $result = & $installScript @params -WhatIf
        $state.workflow_status = 'install_planned_whatif'
    }
    else {
        $result = & $installScript @params -AllowTargetMutation -Confirm:$false
        $state.workflow_status = 'install_attempted'
    }

    $state.install_summary_path = [string]$result.operator_handoff_path
    Save-SasState -Root $OutputRoot -State $state | Out-Null
    Write-Host $(if ($PlanOnly) { 'INSTALL PLAN COMPLETE' } else { 'INSTALL ATTEMPT COMPLETE' })
    Write-Host "Package: $($package.display_name)"
    Write-Host "Install evidence: $($state.install_summary_path)"
}

function Start-SasAfter {
    $state = Read-SasState -Root $OutputRoot
    if ($null -eq $state) { throw 'No approved software operator state found. Run BEFORE snapshot first.' }
    Assert-SasBeforeSnapshotReady -ManifestPath ([string]$state.before_manifest_path)

    $catalog = Get-SasApprovedPackageCatalog
    $package = Get-SasPackageById -Catalog $catalog -Id ([string]$state.package_id)
    $targets = @(Get-SasCsvTargets -CsvPath ([string]$state.targets_csv) -Limit $MaxTargets)
    $afterManifest = Invoke-SasSnapshotSet -Phase 'after' -Targets $targets -RunRoot ([string]$state.run_root) -Package $package -Fixture:$FixtureMode
    $after = Get-Content -LiteralPath $afterManifest -Raw | ConvertFrom-Json
    if ([string]$after.snapshot_status -ne 'complete') {
        throw "After snapshot is incomplete: $($after.snapshot_status)"
    }

    $deltaPath = Compare-SasSnapshots -RunRoot ([string]$state.run_root)
    $state.after_manifest_path = $afterManifest
    $state.delta_path = $deltaPath
    $state.workflow_status = 'after_complete'
    Save-SasState -Root $OutputRoot -State $state | Out-Null
    Write-Host "AFTER SNAPSHOT COMPLETE - Package: $($package.display_name)"
    Write-Host "Delta: $deltaPath"
}

function Open-SasLatest {
    $state = Read-SasState -Root $OutputRoot
    if ($null -eq $state) { throw 'No approved software operator state found.' }
    Write-Host "Latest approved software run root: $($state.run_root)"
    if (-not $NoOpen -and (Test-Path -LiteralPath ([string]$state.run_root))) {
        Start-Process -FilePath ([string]$state.run_root) | Out-Null
    }
}

function Show-SasMenu {
    while ($true) {
        Clear-Host
        Write-Host 'SysAdminSuite - Approved Software Install'
        Write-Host 'Catalog: Epic, AllScripts, AutoLogon'
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
            '^1$' { Show-SasApprovedPackages -Catalog (Get-SasApprovedPackageCatalog); pause }
            '^2$' { Start-SasBefore; pause }
            '^3$' { Invoke-SasInstallWrapper -PlanOnly; pause }
            '^4$' { Invoke-SasInstallWrapper; pause }
            '^5$' { Start-SasAfter; pause }
            '^6$' { Open-SasLatest; pause }
            '(?i)^q$' { return }
            default { Write-Warning "Unknown selection: $choice"; pause }
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
