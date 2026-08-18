#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'C:\SASAL',
    [string]$EvidenceRoot
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasLocalSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
        }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Assert-SasPowerShellParses {
    param([Parameter(Mandatory = $true)][string]$Path)
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -ne 0) {
        throw "PowerShell parser rejected repaired runtime: $($errors[0].Message)"
    }
}

function Write-SasRepairEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Record
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [pscustomobject]$Record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$runtimeRootFull = [IO.Path]::GetFullPath($RuntimeRoot)
$pilotPath = Join-Path -Path $runtimeRootFull -ChildPath 'scripts\Invoke-SasAutoLogonKerberosS4UPilot.ps1'
if (-not (Test-Path -LiteralPath $pilotPath -PathType Leaf)) {
    throw "AutoLogon S4U pilot runtime is missing: $pilotPath"
}

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $localRoot = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $env:TEMP } else { $env:LOCALAPPDATA }
    $EvidenceRoot = Join-Path -Path $localRoot -ChildPath 'SysAdminSuite\field-hotfixes'
}
$repairRunId = 's4u-create-timeout-repair-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
$runRoot = Join-Path -Path ([IO.Path]::GetFullPath($EvidenceRoot)) -ChildPath $repairRunId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$evidencePath = Join-Path -Path $runRoot -ChildPath 's4u-create-timeout-runtime-repair-result.json'
$backupPath = Join-Path -Path $runRoot -ChildPath 'Invoke-SasAutoLogonKerberosS4UPilot.ps1.before'

$record = [ordered]@{
    schema_version = 'sas-autologon-s4u-create-timeout-runtime-repair/v1'
    run_id = $repairRunId
    status = 'STARTED'
    runtime_root = $runtimeRootFull
    target_file = $pilotPath
    backup_path = $backupPath
    evidence_path = $evidencePath
    changed = $false
    already_applied = $false
    parser_valid = $false
    semantic_verification_passed = $false
    original_sha256 = $null
    repaired_sha256 = $null
    git_activity = 'NONE'
    network_activity = 'NONE'
    target_contact = 'NONE'
    target_mutation = 'NONE'
    error = $null
    completed_utc = $null
}

