#Requires -Version 5.1
<#
.SYNOPSIS
Technician-facing Auto Didact install capsule with required before/after snapshots.

.DESCRIPTION
This wrapper enforces a read-only BEFORE software snapshot before any Auto Didact target
mutation, delegates installation to Invoke-SasSoftwareInstall.ps1, then captures an AFTER
snapshot and local delta. Evidence is written only on the admin workstation under
survey/output/autodidact_install. It does not store credentials, suppress logs, clear events,
or create target persistence.
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Before', 'Plan', 'Install', 'After', 'OpenLatest')]
    [string]$Action = 'Menu',

    [string]$TargetsCsv,
    [string]$InstallerRelativePath,
    [string[]]$InstallerArguments = @('/quiet', '/norestart'),
    [ValidateSet('UncDirect', 'CopyThenInstall')]
    [string]$InstallMode = 'UncDirect',
    [string]$SoftwareShareRoot,
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
if (-not (Test-Path -LiteralPath $installScript -PathType Leaf)) { throw "Canonical install wrapper not found: $installScript" }

if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $repoRoot 'survey/output/autodidact_install' }
Assert-SasApprovedOutputPath -Path $OutputRoot -RepoRoot $repoRoot -Role 'Auto Didact install output directory'

function Write-SasJsonFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-SasStatePath { param([string]$Root) Join-Path $Root 'operator-state.json' }
function Read-SasState {
    param([string]$Root)
    $statePath = Get-SasStatePath -Root $Root
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
}
function Save-SasState { param([string]$Root, [Parameter(Mandatory)]$State) $path = Get-SasStatePath -Root $Root; Write-SasJsonFile -Path $path -Value $State; $path }
function ConvertTo-SasSafeName { param([string]$Value) if ([string]::IsNullOrWhiteSpace($Value)) { 'blank' } else { $Value.Trim() -replace '[^A-Za-z0-9._-]', '_' } }

function Get-SasCsvTargets {
    param([Parameter(Mandatory)][string]$CsvPath, [int]$Limit)
    Assert-SasApprovedInputPath -Path $CsvPath -RepoRoot $repoRoot -Role 'Auto Didact target manifest' -AllowStaging
    $items = New-Object System.Collections.Generic.List[string]
    foreach ($row in @(Import-Csv -LiteralPath $CsvPath)) {
        foreach ($column in @('ComputerName', 'HostName', 'Hostname', 'Target')) {
            if ($row.PSObject.Properties.Name -contains $column -and -not [string]::IsNullOrWhiteSpace([string]$row.$column)) { $items.Add(([string]$row.$column).Trim()); break }
        }
    }
    $targets = @($items | Sort-Object -Unique)
    if ($targets.Count -eq 0) { throw 'No targets were supplied. Use a CSV with ComputerName, HostName, Hostname, or Target column.' }
    if ($targets.Count -gt $Limit) { throw "Target count $($targets.Count) exceeds MaxTargets $Limit. Split the Auto Didact pilot batch." }
    @($targets)
}

