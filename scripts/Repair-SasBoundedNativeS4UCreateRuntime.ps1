#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'C:\SASAL',
    [string]$EvidenceRoot,
    [Parameter(Mandatory = $true)][switch]$ConfirmRepair,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if (-not $ConfirmRepair) { throw 'S4U create-timeout runtime repair requires -ConfirmRepair.' }

$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$targetPath = Join-Path $RuntimeRoot 'scripts\SasBoundedNative.psm1'
if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
    throw "Bounded-native runtime surface missing: $targetPath"
}

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $base = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Join-Path $RuntimeRoot 'runs\field-repair'
    } else {
        Join-Path $env:LOCALAPPDATA 'SysAdminSuite\field-hotfixes'
    }
    $EvidenceRoot = Join-Path $base ('s4u-create-timeout-repair-' + (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))
}
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
$backupPath = Join-Path $EvidenceRoot 'SasBoundedNative.before.psm1'
$resultPath = Join-Path $EvidenceRoot 's4u-create-timeout-runtime-repair-result.json'

function Get-RepairHash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Assert-Parse([string]$Text) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw ('Repaired bounded-native module does not parse: ' + (($errors | ForEach-Object { $_.Message }) -join '; '))
    }
}

function Test-RepairPresent([string]$Text) {
    return ($Text.Contains("`$timeoutPolicy = 's4u_task_create_minimum_60'") -and
        $Text.Contains('reconciled_after_timeout = $true') -and
        $Text.Contains("'^SysAdminSuite-AutoLogonS4U(?:Probe|Install)-[0-9a-fA-F]{32}$'") -and
        $Text.Contains("'/Query','/S',`$s4uCreateTarget,'/TN',`$s4uCreateTaskName"))
}

$source = [IO.File]::ReadAllText($targetPath)
$beforeSha = Get-RepairHash $targetPath
$changed = $false
$classification = 'AUTOLOGON_S4U_CREATE_TIMEOUT_RUNTIME_REPAIR_ALREADY_PRESENT'

if (-not (Test-RepairPresent $source)) {
    Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force -ErrorAction Stop
    $newline = if ($source.Contains("`r`n")) { "`r`n" } else { "`n" }
    $text = $source.Replace("`r`n","`n").Replace("`r","`n")

    $startMarker = 'function Invoke-SasBoundedNative {'
    $endMarker = 'function Test-SasBoundedPath {'
    $start = $text.IndexOf($startMarker, [StringComparison]::Ordinal)
    $end = $text.IndexOf($endMarker, [StringComparison]::Ordinal)
    if ($start -lt 0 -or $end -le $start) {
        throw 'Bounded-native repair function boundaries were not found.'
    }
    if ($text.IndexOf($startMarker, $start + 1, [StringComparison]::Ordinal) -ge 0 -or
        $text.IndexOf($endMarker, $end + 1, [StringComparison]::Ordinal) -ge 0) {
        throw 'Bounded-native repair function boundaries are ambiguous.'
    }

    $replacement = @'
function Invoke-SasBoundedNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [ValidateRange(1,300)][int]$TimeoutSeconds = 30
    )

    # S4U task creation is a remote RPC operation. A controller-side timeout does not prove that
    # the exact GUID-unique task failed to commit remotely. Give only the AutoLogon S4U create
    # operation a larger bounded window and, if it still times out, reconcile only that exact task.
    $requestedTimeoutSeconds = $TimeoutSeconds
    $effectiveTimeoutSeconds = $TimeoutSeconds
    $timeoutPolicy = 'requested'
    $s4uCreateTarget = $null
    $s4uCreateTaskName = $null
    $isExactS4UCreate = $false

    if ([IO.Path]::GetFileName($FilePath).Equals('schtasks.exe', [StringComparison]::OrdinalIgnoreCase)) {
        $hasCreate = @($Arguments | Where-Object { ([string]$_).Equals('/Create', [StringComparison]::OrdinalIgnoreCase) }).Count -eq 1
        for ($i = 0; $i -lt $Arguments.Count - 1; $i++) {
            if (([string]$Arguments[$i]).Equals('/S', [StringComparison]::OrdinalIgnoreCase)) {
                $s4uCreateTarget = [string]$Arguments[$i + 1]
            }
            elseif (([string]$Arguments[$i]).Equals('/TN', [StringComparison]::OrdinalIgnoreCase)) {
                $s4uCreateTaskName = [string]$Arguments[$i + 1]
            }
        }
        $isExactS4UCreate = ($hasCreate -and
            -not [string]::IsNullOrWhiteSpace($s4uCreateTarget) -and
            [string]$s4uCreateTaskName -match '^SysAdminSuite-AutoLogonS4U(?:Probe|Install)-[0-9a-fA-F]{32}$')
    }

    if ($isExactS4UCreate -and $effectiveTimeoutSeconds -lt 60) {
        $effectiveTimeoutSeconds = 60
        $timeoutPolicy = 's4u_task_create_minimum_60'
    }

    $payload = [pscustomobject]@{ file_path=$FilePath; arguments=@($Arguments) } | ConvertTo-Json -Depth 4 -Compress
    $payload64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    $child = @'
