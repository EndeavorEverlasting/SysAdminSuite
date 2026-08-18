#Requires -Version 5.1
<#
.SYNOPSIS
Repairs the protected AutoLogon runtime so SMB state-capture task cleanup cannot mask the real capture result.

.DESCRIPTION
Local-only emergency repair for an already prepared SysAdminSuite AutoLogon runtime.
It performs no Git activity, no network activity, and no target contact or mutation.

The sealed state-capture module historically invoked schtasks.exe directly while
$ErrorActionPreference was Stop. On Windows PowerShell 5.1 an expected absent-task
message written to native stderr can therefore terminate cleanup before the code
can inspect the native exit code. The field symptom is a bare:

    ERROR: The system cannot find the file specified.

This repair replaces only the internal schtasks wrapper with the repository's
bounded native runner. stdout and stderr are combined into the wrapper's existing
output contract, so expected absent-task text remains classifiable without becoming
a terminating PowerShell error. The original module is backed up and restored on
any transform or parser failure.
#>
[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'C:\SASAL',
    [string]$EvidenceRoot,
    [switch]$ConfirmRepair,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not $ConfirmRepair) {
    throw 'State-capture runtime repair requires -ConfirmRepair.'
}

$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$modulePath = Join-Path $RuntimeRoot 'scripts\SasAutoLogonSmbStateRecovery.psm1'
$boundedPath = Join-Path $RuntimeRoot 'scripts\SasBoundedNative.psm1'
foreach ($required in @($modulePath, $boundedPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required runtime repair surface missing: $required"
    }
}

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $base = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Join-Path $RuntimeRoot 'runs\field-hotfixes'
    }
    else {
        Join-Path $env:LOCALAPPDATA 'SysAdminSuite\field-hotfixes'
    }
    $EvidenceRoot = Join-Path $base ('smb-state-capture-repair-' + (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))
}
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null

$backupPath = Join-Path $EvidenceRoot 'SasAutoLogonSmbStateRecovery.before.psm1'
$resultPath = Join-Path $EvidenceRoot 'smb-state-capture-runtime-repair-result.json'
Copy-Item -LiteralPath $modulePath -Destination $backupPath -Force

