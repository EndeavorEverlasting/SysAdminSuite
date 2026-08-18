#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$policyPath = Join-Path $repoRoot 'scripts\SasAutoLogonStateCaptureCleanupPolicy.psm1'
$cleanupPath = Join-Path $repoRoot 'scripts\Remove-SasExactRemoteAutoLogonStateCaptureRunRoot.ps1'
foreach ($required in @($policyPath,$cleanupPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing cleanup test surface: $required" }
}

Import-Module $policyPath -Force -ErrorAction Stop

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}

$runId = 'autologon-recovery-20000101-000000-00000000'
$phase = 'baseline'
$observed = @(
    [pscustomobject]@{ path='baseline'; kind='directory' },
    [pscustomobject]@{ path='baseline\Invoke-StateReadWorker.ps1'; kind='file' },
    [pscustomobject]@{ path='baseline\worker-result.json'; kind='file' }
)

$allowed = Test-SasAutoLogonStateCaptureCleanupInventory -RunId $runId -Phase $phase -Entries $observed
Assert-True ([bool]$allowed.allowed) 'Field-observed baseline worker/result residue was not allowlisted.'
Assert-True (@($allowed.unexpected_paths).Count -eq 0) 'Allowed field residue produced unexpected paths.'

$tmpAllowed = @($observed + [pscustomobject]@{ path='baseline\worker-result.json.tmp'; kind='file' })
$tmp = Test-SasAutoLogonStateCaptureCleanupInventory -RunId $runId -Phase $phase -Entries $tmpAllowed
Assert-True ([bool]$tmp.allowed) 'Atomic worker-result temporary file should be within the exact cleanup profile.'

$unexpectedFile = @($observed + [pscustomobject]@{ path='baseline\notes.txt'; kind='file' })
$unexpected = Test-SasAutoLogonStateCaptureCleanupInventory -RunId $runId -Phase $phase -Entries $unexpectedFile
Assert-True (-not [bool]$unexpected.allowed) 'Unexpected file was accepted by the state-capture cleanup policy.'
Assert-True (@($unexpected.unexpected_paths) -contains 'baseline\notes.txt') 'Unexpected file was not reported.'

$unexpectedPhase = @($observed + [pscustomobject]@{ path='after'; kind='directory' })
$phaseMismatch = Test-SasAutoLogonStateCaptureCleanupInventory -RunId $runId -Phase $phase -Entries $unexpectedPhase
Assert-True (-not [bool]$phaseMismatch.allowed) 'Sibling phase directory was accepted by exact cleanup policy.'

$traversalBlocked = $false
try {
    $null = Test-SasAutoLogonStateCaptureCleanupInventory -RunId $runId -Phase $phase -Entries @(
        [pscustomobject]@{ path='baseline\..\outside.txt'; kind='file' }
    )
}
catch { $traversalBlocked = $true }
Assert-True $traversalBlocked 'Parent traversal inventory entry was not rejected.'

$worker = [pscustomobject]@{
    schema_version='sas-autologon-smb-state-worker-result/v1'
    run_id=$runId
    phase=$phase
    result_complete=$true
    execution_as_system=$true
}
$identity = Test-SasAutoLogonStateCaptureWorkerResultIdentity -RunId $runId -Phase $phase -WorkerResult $worker
Assert-True ([bool]$identity.valid) 'Matching worker-result identity was rejected.'

$wrongRun = $worker.PSObject.Copy()
$wrongRun.run_id = 'autologon-recovery-20000101-000000-11111111'
Assert-True (-not [bool](Test-SasAutoLogonStateCaptureWorkerResultIdentity -RunId $runId -Phase $phase -WorkerResult $wrongRun).valid) `
    'Mismatched worker-result run identity was accepted.'

$wrongPhase = $worker.PSObject.Copy()
$wrongPhase.phase = 'after'
Assert-True (-not [bool](Test-SasAutoLogonStateCaptureWorkerResultIdentity -RunId $runId -Phase $phase -WorkerResult $wrongPhase).valid) `
    'Mismatched worker-result phase identity was accepted.'

$missing = Test-SasAutoLogonStateCaptureWorkerResultIdentity -RunId $runId -Phase $phase -WorkerResult $null
Assert-True (-not [bool]$missing.present -and [bool]$missing.valid) 'Missing result should not block cleanup of an otherwise exact interrupted staging root.'

$cleanupText = [IO.File]::ReadAllText($cleanupPath)
foreach ($marker in @(
    'AutoLogonStateRecovery\$RunId',
    'SysAdminSuite-AutoLogonStateRead-',
    'Test-SasAutoLogonStateCaptureCleanupInventory',
    'Test-SasAutoLogonStateCaptureWorkerResultIdentity',
    "classification = 'EXACT_REMOTE_AUTOLOGON_STATE_CAPTURE_RUN_ROOT_CLEANED'",
    "cleanup_scope = 'exact_autologon_state_capture_run_root_only'",
    'autologon_configuration_mutation_performed = $false',
    'software_mutation_performed = $false',
    'automatic_reboot_performed = $false',
    'Remove-Item -LiteralPath `$root -Recurse -Force -ErrorAction Stop'
)) {
    Assert-True ($cleanupText.Contains($marker)) "Exact cleanup script missing contract marker: $marker"
}

$policyIndex = $cleanupText.IndexOf('Test-SasAutoLogonStateCaptureCleanupInventory -RunId $RunId')
$identityIndex = $cleanupText.IndexOf('Test-SasAutoLogonStateCaptureWorkerResultIdentity -RunId $RunId')
$taskIndex = $cleanupText.IndexOf("'/Query','/S',`$ComputerName")
$removeIndex = $cleanupText.IndexOf('Remove-Item -LiteralPath `$root -Recurse -Force -ErrorAction Stop')
Assert-True ($policyIndex -ge 0 -and $identityIndex -gt $policyIndex -and $taskIndex -gt $identityIndex -and $removeIndex -gt $taskIndex) `
    'Cleanup ordering must be inventory policy -> worker identity -> task absence -> exact removal.'

foreach ($forbidden in @(
    "'/Delete'",
    'Remove-Item -Path ',
    'AutoLogonKerberosS4U\$RunId',
    'DefaultPassword',
    'NW_AutoLogon_Setup_x64.exe'
)) {
    Assert-True (-not $cleanupText.Contains($forbidden)) "Exact state-capture cleanup contains forbidden broader behavior: $forbidden"
}

Write-Host 'PASS: exact AutoLogon state-capture residue cleanup policy and ordering contracts'