$nativeAnchor = @'
        native = [ordered]@{
            create = $null
            run = $null
'@
$nativeReplacement = @'
        native = [ordered]@{
            create = $null
            create_timeout_confirmation = $null
            run = $null
'@

$createAnchor = @'
        $lifecycle.native.create = $create
        if ([bool]$create.timed_out) {
            $lifecycle.classification = "S4U_${modeUpper}_CREATE_TIMEOUT"
            throw "S4U $Mode task creation timed out after $NativeTimeoutSeconds seconds."
        }
        if ([int]$create.exit_code -ne 0) {
            $lifecycle.classification = "S4U_${modeUpper}_CREATE_FAILED"
            throw "S4U $Mode task creation failed: $($create.output) $($create.error)"
        }
'@
$createReplacement = @'
        $lifecycle.native.create = $create
        if ([bool]$create.timed_out) {
            # A bounded local schtasks client timeout is ambiguous: the remote Task Scheduler may
            # already have committed the uniquely named task. Resolve only that exact ambiguity.
            $confirmation = Invoke-SasBoundedNative -FilePath "$env:WINDIR\System32\schtasks.exe" -Arguments @(
                '/Query','/S',$Target,'/TN',$TaskName
            ) -TimeoutSeconds $NativeTimeoutSeconds
            $lifecycle.native.create_timeout_confirmation = $confirmation
            if (-not [bool]$confirmation.timed_out -and [int]$confirmation.exit_code -eq 0) {
                $lifecycle.classification = "S4U_${modeUpper}_CREATE_TIMEOUT_CONFIRMED_PRESENT"
                $lifecycle.current_stage = 'create_timeout_confirmed_present'
                Save-SasS4UTaskLifecycle -Path $LifecyclePath -Lifecycle $lifecycle
            }
            elseif (-not [bool]$confirmation.timed_out -and [int]$confirmation.exit_code -ne 0 -and
                (Test-SasS4UTaskAbsentText -Text (([string]$confirmation.output) + "`n" + ([string]$confirmation.error)))) {
                $lifecycle.classification = "S4U_${modeUpper}_CREATE_TIMEOUT_CONFIRMED_ABSENT"
                throw "S4U $Mode task creation timed out after $NativeTimeoutSeconds seconds and exact post-timeout query confirmed the task is absent."
            }
            else {
                $lifecycle.classification = "S4U_${modeUpper}_CREATE_TIMEOUT_CONFIRMATION_UNVERIFIED"
                throw "S4U $Mode task creation timed out after $NativeTimeoutSeconds seconds and exact task presence could not be verified."
            }
        }
        elseif ([int]$create.exit_code -ne 0) {
            $lifecycle.classification = "S4U_${modeUpper}_CREATE_FAILED"
            throw "S4U $Mode task creation failed: $($create.output) $($create.error)"
        }
'@

try {
    $original = [IO.File]::ReadAllText($pilotPath)
    $record.original_sha256 = Get-SasLocalSha256 -Path $pilotPath
    Copy-Item -LiteralPath $pilotPath -Destination $backupPath -Force

    $hasNativeMarker = $original.Contains('create_timeout_confirmation = $null')
    $hasConfirmationMarker = $original.Contains('S4U_${modeUpper}_CREATE_TIMEOUT_CONFIRMED_PRESENT')
    if ($hasNativeMarker -and $hasConfirmationMarker) {
        Assert-SasPowerShellParses -Path $pilotPath
        $record.already_applied = $true
        $record.parser_valid = $true
        $record.semantic_verification_passed = $true
        $record.repaired_sha256 = $record.original_sha256
        $record.status = 'PASS_ALREADY_APPLIED'
    }
    else {
        if ($hasNativeMarker -or $hasConfirmationMarker) {
            throw 'Runtime contains only part of the S4U create-timeout confirmation repair; refusing partial mutation.'
        }

        $lineEnding = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }
        $normalized = $original.Replace("`r`n", "`n")
        $nativeAnchorNormalized = $nativeAnchor.Replace("`r`n", "`n")
        $nativeReplacementNormalized = $nativeReplacement.Replace("`r`n", "`n")
        $createAnchorNormalized = $createAnchor.Replace("`r`n", "`n")
        $createReplacementNormalized = $createReplacement.Replace("`r`n", "`n")

        if (-not $normalized.Contains($nativeAnchorNormalized)) {
            throw 'Native lifecycle anchor was not found exactly once in the protected runtime.'
        }
        if ($normalized.IndexOf($nativeAnchorNormalized) -ne $normalized.LastIndexOf($nativeAnchorNormalized)) {
            throw 'Native lifecycle anchor is ambiguous; refusing repair.'
        }
        if (-not $normalized.Contains($createAnchorNormalized)) {
            throw 'Create-timeout handling anchor was not found exactly once in the protected runtime.'
        }
        if ($normalized.IndexOf($createAnchorNormalized) -ne $normalized.LastIndexOf($createAnchorNormalized)) {
            throw 'Create-timeout handling anchor is ambiguous; refusing repair.'
        }

        $repairedNormalized = $normalized.Replace($nativeAnchorNormalized, $nativeReplacementNormalized).Replace($createAnchorNormalized, $createReplacementNormalized)
        $repaired = if ($lineEnding -eq "`r`n") { $repairedNormalized.Replace("`n", "`r`n") } else { $repairedNormalized }
        [IO.File]::WriteAllText($pilotPath, $repaired, (New-Object Text.UTF8Encoding($false)))
        Assert-SasPowerShellParses -Path $pilotPath

        $verify = [IO.File]::ReadAllText($pilotPath)
        foreach ($marker in @(
            'create_timeout_confirmation = $null',
            'S4U_${modeUpper}_CREATE_TIMEOUT_CONFIRMED_PRESENT',
            'S4U_${modeUpper}_CREATE_TIMEOUT_CONFIRMED_ABSENT',
            'S4U_${modeUpper}_CREATE_TIMEOUT_CONFIRMATION_UNVERIFIED',
            "'/Query','/S',`$Target,'/TN',`$TaskName",
            "elseif ([int]`$create.exit_code -ne 0)"
        )) {
            if (-not $verify.Contains($marker)) {
                throw "Semantic verification failed; marker missing: $marker"
            }
        }
        $record.changed = $true
        $record.parser_valid = $true
        $record.semantic_verification_passed = $true
        $record.repaired_sha256 = Get-SasLocalSha256 -Path $pilotPath
        $record.status = 'PASS_REPAIRED'
    }
}
catch {
    $record.error = $_.Exception.Message
    $record.status = 'FAILED_RESTORED'
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        Copy-Item -LiteralPath $backupPath -Destination $pilotPath -Force
    }
    throw
}
finally {
    $record.completed_utc = (Get-Date).ToUniversalTime().ToString('o')
    Write-SasRepairEvidence -Path $evidencePath -Record $record
    Write-Host ("Repair evidence: {0}" -f $evidencePath)
}

Write-Host 'PASS: S4U CREATE-TIMEOUT CONFIRMATION RUNTIME REPAIR APPLIED AND SEMANTICALLY VERIFIED' -ForegroundColor Green
Write-Host 'Git activity during repair: NONE'
Write-Host 'Network activity during repair: NONE'
Write-Host 'Target contact during repair: NONE'
Write-Host 'Target mutation during repair: NONE'