function New-SasRunId { 'autodidact-install-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8)) }

function New-SasFixtureSnapshot {
    param([string]$Target, [string]$Phase)
    $software = @([pscustomobject]@{ name = 'Contoso Base Agent'; version = '1.0.0'; publisher = 'Contoso'; install_date = '20260101'; registry_path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ContosoBase' })
    if ($Phase -eq 'after') { $software += [pscustomobject]@{ name = 'Auto Didact'; version = '1.0.0'; publisher = 'Auto Didact'; install_date = (Get-Date -Format 'yyyyMMdd'); registry_path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AutoDidact' } }
    [pscustomobject]@{ schema_version = 'sas-autodidact-software-snapshot/v1'; snapshot_phase = $Phase; requested_target = $Target; computer_name = $Target.ToUpperInvariant(); collection_status = 'success'; error = $null; captured_at_utc = (Get-Date).ToUniversalTime().ToString('o'); identity = [pscustomobject]@{ os_caption = 'Microsoft Windows 11 Enterprise'; os_version = '10.0.26100'; last_boot_time_utc = '2026-07-14T00:00:00Z'; logged_on_user = 'FIXTURE\TECH' }; installed_software = @($software); target_mutation_performed = $false; target_side_sysadminsuite_artifacts_written = $false; collection_notes = @('fixture_mode', 'no_network_activity', 'no_target_mutation') }
}

$softwareSnapshotBlock = {
    param([string]$Phase)
    Set-StrictMode -Version 2.0
    $ErrorActionPreference = 'Stop'
    function Get-InstalledSoftwareSafe {
        $roots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
        $rows = foreach ($root in $roots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                try {
                    $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                    $name = ([string]$item.DisplayName).Trim()
                    if ([string]::IsNullOrWhiteSpace($name)) { continue }
                    [pscustomobject]@{ name = $name; version = ([string]$item.DisplayVersion).Trim(); publisher = ([string]$item.Publisher).Trim(); install_date = ([string]$item.InstallDate).Trim(); registry_path = $key.Name }
                } catch {}
            }
        }
        @($rows | Sort-Object -Property name, publisher, version, registry_path -Unique)
    }
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    [pscustomobject]@{ schema_version = 'sas-autodidact-software-snapshot/v1'; snapshot_phase = $Phase; requested_target = $env:COMPUTERNAME; computer_name = $env:COMPUTERNAME; collection_status = 'success'; error = $null; captured_at_utc = (Get-Date).ToUniversalTime().ToString('o'); identity = [pscustomobject]@{ os_caption = [string]$os.Caption; os_version = [string]$os.Version; last_boot_time_utc = $os.LastBootUpTime.ToUniversalTime().ToString('o'); logged_on_user = [string]$cs.UserName }; installed_software = @(Get-InstalledSoftwareSafe); target_mutation_performed = $false; target_side_sysadminsuite_artifacts_written = $false; collection_notes = @('remote_read_only_snapshot', 'no_target_side_sysadminsuite_artifacts') }
}

function Invoke-SasSnapshotSet {
    param([Parameter(Mandatory)][string]$Phase, [Parameter(Mandatory)][string[]]$Targets, [Parameter(Mandatory)][string]$RunRoot, [switch]$Fixture)
    $phaseRoot = Join-Path $RunRoot $Phase
    New-Item -ItemType Directory -Path $phaseRoot -Force | Out-Null
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($target in $Targets) {
        $snapshotPath = Join-Path $phaseRoot ((ConvertTo-SasSafeName -Value $target) + '.json')
        try {
            if ($Fixture) { $snapshot = New-SasFixtureSnapshot -Target $target -Phase $Phase }
            else {
                $sessionOption = New-PSSessionOption -OpenTimeout 30000 -OperationTimeout 300000
                $session = New-PSSession -ComputerName $target -SessionOption $sessionOption
                try { $snapshot = Invoke-Command -Session $session -ScriptBlock $softwareSnapshotBlock -ArgumentList $Phase; $snapshot.requested_target = $target }
                finally { if ($session) { Remove-PSSession -Session $session } }
            }
            Write-SasJsonFile -Path $snapshotPath -Value $snapshot
            $rows.Add([pscustomobject]@{ target = $target; status = $snapshot.collection_status; path = $snapshotPath; error = $snapshot.error })
        } catch {
            $failure = [pscustomobject]@{ schema_version = 'sas-autodidact-software-snapshot/v1'; snapshot_phase = $Phase; requested_target = $target; computer_name = $target; collection_status = 'failed'; error = $_.Exception.Message; captured_at_utc = (Get-Date).ToUniversalTime().ToString('o'); installed_software = @(); target_mutation_performed = $false; target_side_sysadminsuite_artifacts_written = $false }
            Write-SasJsonFile -Path $snapshotPath -Value $failure
            $rows.Add([pscustomobject]@{ target = $target; status = 'failed'; path = $snapshotPath; error = $_.Exception.Message })
        }
    }
    $failed = @($rows | Where-Object { $_.status -ne 'success' })
    $manifest = [pscustomobject]@{ schema_version = 'sas-autodidact-snapshot-manifest/v1'; phase = $Phase; run_root = $RunRoot; target_count = $Targets.Count; success_count = $Targets.Count - $failed.Count; failed_count = $failed.Count; snapshot_status = $(if ($failed.Count -eq 0) { 'complete' } else { 'incomplete' }); snapshots = @($rows); guardrails = @('read_only_snapshot_before_install', 'read_only_snapshot_after_install', 'admin_box_evidence_only', 'no_target_side_sysadminsuite_artifacts', 'no_default_password_or_secret_collection', 'no_target_mutation_from_snapshot') }
    $manifestPath = Join-Path $phaseRoot 'snapshot-manifest.json'
    Write-SasJsonFile -Path $manifestPath -Value $manifest
    $manifestPath
}

function Assert-SasBeforeSnapshotReady {
    param([Parameter(Mandatory)][string]$ManifestPath)
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw 'Before snapshot must complete before Auto Didact install. Missing before snapshot manifest.' }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    if ([string]$manifest.snapshot_status -ne 'complete') { throw "Before snapshot must complete before Auto Didact install. Current status: $($manifest.snapshot_status)" }
    if ([int]$manifest.target_count -le 0) { throw 'Before snapshot must contain at least one approved target before Auto Didact install.' }
}

function Get-SasSoftwareKeys { param([object[]]$Software) @($Software | ForEach-Object { '{0}|{1}|{2}' -f ([string]$_.name).ToUpperInvariant(), ([string]$_.publisher).ToUpperInvariant(), ([string]$_.version).ToUpperInvariant() } | Sort-Object -Unique) }
function Compare-SasSnapshots {
    param([Parameter(Mandatory)][string]$RunRoot)
    $beforeRoot = Join-Path $RunRoot 'before'; $afterRoot = Join-Path $RunRoot 'after'
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($afterFile in @(Get-ChildItem -LiteralPath $afterRoot -Filter '*.json' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'snapshot-manifest.json' })) {
        $beforeFile = Join-Path $beforeRoot $afterFile.Name
        if (-not (Test-Path -LiteralPath $beforeFile -PathType Leaf)) { continue }
        $before = Get-Content -LiteralPath $beforeFile -Raw | ConvertFrom-Json; $after = Get-Content -LiteralPath $afterFile.FullName -Raw | ConvertFrom-Json
        $beforeKeys = @(Get-SasSoftwareKeys -Software @($before.installed_software)); $afterKeys = @(Get-SasSoftwareKeys -Software @($after.installed_software))
        $added = @($afterKeys | Where-Object { $beforeKeys -notcontains $_ }); $removed = @($beforeKeys | Where-Object { $afterKeys -notcontains $_ })
        $rows.Add([pscustomobject]@{ target = [string]$after.requested_target; added_software_count = $added.Count; removed_software_count = $removed.Count; added_software_keys = @($added); removed_software_keys = @($removed) })
    }
    $delta = [pscustomobject]@{ schema_version = 'sas-autodidact-install-delta/v1'; run_root = $RunRoot; target_count = $rows.Count; result = $(if (@($rows | Where-Object { $_.added_software_count -gt 0 }).Count -gt 0) { 'SOFTWARE_DELTA_OBSERVED' } else { 'NO_SOFTWARE_DELTA_OBSERVED' }); proof_boundary = 'snapshot_delta_does_not_prove_app_launch_or_user_acceptance'; deltas = @($rows) }
    $deltaPath = Join-Path $RunRoot 'autodidact-install-delta.json'
    Write-SasJsonFile -Path $deltaPath -Value $delta
    $deltaPath
}

function Get-SasRequiredInput { param([string]$Existing, [string]$Prompt, [switch]$Required) if (-not [string]::IsNullOrWhiteSpace($Existing)) { return $Existing }; if ($NonInteractive -and $Required) { throw "Missing required noninteractive value: $Prompt" }; if ($NonInteractive) { return $Existing }; Read-Host $Prompt }

function Start-SasBefore {
    $effectiveTargetsCsv = Get-SasRequiredInput -Existing $TargetsCsv -Prompt 'Targets CSV under targets/local/ or survey/input/' -Required
    $effectiveInstallerRelativePath = Get-SasRequiredInput -Existing $InstallerRelativePath -Prompt 'Auto Didact installer path relative to approved software root' -Required
    $targets = @(Get-SasCsvTargets -CsvPath $effectiveTargetsCsv -Limit $MaxTargets)
    $runId = New-SasRunId; $runRoot = Join-Path $OutputRoot $runId; New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    $beforeManifest = Invoke-SasSnapshotSet -Phase 'before' -Targets $targets -RunRoot $runRoot -Fixture:$FixtureMode
    Assert-SasBeforeSnapshotReady -ManifestPath $beforeManifest
    $state = [ordered]@{ schema_version = 'sas-autodidact-install-state/v1'; active_run_id = $runId; run_root = $runRoot; targets_csv = $effectiveTargetsCsv; installer_relative_path = $effectiveInstallerRelativePath; installer_arguments = @($InstallerArguments); install_mode = $InstallMode; software_share_root = $SoftwareShareRoot; before_manifest_path = $beforeManifest; install_summary_path = $null; after_manifest_path = $null; delta_path = $null; workflow_status = 'before_complete'; target_count = $targets.Count; snapshot_required_before_install = $true }
    $statePath = Save-SasState -Root $OutputRoot -State $state
    Write-Host "BEFORE SNAPSHOT COMPLETE - State: $statePath"; Write-Host "Run root: $runRoot"
}

function Invoke-SasInstallWrapper {
    param([switch]$PlanOnly)
    $state = Read-SasState -Root $OutputRoot
    if ($null -eq $state) { throw 'No Auto Didact operator state found. Run BEFORE snapshot first.' }
    Assert-SasBeforeSnapshotReady -ManifestPath ([string]$state.before_manifest_path)
    $params = @{ TargetsCsv = [string]$state.targets_csv; PackageName = 'Auto Didact'; InstallerRelativePath = [string]$state.installer_relative_path; InstallerArguments = @($state.installer_arguments); InstallMode = [string]$state.install_mode; OutputRoot = (Join-Path ([string]$state.run_root) 'software_install'); MaxTargets = $MaxTargets }
    if (-not [string]::IsNullOrWhiteSpace([string]$state.software_share_root)) { $params['SoftwareShareRoot'] = [string]$state.software_share_root }
    if ($PlanOnly) { $result = & $installScript @params -WhatIf; $state.workflow_status = 'install_planned_whatif' }
    else { $result = & $installScript @params -AllowTargetMutation -Confirm:$false; $state.workflow_status = 'install_attempted' }
    $state.install_summary_path = [string]$result.operator_handoff_path
    Save-SasState -Root $OutputRoot -State $state | Out-Null
    Write-Host $(if ($PlanOnly) { 'INSTALL PLAN COMPLETE' } else { 'INSTALL ATTEMPT COMPLETE' })
    Write-Host "Install evidence: $($state.install_summary_path)"
}

function Start-SasAfter {
    $state = Read-SasState -Root $OutputRoot
    if ($null -eq $state) { throw 'No Auto Didact operator state found. Run BEFORE snapshot first.' }
    Assert-SasBeforeSnapshotReady -ManifestPath ([string]$state.before_manifest_path)
    $targets = @(Get-SasCsvTargets -CsvPath ([string]$state.targets_csv) -Limit $MaxTargets)
    $afterManifest = Invoke-SasSnapshotSet -Phase 'after' -Targets $targets -RunRoot ([string]$state.run_root) -Fixture:$FixtureMode
    $after = Get-Content -LiteralPath $afterManifest -Raw | ConvertFrom-Json
    if ([string]$after.snapshot_status -ne 'complete') { throw "After snapshot is incomplete: $($after.snapshot_status)" }
    $deltaPath = Compare-SasSnapshots -RunRoot ([string]$state.run_root)
    $state.after_manifest_path = $afterManifest; $state.delta_path = $deltaPath; $state.workflow_status = 'after_complete'
    Save-SasState -Root $OutputRoot -State $state | Out-Null
    Write-Host "AFTER SNAPSHOT COMPLETE - Delta: $deltaPath"
}

function Open-SasLatest {
    $state = Read-SasState -Root $OutputRoot
    if ($null -eq $state) { throw 'No Auto Didact operator state found.' }
    Write-Host "Latest Auto Didact run root: $($state.run_root)"
    if (-not $NoOpen -and (Test-Path -LiteralPath ([string]$state.run_root))) { Start-Process -FilePath ([string]$state.run_root) | Out-Null }
}

function Show-SasMenu {
    while ($true) {
        Clear-Host; Write-Host 'SysAdminSuite - Auto Didact Install'; Write-Host ''; Write-Host '[1] Capture BEFORE snapshot'; Write-Host '[2] Plan Auto Didact install (WhatIf)'; Write-Host '[3] Install Auto Didact after confirmed BEFORE snapshot'; Write-Host '[4] Capture AFTER snapshot and compare'; Write-Host '[5] Open latest evidence folder'; Write-Host '[Q] Quit'; Write-Host ''
        $choice = Read-Host 'Select action'
        switch -Regex ($choice) { '^1$' { Start-SasBefore; pause } '^2$' { Invoke-SasInstallWrapper -PlanOnly; pause } '^3$' { Invoke-SasInstallWrapper; pause } '^4$' { Start-SasAfter; pause } '^5$' { Open-SasLatest; pause } '(?i)^q$' { return } default { Write-Warning "Unknown selection: $choice"; pause } }
    }
}

switch ($Action) { 'Before' { Start-SasBefore } 'Plan' { Invoke-SasInstallWrapper -PlanOnly } 'Install' { Invoke-SasInstallWrapper } 'After' { Start-SasAfter } 'OpenLatest' { Open-SasLatest } 'Menu' { Show-SasMenu } }
