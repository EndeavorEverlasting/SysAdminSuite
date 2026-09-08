#Requires -Version 5.1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runnerPath = Join-Path $repoRoot 'scripts\Invoke-SasAutoLogonCrashSafeFieldRun.ps1'
$progressPath = Join-Path $repoRoot 'scripts\SasAutoLogonProgress.psm1'
foreach ($required in @($runnerPath, $progressPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing crash-safe progress fixture dependency: $required"
    }
}

$runnerText = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
if ($runnerText -notmatch [regex]::Escape('Tee-Object -FilePath $childOutputPath -ErrorAction Stop')) {
    throw 'Crash-safe runner must keep durable child-output write failures terminating.'
}

$tempRoot = Join-Path $env:TEMP ('sas-crash-safe-progress-' + [guid]::NewGuid().ToString('N'))
$runtimeRoot = Join-Path $tempRoot 'runtime'
$scriptsRoot = Join-Path $runtimeRoot 'scripts'
$localAppData = Join-Path $tempRoot 'LocalAppData'
New-Item -ItemType Directory -Path $scriptsRoot -Force | Out-Null
New-Item -ItemType Directory -Path $localAppData -Force | Out-Null
Copy-Item -LiteralPath $progressPath -Destination (Join-Path $scriptsRoot 'SasAutoLogonProgress.psm1') -Force

$onsiteFixture = @'
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Action,
    [Parameter(Mandatory = $true)][string]$ComputerName
)
Write-Output '[8/22] staging/hash verification: PASS'
Write-Output '[9/22] Probe task create: START'
[Console]::Error.WriteLine('synthetic canonical stderr')
Write-Output '[9/22] Probe task: FAIL - synthetic create timeout'
Write-Output '[11/22] Probe result: FAIL - synthetic legacy failure attribution'
Write-Output '[12/22] Probe cleanup: START'
exit 37
'@
Set-Content -LiteralPath (Join-Path $scriptsRoot 'Invoke-SasAutoLogonOnsite.ps1') -Value $onsiteFixture -Encoding UTF8

$evidenceFixture = @'
#Requires -Version 5.1
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
Write-Output 'fixture offline evidence recovery'
exit 0
'@
Set-Content -LiteralPath (Join-Path $scriptsRoot 'Show-SasOperatorEvidence.ps1') -Value $evidenceFixture -Encoding UTF8

$previousLocalAppData = $env:LOCALAPPDATA
$startingPreference = $ErrorActionPreference
try {
    $env:LOCALAPPDATA = $localAppData
    $threw = $false
    try {
        & $runnerPath `
            -ComputerName 'fixture.example.invalid' `
            -RepositoryRoot $runtimeRoot `
            -RepositoryHead 'fixture-protected-window-floor' `
            -ConfirmDeployment | Out-Null
    }
    catch {
        $threw = $true
    }

    if (-not $threw) { throw 'Crash-safe runner did not surface the synthetic child failure.' }
    if ($ErrorActionPreference -ne $startingPreference) {
        throw "Crash-safe runner leaked ErrorActionPreference. Expected '$startingPreference'; got '$ErrorActionPreference'."
    }

    $pointerPath = Join-Path $localAppData 'SysAdminSuite\last-autologon-field-run.json'
    if (-not (Test-Path -LiteralPath $pointerPath -PathType Leaf)) {
        throw 'Crash-safe runner did not preserve the latest field-run pointer.'
    }
    $pointer = Get-Content -LiteralPath $pointerPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $result = Get-Content -LiteralPath ([string]$pointer.result_path) -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$result.child_exit_code -ne 37) {
        throw "Crash-safe runner did not preserve child exit code 37; got $($result.child_exit_code)."
    }
    if ([string]$result.status -ne 'FAILED') {
        throw "Synthetic nonzero child was not classified FAILED: $($result.status)"
    }

    $childOutput = Get-Content -LiteralPath ([string]$pointer.child_output_path) -Raw -Encoding UTF8
    if ($childOutput -notmatch 'synthetic canonical stderr') {
        throw 'Merged canonical stderr was not persisted in crash-safe child output.'
    }
    $skip = '[10/22] Probe task run: SKIP - underlying path did not enter this stage before advancing to stage 11.'
    if ($childOutput -notmatch [regex]::Escape($skip)) {
        throw 'Crash-safe child output did not synthesize the missing numbered stage.'
    }
    if ($childOutput.IndexOf($skip, [StringComparison]::Ordinal) -gt $childOutput.IndexOf('[11/22] Probe result: FAIL', [StringComparison]::Ordinal)) {
        throw 'Synthesized skipped stage appeared after the later result stage.'
    }
}
finally {
    if ($null -eq $previousLocalAppData) {
        Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue
    }
    else {
        $env:LOCALAPPDATA = $previousLocalAppData
    }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: crash-safe AutoLogon preserves stderr/exit evidence and contiguous progress under Windows PowerShell 5.1.' -ForegroundColor Green
