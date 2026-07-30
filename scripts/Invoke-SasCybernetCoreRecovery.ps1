#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ComputerName,
    [string]$RunId,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sessionModule = Join-Path $repoRoot 'scripts\SasOperatorSession.psm1'
$resolverPath = Join-Path $repoRoot 'scripts\SasTargetNameResolution.psm1'
$networkGatePath = Join-Path $repoRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'
Import-Module $sessionModule -Force
Import-Module $resolverPath -Force

Write-Host 'NETWORK REQUIRED: PROTECTED NORTHWELL' -ForegroundColor Cyan
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $networkGatePath -Purpose "Cybernet exact recovery for $ComputerName" -NonInteractive -NoOpenWifiSettings
if ($LASTEXITCODE -ne 0) {
    [void](Set-SasOperatorNextAction -Network 'PROTECTED NORTHWELL' -Command "sas cybernet Recover $ComputerName")
    Write-Host 'FAILED PHASE: NETWORK' -ForegroundColor Yellow
    Write-Host 'TARGET MUTATED: NO'
    Write-Host 'NEXT NETWORK: PROTECTED NORTHWELL' -ForegroundColor Cyan
    Write-Host "NEXT COMMAND: sas cybernet Recover $ComputerName" -ForegroundColor Green
    exit 20
}

$resolution = Resolve-SasCanonicalTargetFqdn -TargetName $ComputerName
$target = [string]$resolution.fqdn
[void](Initialize-SasCybernetCoreSession -RepoRoot $repoRoot -TargetInput $ComputerName -TargetFqdn $target)

$evidence = $null
if ([string]::IsNullOrWhiteSpace($RunId)) {
    $found = @(Find-SasLatestCybernetCoreEvidence -RepoRoot $repoRoot -TargetFqdn $target)
    if ($found.Count -gt 0) { $evidence = $found[0] }
    if ($evidence) { $RunId = [string]$evidence.value.run_id }
}
else {
    foreach ($root in @(Get-SasEvidenceRoots -RepoRoot $repoRoot)) {
        $candidate = Join-Path $root "survey\output\runs\cybernet-profiled-clinical-core\$RunId\cybernet_profiled_clinical_core_result.json"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            try { $evidence = [pscustomobject]@{ path=$candidate; value=(Get-Content -LiteralPath $candidate -Raw -Encoding UTF8 | ConvertFrom-Json) } } catch {}
            if ($evidence) { break }
        }
    }
}

if ([string]::IsNullOrWhiteSpace($RunId)) {
    Write-Host 'No prior profiled clinical-core run was found for this target.' -ForegroundColor Green
    [void](Set-SasOperatorSessionValues -Values @{ cleanup_status='VERIFIED'; cleanup_outstanding=$false; next_required_network='PROTECTED NORTHWELL'; next_command="sas cybernet Core $ComputerName" })
    Write-Host 'NEXT NETWORK: PROTECTED NORTHWELL' -ForegroundColor Cyan
    Write-Host "NEXT COMMAND: sas cybernet Core $ComputerName" -ForegroundColor Green
    exit 0
}

if ($RunId -notmatch '^cybernet-(?:profiled-)?core-[A-Za-z0-9-]+$') { throw "Unsafe or unrecognized run ID for bounded recovery: $RunId" }
$remoteRunUnc = "\\$target\C$\ProgramData\SysAdminSuite\CybernetProfiledCore\$RunId"
$remoteCheckpoint = Join-Path $remoteRunUnc 'worker_checkpoint.json'
$recoveryRoot = Join-Path $repoRoot "survey\output\runs\cybernet-profiled-clinical-core-recovery\$RunId"
New-Item -ItemType Directory -Path $recoveryRoot -Force | Out-Null
$recoveryPath = Join-Path $recoveryRoot ('recovery-{0}.json' -f (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))

$scheduledTaskCreated = $false
$knownTaskName = $null
$completedPackageIds = @()
if ($evidence) {
    if ($evidence.value.PSObject.Properties['scheduled_task_created']) { $scheduledTaskCreated = [bool]$evidence.value.scheduled_task_created }
    if ($evidence.value.PSObject.Properties['task_name']) { $knownTaskName = [string]$evidence.value.task_name }
    foreach ($row in @($evidence.value.package_results)) { if ($row -and [bool]$row.success -and $row.id) { $completedPackageIds += [string]$row.id } }
    if ($evidence.value.PSObject.Properties['completed_package_ids']) { $completedPackageIds += @($evidence.value.completed_package_ids | ForEach-Object { [string]$_ }) }
}

$checkpointRetrieved = $false
if (Test-Path -LiteralPath $remoteCheckpoint -PathType Leaf) {
    try {
        $checkpointLocal = Join-Path $recoveryRoot 'worker_checkpoint_recovered.json'
        Copy-Item -LiteralPath $remoteCheckpoint -Destination $checkpointLocal -Force
        $checkpoint = Get-Content -LiteralPath $checkpointLocal -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($id in @($checkpoint.completed_package_ids)) { if ($id) { $completedPackageIds += [string]$id } }
        foreach ($row in @($checkpoint.packages)) { if ($row -and [bool]$row.success -and $row.id) { $completedPackageIds += [string]$row.id } }
        $checkpointRetrieved = $true
    } catch {}
}
$completedPackageIds = @($completedPackageIds | Sort-Object -Unique)

