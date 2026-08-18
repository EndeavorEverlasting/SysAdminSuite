#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$sourceModule = Join-Path $repoRoot 'scripts\SasAutoLogonSmbStateRecovery.psm1'
$repairScript = Join-Path $repoRoot 'scripts\Repair-SasAutoLogonSmbStateCaptureRuntime.ps1'

foreach ($required in @($sourceModule,$repairScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing test surface: $required"
    }
}

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}

function Test-BoundedStateRepairInvocation {
    param([Parameter(Mandatory = $true)][string]$Text)
    $pattern = 'Invoke-SasBoundedNative(?:\s|`)+-FilePath(?:\s|`)+\$schtasksPath(?:\s|`)+-Arguments(?:\s|`)+\$Arguments(?:\s|`)+-TimeoutSeconds(?:\s|`)+\$TimeoutSeconds'
    return [regex]::IsMatch(
        $Text,
        $pattern,
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
}

function Write-FixtureBoundedNativeModule {
    param([Parameter(Mandatory = $true)][string]$Path)
    @'
#Requires -Version 5.1
function Invoke-SasBoundedNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [int]$TimeoutSeconds = 30
    )
    [pscustomobject][ordered]@{
        exit_code = 1
        timed_out = $false
        timeout_seconds = $TimeoutSeconds
        output = ''
        error = 'ERROR: The system cannot find the file specified.'
    }
}
Export-ModuleMember -Function Invoke-SasBoundedNative
'@ | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-RepairFixture {
    param([Parameter(Mandatory = $true)][ValidateSet('crlf','lf')][string]$LineEnding)

    $root = Join-Path ([IO.Path]::GetTempPath()) ('sas-state-repair-' + [guid]::NewGuid().ToString('N'))
    $scripts = Join-Path $root 'scripts'
    $evidence1 = Join-Path $root 'evidence-one'
    $evidence2 = Join-Path $root 'evidence-two'
    New-Item -ItemType Directory -Path $scripts -Force | Out-Null

    try {
        $text = [IO.File]::ReadAllText($sourceModule)
        $normalized = $text.Replace("`r`n","`n").Replace("`r","`n")
        if ($LineEnding -eq 'crlf') {
            $normalized = $normalized.Replace("`n","`r`n")
        }
        [IO.File]::WriteAllText(
            (Join-Path $scripts 'SasAutoLogonSmbStateRecovery.psm1'),
            $normalized,
            (New-Object Text.UTF8Encoding($false))
        )
        Write-FixtureBoundedNativeModule -Path (Join-Path $scripts 'SasBoundedNative.psm1')

        $first = & $repairScript -RuntimeRoot $root -EvidenceRoot $evidence1 -ConfirmRepair -PassThru
        Assert-True ($first.classification -eq 'AUTOLOGON_SMB_STATE_CAPTURE_RUNTIME_REPAIR_APPLIED') `
            "$LineEnding first repair classification was $($first.classification)"
        Assert-True ([bool]$first.powershell_parse_passed) "$LineEnding repair did not record parse proof."
        Assert-True ([bool]$first.bounded_invocation_semantic_verification) `
            "$LineEnding repair did not record semantic bounded-invocation proof."
        Assert-True (-not [bool]$first.git_performed) "$LineEnding repair performed Git activity."
        Assert-True (-not [bool]$first.network_activity_performed) "$LineEnding repair performed network activity."
        Assert-True (-not [bool]$first.target_contact_performed) "$LineEnding repair contacted a target."
        Assert-True (-not [bool]$first.target_mutation_performed) "$LineEnding repair mutated a target."

        $modulePath = Join-Path $scripts 'SasAutoLogonSmbStateRecovery.psm1'
        $repaired = [IO.File]::ReadAllText($modulePath)
        foreach ($marker in @(
            'native_stderr_is_data_not_terminating_error',
            "Join-Path `$PSScriptRoot 'SasBoundedNative.psm1'",
            '$lines += ([string]$run.error).Trim()',
            'timed_out = [bool]$run.timed_out'
        )) {
            Assert-True ($repaired.Contains($marker)) "$LineEnding repaired module missing marker: $marker"
        }
        Assert-True (Test-BoundedStateRepairInvocation -Text $repaired) `
            "$LineEnding repaired module failed semantic bounded invocation verification."
        Assert-True ($repaired.Contains('Invoke-SasBoundedNative `')) `
            "$LineEnding repaired module did not preserve the field-style multiline command continuation."
        Assert-True (-not $repaired.Contains('Invoke-SasBoundedNative -FilePath $schtasksPath')) `
            "$LineEnding fixture unexpectedly collapsed the bounded invocation to the brittle single-line form."
        Assert-True (-not $repaired.Contains('$output = @(& "$env:WINDIR\System32\schtasks.exe" @Arguments 2>&1')) `
            "$LineEnding repaired module retained the unsafe direct schtasks wrapper."

        Remove-Module SasAutoLogonSmbStateRecovery -Force -ErrorAction SilentlyContinue
        Remove-Module SasBoundedNative -Force -ErrorAction SilentlyContinue
        Import-Module $modulePath -Force -ErrorAction Stop
        $module = Get-Module SasAutoLogonSmbStateRecovery
        if ($null -eq $module) { throw "$LineEnding repaired state module did not import." }

        $native = & $module { Invoke-SasAutoLogonRecoverySchtasksCommand -Arguments @('/Query','/S','fixture.example.invalid','/TN','missing-task') }
        Assert-True ([int]$native.exit_code -eq 1) "$LineEnding wrapper did not preserve native exit code."
        Assert-True (-not [bool]$native.timed_out) "$LineEnding wrapper incorrectly reported timeout."
        Assert-True ([string]$native.output -match 'system cannot find the file specified') `
            "$LineEnding wrapper did not preserve native stderr as data."
        $absent = & $module { param($Text) Test-SasAutoLogonRecoveryTaskAbsentText -Text $Text } ([string]$native.output)
        Assert-True ([bool]$absent) "$LineEnding absent-task text was not classifiable after bounded capture."

        Remove-Module SasAutoLogonSmbStateRecovery -Force -ErrorAction SilentlyContinue
        Remove-Module SasBoundedNative -Force -ErrorAction SilentlyContinue
        $second = & $repairScript -RuntimeRoot $root -EvidenceRoot $evidence2 -ConfirmRepair -PassThru
        Assert-True ($second.classification -eq 'AUTOLOGON_SMB_STATE_CAPTURE_RUNTIME_REPAIR_ALREADY_PRESENT') `
            "$LineEnding multiline second repair was not idempotent: $($second.classification)"
        Assert-True ([bool]$second.bounded_invocation_semantic_verification) `
            "$LineEnding multiline second repair lost semantic verification proof."

        Write-Host "PASS: $LineEnding multiline state-capture repair, stderr preservation, semantic verification, and idempotence"
    }
    finally {
        Remove-Module SasAutoLogonSmbStateRecovery -Force -ErrorAction SilentlyContinue
        Remove-Module SasBoundedNative -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-RepairFixture -LineEnding crlf
Invoke-RepairFixture -LineEnding lf
Write-Host 'PASS: AutoLogon SMB state-capture runtime repair contracts'
