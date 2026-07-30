#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ComputerName,
    [ValidateRange(30,7200)][int]$ResultTimeoutSeconds=1800,
    [switch]$AllowTargetMutation,
    [switch]$ConfirmDeployment,
    [switch]$PassThru
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$targetInput=$ComputerName.Trim()
if ($targetInput -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') { throw "Invalid Cybernet hostname or FQDN: $targetInput" }
if (-not $AllowTargetMutation -or -not $ConfirmDeployment) { throw 'Live deployment requires both -AllowTargetMutation and -ConfirmDeployment.' }

$repoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$catalogPath=Join-Path $repoRoot 'configs\software-packages\windows-native-package-sets.json'
$networkGatePath=Join-Path $repoRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'
$resolverPath=Join-Path $repoRoot 'scripts\SasTargetNameResolution.psm1'
$sessionPath=Join-Path $repoRoot 'scripts\SasOperatorSession.psm1'
$preflightPath=Join-Path $repoRoot 'scripts\Test-SasCybernetClinicalCoreSources.ps1'
$recoveryPath=Join-Path $repoRoot 'scripts\Invoke-SasCybernetCoreRecovery.ps1'
foreach ($required in @($catalogPath,$networkGatePath,$resolverPath,$sessionPath,$preflightPath,$recoveryPath)) { if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing dependency: $required" } }
Import-Module $resolverPath -Force
Import-Module $sessionPath -Force

Write-Host 'NETWORK REQUIRED: PROTECTED NORTHWELL' -ForegroundColor Cyan
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $networkGatePath -Purpose "Cybernet profiled clinical-core deployment to $targetInput" -NonInteractive -NoOpenWifiSettings
if ($LASTEXITCODE -ne 0) {
    [void](Set-SasOperatorNextAction -Network 'PROTECTED NORTHWELL' -Command "sas cybernet Core $targetInput")
    Write-Host 'FAILED PHASE: NETWORK' -ForegroundColor Yellow
    Write-Host 'TARGET MUTATED: NO'
    Write-Host 'NEXT NETWORK: PROTECTED NORTHWELL' -ForegroundColor Cyan
    Write-Host "NEXT COMMAND: sas cybernet Core $targetInput" -ForegroundColor Green
    exit 20
}
$resolution=Resolve-SasCanonicalTargetFqdn -TargetName $targetInput
$target=[string]$resolution.fqdn
[void](Initialize-SasCybernetCoreSession -RepoRoot $repoRoot -TargetInput $targetInput -TargetFqdn $target)
Write-Host '[1/7] NETWORK READY' -ForegroundColor Green
Write-Host "[2/7] TARGET LOCKED: $target" -ForegroundColor Green

$prior=@(Find-SasLatestCybernetCoreEvidence -RepoRoot $repoRoot -TargetFqdn $target)
$priorCompletedIds=@()
if ($prior.Count -gt 0) {
    $priorValue=$prior[0].value
    $priorStatus=[string](Get-SasObjectPropertyValue $priorValue 'status')
    if ($priorStatus -eq 'CYBERNET_PROFILED_CLINICAL_CORE_COMPLETED') {
        Write-Host 'CYBERNET PROFILED CLINICAL CORE ALREADY COMPLETE' -ForegroundColor Green
        Write-Host "Evidence: $($prior[0].path)"
        Write-Host 'AutoLogon remains outside this lane. Imprivata remains observational/external.' -ForegroundColor Yellow
        [void](Set-SasOperatorSessionValues -Values @{ latest_run_id=[string](Get-SasObjectPropertyValue $priorValue 'run_id'); latest_status=$priorStatus; cleanup_status='VERIFIED'; cleanup_outstanding=$false; evidence_path=$prior[0].path; next_required_network='NONE'; next_command='sas evidence Cybernet' })
        exit 0
    }
    $cleanupProven=[bool](Get-SasObjectPropertyValue $priorValue 'cleanup_succeeded' $false)
    if (-not $cleanupProven) {
        $priorRunId=[string](Get-SasObjectPropertyValue $priorValue 'run_id')
        Write-Host "Prior run cleanup is unproven: $priorRunId. Running exact bounded recovery first." -ForegroundColor Yellow
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $recoveryPath -ComputerName $targetInput -RunId $priorRunId
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'FAILED PHASE: RECOVERY' -ForegroundColor Yellow
            Write-Host 'NEXT NETWORK: PROTECTED NORTHWELL' -ForegroundColor Cyan
            Write-Host "NEXT COMMAND: sas cybernet Recover $targetInput" -ForegroundColor Green
            exit $LASTEXITCODE
        }
        $sessionAfterRecovery=Read-SasOperatorSession
        $priorCompletedIds=@($sessionAfterRecovery.completed_package_ids | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
    }
    else {
        foreach ($row in @((Get-SasObjectPropertyValue $priorValue 'package_results' @()))) { if ($row -and [bool](Get-SasObjectPropertyValue $row 'success' $false) -and (Get-SasObjectPropertyValue $row 'id')) { $priorCompletedIds += [string](Get-SasObjectPropertyValue $row 'id') } }
        foreach ($id in @((Get-SasObjectPropertyValue $priorValue 'completed_package_ids' @()))) { if ($id) { $priorCompletedIds += [string]$id } }
        $priorCompletedIds=@($priorCompletedIds | Sort-Object -Unique)
    }
}

$expectedIds=@('allscripts-eehr-shortcut-uai-2-2','epic-downtime-guide-shortcut-1-0','nuance-dragon-medical-one-2025','hyland-fos-epic-integration-23-1-33-1000','bca')
$priorCompletedIds=@($expectedIds | Where-Object { $_ -in $priorCompletedIds })
$runId='cybernet-core-{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'),([guid]::NewGuid().ToString('N').Substring(0,8))
$runRoot=Join-Path $repoRoot "survey\output\runs\cybernet-profiled-clinical-core\$runId"
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$summaryPath=Join-Path $runRoot 'cybernet_profiled_clinical_core_result.json'
$sourcePreflightRoot=Join-Path $runRoot 'source-preflight'
$sourceManifestPath=Join-Path $runRoot 'source_manifest.json'
$targetManifestPath=Join-Path $runRoot 'target_manifest.json'
$profileBeforePath=Join-Path $runRoot 'cybernet_profile_before.json'
$profileAfterPath=Join-Path $runRoot 'cybernet_profile_after.json'
$workerResultLocal=Join-Path $runRoot 'worker_result.json'
$workerCheckpointLocal=Join-Path $runRoot 'worker_checkpoint.json'
$workerLocal=Join-Path $runRoot 'Invoke-CybernetProfiledCoreWorker.ps1'
$taskName="SysAdminSuite-CybernetCore-$runId"
$remoteRunWindows="C:\ProgramData\SysAdminSuite\CybernetProfiledCore\$runId"
$remoteRunUnc="\\$target\C$\ProgramData\SysAdminSuite\CybernetProfiledCore\$runId"
$remoteWorkerWindows=Join-Path $remoteRunWindows 'worker.ps1'
$remoteWorkerUnc=Join-Path $remoteRunUnc 'worker.ps1'
$remoteResultWindows=Join-Path $remoteRunWindows 'worker_result.json'
$remoteResultUnc=Join-Path $remoteRunUnc 'worker_result.json'
$remoteCheckpointWindows=Join-Path $remoteRunWindows 'worker_checkpoint.json'
$remoteCheckpointUnc=Join-Path $remoteRunUnc 'worker_checkpoint.json'
$history=@(
    [pscustomobject][ordered]@{ at_utc=(Get-Date).ToUniversalTime().ToString('o'); phase='NETWORK'; checkpoint='[1/7] NETWORK READY' },
    [pscustomobject][ordered]@{ at_utc=(Get-Date).ToUniversalTime().ToString('o'); phase='TARGET'; checkpoint='[2/7] TARGET LOCKED' }
)
$result=[ordered]@{
    schema_version='sas-cybernet-profiled-clinical-core/v2'; run_id=$runId; target_input=$targetInput; target_fqdn=$target; target_resolution=$resolution
    equipment_profile='Cybernet'; deployment_lane='profiled_clinical_core'; package_set_id='cybernet-clinical-core'; package_ids=$expectedIds
    expected_autologon_state='disabled_preserve_only'; expected_autologon_enabled=$false; autologon_included=$false; autologon_state_preserved=$null
    imprivata_managed_by_this_run=$false; imprivata_disposition='observational/external'; automatic_reboot_performed=$false; reboot_required_but_not_performed=$false
    source_preflight_complete_before_target_mutation=$false; source_preflight_path=$null; source_inventory_drift_package_count=0; source_manifest_path=$sourceManifestPath; target_manifest_path=$targetManifestPath
    target_contact_performed=$false; target_mutation_performed=$false; staging_started=$false; task_name=$taskName; remote_run_unc=$remoteRunUnc
    scheduled_task_created=$false; scheduled_task_started=$false; package_execution_started=$false; completed_package_ids=@($priorCompletedIds); resumed_completed_package_ids=@($priorCompletedIds)
    worker_result_retrieved=$false; cleanup_attempted=$false; cleanup_succeeded=$false; phase='TARGET'; checkpoint='[2/7] TARGET LOCKED'; checkpoint_history=$history
    status='STARTED'; reason=$null; failed_package=$null; package_results=@(); profile_before_path=$profileBeforePath; profile_after_path=$profileAfterPath; worker_result_path=$workerResultLocal; evidence_path=$summaryPath
}
function Get-ResultPropertyBool([string]$Name) { if ($result.Contains($Name) -and $null -ne $result[$Name]) { return [bool]$result[$Name] }; return $false }
function Save-Result {
    $result | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    [void](Set-SasOperatorSessionValues -Values @{
        latest_run_id=$runId; latest_status=[string]$result.status; latest_phase=[string]$result.phase; latest_checkpoint=[string]$result.checkpoint
        cleanup_status=$(if (Get-ResultPropertyBool 'cleanup_succeeded') { 'VERIFIED' } elseif (Get-ResultPropertyBool 'cleanup_attempted') { 'OUTSTANDING_OR_UNPROVEN' } else { 'NOT_REQUIRED_YET' })
        cleanup_outstanding=((Get-ResultPropertyBool 'target_mutation_performed') -and -not (Get-ResultPropertyBool 'cleanup_succeeded'))
        target_contact_performed=(Get-ResultPropertyBool 'target_contact_performed'); target_mutation_performed=(Get-ResultPropertyBool 'target_mutation_performed'); package_execution_started=(Get-ResultPropertyBool 'package_execution_started')
        completed_package_ids=@($result.completed_package_ids); evidence_path=$summaryPath; next_required_network='PROTECTED NORTHWELL'
        next_command=$(if ((Get-ResultPropertyBool 'target_mutation_performed') -and -not (Get-ResultPropertyBool 'cleanup_succeeded')) { "sas cybernet Recover $targetInput" } else { "sas cybernet Core $targetInput" })
    })
}
function Set-Checkpoint([string]$Phase,[string]$Checkpoint) {
    $result.phase=$Phase; $result.checkpoint=$Checkpoint
    $result.checkpoint_history=@($result.checkpoint_history)+@([pscustomobject][ordered]@{ at_utc=(Get-Date).ToUniversalTime().ToString('o'); phase=$Phase; checkpoint=$Checkpoint })
    Save-Result
}
Save-Result

$failure=$null
$deploymentSucceeded=$false
try {
    Set-Checkpoint -Phase 'SOURCE PREFLIGHT' -Checkpoint 'SOURCE PREFLIGHT RUNNING'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $preflightPath -OutputRoot $sourcePreflightRoot
    $preflightExit=$LASTEXITCODE
    $preflightFile=@(Get-ChildItem -LiteralPath $sourcePreflightRoot -Filter 'cybernet_clinical_core_source_preflight.json' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
    $preflight=$null
    if ($preflightFile.Count -eq 1) {
        $result.source_preflight_path=$preflightFile[0].FullName
        $preflight=Get-Content -LiteralPath $preflightFile[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $result.source_inventory_drift_package_count=[int](Get-SasObjectPropertyValue $preflight 'inventory_drift_package_count' 0)
    }
    if ($preflightExit -ne 0 -or $null -eq $preflight -or -not [bool](Get-SasObjectPropertyValue $preflight 'ready_for_target_staging' $false)) { throw "Source preflight failed before target mutation (exit $preflightExit)." }
    $result.source_preflight_complete_before_target_mutation=$true
    Set-Checkpoint -Phase 'SOURCE PREFLIGHT' -Checkpoint '[3/7] SOURCES READY 5/5'
    Write-Host '[3/7] SOURCES READY 5/5' -ForegroundColor Green

    $catalog=Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $packageById=@{}; foreach ($package in @($catalog.packages)) { $packageById[[string]$package.id]=$package }
    $sourcePlan=@()
    foreach ($sourceRow in @($preflight.packages)) {
        $id=[string]$sourceRow.id
        if (-not $packageById.ContainsKey($id)) { throw "Package metadata disappeared after preflight: $id" }
        $package=$packageById[$id]
        $files=@($sourceRow.actual_files | ForEach-Object { [pscustomobject][ordered]@{ relative_path=[string]$_.relative_path; source_path=[string]$_.full_path; length=[int64]$_.length; sha256=[string]$_.sha256 } })
        $sourcePlan += [pscustomobject][ordered]@{ id=$id; display_name=[string]$package.display_name; package_kind=[string]$package.package_kind; installer_type=[string]$package.installer_type; installer_arguments=@($package.installer_arguments | ForEach-Object { [string]$_ }); entrypoint_file=[string]$package.entrypoint_file; files=$files; inventory_drift=[bool]$sourceRow.inventory_drift; source_selection=[string]$sourceRow.source_selection }
    }
    $sourcePlan | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $sourceManifestPath -Encoding UTF8

    $cRoot="\\$target\C$"; $adminRoot="\\$target\ADMIN$"
    $result.target_contact_performed=$true; Save-Result
    if (-not (Test-Path -LiteralPath $adminRoot -PathType Container)) { throw 'ADMIN$ access denied or unavailable.' }
    if (-not (Test-Path -LiteralPath $cRoot -PathType Container)) { throw 'C$ access denied or unavailable.' }
    New-Item -ItemType Directory -Path $remoteRunUnc -Force -ErrorAction Stop | Out-Null
    $result.staging_started=$true; $result.target_mutation_performed=$true; Save-Result

    $stagedPlan=@(); $targetManifest=@()
    foreach ($package in $sourcePlan) {
        $remotePackageUnc=Join-Path $remoteRunUnc $package.id; $remotePackageWindows=Join-Path $remoteRunWindows $package.id
        New-Item -ItemType Directory -Path $remotePackageUnc -Force | Out-Null
        $targetFiles=@()
        foreach ($file in @($package.files)) {
            $destination=Join-Path $remotePackageUnc ([string]$file.relative_path); $parent=Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath ([string]$file.source_path) -Destination $destination -Force -ErrorAction Stop
            $targetHash=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($targetHash -ne ([string]$file.sha256).ToLowerInvariant()) { throw "Target hash mismatch after staging $($package.id)\$($file.relative_path)" }
            $targetFiles += [pscustomobject][ordered]@{ relative_path=[string]$file.relative_path; sha256=$targetHash; length=[int64](Get-Item -LiteralPath $destination).Length }
        }
        $targetManifest += [pscustomobject][ordered]@{ id=$package.id; files=$targetFiles }
        if ($package.id -notin $priorCompletedIds) { $stagedPlan += [pscustomobject][ordered]@{ id=$package.id; display_name=$package.display_name; installer_type=$package.installer_type; entrypoint=Join-Path $remotePackageWindows $package.entrypoint_file; working_directory=$remotePackageWindows; installer_arguments=@($package.installer_arguments) } }
    }
    $targetManifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $targetManifestPath -Encoding UTF8
    Set-Checkpoint -Phase 'TARGET STAGING' -Checkpoint '[4/7] TARGET STAGING HASH VERIFIED'
    Write-Host '[4/7] TARGET STAGING HASH VERIFIED' -ForegroundColor Green

    $workerConfig=[ordered]@{ run_id=$runId; target=$target; result_path=$remoteResultWindows; checkpoint_path=$remoteCheckpointWindows; expected_autologon_enabled=$false; expected_package_ids=$expectedIds; packages=$stagedPlan; prior_completed_package_ids=@($priorCompletedIds) }
    $workerConfigB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($workerConfig | ConvertTo-Json -Depth 24 -Compress)))
    $workerTemplate=@'
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$config=([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CONFIG_B64__'))) | ConvertFrom-Json
function Get-CybernetProfile {
    $autoAdminLogon=$null
    try { $w=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction Stop; $autoAdminLogon=if ($null -eq $w.AutoAdminLogon) { $null } else { [string]$w.AutoAdminLogon } } catch {}
    $apps=@(); foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) { $apps += @(Get-ItemProperty -Path $root -ErrorAction SilentlyContinue | Where-Object { [string]$_.DisplayName -match '(?i)imprivata' } | ForEach-Object { [string]$_.DisplayName }) }
    $services=@()
    try { foreach ($svc in @(Get-CimInstance Win32_Service -ErrorAction Stop | Where-Object { $_.Name -match '(?i)imprivata' -or $_.DisplayName -match '(?i)imprivata' })) { $services += [pscustomobject][ordered]@{ name=[string]$svc.Name; display_name=[string]$svc.DisplayName; status=[string]$svc.State; startup_type=[string]$svc.StartMode } } }
    catch { foreach ($svc in @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)imprivata' -or $_.DisplayName -match '(?i)imprivata' })) { $services += [pscustomobject][ordered]@{ name=$svc.Name; display_name=$svc.DisplayName; status=[string]$svc.Status; startup_type=$null } } }
    [pscustomobject][ordered]@{ captured_at_utc=(Get-Date).ToUniversalTime().ToString('o'); computer_name=$env:COMPUTERNAME; autologon=[ordered]@{ auto_admin_logon=$autoAdminLogon; enabled=($autoAdminLogon -eq '1') }; imprivata=[ordered]@{ observed=($apps.Count -gt 0 -or $services.Count -gt 0); installed_display_names=@($apps | Sort-Object -Unique); services=$services; managed_by_this_run=$false; interpretation='observational/external state only' } }
}
$result=[ordered]@{ schema_version='sas-cybernet-profiled-clinical-core-worker/v2'; run_id=[string]$config.run_id; execution_identity_sid=$null; execution_as_system=$false; profile_before=$null; profile_after=$null; packages=@(); completed_package_ids=@($config.prior_completed_package_ids); overall_success=$false; reboot_required=$false; autologon_state_preserved=$null; expected_autologon_enabled=[bool]$config.expected_autologon_enabled; failed_package_id=$null; error=$null }
function Save-Checkpoint([string]$Phase,[AllowNull()][string]$PackageId) { [pscustomobject][ordered]@{ schema_version='sas-cybernet-profiled-core-worker-checkpoint/v1'; run_id=[string]$config.run_id; updated_at_utc=(Get-Date).ToUniversalTime().ToString('o'); phase=$Phase; package_id=$PackageId; completed_package_ids=@($result.completed_package_ids); packages=@($result.packages) } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath ([string]$config.checkpoint_path) -Encoding UTF8 }
$currentPackage=$null
try {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent(); $result.execution_identity_sid=[string]$identity.User.Value; $result.execution_as_system=($result.execution_identity_sid -eq 'S-1-5-18')
    if (-not $result.execution_as_system) { throw 'Worker did not execute as LocalSystem.' }
    $result.profile_before=Get-CybernetProfile; Save-Checkpoint -Phase 'PROFILE_BEFORE_CAPTURED' -PackageId $null
    if ([bool]$result.profile_before.autologon.enabled -ne [bool]$config.expected_autologon_enabled) { throw "AutoLogon precondition mismatch. Expected enabled=$($config.expected_autologon_enabled); observed enabled=$($result.profile_before.autologon.enabled)." }
    foreach ($package in @($config.packages)) {
        $currentPackage=[string]$package.id; Save-Checkpoint -Phase 'PACKAGE_STARTING' -PackageId $currentPackage
        $entry=[string]$package.entrypoint; $working=[string]$package.working_directory
        if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw "Staged entrypoint missing: $entry" }
        $type=([string]$package.installer_type).ToLowerInvariant()
        if ($type -eq 'msi') { $arguments=@('/i',('"{0}"' -f $entry))+@($package.installer_arguments | ForEach-Object { [string]$_ }); $exitCode=[int](Start-Process -FilePath "$env:WINDIR\System32\msiexec.exe" -ArgumentList $arguments -WorkingDirectory $working -Wait -PassThru -NoNewWindow).ExitCode }
        elseif ($type -eq 'cmd') { $arguments='/d /s /c ""{0}""' -f $entry; $exitCode=[int](Start-Process -FilePath $env:ComSpec -ArgumentList $arguments -WorkingDirectory $working -Wait -PassThru -NoNewWindow).ExitCode }
        elseif ($type -eq 'exe') { $arguments=@($package.installer_arguments | ForEach-Object { [string]$_ }); $exitCode=[int](Start-Process -FilePath $entry -ArgumentList $arguments -WorkingDirectory $working -Wait -PassThru -NoNewWindow).ExitCode }
        else { throw "Unsupported installer type: $type" }
        if ($exitCode -eq 1641) { throw "Package $($package.id) initiated an unauthorized reboot (exit 1641)." }
        $success=($exitCode -in @(0,3010)); if ($exitCode -eq 3010) { $result.reboot_required=$true }
        $row=[pscustomobject][ordered]@{ id=[string]$package.id; display_name=[string]$package.display_name; installer_type=$type; exit_code=$exitCode; success=$success }
        $result.packages=@($result.packages)+@($row); if ($success) { $result.completed_package_ids=@($result.completed_package_ids)+@([string]$package.id) }
        Save-Checkpoint -Phase 'PACKAGE_COMPLETED' -PackageId $currentPackage
        if (-not $success) { throw "Package failed: $($package.id) exit $exitCode" }
        $currentPackage=$null
    }
    $result.profile_after=Get-CybernetProfile; $result.autologon_state_preserved=([bool]$result.profile_before.autologon.enabled -eq [bool]$result.profile_after.autologon.enabled)
    if (-not $result.autologon_state_preserved) { throw 'AutoLogon state changed during the clinical-core run.' }
    if ([bool]$result.profile_after.autologon.enabled -ne [bool]$config.expected_autologon_enabled) { throw 'AutoLogon final state does not match the disabled-preserve-only expectation.' }
    $observed=@($result.completed_package_ids | Sort-Object -Unique); $result.completed_package_ids=@($config.expected_package_ids | Where-Object { $_ -in $observed })
    $result.overall_success=$true; Save-Checkpoint -Phase 'PROFILE_AFTER_CAPTURED' -PackageId $null
}
catch { $result.failed_package_id=$currentPackage; $result.error=$_.Exception.Message; if (-not $result.profile_after) { try { $result.profile_after=Get-CybernetProfile } catch {} }; try { Save-Checkpoint -Phase 'ACTION_REQUIRED' -PackageId $currentPackage } catch {} }
finally { $result | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath ([string]$config.result_path) -Encoding UTF8 }
exit $(if ($result.overall_success) { 0 } else { 1 })
'@
    $workerText=$workerTemplate.Replace('__CONFIG_B64__',$workerConfigB64)
    [IO.File]::WriteAllText($workerLocal,$workerText,(New-Object Text.UTF8Encoding($false)))
    $tokens=$null; $parseErrors=$null; [void][System.Management.Automation.Language.Parser]::ParseFile($workerLocal,[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) { throw "Generated worker parse failure: $($parseErrors[0].Message)" }
    Copy-Item -LiteralPath $workerLocal -Destination $remoteWorkerUnc -Force -ErrorAction Stop

    foreach ($id in $priorCompletedIds) { Write-Host "[resume] $id already complete in prior evidence; installer will NOT repeat." -ForegroundColor Yellow }
    $when=(Get-Date).AddMinutes(1).ToString('HH:mm')
    $taskCommand='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $remoteWorkerWindows
    $createOutput=@(& "$env:WINDIR\System32\schtasks.exe" /Create /S $target /RU SYSTEM /SC ONCE /ST $when /TN $taskName /TR $taskCommand /RL HIGHEST /F 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) { throw "Scheduled-task creation failed: $($createOutput -join ' | ')" }
    $result.scheduled_task_created=$true; Save-Result
    $runOutput=@(& "$env:WINDIR\System32\schtasks.exe" /Run /S $target /TN $taskName 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) { throw "Scheduled-task start failed: $($runOutput -join ' | ')" }
    $result.scheduled_task_started=$true; $result.package_execution_started=$true; Set-Checkpoint -Phase 'SYSTEM INSTALL' -Checkpoint '[5/7] SYSTEM INSTALL RUNNING'
    Write-Host '[5/7] SYSTEM INSTALL RUNNING' -ForegroundColor Green

    $deadline=(Get-Date).AddSeconds($ResultTimeoutSeconds); $lastCompleted=@($priorCompletedIds)
    while (-not (Test-Path -LiteralPath $remoteResultUnc -PathType Leaf)) {
        if (Test-Path -LiteralPath $remoteCheckpointUnc -PathType Leaf) {
            try {
                Copy-Item -LiteralPath $remoteCheckpointUnc -Destination $workerCheckpointLocal -Force
                $checkpoint=Get-Content -LiteralPath $workerCheckpointLocal -Raw -Encoding UTF8 | ConvertFrom-Json
                $completedNow=@($expectedIds | Where-Object { $_ -in @($checkpoint.completed_package_ids) })
                foreach ($newId in @($completedNow | Where-Object { $_ -notin $lastCompleted })) { $position=[Array]::IndexOf($expectedIds,$newId)+1; Write-Host "[$position/5] $newId COMPLETE" -ForegroundColor Green }
                if ($completedNow.Count -ne $lastCompleted.Count) { $lastCompleted=@($completedNow); $result.completed_package_ids=@($completedNow); Save-Result }
            } catch {}
        }
        if ((Get-Date) -ge $deadline) { throw "Timed out waiting for worker result after $ResultTimeoutSeconds seconds." }
        Start-Sleep -Seconds 2
    }

    Copy-Item -LiteralPath $remoteResultUnc -Destination $workerResultLocal -Force -ErrorAction Stop
    if (Test-Path -LiteralPath $remoteCheckpointUnc -PathType Leaf) { Copy-Item -LiteralPath $remoteCheckpointUnc -Destination $workerCheckpointLocal -Force -ErrorAction SilentlyContinue }
    $workerResult=Get-Content -LiteralPath $workerResultLocal -Raw -Encoding UTF8 | ConvertFrom-Json
    $result.worker_result_retrieved=$true
    $workerResult.profile_before | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $profileBeforePath -Encoding UTF8
    $workerResult.profile_after | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $profileAfterPath -Encoding UTF8
    $result.autologon_state_preserved=$workerResult.autologon_state_preserved; $result.reboot_required_but_not_performed=[bool]$workerResult.reboot_required
    $result.completed_package_ids=@($expectedIds | Where-Object { $_ -in @($workerResult.completed_package_ids) })
    $result.failed_package=[string](Get-SasObjectPropertyValue $workerResult 'failed_package_id')
    $priorRows=@($priorCompletedIds | ForEach-Object { [pscustomobject][ordered]@{ id=$_; success=$true; result='preserved_prior_success_not_reexecuted' } }); $result.package_results=@($priorRows)+@($workerResult.packages)
    if (-not [bool]$workerResult.execution_as_system) { throw 'Worker result did not prove LocalSystem execution.' }
    if (-not [bool]$workerResult.autologon_state_preserved) { throw 'Worker result did not prove AutoLogon state preservation.' }
    if (-not [bool]$workerResult.overall_success) { throw "Clinical-core worker failed: $($workerResult.error)" }
    $missingCompletion=@($expectedIds | Where-Object { $_ -notin $result.completed_package_ids })
    if ($missingCompletion.Count -gt 0) { throw "Completion set mismatch. Missing: $($missingCompletion -join ', ')." }
    Set-Checkpoint -Phase 'PROFILE CAPTURE' -Checkpoint '[6/7] BEFORE/AFTER PROFILE CAPTURED'
    Write-Host '[6/7] BEFORE/AFTER PROFILE CAPTURED' -ForegroundColor Green
    $deploymentSucceeded=$true
}
catch { $failure=$_.Exception.Message; $result.reason=$failure; $result.status='ACTION_REQUIRED'; Save-Result; Write-Host "ACTION REQUIRED: $failure" -ForegroundColor Yellow }
finally {
    $result.cleanup_attempted=$true; $taskDeleted=(-not $result.scheduled_task_created); $runDeleted=(-not $result.staging_started)
    if ($result.scheduled_task_created) { try { $deleteOutput=@(& "$env:WINDIR\System32\schtasks.exe" /Delete /S $target /TN $taskName /F 2>&1 | ForEach-Object { [string]$_ }); $taskDeleted=($LASTEXITCODE -eq 0 -or ($deleteOutput -join ' ') -match '(?i)cannot find|does not exist|not exist') } catch { $taskDeleted=$false } }
    if ($result.staging_started) { try { if (Test-Path -LiteralPath $remoteRunUnc) { Remove-Item -LiteralPath $remoteRunUnc -Recurse -Force -ErrorAction Stop }; $runDeleted=(-not (Test-Path -LiteralPath $remoteRunUnc)) } catch { $runDeleted=$false } }
    $result.cleanup_succeeded=($taskDeleted -and $runDeleted)
    if ($result.cleanup_succeeded) { $result.checkpoint='[7/7] CLEANUP VERIFIED'; $result.checkpoint_history=@($result.checkpoint_history)+@([pscustomobject][ordered]@{ at_utc=(Get-Date).ToUniversalTime().ToString('o'); phase='CLEANUP'; checkpoint='[7/7] CLEANUP VERIFIED' }); Write-Host '[7/7] CLEANUP VERIFIED' -ForegroundColor Green }
    if ($deploymentSucceeded -and $result.cleanup_succeeded) { $result.status='CYBERNET_PROFILED_CLINICAL_CORE_COMPLETED'; $result.phase='COMPLETED'; $result.reason=$null }
    elseif (-not $result.cleanup_succeeded) { $result.status='ACTION_REQUIRED'; if (-not $result.reason) { $result.reason='Deployment transaction cleanup is not proven.' } }
    Save-Result
}

if ($result.status -eq 'CYBERNET_PROFILED_CLINICAL_CORE_COMPLETED') {
    [void](Set-SasOperatorSessionValues -Values @{ latest_status=$result.status; cleanup_status='VERIFIED'; cleanup_outstanding=$false; next_required_network='NONE'; next_command='sas evidence Cybernet'; evidence_path=$summaryPath })
    Write-Host 'CYBERNET PROFILED CLINICAL CORE COMPLETED' -ForegroundColor Green
    Write-Host 'Five clinical-core apps complete. AutoLogon untouched/preserved. Imprivata observational only. No reboot performed.'
    Write-Host "Evidence: $summaryPath"
    if ($PassThru) { [pscustomobject]$result }
    exit 0
}
$nextCommand=if (-not $result.cleanup_succeeded -and $result.target_mutation_performed) { "sas cybernet Recover $targetInput" } else { "sas cybernet Core $targetInput" }
[void](Set-SasOperatorSessionValues -Values @{ next_required_network='PROTECTED NORTHWELL'; next_command=$nextCommand; evidence_path=$summaryPath })
Write-Host "FAILED PHASE: $($result.phase)" -ForegroundColor Yellow
Write-Host "TARGET MUTATED: $(if ($result.target_mutation_performed) { 'YES' } else { 'NO' })"
if ($result.failed_package) { Write-Host "FAILED PACKAGE: $($result.failed_package)" }
Write-Host "Evidence: $summaryPath"
Write-Host 'NEXT NETWORK: PROTECTED NORTHWELL' -ForegroundColor Cyan
Write-Host "NEXT COMMAND: $nextCommand" -ForegroundColor Green
if ($PassThru) { [pscustomobject]$result }
exit 1