function Get-SasStateRepairSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = $null
    $sha = $null
    try {
        $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $sha = [Security.Cryptography.SHA256]::Create()
        return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()
    }
    finally {
        if ($null -ne $sha) { $sha.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Assert-SasStateRepairParse {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) {
        $detail = (@($errors | ForEach-Object { $_.Message }) -join '; ')
        throw "PowerShell parser rejected repaired surface ${Label}: $detail"
    }
}

function Replace-SasStateRepairFunction {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$FunctionAnchor,
        [Parameter(Mandatory = $true)][string]$NextFunctionAnchor,
        [Parameter(Mandatory = $true)][string]$Replacement
    )

    $start = $Text.IndexOf($FunctionAnchor,[StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Repair function anchor not found: $FunctionAnchor" }
    if ($Text.IndexOf($FunctionAnchor,$start + $FunctionAnchor.Length,[StringComparison]::Ordinal) -ge 0) {
        throw "Repair function anchor is ambiguous: $FunctionAnchor"
    }

    $next = $Text.IndexOf($NextFunctionAnchor,$start + $FunctionAnchor.Length,[StringComparison]::Ordinal)
    if ($next -lt 0) { throw "Repair next-function anchor not found: $NextFunctionAnchor" }
    if ($Text.IndexOf($NextFunctionAnchor,$next + $NextFunctionAnchor.Length,[StringComparison]::Ordinal) -ge 0) {
        throw "Repair next-function anchor is ambiguous: $NextFunctionAnchor"
    }

    return $Text.Remove($start,$next - $start).Insert($start,$Replacement)
}

$beforeSha256 = Get-SasStateRepairSha256 -Path $modulePath
$classification = 'AUTOLOGON_SMB_STATE_CAPTURE_RUNTIME_REPAIR_APPLIED'

try {
    $text = [IO.File]::ReadAllText($modulePath)

    $alreadyPresent = (
        $text.Contains('Invoke-SasBoundedNative -FilePath $schtasksPath') -and
        $text.Contains('native_stderr_is_data_not_terminating_error') -and
        -not $text.Contains('$output = @(& "$env:WINDIR\System32\schtasks.exe" @Arguments 2>&1')
    )

    if ($alreadyPresent) {
        Assert-SasStateRepairParse -Text $text -Label $modulePath
        $classification = 'AUTOLOGON_SMB_STATE_CAPTURE_RUNTIME_REPAIR_ALREADY_PRESENT'
    }
    else {
        $replacement = @'
function Invoke-SasAutoLogonRecoverySchtasksCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [ValidateRange(5,120)][int]$TimeoutSeconds = 30
    )

    # native_stderr_is_data_not_terminating_error
    # Expected schtasks absence responses are written to stderr. Run the native
    # command inside the bounded child-process adapter so module-level
    # ErrorActionPreference=Stop cannot convert that expected stderr into a
    # terminating PowerShell error before LASTEXITCODE is classified.
    $boundedModule = Join-Path $PSScriptRoot 'SasBoundedNative.psm1'
    Import-Module $boundedModule -ErrorAction Stop
    $schtasksPath = Join-Path $env:WINDIR 'System32\schtasks.exe'
    $run = Invoke-SasBoundedNative -FilePath $schtasksPath -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds

    $lines = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$run.output)) {
        $lines += ([string]$run.output).Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$run.error)) {
        $lines += ([string]$run.error).Trim()
    }

    [pscustomobject]@{
        exit_code = [int]$run.exit_code
        timed_out = [bool]$run.timed_out
        timeout_seconds = [int]$run.timeout_seconds
        output = ($lines -join [Environment]::NewLine)
    }
}

'@

        $text = Replace-SasStateRepairFunction -Text $text `
            -FunctionAnchor 'function Invoke-SasAutoLogonRecoverySchtasksCommand {' `
            -NextFunctionAnchor 'function Test-SasAutoLogonRecoveryTaskAbsentText {' `
            -Replacement $replacement

        foreach ($marker in @(
            'native_stderr_is_data_not_terminating_error',
            "Join-Path `$PSScriptRoot 'SasBoundedNative.psm1'",
            'Invoke-SasBoundedNative -FilePath $schtasksPath',
            '$lines += ([string]$run.error).Trim()',
            'timed_out = [bool]$run.timed_out'
        )) {
            if (-not $text.Contains($marker)) {
                throw "State-capture repair marker missing: $marker"
            }
        }
        if ($text.Contains('$output = @(& "$env:WINDIR\System32\schtasks.exe" @Arguments 2>&1')) {
            throw 'Unsafe direct schtasks wrapper remains after repair.'
        }

        Assert-SasStateRepairParse -Text $text -Label $modulePath
        $utf8 = New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($modulePath,$text,$utf8)
    }
}
catch {
    Copy-Item -LiteralPath $backupPath -Destination $modulePath -Force
    throw "AUTOLOGON_SMB_STATE_CAPTURE_RUNTIME_REPAIR_FAILED: original restored. $($_.Exception.Message)"
}

$afterSha256 = Get-SasStateRepairSha256 -Path $modulePath
$result = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-smb-state-capture-runtime-repair/v1'
    classification = $classification
    runtime_root = $RuntimeRoot
    evidence_root = $EvidenceRoot
    module_path = $modulePath
    backup_path = $backupPath
    module_sha256_before = $beforeSha256
    module_sha256_after = $afterSha256
    powershell_parse_passed = $true
    bounded_native_task_scheduler = $true
    native_stderr_preserved_as_data = $true
    git_performed = $false
    network_activity_performed = $false
    target_contact_performed = $false
    target_mutation_performed = $false
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8

if ($PassThru) { return $result }
Write-Host $classification -ForegroundColor Green
Write-Host "Evidence: $resultPath"
