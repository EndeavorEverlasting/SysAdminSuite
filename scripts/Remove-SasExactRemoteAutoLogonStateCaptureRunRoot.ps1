#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^(?=.{1,253}$)(?=.{1,63}\.)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$')]
    [string]$ComputerName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^autologon-recovery-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$')]
    [string]$RunId,

    [Parameter(Mandatory = $true)]
    [ValidateSet('baseline','after','current')]
    [string]$Phase,

    [Parameter(Mandatory = $true)]
    [switch]$ConfirmExactCleanup,

    [string]$EvidenceRoot,

    [ValidateRange(5,60)]
    [int]$TimeoutSeconds = 20,

    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not $ConfirmExactCleanup) {
    throw 'Exact AutoLogon state-capture cleanup requires -ConfirmExactCleanup.'
}

$boundedModule = Join-Path $PSScriptRoot 'SasBoundedNative.psm1'
$policyModule = Join-Path $PSScriptRoot 'SasAutoLogonStateCaptureCleanupPolicy.psm1'
foreach ($required in @($boundedModule,$policyModule)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required cleanup dependency missing: $required"
    }
}
Import-Module $boundedModule -Force -ErrorAction Stop
Import-Module $policyModule -Force -ErrorAction Stop

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $base = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Join-Path (Split-Path -Parent $PSScriptRoot) 'runs\field-recovery'
    }
    else {
        Join-Path $env:LOCALAPPDATA 'SysAdminSuite\field-runs\autologon-state-recovery-cleanup'
    }
    $EvidenceRoot = Join-Path $base ('cleanup-' + (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))
}
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
$resultPath = Join-Path $EvidenceRoot 'autologon-state-capture-cleanup-result.json'

$remoteRoot = "\\$ComputerName\C$\ProgramData\SysAdminSuite\AutoLogonStateRecovery\$RunId"
$remotePhaseRoot = Join-Path $remoteRoot $Phase
$remoteWorkerResult = Join-Path $remotePhaseRoot 'worker-result.json'

$root64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteRoot))
$phaseResult64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteWorkerResult))
$inventoryScript = @"
`$ErrorActionPreference = 'Stop'
`$root = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$root64'))
`$resultPath = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$phaseResult64'))
if (-not (Test-Path -LiteralPath `$root -PathType Container)) {
    [Console]::Out.Write(([pscustomobject]@{ exists=`$false; entries=@(); worker_result=`$null } | ConvertTo-Json -Depth 8 -Compress))
    exit 0
}
`$entries = @(
    Get-ChildItem -LiteralPath `$root -Force -Recurse -ErrorAction Stop | ForEach-Object {
        `$relative = `$_.FullName.Substring(`$root.Length).TrimStart('\')
        [pscustomobject]@{
            path = [string]`$relative
            kind = `$(if (`$_.PSIsContainer) { 'directory' } else { 'file' })
        }
    }
)
`$worker = `$null
if (Test-Path -LiteralPath `$resultPath -PathType Leaf) {
    `$raw = Get-Content -LiteralPath `$resultPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
    `$worker = [pscustomobject]@{
        schema_version = [string]`$raw.schema_version
        run_id = [string]`$raw.run_id
        phase = [string]`$raw.phase
        result_complete = [bool]`$raw.result_complete
        execution_as_system = [bool]`$raw.execution_as_system
    }
}
[Console]::Out.Write(([pscustomobject]@{ exists=`$true; entries=@(`$entries); worker_result=`$worker } | ConvertTo-Json -Depth 10 -Compress))
exit 0
"@

$inventoryRun = Invoke-SasBoundedPowerShell -ScriptText $inventoryScript -TimeoutSeconds $TimeoutSeconds
if ($inventoryRun.timed_out) { throw 'Timed out inventorying the exact AutoLogon state-capture run root.' }
if ($inventoryRun.exit_code -ne 0) { throw "State-capture run-root inventory failed: $($inventoryRun.error)" }
if ([string]::IsNullOrWhiteSpace([string]$inventoryRun.output)) { throw 'State-capture run-root inventory returned no result.' }
$inventory = $inventoryRun.output | ConvertFrom-Json