$matchingTasks = New-Object 'System.Collections.Generic.List[string]'
if (-not [string]::IsNullOrWhiteSpace($knownTaskName)) { [void]$matchingTasks.Add($knownTaskName) }
if ($scheduledTaskCreated -and [string]::IsNullOrWhiteSpace($knownTaskName)) {
    $query = @(& "$env:WINDIR\System32\schtasks.exe" /Query /S $target /FO LIST /V 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -eq 0) {
        $blocks = (($query -join "`n") -split "(?:`r?`n){2,}")
        foreach ($block in $blocks) {
            if ($block -notmatch [regex]::Escape($RunId)) { continue }
            $taskLine = @($block -split "`r?`n" | Where-Object { $_ -match '^\s*TaskName\s*:' } | Select-Object -First 1)
            if ($taskLine.Count -eq 1) {
                $name = ($taskLine[0] -replace '^\s*TaskName\s*:\s*','').Trim()
                if ($name -like '\SysAdminSuite-*' -or $name -like 'SysAdminSuite-*') { [void]$matchingTasks.Add($name) }
            }
        }
    }
}

$taskDelete = @()
foreach ($task in @($matchingTasks | Sort-Object -Unique)) {
    $output = @(& "$env:WINDIR\System32\schtasks.exe" /Delete /S $target /TN $task /F 2>&1 | ForEach-Object { [string]$_ })
    $ok = ($LASTEXITCODE -eq 0 -or ($output -join ' ') -match '(?i)cannot find|does not exist|not exist')
    $taskDelete += [pscustomobject][ordered]@{ task_name=$task; deleted_or_absent=$ok; output=$output }
}

$runExistedBefore = Test-Path -LiteralPath $remoteRunUnc
$runDeleteError = $null
if ($runExistedBefore) {
    try { Remove-Item -LiteralPath $remoteRunUnc -Recurse -Force -ErrorAction Stop } catch { $runDeleteError = $_.Exception.Message }
}
$runAbsentAfter = -not (Test-Path -LiteralPath $remoteRunUnc)
$taskCleanupOk = (@($taskDelete | Where-Object { -not $_.deleted_or_absent }).Count -eq 0)
$cleanupSucceeded = ($runAbsentAfter -and $taskCleanupOk)

$result = [pscustomobject][ordered]@{
    schema_version='sas-cybernet-profiled-clinical-core-recovery/v1'
    generated_at_utc=(Get-Date).ToUniversalTime().ToString('o')
    target_input=$ComputerName
    target_fqdn=$target
    recovered_run_id=$RunId
    prior_evidence_path=$(if ($evidence) { $evidence.path } else { $null })
    exact_remote_run_unc=$remoteRunUnc
    run_root_existed_before=$runExistedBefore
    run_root_absent_after=$runAbsentAfter
    run_root_delete_error=$runDeleteError
    scheduled_task_created_in_prior_evidence=$scheduledTaskCreated
    matching_run_owned_tasks=@($matchingTasks | Sort-Object -Unique)
    task_cleanup=$taskDelete
    worker_checkpoint_retrieved=$checkpointRetrieved
    completed_package_ids=$completedPackageIds
    cleanup_succeeded=$cleanupSucceeded
    status=$(if ($cleanupSucceeded) { 'CYBERNET_PROFILED_CLINICAL_CORE_RECOVERY_VERIFIED' } else { 'ACTION_REQUIRED' })
}
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $recoveryPath -Encoding UTF8

[void](Set-SasOperatorSessionValues -Values @{
    latest_run_id=$RunId
    latest_status=$result.status
    latest_phase='RECOVERY'
    latest_checkpoint='RECOVERY VERIFIED'
    cleanup_status=$(if ($cleanupSucceeded) { 'VERIFIED' } else { 'OUTSTANDING_OR_UNPROVEN' })
    cleanup_outstanding=(-not $cleanupSucceeded)
    completed_package_ids=$completedPackageIds
    evidence_path=$recoveryPath
    next_required_network='PROTECTED NORTHWELL'
    next_command=$(if ($cleanupSucceeded) { "sas cybernet Core $ComputerName" } else { "sas cybernet Recover $ComputerName" })
})

if (-not $cleanupSucceeded) {
    Write-Host 'FAILED PHASE: RECOVERY' -ForegroundColor Yellow
    Write-Host 'TARGET MUTATED: RECOVERY-ONLY'
    Write-Host "Evidence: $recoveryPath"
    Write-Host 'NEXT NETWORK: PROTECTED NORTHWELL' -ForegroundColor Cyan
    Write-Host "NEXT COMMAND: sas cybernet Recover $ComputerName" -ForegroundColor Green
    if ($PassThru) { $result }
    exit 51
}

Write-Host "RECOVERY VERIFIED: $RunId" -ForegroundColor Green
Write-Host "Exact run root absent: $remoteRunUnc"
if ($completedPackageIds.Count -gt 0) { Write-Host "Prior completed packages preserved for resume: $($completedPackageIds -join ', ')" -ForegroundColor Yellow }
Write-Host "Evidence: $recoveryPath"
Write-Host 'NEXT NETWORK: PROTECTED NORTHWELL' -ForegroundColor Cyan
Write-Host "NEXT COMMAND: sas cybernet Core $ComputerName" -ForegroundColor Green
if ($PassThru) { $result }
exit 0