$ErrorActionPreference = 'Stop'
$p = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__'))) | ConvertFrom-Json
try {
    $lines = @(& ([string]$p.file_path) @($p.arguments | ForEach-Object { [string]$_ }) 2>&1 | ForEach-Object { [string]$_ })
    if ($lines.Count -gt 0) { [Console]::Out.Write(($lines -join [Environment]::NewLine)) }
    exit [int]$LASTEXITCODE
}
catch {
    [Console]::Error.Write($_.Exception.Message)
    exit 1
}
'@.Replace('__PAYLOAD__', $payload64)

    $result = Invoke-SasBoundedPowerShell -ScriptText $child -TimeoutSeconds $effectiveTimeoutSeconds
    $initialTimedOut = [bool]$result.timed_out
    $reconciledAfterTimeout = $false
    $reconciliation = $null

    if ($isExactS4UCreate -and $initialTimedOut) {
        $reconciliation = Invoke-SasBoundedNative -FilePath $FilePath -Arguments @(
            '/Query','/S',$s4uCreateTarget,'/TN',$s4uCreateTaskName
        ) -TimeoutSeconds $requestedTimeoutSeconds
        $reconciledAfterTimeout = (-not [bool]$reconciliation.timed_out -and [int]$reconciliation.exit_code -eq 0)
    }

    if ($reconciledAfterTimeout) {
        return [pscustomobject][ordered]@{
            file_path = $FilePath
            arguments = @($Arguments)
            process_id = $result.process_id
            exit_code = 0
            timed_out = $false
            timeout_seconds = $effectiveTimeoutSeconds
            requested_timeout_seconds = $requestedTimeoutSeconds
            timeout_policy = $timeoutPolicy
            initial_timed_out = $true
            reconciled_after_timeout = $true
            reconciliation = $reconciliation
            child_tree_termination_attempted = $result.child_tree_termination_attempted
            child_tree_terminated = $result.child_tree_terminated
            output = [string]$reconciliation.output
            error = ''
            initial_error = [string]$result.error
            started_utc = $result.started_utc
            completed_utc = $reconciliation.completed_utc
        }
    }

    [pscustomobject][ordered]@{
        file_path = $FilePath
        arguments = @($Arguments)
        process_id = $result.process_id
        exit_code = $result.exit_code
        timed_out = $result.timed_out
        timeout_seconds = $effectiveTimeoutSeconds
        requested_timeout_seconds = $requestedTimeoutSeconds
        timeout_policy = $timeoutPolicy
        initial_timed_out = $initialTimedOut
        reconciled_after_timeout = $false
        reconciliation = $reconciliation
        child_tree_termination_attempted = $result.child_tree_termination_attempted
        child_tree_terminated = $result.child_tree_terminated
        output = $result.output
        error = $result.error
        initial_error = $null
        started_utc = $result.started_utc
        completed_utc = $result.completed_utc
    }
}

'@

    $candidate = $text.Substring(0,$start) + $replacement + $text.Substring($end)
    if ($newline -eq "`r`n") { $candidate = $candidate.Replace("`n","`r`n") }

    try {
        Assert-Parse $candidate
        if (-not (Test-RepairPresent $candidate)) {
            throw 'S4U create-timeout repair semantic verification failed.'
        }
        [IO.File]::WriteAllText($targetPath, $candidate, (New-Object Text.UTF8Encoding($false)))
        $changed = $true
        $classification = 'AUTOLOGON_S4U_CREATE_TIMEOUT_RUNTIME_REPAIR_APPLIED'
    }
    catch {
        Copy-Item -LiteralPath $backupPath -Destination $targetPath -Force -ErrorAction SilentlyContinue
        throw "S4U CREATE-TIMEOUT REPAIR FAILED; ORIGINAL RESTORED. $($_.Exception.Message)"
    }
}

$final = [IO.File]::ReadAllText($targetPath)
Assert-Parse $final
if (-not (Test-RepairPresent $final)) {
    throw 'S4U create-timeout repair markers are absent after repair.'
}
$afterSha = Get-RepairHash $targetPath
$result = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-s4u-create-timeout-runtime-repair/v1'
    classification = $classification
    runtime_root = $RuntimeRoot
    target_path = $targetPath
    changed = $changed
    before_sha256 = $beforeSha
    after_sha256 = $afterSha
    s4u_create_minimum_timeout_seconds = 60
    exact_task_name_pattern = '^SysAdminSuite-AutoLogonS4U(?:Probe|Install)-[0-9a-fA-F]{32}$'
    exact_query_reconciliation = $true
    powershell_parse_passed = $true
    semantic_verification = $true
    git_performed = $false
    network_activity_performed = $false
    target_contact_performed = $false
    target_mutation_performed = $false
    evidence_path = $resultPath
    completed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
if ($PassThru) { return $result }
Write-Host $result.classification -ForegroundColor Green
Write-Host "Evidence: $resultPath"