$policy = Test-SasAutoLogonStateCaptureCleanupInventory -RunId $RunId -Phase $Phase -Entries @($inventory.entries)
if (-not [bool]$policy.allowed) {
    throw "Exact state-capture run root contains entries outside the cleanup allowlist; refusing cleanup: $(@($policy.unexpected_paths) -join ', ')"
}

$identity = Test-SasAutoLogonStateCaptureWorkerResultIdentity -RunId $RunId -Phase $Phase -WorkerResult $inventory.worker_result
if (-not [bool]$identity.valid) {
    throw 'State-capture worker result identity does not match the requested run/phase; refusing cleanup.'
}

$schtasks = Join-Path $env:WINDIR 'System32\schtasks.exe'
$taskQuery = Invoke-SasBoundedNative -FilePath $schtasks -Arguments @('/Query','/S',$ComputerName,'/FO','CSV','/NH') -TimeoutSeconds $TimeoutSeconds
if ($taskQuery.timed_out) { throw 'Timed out proving AutoLogon state-reader task absence.' }
if ($taskQuery.exit_code -ne 0) {
    throw "Unable to prove AutoLogon state-reader task absence: $($taskQuery.error) $($taskQuery.output)"
}
$taskText = (([string]$taskQuery.output) + [Environment]::NewLine + ([string]$taskQuery.error))
$stateReaderTasks = @(
    $taskText -split "`r?`n" | Where-Object {
        [string]$_ -match 'SysAdminSuite-AutoLogonStateRead-'
    }
)
if ($stateReaderTasks.Count -gt 0) {
    throw "AutoLogon state-reader scheduled task still exists; refusing run-root cleanup: $($stateReaderTasks -join ' | ')"
}

if ([bool]$inventory.exists) {
    $cleanupScript = @"
`$ErrorActionPreference = 'Stop'
`$root = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$root64'))
if (Test-Path -LiteralPath `$root -PathType Container) {
    Remove-Item -LiteralPath `$root -Recurse -Force -ErrorAction Stop
}
if (Test-Path -LiteralPath `$root) { exit 5 }
exit 0
"@
    $cleanup = Invoke-SasBoundedPowerShell -ScriptText $cleanupScript -TimeoutSeconds $TimeoutSeconds
    if ($cleanup.timed_out) { throw 'Timed out removing the exact AutoLogon state-capture run root.' }
    if ($cleanup.exit_code -ne 0) { throw "Exact state-capture run-root removal failed: $($cleanup.error)" }
}

$verifyScript = @"
`$ErrorActionPreference = 'Stop'
`$root = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$root64'))
if (Test-Path -LiteralPath `$root) { exit 5 }
exit 0
"@
$verify = Invoke-SasBoundedPowerShell -ScriptText $verifyScript -TimeoutSeconds $TimeoutSeconds
if ($verify.timed_out) { throw 'Timed out verifying exact AutoLogon state-capture run-root absence.' }
if ($verify.exit_code -ne 0) { throw 'Exact AutoLogon state-capture run root remains after cleanup.' }

$result = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-state-capture-exact-cleanup/v1'
    classification = 'EXACT_REMOTE_AUTOLOGON_STATE_CAPTURE_RUN_ROOT_CLEANED'
    target = $ComputerName
    run_id = $RunId
    phase = $Phase
    root_existed_before_cleanup = [bool]$inventory.exists
    inventory_paths = @($policy.inventory_paths)
    unexpected_paths = @($policy.unexpected_paths)
    worker_result_present = [bool]$identity.present
    worker_result_identity_verified = [bool]$identity.valid
    state_reader_task_count_before_cleanup = $stateReaderTasks.Count
    exact_run_root_absent = $true
    cleanup_scope = 'exact_autologon_state_capture_run_root_only'
    target_mutation_performed = [bool]$inventory.exists
    autologon_configuration_mutation_performed = $false
    software_mutation_performed = $false
    automatic_reboot_performed = $false
    default_password_value_collected = $false
    evidence_path = $resultPath
    completed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
}
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8

if ($PassThru) { return $result }
Write-Host $result.classification -ForegroundColor Green
Write-Host "Evidence: $resultPath"
