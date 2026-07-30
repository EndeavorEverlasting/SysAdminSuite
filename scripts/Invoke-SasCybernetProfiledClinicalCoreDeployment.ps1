#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ComputerName,
    [ValidateRange(30,7200)][int]$ResultTimeoutSeconds = 1800,
    [switch]$AllowTargetMutation,
    [switch]$ConfirmDeployment,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$targetInput = $ComputerName.Trim()
if ($targetInput -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') { throw "Invalid Cybernet hostname or FQDN: $targetInput" }
if (-not $AllowTargetMutation -or -not $ConfirmDeployment) { throw 'Live deployment requires both -AllowTargetMutation and -ConfirmDeployment.' }

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$catalogPath = Join-Path $repoRoot 'configs\software-packages\windows-native-package-sets.json'
$networkGatePath = Join-Path $repoRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'
$resolverPath = Join-Path $repoRoot 'scripts\SasTargetNameResolution.psm1'
$harnessApiPath = Join-Path $repoRoot 'harness\api\sas-harness-api.json'
foreach ($required in @($catalogPath,$networkGatePath,$resolverPath,$harnessApiPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing dependency: $required" }
}

& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $networkGatePath -Purpose "Cybernet profiled clinical-core deployment to $targetInput" -NoOpenWifiSettings
if ($LASTEXITCODE -ne 0) { throw "Network gate stopped deployment with exit code $LASTEXITCODE." }

Import-Module $resolverPath -Force
$resolution = Resolve-SasCanonicalTargetFqdn -TargetName $targetInput
$target = [string]$resolution.fqdn
Write-Host "Canonical target: $target" -ForegroundColor Cyan

$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$catalog.schema_version -ne 'sas-windows-native-package-sets/v1') { throw 'Unsupported package-set catalog schema.' }
$set = @($catalog.package_sets | Where-Object { [string]$_.id -eq 'cybernet-clinical-core' })
if ($set.Count -ne 1) { throw 'cybernet-clinical-core package set is missing or ambiguous.' }
$expectedIds = @(
    'allscripts-eehr-shortcut-uai-2-2',
    'epic-downtime-guide-shortcut-1-0',
    'nuance-dragon-medical-one-2025',
    'hyland-fos-epic-integration-23-1-33-1000',
    'bca'
)
$setIds = @($set[0].package_ids | ForEach-Object { [string]$_ })
if (($setIds -join '|') -ne ($expectedIds -join '|')) { throw 'Tracked clinical-core membership/order drifted.' }
if ($setIds -contains 'autologon') { throw 'AutoLogon is forbidden in the profiled clinical-core lane.' }

$shareRoot = ([string]$catalog.software_share_root).Trim().TrimEnd('\')
$harnessApi = Get-Content -LiteralPath $harnessApiPath -Raw -Encoding UTF8 | ConvertFrom-Json
$approvedRoots = @($harnessApi.posture.approved_software_sources | ForEach-Object { ([string]$_).Trim().TrimEnd('\') })
if (@($approvedRoots | Where-Object { $_.Equals($shareRoot,[StringComparison]::OrdinalIgnoreCase) }).Count -ne 1) {
    throw "Software share root is not the single approved package source: $shareRoot"
}

$packageById = @{}
foreach ($package in @($catalog.packages)) { $packageById[[string]$package.id] = $package }

# Source authority is resolved and fully hashed before ADMIN$, C$, staging, or task creation.
$sourcePlan = @()
foreach ($id in $expectedIds) {
    if (-not $packageById.ContainsKey($id)) { throw "Missing package definition: $id" }
    $package = $packageById[$id]
    if (-not [bool]$package.install_enabled) { throw "Package is disabled: $id" }
    $sourceFolder = Join-Path $shareRoot ([string]$package.source_folder_relative_path)
    if (-not (Test-Path -LiteralPath $sourceFolder -PathType Container)) { throw "Package source folder not found: $sourceFolder" }
    $entrypoint = Join-Path $sourceFolder ([string]$package.entrypoint_file)
    if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) { throw "Package entrypoint not found: $entrypoint" }

    $sourceFiles = @()
    if ([string]$package.package_kind -eq 'bundle') {
        $sourceFiles = @(Get-ChildItem -LiteralPath $sourceFolder -Recurse -File -ErrorAction Stop)
    }
    else {
        foreach ($relativeFile in @($package.staged_files | ForEach-Object { [string]$_ })) {
            if ([string]::IsNullOrWhiteSpace($relativeFile) -or $relativeFile -match '(^|\\)\.\.(\\|$)') { throw "Unsafe staged file path in ${id}: $relativeFile" }
            $sourceFile = Join-Path $sourceFolder $relativeFile
            if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) { throw "Pinned package file not found: $sourceFile" }
            $sourceFiles += Get-Item -LiteralPath $sourceFile -ErrorAction Stop
        }
    }
    if ($sourceFiles.Count -eq 0) { throw "Package source is empty: $sourceFolder" }

    $files = @($sourceFiles | ForEach-Object {
        [pscustomobject][ordered]@{
            relative_path = $_.FullName.Substring($sourceFolder.Length).TrimStart('\')
            source_path = $_.FullName
            length = [int64]$_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    } | Sort-Object relative_path)

    $sourcePlan += [pscustomobject][ordered]@{
        id = $id
        display_name = [string]$package.display_name
        package_kind = [string]$package.package_kind
        installer_type = [string]$package.installer_type
        installer_arguments = @($package.installer_arguments | ForEach-Object { [string]$_ })
        source_folder = $sourceFolder
        entrypoint_file = [string]$package.entrypoint_file
        files = $files
        source_selection = $(if ([string]$package.package_kind -eq 'bundle') { 'all_files_recursive_from_approved_bundle_folder' } else { 'tracked_staged_files_only' })
    }
}
Write-Host 'SOURCE PREFLIGHT READY: 5/5 packages; no target mutation has occurred.' -ForegroundColor Green

$runId = 'cybernet-profiled-core-{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'),([guid]::NewGuid().ToString('N').Substring(0,8))
$runRoot = Join-Path $repoRoot "survey\output\runs\cybernet-profiled-clinical-core\$runId"
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$summaryPath = Join-Path $runRoot 'cybernet_profiled_clinical_core_result.json'
$profileBeforePath = Join-Path $runRoot 'cybernet_profile_before.json'
$profileAfterPath = Join-Path $runRoot 'cybernet_profile_after.json'
$workerResultLocal = Join-Path $runRoot 'worker_result.json'
$workerLocal = Join-Path $runRoot 'Invoke-CybernetProfiledCoreWorker.ps1'
$sourceManifestPath = Join-Path $runRoot 'source_manifest.json'
$sourcePlan | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $sourceManifestPath -Encoding UTF8

$cRoot = "\\$target\C$"
$adminRoot = "\\$target\ADMIN$"
$remoteRunWindows = "C:\ProgramData\SysAdminSuite\CybernetProfiledCore\$runId"
$remoteRunUnc = Join-Path $cRoot "ProgramData\SysAdminSuite\CybernetProfiledCore\$runId"
$remoteWorkerWindows = Join-Path $remoteRunWindows 'worker.ps1'
$remoteWorkerUnc = Join-Path $remoteRunUnc 'worker.ps1'
$remoteResultWindows = Join-Path $remoteRunWindows 'worker_result.json'
$remoteResultUnc = Join-Path $remoteRunUnc 'worker_result.json'
$taskName = 'SysAdminSuite-CybernetProfiledCore-{0}' -f ([guid]::NewGuid().ToString('N'))

$result = [ordered]@{
    schema_version = 'sas-cybernet-profiled-clinical-core/v1'
    run_id = $runId
    target_input = $targetInput
    target_fqdn = $target
    target_resolution = $resolution
    package_set_id = 'cybernet-clinical-core'
    package_ids = $expectedIds
    source_manifest_path = $sourceManifestPath
    source_preflight_complete_before_target_mutation = $true
    bundle_source_policy = 'copy_and_hash_all_files_recursive_from_approved_bundle_folder'
    autologon_included = $false
    autologon_state_preserved = $null
    automatic_reboot_performed = $false
    reboot_required_but_not_performed = $false
    imprivata_managed_by_this_run = $false
    network_gate_passed = $true
    staging_started = $false
    scheduled_task_created = $false
    scheduled_task_started = $false
    worker_result_retrieved = $false
    cleanup_attempted = $false
    cleanup_succeeded = $false
    status = 'STARTED'
    reason = $null
    profile_before_path = $profileBeforePath
    profile_after_path = $profileAfterPath
    worker_result_path = $workerResultLocal
    summary_path = $summaryPath
}
function Save-Result { $result | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $summaryPath -Encoding UTF8 }
Save-Result

$failure = $null
$stagedPlan = @()
try {
    if (-not (Test-Path -LiteralPath $adminRoot -PathType Container)) { throw 'ADMIN$ access denied or unavailable.' }
    if (-not (Test-Path -LiteralPath $cRoot -PathType Container)) { throw 'C$ access denied or unavailable.' }
    New-Item -ItemType Directory -Path $remoteRunUnc -Force -ErrorAction Stop | Out-Null
    $result.staging_started = $true
    Save-Result

    foreach ($package in $sourcePlan) {
        $remotePackageUnc = Join-Path $remoteRunUnc $package.id
        $remotePackageWindows = Join-Path $remoteRunWindows $package.id
        New-Item -ItemType Directory -Path $remotePackageUnc -Force | Out-Null
        foreach ($file in @($package.files)) {
            $destination = Join-Path $remotePackageUnc ([string]$file.relative_path)
            $destinationParent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) { New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null }
            Copy-Item -LiteralPath ([string]$file.source_path) -Destination $destination -Force -ErrorAction Stop
            $targetHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($targetHash -ne [string]$file.sha256) { throw "Target hash mismatch after staging $($package.id)\$($file.relative_path)" }
        }
        $stagedPlan += [pscustomobject][ordered]@{
            id = $package.id
            display_name = $package.display_name
            installer_type = $package.installer_type
            entrypoint = Join-Path $remotePackageWindows $package.entrypoint_file
            working_directory = $remotePackageWindows
            installer_arguments = @($package.installer_arguments)
        }
    }
    Write-Host 'TARGET STAGING HASH-VERIFIED: 5/5 packages.' -ForegroundColor Green

    $workerConfig = [ordered]@{ run_id=$runId; target=$target; result_path=$remoteResultWindows; packages=$stagedPlan }
    $workerConfigB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($workerConfig | ConvertTo-Json -Depth 20 -Compress)))
    $workerTemplate = @'
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$config = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CONFIG_B64__'))) | ConvertFrom-Json
function Get-CybernetProfile {
    $autoAdminLogon = $null
    try {
        $winlogon = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction Stop
        $autoAdminLogon = if ($null -eq $winlogon.AutoAdminLogon) { $null } else { [string]$winlogon.AutoAdminLogon }
    } catch {}
    $imprivataApps = @()
    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        $imprivataApps += @(Get-ItemProperty -Path $root -ErrorAction SilentlyContinue | Where-Object { [string]$_.DisplayName -match '(?i)imprivata' } | ForEach-Object { [string]$_.DisplayName })
    }
    $imprivataServices = @()
    foreach ($service in @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)imprivata' -or $_.DisplayName -match '(?i)imprivata' })) {
        $imprivataServices += [pscustomobject][ordered]@{ name=$service.Name; display_name=$service.DisplayName; status=[string]$service.Status }
    }
    [pscustomobject][ordered]@{
        captured_at_utc=(Get-Date).ToUniversalTime().ToString('o')
        computer_name=$env:COMPUTERNAME
        autologon=[ordered]@{ auto_admin_logon=$autoAdminLogon; enabled=($autoAdminLogon -eq '1') }
        imprivata=[ordered]@{
            observed=($imprivataApps.Count -gt 0 -or $imprivataServices.Count -gt 0)
            installed_display_names=@($imprivataApps | Sort-Object -Unique)
            services=$imprivataServices
            managed_by_this_run=$false
            interpretation='Observational only. Imprivata is a pre-existing or externally managed Cybernet condition and is not installed, removed, or configured by this clinical-core run.'
        }
    }
}
$result = [ordered]@{ schema_version='sas-cybernet-profiled-clinical-core-worker/v1'; run_id=[string]$config.run_id; execution_identity_sid=$null; execution_as_system=$false; profile_before=$null; profile_after=$null; packages=@(); overall_success=$false; reboot_required=$false; autologon_state_preserved=$null; error=$null }
$packageResults = @()
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $result.execution_identity_sid = [string]$identity.User.Value
    $result.execution_as_system = ($result.execution_identity_sid -eq 'S-1-5-18')
    if (-not $result.execution_as_system) { throw 'Worker did not execute as LocalSystem.' }
    $result.profile_before = Get-CybernetProfile
    foreach ($package in @($config.packages)) {
        $entry = [string]$package.entrypoint
        $working = [string]$package.working_directory
        if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw "Staged entrypoint missing: $entry" }
        $type = ([string]$package.installer_type).ToLowerInvariant()
        if ($type -eq 'msi') {
            $arguments = @('/i',('"{0}"' -f $entry)) + @($package.installer_arguments | ForEach-Object { [string]$_ })
            $exitCode = [int](Start-Process -FilePath "$env:WINDIR\System32\msiexec.exe" -ArgumentList $arguments -WorkingDirectory $working -Wait -PassThru -NoNewWindow).ExitCode
        }
        elseif ($type -eq 'cmd') {
            $arguments = '/d /s /c ""{0}""' -f $entry
            $exitCode = [int](Start-Process -FilePath $env:ComSpec -ArgumentList $arguments -WorkingDirectory $working -Wait -PassThru -NoNewWindow).ExitCode
        }
        elseif ($type -eq 'exe') {
            $arguments = @($package.installer_arguments | ForEach-Object { [string]$_ })
            $exitCode = [int](Start-Process -FilePath $entry -ArgumentList $arguments -WorkingDirectory $working -Wait -PassThru -NoNewWindow).ExitCode
        }
        else { throw "Unsupported installer type: $type" }
        if ($exitCode -eq 1641) { throw "Package $($package.id) initiated an unauthorized reboot (exit 1641)." }
        $success = ($exitCode -in @(0,3010))
        if ($exitCode -eq 3010) { $result.reboot_required = $true }
        $packageResults += [pscustomobject][ordered]@{ id=[string]$package.id; display_name=[string]$package.display_name; installer_type=$type; exit_code=$exitCode; success=$success }
        $result.packages = $packageResults
        if (-not $success) { throw "Package failed: $($package.id) exit $exitCode" }
    }
    $result.profile_after = Get-CybernetProfile
    $result.autologon_state_preserved = ([bool]$result.profile_before.autologon.enabled -eq [bool]$result.profile_after.autologon.enabled)
    if (-not $result.autologon_state_preserved) { throw 'AutoLogon state changed during the clinical-core run.' }
    $result.overall_success = $true
}
catch {
    $result.packages = $packageResults
    $result.error = $_.Exception.Message
    if (-not $result.profile_after) { try { $result.profile_after = Get-CybernetProfile } catch {} }
}
finally { $result | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath ([string]$config.result_path) -Encoding UTF8 }
exit $(if ($result.overall_success) { 0 } else { 1 })
'@
    $workerText = $workerTemplate.Replace('__CONFIG_B64__',$workerConfigB64)
    [IO.File]::WriteAllText($workerLocal,$workerText,(New-Object Text.UTF8Encoding($false)))
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($workerLocal,[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) { throw "Generated worker parse failure: $($parseErrors[0].Message)" }
    Copy-Item -LiteralPath $workerLocal -Destination $remoteWorkerUnc -Force -ErrorAction Stop

    $when = (Get-Date).AddMinutes(1).ToString('HH:mm')
    $taskCommand = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $remoteWorkerWindows
    $createOutput = @(& "$env:WINDIR\System32\schtasks.exe" /Create /S $target /RU SYSTEM /SC ONCE /ST $when /TN $taskName /TR $taskCommand /RL HIGHEST /F 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) { throw "Scheduled-task creation failed: $($createOutput -join ' | ')" }
    $result.scheduled_task_created = $true; Save-Result

    $runOutput = @(& "$env:WINDIR\System32\schtasks.exe" /Run /S $target /TN $taskName 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) { throw "Scheduled-task start failed: $($runOutput -join ' | ')" }
    $result.scheduled_task_started = $true; Save-Result

    $deadline = (Get-Date).AddSeconds($ResultTimeoutSeconds)
    while (-not (Test-Path -LiteralPath $remoteResultUnc -PathType Leaf)) {
        if ((Get-Date) -ge $deadline) { throw "Timed out waiting for worker result after $ResultTimeoutSeconds seconds." }
        Start-Sleep -Seconds 2
    }
    Copy-Item -LiteralPath $remoteResultUnc -Destination $workerResultLocal -Force -ErrorAction Stop
    $workerResult = Get-Content -LiteralPath $workerResultLocal -Raw -Encoding UTF8 | ConvertFrom-Json
    $result.worker_result_retrieved = $true
    $workerResult.profile_before | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $profileBeforePath -Encoding UTF8
    $workerResult.profile_after | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $profileAfterPath -Encoding UTF8
    $result.autologon_state_preserved = $workerResult.autologon_state_preserved
    $result.reboot_required_but_not_performed = [bool]$workerResult.reboot_required
    $result.package_results = $workerResult.packages
    if (-not [bool]$workerResult.execution_as_system) { throw 'Worker result did not prove LocalSystem execution.' }
    if (-not [bool]$workerResult.autologon_state_preserved) { throw 'Worker result did not prove AutoLogon state preservation.' }
    if (-not [bool]$workerResult.overall_success) { throw "Clinical-core worker failed: $($workerResult.error)" }
    $result.status = 'CYBERNET_PROFILED_CLINICAL_CORE_COMPLETED'
    Save-Result
    Write-Host "`nCYBERNET PROFILED CLINICAL CORE COMPLETED" -ForegroundColor Green
    Write-Host 'Packages: 5 approved clinical-core applications' -ForegroundColor Green
    Write-Host 'AutoLogon: NOT INCLUDED; existing state preserved.' -ForegroundColor Yellow
    Write-Host 'Imprivata: observational profile only; not managed by this run.' -ForegroundColor Yellow
    Write-Host 'Reboot: NOT PERFORMED.' -ForegroundColor Yellow
    Write-Host "Profile before: $profileBeforePath"
    Write-Host "Profile after:  $profileAfterPath"
    Write-Host "Summary:        $summaryPath"
}
catch {
    $failure = $_.Exception.Message
    $result.status = 'ACTION_REQUIRED'
    $result.reason = $failure
    Save-Result
    Write-Host "`nACTION REQUIRED: $failure" -ForegroundColor Yellow
    Write-Host "Summary: $summaryPath"
}
finally {
    $result.cleanup_attempted = $true
    $taskDeleted = (-not $result.scheduled_task_created)
    $runDeleted = (-not $result.staging_started)
    if ($result.scheduled_task_created) {
        try {
            $deleteOutput = @(& "$env:WINDIR\System32\schtasks.exe" /Delete /S $target /TN $taskName /F 2>&1 | ForEach-Object { [string]$_ })
            $taskDeleted = ($LASTEXITCODE -eq 0 -or ($deleteOutput -join ' ') -match '(?i)cannot find|does not exist|not exist')
        } catch { $taskDeleted = $false }
    }
    if ($result.staging_started) {
        try {
            if (Test-Path -LiteralPath $remoteRunUnc) { Remove-Item -LiteralPath $remoteRunUnc -Recurse -Force -ErrorAction Stop }
            $runDeleted = (-not (Test-Path -LiteralPath $remoteRunUnc))
        } catch { $runDeleted = $false }
    }
    $result.cleanup_succeeded = ($taskDeleted -and $runDeleted)
    Save-Result
}

if ($PassThru) { [pscustomobject]$result }
if ($failure) { throw $failure }
exit 0
